# Pool the --bodies measurements of several runs (files of foot_check/body_check output): treading, bodies in the soil
# by what the ant does, diggers in the air.   python tools/dev/bodies_pool.py <file> [<file> ...]
import re,sys
d={}
for f in sys.argv[1:]:
    t=open(f,encoding='utf-8').read()
    for m in re.finditer(r'TREAD (.+?): legs stepping while the body stays put ([\d.]+)% of (\d+)',t):
        a=d.setdefault('tread '+m.group(1),[0,0]); a[0]+=float(m.group(2))/100*int(m.group(3)); a[1]+=int(m.group(3))
    for m in re.finditer(r'diggers in the air ([\d.]+)% of (\d+) digger-frames',t):
        a=d.setdefault('digger in the air',[0,0]); a[0]+=float(m.group(1))/100*int(m.group(2)); a[1]+=int(m.group(2))
    for m in re.finditer(r'\n\s+(nurse, narrow|resting|walking|meeting)\s+(\d+) ant-frames: skin\s+([\d.]+)%\s+deep\s+([\d.]+)%',t):
        for kind,i in (('skin',3),('deep',4)):
            a=d.setdefault('%s %s'%(m.group(1),kind),[0,0]); a[0]+=float(m.group(i))/100*int(m.group(2)); a[1]+=int(m.group(2))
for k,(x,n) in sorted(d.items()):
    print('%-28s %6.2f%%  of %d'%(k,100*x/max(1,n),n))
