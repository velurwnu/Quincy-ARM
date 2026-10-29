import pefile, sys, os, struct
pe = pefile.PE(sys.argv[1]); out=sys.argv[2]
T={1:'CURSOR',2:'BITMAP',3:'ICON',4:'MENU',5:'DIALOG',6:'STRING',9:'ACCEL',12:'GROUP_CURSOR',14:'GROUP_ICON',16:'VERSION',241:'TOOLBAR',24:'MANIFEST'}
for t in pe.DIRECTORY_ENTRY_RESOURCE.entries:
    tn = T.get(t.id, str(t.name) if t.name else str(t.id))
    for n in t.directory.entries:
        nid = str(n.name) if n.name else str(n.id)
        for l in n.directory.entries:
            d=l.data.struct
            data=pe.get_data(d.OffsetToData,d.Size)
            fn=f"{out}/{tn}_{nid}_{l.id}.bin"
            open(fn,'wb').write(data)
            print(tn,nid,l.id,d.Size)
