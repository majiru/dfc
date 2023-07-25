%{

#include <u.h>
#include <libc.h>
#include <bio.h>
#include <ctype.h>

int goteof;
int lineno;
int yyparse(void);
void yyerror(char*);

enum{
	Big,
	Little,
};

int ordermode = Big;
int donebyteprint = 0;
int nextenumval = 0;

enum{
	TCmplx,
	TUchar,
	TU16,
	TU32,
	TU64,
	TEnum,
};

typedef struct Field Field;
typedef struct Sym Sym;

struct Sym{
	char *name;
	int type;
	int val;
};

struct Field{
	char *name;
	int len;
	Sym sym;
};


Field	tobe[128];
int	ntobe;

Sym	defs[128];
int	ndef;

static void
mklower(char *d, char *e, char *s)
{
	assert(d <= e-1);
	for(; *s != 0 && d < e-1; s++){
		if(!isascii(*s))
			continue;
		*d++ = tolower(*s);
	}
	*d = 0;
}

static char*
size2type(int x)
{
	switch(x){
	case 1:
		return "uchar";
	case 2:
		return "u16int";
	case 3: case 4:
		return "u32int";
	case 5: case 6: case 7: case 8:
		return "u64int";
	default:
		yyerror("invalid size");
		return nil;
	}
}

static int
aligned2size(Sym *s)
{
	switch(s->type){
	case TU16:
		return 2;
	case TU32:
		return 4;
	case TU64:
		return 8;
	default:
		return 0;
	}
}

static int
aligned(Sym *s)
{
	switch(s->type){
	case TU16: case TU32: case TU64:
		return 1;
	default:
		return 0;
	}
}

static void
byteprint(void)
{
	int x, y;
	int shift;

	if(donebyteprint)
	for(x = 2; x <= 8; x++)
		print("#undef GET%d\n#undef PUT%d\n", x, x);

	if(ordermode == Big)
	for(x = 2; x <= 8; x++){
		print("#define GET%d(p) ", x);
		for(shift = 0, y = x-1; y >= 0; y--, shift += 8){
			print("(%s)(p)[%d]", size2type(x), y);
			if(shift != 0)
				print("<<%d", shift);
			if(y != 0)
				print(" | ");
		}
		print("\n");
		print("#define PUT%d(p, u) ", x);
		for(shift = 8*(x-1), y = 0; y < x; y++, shift -= 8){
			print("(p)[%d] = (u)", y);
			if(shift != 0)
				print(">>%d, ", shift);
		}
		print("\n");
	}

	if(ordermode == Little)
	for(x = 2; x <= 8; x++){
		print("#define GET%d(p) ", x);
		for(shift = 0, y = 0; y < x; y++, shift += 8){
			print("(%s)(p)[%d]", size2type(x), y);
			if(shift != 0)
				print("<<%d", shift);
			if(y != x-1)
				print(" | ");
		}
		print("\n");
		print("#define PUT%d(p, u) ", x);
		for(shift = 8*(x-1), y = x - 1; y >= 0; y--, shift -= 8){
			print("(p)[%d] = (u)", y);
			if(shift != 0)
				print(">>%d, ", shift);
		}
		print("\n");
	}
	print("\n");
	donebyteprint = 1;
}

static void
cprint(char *name)
{
	int i, j;
	char buf[128];

	mklower(buf, buf + sizeof buf - 1, name);
	print("long\nget%s(%s *ret, uchar *data)\n{\n\tlong n;\n\n\tn = 0;\n", buf, name);
	for(i = 0; i < ntobe; i++){
		if(tobe[i].sym.type == TCmplx){
			mklower(buf, buf + sizeof buf - 1, tobe[i].sym.name);
			if(tobe[i].len == 1)
				print("\tn += get%s(&ret->%s, data+n);\n", buf, tobe[i].name);
			else for(j = 0; j < tobe[i].len; j++)
				print("\tn += get%s(&ret->%s[%d], data+n);\n", buf, tobe[i].name, j);
			continue;
		}
		if(aligned(&tobe[i].sym)){
			if(tobe[i].len == 1){
				print("\tret->%s = GET%d(data+n);\n", tobe[i].name, aligned2size(&tobe[i].sym));
				print("\tn += %d;\n", aligned2size(&tobe[i].sym));
			} else for(j = 0; j < tobe[i].len; j++){
				print("\tret->%s[%d] = GET%d(data+n);\n", tobe[i].name, j, aligned2size(&tobe[i].sym));
				print("\tn += %d;\n", aligned2size(&tobe[i].sym));
			}
			continue;
		}
		if(tobe[i].len == 1)
			print("\tret->%s = data[n];\n", tobe[i].name);
		else
			print("\tmemcpy(ret->%s, data+n, %d);\n", tobe[i].name, tobe[i].len);
		print("\tn += %d;\n", tobe[i].len);
	}
	print("\treturn n;\n}\n\n");

	mklower(buf, buf + sizeof buf - 1, name);
	print("long\nput%s(uchar *dst, %s *src)\n{\n\tlong n;\n\n\tn = 0;\n", buf, name);
	for(i = 0; i < ntobe; i++){
		if(tobe[i].sym.type == TCmplx){
			mklower(buf, buf + sizeof buf - 1, tobe[i].sym.name);
			if(tobe[i].len == 1)
				print("\tn += put%s(dst+n, &src->%s);\n", buf, tobe[i].name);
			else for(j = 0; j < tobe[i].len; j++)
				print("\tn += put%s(dst+n, &src->%s[%d]);\n", buf, tobe[i].name, j);
			continue;
		}
		if(aligned(&tobe[i].sym)){
			if(tobe[i].len == 1){
				print("\tPUT%d(dst+n, src->%s);\n", aligned2size(&tobe[i].sym), tobe[i].name);
				print("\tn += %d;\n", aligned2size(&tobe[i].sym));
			} else for(j = 0; j < tobe[i].len; j++){
				print("\tPUT%d(dst+n, src->%s[%d]);\n", aligned2size(&tobe[i].sym), tobe[i].name, j);
				print("\tn += %d;\n", aligned2size(&tobe[i].sym));
			}
			continue;
		}
		if(tobe[i].len == 1)
			print("\tdst[n] = src->%s;\n", tobe[i].name);
		else
			print("\tmemcpy(dst+n, src->%s, %d);\n", tobe[i].name, tobe[i].len);
		print("\tn += %d;\n", tobe[i].len);
	}
	print("\treturn n;\n}\n\n");
}

%}

%union
{
	char *sval;
	long ival;
	Sym yval;
}

%type	<sval>	name
%type	<ival>	num
%type	<yval>	type

%left '{' '}' '[' ']' ';' '=' '(' ')' '.'

%token STRUCT TYPEDEF ENUM UCHAR U16 U32 U64
%token <sval>	NAME
%token <ival>	NUM CMPLX

%%

prog:
	prog top
|	top
|

name:
	NAME
	{
		$$ = $1;
	}

num:
	NUM
	{
		$$ = $1;
	}

type:
	UCHAR
	{
		$$.type = TUchar;
		$$.val = 1;
	}
|	U16
	{
		$$.type = TU16;
		$$.val = 2;
	}
|	U32
	{
		$$.type = TU32;	
		$$.val = 4;
	}
|	U64
	{
		$$.type = TU64;
		$$.val = 8;
	}
|	CMPLX
	{
		$$ = defs[$1];
	}

sem:
	sem ';'
|	';'

top:
	TYPEDEF STRUCT name name sem
|	STRUCT name '{' members '}' sem
	{
		if(!donebyteprint)
			byteprint();
		cprint($2);
		defs[ndef].name = $2;
		defs[ndef].type = TCmplx;
		defs[ndef].val = -1;
		ntobe = 0;
		ndef++;
	}
|	ENUM '{' emembers '}' sem
	{
		nextenumval = 0;
	}

members:
	members member
|	member

member:
	type name sem
	{
		tobe[ntobe].name = $2;
		tobe[ntobe].len = 1;
		tobe[ntobe].sym = $1;
		ntobe++;
	}
|	type name '[' num ']' sem
	{
		tobe[ntobe].name = $2;
		tobe[ntobe].len = $4;
		tobe[ntobe].sym = $1;
		ntobe++;
	}

emembers:
	emembers emember
|	emember

emember:
	name '=' num
	{
		defs[ndef].name = $1;
		defs[ndef].type = TEnum;
		defs[ndef].val = $3;
		nextenumval = $3+1;
		ndef++;
	}
|	name
	{
		defs[ndef].name = $1;
		defs[ndef].type = TEnum;
		defs[ndef].val = nextenumval;
		nextenumval++;
		ndef++;
	}

%%

Biobuf *bin;

int
getch(void)
{
	int c;

	c = Bgetc(bin);
	if(c == Beof){
		goteof = 1;
		return -1;
	}
	if(c == '\n')
		lineno++;
	return c;
}

void
ungetc(void)
{
	Bungetc(bin);
}

void
yyerror(char *s)
{
	fprint(2, "%d: %s\n", lineno, s);
	exits(s);
}

void
wordlex(char *dst, int n)
{
	int c;

	while(--n > 0){
		c = getch();
		if((c >= Runeself)
		|| (c == '_')
		|| (c == ':')
		|| isalnum(c)){
			*dst++ = c;
			continue;
		}
		ungetc();
		break;
	}
	if(n <= 0)
		yyerror("symbol buffer overrun");
	*dst = '\0';
}

int
praglex(void)
{
	char buf[200];
	int i;
	int newmode;
	char *wordtab[] = {
		"pragma",
		"dfc",
	};

	for(i = 0; i < nelem(wordtab); i++){
		wordlex(buf, sizeof buf - 1);
		if(strcmp(buf, wordtab[i]) != 0)
			return 0;
		if(getch() != ' '){
			ungetc();
			return 0;
		}
	}

	wordlex(buf, sizeof buf - 1);
	if(strcmp(buf, "big") == 0)
		newmode = Big;
	else if(strcmp(buf, "little") == 0)
		newmode = Little;
	else if(strcmp(buf, "done") == 0){
		goteof = 1;
		return -1;
	} else
		return 0;

	if(ordermode != newmode){
		ordermode = newmode;
		byteprint();
	}
	return 0;
}

int
yylex(void)
{
	static char buf[200];
	int c;
	int i;

Loop:
	c = getch();
	switch(c){
	case -1:
		return -1;
	case ' ':
	case '\t':
	case '\n':
	case ',':
		goto Loop;
	case '/':
		if(getch() != '*'){
			ungetc();
			goto Loop;
		}
More:
		while((c = getch()) > 0)
			if(c == '*')
				break;
		if(c != '*')
			goto Loop;
		if(getch() == '/')
			goto Loop;
		goto More;
	case '#':
		if(praglex() < 0)
			return -1;
		while((c = getch()) > 0)
			if(c == '\n')
				break;
		goto Loop;
	}

	switch(c){
	case ';': case '=':
	case '{': case '}':
	case '[': case ']':
	case '(': case ')':
		return c;
	}

	ungetc();
	wordlex(buf, sizeof buf);

	if(strcmp(buf, "struct") == 0)
		return STRUCT;
	if(strcmp(buf, "typedef") == 0)
		return TYPEDEF;
	if(strcmp(buf, "uchar") == 0)
		return UCHAR;
	if(strcmp(buf, "u16int") == 0)
		return U16;
	if(strcmp(buf, "u32int") == 0)
		return U32;
	if(strcmp(buf, "u64int") == 0)
		return U64;
	if(strcmp(buf, "enum") == 0)
		return ENUM;

	for(i = 0; i < ndef; i++){
		if(strcmp(buf, defs[i].name) != 0)
			continue;
		if(defs[i].type == TCmplx){
			yylval.ival = i;
			return CMPLX;
		}
		yylval.ival = defs[i].val;
		return NUM;
	}

	if(isdigit(buf[0])){
		yylval.ival = atoi(buf);
		return NUM;
	}

	yylval.sval = strdup(buf);
	return NAME;
}

void
usage(void)
{
	fprint(2, "usage: %s [-lb] dat.h\n", argv0);
	exits("usage");
}

void
main(int argc, char **argv)
{
	ARGBEGIN{
	case 'l':
		ordermode = Little;
		break;
	case 'b':
		ordermode = Big;
		break;
	default:
		usage();
		break;
	}ARGEND;
	if(argc != 1)
		usage();
	bin = Bopen(argv[0], OREAD);
	goteof = 0;
	print("#include <u.h>\n#include <libc.h>\n#include \"%s\"\n\n", argv[0]);
	while(!goteof)
		yyparse();
	Bterm(bin);
	exits(nil);
}
