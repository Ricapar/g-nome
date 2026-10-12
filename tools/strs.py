import sys,re
n=int(sys.argv[1]); 
for p in sys.argv[2:]:
    d=open(p,'rb').read()
    for m in re.finditer(rb'[\x20-\x7e]{%d,}'%n,d): print(f"{p}:{m.start():08x}: {m.group().decode()}")
