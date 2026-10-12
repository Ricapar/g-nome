import sys, pefile, datetime
for p in sys.argv[1:]:
    pe = pefile.PE(p)
    ts = datetime.datetime.utcfromtimestamp(pe.FILE_HEADER.TimeDateStamp)
    print(f"===== {p}  ts={ts}  linker={pe.OPTIONAL_HEADER.MajorLinkerVersion}.{pe.OPTIONAL_HEADER.MinorLinkerVersion} base={hex(pe.OPTIONAL_HEADER.ImageBase)} subsys={pe.OPTIONAL_HEADER.MajorSubsystemVersion}.{pe.OPTIONAL_HEADER.MinorSubsystemVersion}")
    for s in pe.sections: print(f"  sec {s.Name.rstrip(b'\0').decode():8} va={hex(s.VirtualAddress)} vs={hex(s.Misc_VirtualSize)} raw={hex(s.SizeOfRawData)} ch={hex(s.Characteristics)}")
    if hasattr(pe,'DIRECTORY_ENTRY_IMPORT'):
        for d in pe.DIRECTORY_ENTRY_IMPORT:
            names=[(i.name.decode() if i.name else f"#{i.ordinal}") for i in d.imports]
            print(f"  IMPORT {d.dll.decode()}: {', '.join(names)}")
    if hasattr(pe,'DIRECTORY_ENTRY_EXPORT'):
        ex=[(e.name.decode() if e.name else f"#{e.ordinal}") for e in pe.DIRECTORY_ENTRY_EXPORT.symbols]
        print(f"  EXPORTS({len(ex)}): {', '.join(ex[:400])}")
