import struct, glob, os, sys
R=sys.argv[1]
def wstr(b,o):
    e=o
    while b[e:e+2]!=b'\0\0': e+=2
    return b[o:e].decode('utf-16le'), e+2
def sz_or_ord(b,o):
    if b[o:o+2]==b'\xff\xff': return ('#%d'%struct.unpack_from('<H',b,o+2)[0]), o+4
    return wstr(b,o)
# MENU
b=open(f'{R}/MENU_128_1033.bin','rb').read()
o=4; depth=0; stack=[]
print("=== MENU")
def menu(b,o,ind):
    while True:
        fl,=struct.unpack_from('<H',b,o); o+=2
        if fl&0x10:
            s,o=wstr(b,o); print('  '*ind+'['+s+']'); o=menu(b,o,ind+1)
        else:
            id,=struct.unpack_from('<H',b,o); o+=2; s,o=wstr(b,o)
            print('  '*ind+(f'{id}: {s}' if s or id else '----'))
        if fl&0x80: return o
menu(b,4,0)
# ACCEL
VK={0x70+i:f'F{i+1}' for i in range(12)}; VK.update({0x2D:'Ins',0x2E:'Del',0x08:'Back',0x09:'Tab',0x0D:'Enter',0x1B:'Esc',0x21:'PgUp',0x22:'PgDn',0x23:'End',0x24:'Home',0x25:'Left',0x26:'Up',0x27:'Right',0x28:'Down'})
for f in sorted(glob.glob(f'{R}/ACCEL_*')):
    print('===',os.path.basename(f)); b=open(f,'rb').read()
    for i in range(0,len(b),8):
        fl,key,cmd,_=struct.unpack_from('<HHHH',b,i)
        m=('Ctrl+' if fl&8 else '')+('Shift+' if fl&4 else '')+('Alt+' if fl&16 else '')
        k=VK.get(key, chr(key) if 32<=key<127 else hex(key)) if fl&1 else repr(chr(key))
        print(f'  {cmd}: {m}{k}')
# STRING
print('=== STRINGS')
for f in sorted(glob.glob(f'{R}/STRING_*'), key=lambda x:int(x.split('_')[1])):
    blk=int(f.split('_')[1]); b=open(f,'rb').read(); o=0
    for i in range(16):
        n,=struct.unpack_from('<H',b,o); o+=2
        s=b[o:o+2*n].decode('utf-16le'); o+=2*n
        if s: print(f'  {(blk-1)*16+i}: {s!r}')
# TOOLBAR
b=open(f'{R}/TOOLBAR_128_1033.bin','rb').read()
v,w,h,n=struct.unpack_from('<HHHH',b,0)
print('=== TOOLBAR',w,h,[struct.unpack_from('<H',b,8+2*i)[0] for i in range(n)])
