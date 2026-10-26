#!/usr/bin/env python3
"""Zero-dep BM25 over skill name + description + More triggers + original description. Usage: retriever.py "prompt" [k]"""
import os,re,glob,math,sys,collections,time
H=os.path.expanduser('~')
tok=lambda s:[w for w in re.findall(r'[a-z0-9#]+',s.lower()) if len(w)>1 and w not in STOP]
STOP=set('the a an to of and or in on for with my me i is it this that be can do how what use when you your from by at as are not into run show make'.split())
def docs():
    out={}
    root=os.path.expanduser(os.environ.get('SKILLS_DIR') or H+'/.claude/skills')
    for f in glob.glob(root+'/*/SKILL.md'):
        n=f.split('/')[-2];t=open(f,errors='ignore').read()
        m=re.match(r'---\n(.*?)\n---(.*)',t,re.S)
        fm,body=(m.group(1),m.group(2)) if m else ('',t)
        more=re.search(r'## More triggers\n(.*?)(?=\n# |\n## (?!More)|\Z)',body,re.S)
        out[n]=(n.replace('-',' ')+' ')*3+fm+' '+(more.group(1) if more else '')
    return out
def rank(q,D,k=3,k1=1.4,b=0.75):
    T={n:tok(d) for n,d in D.items()};N=len(T);avg=sum(map(len,T.values()))/N
    df=collections.Counter(w for t in T.values() for w in set(t));qs=tok(q);S={}
    for n,t in T.items():
        tf=collections.Counter(t);s=0
        for w in qs:
            if w in tf: s+=math.log(1+(N-df[w]+.5)/(df[w]+.5))*tf[w]*(k1+1)/(tf[w]+k1*(1-b+b*len(t)/avg))
        S[n]=s
    return sorted(S.items(),key=lambda x:-x[1])[:k]
if __name__=='__main__':
    t=time.time();D=docs();r=rank(sys.argv[1],D,int(sys.argv[2]) if len(sys.argv)>2 else 3)
    print(r,f'{(time.time()-t)*1000:.0f}ms')
