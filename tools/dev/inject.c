// inject <pid> <dllpath>: LoadLibraryA the DLL inside a 32-bit process.
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    HANDLE p = OpenProcess(PROCESS_ALL_ACCESS, 0, atoi(argv[1]));
    if (!p) { printf("open fail %lu\n", GetLastError()); return 1; }
    SIZE_T n = strlen(argv[2]) + 1; void *m = VirtualAllocEx(p, 0, n, MEM_COMMIT, PAGE_READWRITE);
    WriteProcessMemory(p, m, argv[2], n, 0);
    HANDLE t = CreateRemoteThread(p, 0, 0, (LPTHREAD_START_ROUTINE)GetProcAddress(GetModuleHandleA("kernel32"), "LoadLibraryA"), m, 0, 0);
    WaitForSingleObject(t, 5000); DWORD ec; GetExitCodeThread(t, &ec); printf("LoadLibrary -> %08lx\n", ec);
    return 0;
}
