#!/bin/sh
# JSON boundary for the Codex adapter. POSIX awk only; no eval or jq.
# JSON pointers address keys (including dots); duplicate keys/NUL fail closed.
set -eu

cj_run() {
  CJ_MODE=$1 CJ_POINTER=${2:-} LC_ALL=C awk '
function fail(m) { print "codex-json: " m > "/dev/stderr"; bad=1; exit 1 }
function ws() { while (substr(s,p,1) ~ /^[ \t\r\n]$/ && p<=length(s)) p++ }
function hex(x, i,n,c) { n=0; for(i=1;i<=length(x);i++){c=index("0123456789abcdef",tolower(substr(x,i,1)))-1;if(c<0)fail("invalid Unicode escape");n=n*16+c}return n }
function utf(n) {
  if(n==0)fail("NUL cannot cross the shell boundary")
  if(n<128)return sprintf("%c",n)
  if(n<2048)return sprintf("%c%c",192+int(n/64),128+n%64)
  if(n<65536)return sprintf("%c%c%c",224+int(n/4096),128+int(n/64)%64,128+n%64)
  return sprintf("%c%c%c%c",240+int(n/262144),128+int(n/4096)%64,128+int(n/64)%64,128+n%64)
}
function string( out,c,e,h,lo) {
  if(substr(s,p++,1)!="\"")fail("string expected")
  out=""
  while(p<=length(s)) {
    c=substr(s,p++,1)
    if(c=="\""){valid_utf8(out);return out}
    if(c==sprintf("%c",0))fail("NUL cannot cross the shell boundary")
    if(c=="\\") {
      e=substr(s,p++,1)
      if(e=="\""||e=="\\"||e=="/")out=out e
      else if(e=="b")out=out sprintf("%c",8)
      else if(e=="f")out=out sprintf("%c",12)
      else if(e=="n")out=out "\n"
      else if(e=="r")out=out "\r"
      else if(e=="t")out=out "\t"
      else if(e=="u") {
        h=substr(s,p,4);if(length(h)!=4)fail("short Unicode escape");p+=4;h=hex(h)
        if(h>=55296&&h<=56319) {
          if(substr(s,p,2)!="\\u")fail("missing low surrogate");p+=2
          lo=substr(s,p,4);if(length(lo)!=4)fail("short low surrogate");p+=4;lo=hex(lo)
          if(lo<56320||lo>57343)fail("invalid low surrogate")
          h=65536+(h-55296)*1024+lo-56320
        } else if(h>=56320&&h<=57343)fail("unpaired surrogate")
        out=out utf(h)
      } else fail("invalid string escape")
    } else { if(c ~ /[\001-\037]/)fail("unescaped control byte");out=out c }
  }
  fail("unterminated string")
}
function node(t,v, n) { n=++serial;typ[n]=t;val[n]=v;count[n]=0;return n }
function parse(depth, n,c,k,v,beg,key) {
  if(depth>128)fail("nesting limit exceeded");ws();c=substr(s,p,1)
  if(c=="\"")return node("string",string())
  if(c=="{"||c=="[") {
    p++;n=node(c=="{"?"object":"array","");ws()
    if(substr(s,p,1)==(c=="{"?"}":"]")){p++;return n}
    while(1) {
      ws();if(c=="{"){k=string();ws();if(substr(s,p++,1)!=":")fail("colon expected");key=n SUBSEP k;if(key in member)fail("duplicate object key")}
      else k=count[n]
      v=parse(depth+1);child[n,++count[n]]=v;label[n,count[n]]=k;member[n,k]=v;ws()
      if(substr(s,p,1)==(c=="{"?"}":"]")){p++;return n}
      if(substr(s,p++,1)!=",")fail("comma expected")
    }
  }
  beg=p;while(p<=length(s)&&substr(s,p,1)!~/[ \t\r\n,\]}]/)p++
  v=substr(s,beg,p-beg)
  if(v=="true"||v=="false")return node("boolean",v)
  if(v=="null")return node("null",v)
  if(v~/^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/)return node("number",v)
  fail("invalid value")
}
function quote(v, i,c,out,j) {
  valid_utf8(v)
  out="\""
  for(i=1;i<=length(v);i++) {
    c=substr(v,i,1)
    if(c=="\"")out=out "\\\""
    else if(c=="\\")out=out "\\\\"
    else if(c=="\n")out=out "\\n"
    else if(c=="\r")out=out "\\r"
    else if(c=="\t")out=out "\\t"
    else if(c ~ /[\001-\037]/){for(j=1;j<32;j++)if(c==sprintf("%c",j))break;out=out sprintf("\\u%04x",j)}
    else out=out c
  }
  return out "\""
}
function byte(c) { return (c in bytes)?bytes[c]:-1 }
function valid_utf8(v, i,b,n,j,c,cp,min) {
  for(i=1;i<=length(v);i++) {
    b=byte(substr(v,i,1));if(b==0)fail("NUL cannot cross the shell boundary")
    if(b<128)continue
    if(b>=194&&b<=223){n=1;cp=b-192;min=128}
    else if(b>=224&&b<=239){n=2;cp=b-224;min=2048}
    else if(b>=240&&b<=244){n=3;cp=b-240;min=65536}
    else fail("invalid UTF-8")
    for(j=1;j<=n;j++){c=byte(substr(v,++i,1));if(c<128||c>191)fail("invalid UTF-8 continuation");cp=cp*64+c-128}
    if(cp<min||cp>1114111||(cp>=55296&&cp<=57343))fail("invalid UTF-8 code point")
  }
}
function chars(v, i,n) { n=0;for(i=1;i<=length(v);i++)if(byte(substr(v,i,1))<128||byte(substr(v,i,1))>=192)n++;return n }
function equal(a,b, i,k) {
  if(typ[a]!=typ[b])return 0
  if(typ[a]!="array"&&typ[a]!="object")return val[a]==val[b]
  if(count[a]!=count[b])return 0
  for(i=1;i<=count[a];i++) {
    if(typ[a]=="array"){if(!equal(child[a,i],child[b,i]))return 0}
    else {k=label[a,i];if(!((b SUBSEP k) in member)||!equal(child[a,i],member[b,k]))return 0}
  }
  return 1
}
function emit(n, i,out,t,v) {
  t=typ[n];if(t=="string")return quote(val[n]);if(t!="object"&&t!="array")return val[n]
  out=t=="object"?"{":"["
  for(i=1;i<=count[n];i++) {v=child[n,i];if(!v||deleted[v])continue;if(out!="{"&&out!="[")out=out ",";if(t=="object")out=out quote(label[n,i]) ":";out=out emit(v)}
  return out (t=="object"?"}":"]")
}
function pointer(n,path, create, a,len,i,k,v) {
  if(path=="")return n;if(substr(path,1,1)!="/")fail("JSON pointer must begin with slash")
  len=split(substr(path,2),a,"/")
  for(i=1;i<=len;i++) {
    k=a[i];gsub(/~1/,"/",k);gsub(/~0/,"~",k)
    if(typ[n]=="array") {
      if(k=="-1")k=count[n]-1
      if(k!~/^(0|[1-9][0-9]*)$/)fail("invalid array index")
    } else if(typ[n]!="object")fail("pointer crosses scalar")
    if(!((n SUBSEP k) in member)) {
      if(!create)return 0
      v=node("object","");member[n,k]=v;child[n,++count[n]]=v;label[n,count[n]]=k
    }
    n=member[n,k]
  }
  return n
}
BEGIN { for(code=0;code<256;code++)bytes[sprintf("%c",code)]=code }
{ input=input $0 "\n" }
END {
  if(bad)exit 1
  mode=ENVIRON["CJ_MODE"];path=ENVIRON["CJ_POINTER"]
  if(mode=="quote"){print quote(substr(input,1,length(input)-1));exit}
  s=input;p=1;root=parse(0);ws()
  if(mode=="set"||mode=="append"||mode=="equal"||mode=="merge") {other=parse(0);ws()}
  if(p<=length(s))fail("trailing input")
  n=pointer(root,path,mode=="set")
  if(!n){exit 4}
  if(mode=="get"){if(typ[n]=="string")printf "%s",val[n];else printf "%s",emit(n)}
  else if(mode=="value"||mode=="validate")print emit(n)
  else if(mode=="type")print typ[n]
  else if(mode=="length")print (typ[n]=="array"||typ[n]=="object")?count[n]:chars(val[n])
  else if(mode=="each"){if(typ[n]!="array")fail("array expected");for(i=1;i<=count[n];i++)print emit(child[n,i])}
  else if(mode=="keys"){if(typ[n]!="object")fail("object expected");for(i=1;i<=count[n];i++)print quote(label[n,i])}
  else if(mode=="set") {
    if(path=="")root=other
    else {typ[n]=typ[other];val[n]=val[other];count[n]=count[other];for(i=1;i<=count[other];i++){child[n,i]=child[other,i];label[n,i]=label[other,i];member[n,label[n,i]]=child[n,i]}}
    print emit(root)
  }
  else if(mode=="append"){if(typ[n]!="array")fail("array expected");child[n,++count[n]]=other;label[n,count[n]]=count[n]-1;print emit(root)}
  else if(mode=="delete"){if(path=="")fail("cannot delete root");deleted[n]=1;print emit(root)}
  else if(mode=="equal"){exit equal(root,other)?0:1}
  else fail("unknown operation")
}
'
}
cj_quote() { printf '%s\n' "$1" | cj_run quote; }
cj_get() { printf '%s\n' "$1" | cj_run get "${2:-}"; }
cj_value() { printf '%s\n' "$1" | cj_run value "${2:-}"; }
cj_type() { printf '%s\n' "$1" | cj_run type "${2:-}"; }
cj_length() { printf '%s\n' "$1" | cj_run length "${2:-}"; }
cj_each() { printf '%s\n' "$1" | cj_run each "${2:-}"; }
cj_keys() { printf '%s\n' "$1" | cj_run keys "${2:-}"; }
cj_set() { printf '%s\n%s\n' "$1" "$3" | cj_run set "$2"; }
cj_append() { printf '%s\n%s\n' "$1" "$3" | cj_run append "$2"; }
cj_equal() { printf '%s\n%s\n' "$1" "$2" | cj_run equal; }
cj_delete() { printf '%s\n' "$1" | cj_run delete "$2"; }
