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

enum{
	TCmplx,
	TNum,
	TUchar,
	TU16,
	TU32,
	TU64,
	TVLA,
};

typedef struct Field Field;
typedef struct Sym Sym;

struct Sym{
	char *name;
	int type;
	int val;
	char *from;
};

struct Field{
	char *name;
	int len;
	int count;
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
}

static void
cprint(char *name)
{
	int i, j;
	char buf[128];

/*
	print("typedef struct %s %s;\n", name, name);
	print("struct %s{\n", name);
	for(i = 0; i < ntobe; i++){
		if(tobe[i].sym.type == TCmplx){
			print("\t%s %s;\n", tobe[i].sym.name, tobe[i].name);
			continue;
		}
		if(tobe[i].len == 0)
			print("\tuchar *%s;\n", tobe[i].name);
		else if(aligned(tobe[i].len))
			print("\t%s %s;\n", size2type(tobe[i].len), tobe[i].name);
		else
			print("\tuchar %s[%d];\n", tobe[i].name, tobe[i].len);
	}
	print("};\n\n");
*/

	mklower(buf, buf + sizeof buf - 1, name);
	print("long\nget%s(%s *ret, uchar *data)\n{\n\tlong n;\n\n\tn = 0;\n", buf, name);
	for(i = 0; i < ntobe; i++){
		switch(tobe[i].sym.type){
		case TCmplx:
			mklower(buf, buf + sizeof buf - 1, tobe[i].sym.name);
			if(tobe[i].count == 1)
				print("\tn += get%s(&ret->%s, data+n);\n", buf, tobe[i].name);
			else for(j = 0; j < tobe[i].count; j++)
				print("\tn += get%s(&ret->%s[%d], data+n);\n", buf, tobe[i].name, j);
			continue;
		case TVLA:
			print("\tret->%s = data+n;\n", tobe[i].name);
			print("\tn += ret->%s;\n", tobe[i].sym.from);
			continue;
		}
		if(tobe[i].len == 1)
			print("\tret->%s = data[n];\n", tobe[i].name);
		else if(aligned(&tobe[i].sym))
			print("\tret->%s = GET%d(data+n);\n", tobe[i].name, tobe[i].len);
		else
			print("\tmemcpy(ret->%s, data+n, %d);\n", tobe[i].name, tobe[i].len);
		print("\tn += %d;\n", tobe[i].len);
	}
	print("\treturn n;\n}\n\n");

	mklower(buf, buf + sizeof buf - 1, name);
	print("long\nput%s(uchar *dst, %s *src)\n{\n\tlong n;\n\n\tn = 0;\n", buf, name);
	for(i = 0; i < ntobe; i++){
		switch(tobe[i].sym.type){
		case TCmplx:
			mklower(buf, buf + sizeof buf - 1, tobe[i].sym.name);
			if(tobe[i].count == 1)
				print("\tn += put%s(dst+n, &src->%s);\n", buf, tobe[i].name);
			else for(j = 0; j < tobe[i].count; j++)
				print("\tn += put%s(dst+n, &src->%s[%d]);\n", buf, tobe[i].name, j);
			continue;
		case TVLA:
			print("\tmemmove(dst+n, src->%s, src->%s);\n", tobe[i].name, tobe[i].sym.from);
			print("\tn += src->%s;\n", tobe[i].sym.from);
			continue;
		}
		if(tobe[i].len == 1)
			print("\tdst[n] = src->%s;\n", tobe[i].name);
		else if(aligned(&tobe[i].sym))
			print("\tPUT%d(dst+n, src->%s);\n", tobe[i].len, tobe[i].name);
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

%token STRUCT TYPEDEF UCHAR U16 U32 U64
%token <sval>	NAME NUM CHAR
%token <ival>	VAR CMPLX

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
		$$ = atoi($1);
	}
|	VAR
	{
		$$ = defs[$1].val;
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
		cprint($2);
		defs[ndef].name = $2;
		defs[ndef].type = TCmplx;
		defs[ndef].val = -1;
		ntobe = 0;
		ndef++;
	}
|	name '=' num sem
	{
		defs[ndef].name = $1;
		defs[ndef].type = TNum;
		defs[ndef].val = $3;
		ndef++;
	}

members:
	members member
|	member

member:
	type name sem
	{
		tobe[ntobe].name = $2;
		tobe[ntobe].len = $1.val;
		tobe[ntobe].count = 1;
		tobe[ntobe].sym = $1;
		ntobe++;
	}
|	type name '[' num ']' sem
	{
		tobe[ntobe].name = $2;
		tobe[ntobe].len = $4;
		tobe[ntobe].count = $4;
		tobe[ntobe].sym = $1;
		ntobe++;
	}
|	type name '[' '.' name ']' sem
	{

		tobe[ntobe].name = $2;
		tobe[ntobe].len = 0;
		$1.type = TVLA;
		$1.from = $5;
		tobe[ntobe].sym = $1;
		ntobe++;
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

int
yylex(void)
{
	static char buf[200];
	char *p;
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
	case '.':
		return c;
	}

	ungetc();
	p = buf;
	for(;;){
		c = getch();
		if((c >= Runeself)
		|| (c == '_')
		|| (c == ':')
		|| (c >= 'a' && c <= 'z')
		|| (c >= 'A' && c <= 'Z')
		|| (c >= '0' && c <= '9')){
			*p++ = c;
			continue;
		}
		ungetc();
		break;
	}
	*p = '\0';

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

	for(i = 0; i < ndef; i++){
		if(strcmp(buf, defs[i].name) != 0)
			continue;
		yylval.ival = i;
		return defs[i].type == TNum ? VAR : CMPLX;
	}

	yylval.sval = strdup(buf);
	return (buf[0] >= '0' && buf[0] <= '9') ? NUM : NAME;
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
	byteprint();
	while(!goteof)
		yyparse();
	Bterm(bin);
	exits(nil);
}
