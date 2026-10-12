// peek <pid> <module> <offset-hex> <ndwords> [deref-index ...]
// Reads ndwords at module+offset; each extra arg i follows dword[i] as a pointer and dumps ndwords there.
#include <windows.h>
#include <psapi.h>
#include <stdio.h>
#include <stdlib.h>

static HANDLE p;
static void dump(DWORD a, int n, const char *tag) {
    DWORD buf[256]; SIZE_T rd = 0; if (n > 256) n = 256;
    printf("%s @%08x:", tag, a);
    if (!ReadProcessMemory(p, (void *)(UINT_PTR)a, buf, n * 4, &rd)) { printf(" <unreadable>\n"); return; }
    for (int i = 0; i < n; i++) printf("%s[%x]=%08x", i % 8 ? " " : "\n  ", i * 4, buf[i]);
    printf("\n");
}
int main(int argc, char **argv) {
    p = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, 0, atoi(argv[1]));
    HMODULE mods[512]; DWORD need; char nm[64]; DWORD base = 0;
    EnumProcessModulesEx(p, mods, sizeof mods, &need, LIST_MODULES_32BIT);
    for (unsigned i = 0; i < need / sizeof(HMODULE); i++) {
        GetModuleBaseNameA(p, mods[i], nm, 64);
        if (!_stricmp(nm, argv[2])) base = (DWORD)(UINT_PTR)mods[i];
    }
    if (!base) { printf("module not found\n"); return 1; }
    DWORD a = base + strtoul(argv[3], 0, 16); int n = atoi(argv[4]);
    DWORD ptr; SIZE_T rd; ReadProcessMemory(p, (void *)(UINT_PTR)a, &ptr, 4, &rd);
    printf("%s base %08x, [%08x] = %08x\n", argv[2], base, a, ptr);
    DWORD v[256]; ReadProcessMemory(p, (void *)(UINT_PTR)ptr, v, sizeof v, &rd);
    dump(ptr, n, "obj");
    for (int k = 5; k < argc; k++) { int i = strtol(argv[k], 0, 16); char t[32]; sprintf(t, "obj[%x]", i * 4); dump(v[i], n, t); }
    return 0;
}
