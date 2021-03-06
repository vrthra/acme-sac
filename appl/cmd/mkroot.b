implement Mkroot;

include "sys.m";
	sys: Sys;
	sprint, fprint, print, fildes: import sys;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "draw.m";

Mkroot: module {
	init: fn(nil: ref Draw->Context, args:list of string);
};

Entry : adt {
	key: string;
	qid: int;
};

keys: list of ref Entry;

lookup(key: string): ref Entry
{	
	for(l := keys; l != nil; l = tl l)
		if((hd l).key == key)
			return hd l;
	return nil;
}
	
isdir := array[1024] of int;
dotdot := array[1024] of int;
sort := array[1024] of int;
unsort := array[1024] of int;
nchild := array[1024] of int;
child0 := array[1024] of int;
name := array[128] of string;

init(nil: ref Draw->Context, args:list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	
	args = tl args;
	if(len args != 1){
		fprint(fildes(2), "usage mkroot name\n");
		raise "fail:arg";
	}
	
	rootdata := hd args + ".root.c";
	bout := bufio->create(rootdata, Bufio->OWRITE, 8r666);
	bout.puts("/* Generated by mkroot */");
	nroot := 0;
	src := array[128] of string;
	dst := array[128] of string;
	
	bin := bufio->fopen(fildes(0), Bufio->OREAD);
	
	collect := 0;
	while((s := bin.gets('\n')) != nil){
		if(len s >4 && s[:4] == "root"){
			collect = 1;
			continue;
		}
		if(!collect || len s < 1 || s[0] != '	' )
			continue;
		(n , flds) := sys->tokenize(s, " \t\n\r");
		if(n == 0)
			continue;
		dst[nroot] = hd flds;
		if(n > 1)
			src[nroot] = hd tl flds;
		for(i:=0; i<nroot; i++)
			if(dst[i] == dst[nroot])
				break;
		if(i == nroot)
			nroot++;
	}
	
	isdir[0] = 1;
	dotdot[0] = 0;
	qid := 1;
	q := 0;
	for (i := 0; i < nroot; i++) {
		(ncomp, f) := sys->tokenize(dst[i], "/");
		comp := array[ncomp] of string;
		for(ncomp = 0; f != nil; f = tl f)
			comp[ncomp++] = hd f;
		if (ncomp < 1)
			continue;
		q = 0;
		for (j := 0; j < ncomp; j++) {
			key := string q + "/" + comp[j];
			e := lookup(key);
			if (e == nil) {
				keys = ref Entry(key, qid) :: keys;
				dotdot[qid] = q;
				q = qid++;
				name[q] = comp[j];
			#	if (j < ncomp)
			#		isdir[q] = 1;
			}
			else
				q = e.qid;
		}
		(nil, dir) := sys->stat(src[i]);
		if (dir.qid.qtype & Sys->QTDIR)
			isdir[q] = 1;
		else {
			data2c("root" + string q, bout, src[i]);
			print("extern unsigned char root%dcode[];\n", q);
			print("extern int root%dlen;\n", q);
		}
	}

	x := 1;
	sort[0] = 0;
	unsort[0] = 0;
	for (q = 0; q < qid; q++) {
		if (isdir[q]) {
			nchild[q] = 0;
			for (q2 := 1; q2 < qid; q2++) {
				if (dotdot[q2] == q) {
					if (nchild[q]++ == 0)
						child0[q] = x;
					sort[q2] = x++;
					unsort[sort[q2]] = q2;
				}
			}
		}
	}

	print("int rootmaxq = %d;\n", qid);

	print("Dirtab roottab[%d] = {\n", qid);
	for (oq := 0; oq < qid; oq++) {
		q = unsort[oq];
		if (!isdir[q])
			print("\t\"%s\",\t{%d, 0, QTFILE},\t0,\t0444,\n",  name[q], oq);
		else
			print("\t\"%s\",\t{%d, 0, QTDIR},\t0,\t0555,\n", name[q], oq);
	}
	print("};\n\n");

	print("Rootdata rootdata[%d] = {\n", qid);
	for (oq = 0; oq < qid; oq++) {
		q = unsort[oq];
		if (!isdir[q])
			print("\t%d,\t root%dcode,\t0,\t&root%dlen,\n", sort[dotdot[q]], q, q);
		else if (nchild[q])
			print("\t%d,\t &roottab[%d],\t%d,\tnil,\n", sort[dotdot[q]], child0[q], nchild[q]);
		else
			print("\t%d,\tnil,\t0,\tnil,\n", sort[dotdot[q]]);
	}
	print("};\n");
	bout.close();
}
	
data2c(name: string, bout: ref Iobuf, src: string)
{
	bin := bufio->open(src, Bufio->OREAD);
	if(bin == nil)
		return;
	bout.puts(sprint("unsigned char %scode[] ={\n", name));
	
	block := array[16] of byte;
	l := 0;
	for(l = 0; (n:=bin.read(block, len block)) > 0; l += n){
		for(i := 0; i < n; i++)
			if(int block[i])
				bout.puts(sprint("0x%ux,", int block[i]));
			else
				bout.puts("0,");
		bout.puts("\n");
	}
	if(l == 0)
		bout.puts("0\n");
	bout.puts("};\n");
	bout.puts(sprint("int %slen = %d;\n", name, l));
	bout.flush();
}
