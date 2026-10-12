// stacksample <pid> [samples] [interval_ms]: dump EIP + EBP-chain for every thread of a 32-bit process.
#include <windows.h>
#include <tlhelp32.h>
#include <psapi.h>
#include <stdio.h>
#include <stdlib.h>

static HMODULE mods[512]; static MODULEINFO mi[512]; static char names[512][64]; static int nmods;

static void load_mods(HANDLE p) {
    DWORD need; EnumProcessModulesEx(p, mods, sizeof mods, &need, LIST_MODULES_32BIT);
    nmods = need / sizeof(HMODULE); if (nmods > 512) nmods = 512;
    for (int i = 0; i < nmods; i++) {
        GetModuleInformation(p, mods[i], &mi[i], sizeof mi[i]);
        GetModuleBaseNameA(p, mods[i], names[i], 64);
    }
}
static void sym(DWORD a) {
    for (int i = 0; i < nmods; i++) {
        DWORD b = (DWORD)(UINT_PTR)mi[i].lpBaseOfDll;
        if (a >= b && a < b + mi[i].SizeOfImage) { printf(" %s+%x(%08x)", names[i], a - b, a); return; }
    }
    printf(" ?%08x", a);
}

int main(int argc, char **argv) {
    DWORD pid = atoi(argv[1]); int n = argc > 2 ? atoi(argv[2]) : 1, iv = argc > 3 ? atoi(argv[3]) : 200;
    HANDLE p = OpenProcess(PROCESS_ALL_ACCESS, 0, pid);
    if (!p) { printf("open fail %lu\n", GetLastError()); return 1; }
    load_mods(p);
    for (int s = 0; s < n; s++) {
        printf("--- sample %d\n", s);
        HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0); THREADENTRY32 te = { sizeof te };
        for (BOOL ok = Thread32First(snap, &te); ok; ok = Thread32Next(snap, &te)) {
            if (te.th32OwnerProcessID != pid) continue;
            HANDLE t = OpenThread(THREAD_ALL_ACCESS, 0, te.th32ThreadID); if (!t) continue;
            SuspendThread(t);
            CONTEXT c = { 0 }; c.ContextFlags = CONTEXT_FULL;
            if (GetThreadContext(t, &c)) {
                printf("tid %5lu:", te.th32ThreadID); sym(c.Eip);
                DWORD ebp = c.Ebp;
                for (int d = 0; d < 24 && ebp; d++) {
                    DWORD fr[2]; SIZE_T rd;
                    if (!ReadProcessMemory(p, (void *)(UINT_PTR)ebp, fr, 8, &rd) || fr[0] <= ebp) { if (ReadProcessMemory(p, (void *)(UINT_PTR)ebp, fr, 8, &rd)) sym(fr[1]); break; }
                    sym(fr[1]); ebp = fr[0];
                }
                printf("\n");
            }
            ResumeThread(t); CloseHandle(t);
        }
        CloseHandle(snap); Sleep(iv);
    }
    return 0;
}
