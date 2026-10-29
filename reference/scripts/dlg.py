import struct, glob, os, sys
R=sys.argv[1]
def wstr(b,o):
    e=o
    while b[e:e+2]!=b'\0\0': e+=2
    return b[o:e].decode('utf-16le'), e+2
def so(b,o):
    if b[o:o+2]==b'\xff\xff': return ('#%d'%struct.unpack_from('<H',b,o+2)[0]), o+4
    return wstr(b,o)
CLS={'#128':'BUTTON','#129':'EDIT','#130':'STATIC','#131':'LISTBOX','#132':'SCROLLBAR','#133':'COMBOBOX'}
def al(o): return (o+3)&~3
for f in sorted(glob.glob(f'{R}/DIALOG_*'), key=lambda x:int(x.split('_')[1])):
    b=open(f,'rb').read()
    ex = struct.unpack_from('<HH',b,0)==(1,0xFFFF)
    if ex:
        _,_,help,exst,style,n,x,y,cx,cy=struct.unpack_from('<HHIIIHhhhh',b,0); o=26
    else:
        style,exst,n,x,y,cx,cy=struct.unpack_from('<IIHhhhh',b,0); o=18
    menu,o=so(b,o); cls,o=so(b,o); title,o=wstr(b,o)
    font=''
    if style&0x40:
        if ex:
            pt,w,it,cs=struct.unpack_from('<HHBB',b,o); o+=6
        else:
            pt,=struct.unpack_from('<H',b,o); o+=2
        fn,o=wstr(b,o); font=f'{fn} {pt}'
    print(f'=== DIALOG {f.split("_")[1]} "{title}" {cx}x{cy} font={font} style={style:#x}')
    for i in range(n):
        o=al(o)
        if ex:
            hid,exs,st,x,y,cx,cy,id=struct.unpack_from('<IIIhhhhI',b,o); o+=24
        else:
            st,exs,x,y,cx,cy,id=struct.unpack_from('<IIhhhhH',b,o); o+=18
        c,o=so(b,o); t,o=so(b,o)
        ln,=struct.unpack_from('<H',b,o); o+=2+ln
        c=CLS.get(c,c)
        print(f'   {c:12s} id={id:<6d} ({x},{y},{cx},{cy}) st={st:#x} "{t}"')
