// gtrace.dll: IAT-hooks GDI/USER imports of chosen modules and logs calls to gtrace.log.
#include <windows.h>
#include <stdio.h>
#include <intrin.h>

static int diag, flush; static FILE *lg; static CRITICAL_SECTION cs; static LONG counts[64];
#define LOG(...) do { EnterCriticalSection(&cs); fprintf(lg, "%lu ", GetTickCount()); fprintf(lg, __VA_ARGS__); fflush(lg); LeaveCriticalSection(&cs); } while (0)
static const char *who(void *ra) {
    static char b[8][32]; static int k; char *s = b[k++ & 7]; HMODULE m = 0;
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, ra, &m);
    char f[MAX_PATH] = "?"; if (m) GetModuleFileNameA(m, f, MAX_PATH); char *n = strrchr(f, 92); strncpy(s, n ? n + 1 : f, 31); s[31] = 0; return s;
}
static int limit(int id) { return InterlockedIncrement(&counts[id]) <= (getenv("GTRACE_MAX") ? atoi(getenv("GTRACE_MAX")) : 40); }

static const char *dck(HDC dc) {
    static char b[8][96]; static int k; char *s = b[k++ & 7];
    DWORD t = GetObjectType(dc); HWND w = WindowFromDC(dc); POINT o; GetViewportOrgEx(dc, &o);
    sprintf(s, "dc=%p(type%lu hwnd=%p vp=%ld,%ld bpp=%d)", dc, t, w, o.x, o.y, GetDeviceCaps(dc, BITSPIXEL));
    return s;
}

static BOOL (WINAPI *oBitBlt)(HDC, int, int, int, int, HDC, int, int, DWORD);
static BOOL WINAPI hBitBlt(HDC d, int x, int y, int w, int h, HDC s, int sx, int sy, DWORD r) {
    BOOL v = oBitBlt(d, x, y, w, h, s, sx, sy, r);
    if (limit(0)) LOG("[%s] BitBlt %s %d,%d %dx%d src=%s %d,%d rop=%lx -> %d\n", who(_ReturnAddress()), dck(d), x, y, w, h, dck(s), sx, sy, r, v);
    return v;
}
static BOOL (WINAPI *oStretchBlt)(HDC, int, int, int, int, HDC, int, int, int, int, DWORD);
static BOOL WINAPI hStretchBlt(HDC d, int x, int y, int w, int h, HDC s, int sx, int sy, int sw, int sh, DWORD r) {
    BOOL v = oStretchBlt(d, x, y, w, h, s, sx, sy, sw, sh, r);
    if (limit(1)) LOG("[%s] StretchBlt %s %d,%d %dx%d src=%s %d,%d %dx%d -> %d\n", who(_ReturnAddress()), dck(d), x, y, w, h, dck(s), sx, sy, sw, sh, v);
    return v;
}
static int (WINAPI *oStretchDIBits)(HDC, int, int, int, int, int, int, int, int, const void *, const BITMAPINFO *, UINT, DWORD);
static int WINAPI hStretchDIBits(HDC d, int x, int y, int w, int h, int sx, int sy, int sw, int sh, const void *bits, const BITMAPINFO *bi, UINT u, DWORD r) {
    x = (short)x; y = (short)y; // Win9x GDI truncated coords to 16 bits
    if (diag && counts[2] < 40) { HDC sdc = GetDC(NULL); LOG("  before: screen(319,219)=%06lx\n", GetPixel(sdc, 319, 219)); ReleaseDC(NULL, sdc); }
    static struct { BITMAPINFOHEADER h; RGBQUAD c[256]; } rgb;
    if (u == DIB_PAL_COLORS && bi->bmiHeader.biBitCount == 8) {
        // Resolve palette indices against the DC's logical palette ourselves.
        PALETTEENTRY pe[256] = { 0 }; HPALETTE hp = (HPALETTE)GetCurrentObject(d, OBJ_PAL);
        UINT n = GetPaletteEntries(hp, 0, 256, pe); const WORD *idx = (const WORD *)bi->bmiColors;
        rgb.h = bi->bmiHeader; rgb.h.biClrUsed = 256;
        for (int i = 0; i < 256; i++) { PALETTEENTRY *e = &pe[idx[i] & 255]; rgb.c[i].rgbRed = e->peRed; rgb.c[i].rgbGreen = e->peGreen; rgb.c[i].rgbBlue = e->peBlue; rgb.c[i].rgbReserved = 0; }
        if (limit(7)) LOG("  pal %p n=%u idx0..3=%u,%u,%u,%u e[1]=%02x%02x%02x e[100]=%02x%02x%02x e[200]=%02x%02x%02x\n", hp, n, idx[0], idx[1], idx[2], idx[3],
            pe[1].peRed, pe[1].peGreen, pe[1].peBlue, pe[100].peRed, pe[100].peGreen, pe[100].peBlue, pe[200].peRed, pe[200].peGreen, pe[200].peBlue);
        if (getenv("GTRACE_RGB")) { bi = (const BITMAPINFO *)&rgb; u = DIB_RGB_COLORS; }
    }
    int v = oStretchDIBits(d, x, y, w, h, sx, sy, sw, sh, bits, bi, u, r);
    if (flush) GdiFlush();
    if (getenv("GTRACE_READ")) { HDC sdc = GetDC(NULL); GetPixel(sdc, 0, 0); ReleaseDC(NULL, sdc); }
    if (getenv("GTRACE_ANIM")) {
        // Re-apply the DC's current palette entries unchanged to provoke a present.
        HPALETTE hp = (HPALETTE)GetCurrentObject(d, OBJ_PAL); PALETTEENTRY pe[256];
        UINT n = GetPaletteEntries(hp, 0, 256, pe); AnimatePalette(hp, 0, n, pe);
    }
    if (diag && counts[2] < 40 && bi->bmiHeader.biBitCount == 8) {
        int stride = (bi->bmiHeader.biWidth + 3) & ~3, H = abs(bi->bmiHeader.biHeight), nz = 0;
        for (int i = 0; i < stride * H; i++) nz += ((const BYTE *)bits)[i] != 0;
        COLORREF px = GetPixel(d, x + w / 2, y + h / 2);
        POINT sp0 = { x + w / 2, y + h / 2 }; LPtoDP(d, &sp0, 1); ClientToScreen(WindowFromDC(d), &sp0);
        HDC sdc = GetDC(NULL); COLORREF spx = GetPixel(sdc, sp0.x, sp0.y); ReleaseDC(NULL, sdc);
        LOG("  screen(%ld,%ld)=%06lx\n", sp0.x, sp0.y, spx);
        RECT cr; GetClipBox(d, &cr);
        PALETTEENTRY sp[256] = { 0 }; UINT sn = GetSystemPaletteEntries(d, 0, 256, sp); int snz = 0;
        for (int i = 0; i < 256; i++) snz += (sp[i].peRed | sp[i].peGreen | sp[i].peBlue) != 0;
        LOG("  syspal n=%u nonblack=%d e[1]=%02x%02x%02x e[100]=%02x%02x%02x use=%u\n", sn, snz, sp[1].peRed, sp[1].peGreen, sp[1].peBlue,
            sp[100].peRed, sp[100].peGreen, sp[100].peBlue, GetSystemPaletteUse(d));
        LOG("  nonzero src px=%d/%d pixel@center=%06lx clip=%ld,%ld,%ld,%ld fg=%p visible=%d\n", nz, stride * H, px, cr.left, cr.top, cr.right, cr.bottom,
            GetForegroundWindow(), IsWindowVisible(WindowFromDC(d)));
    }
    if (limit(2)) LOG("[%s] StretchDIBits %s %d,%d %dx%d src %d,%d %dx%d bi=%ldx%ld bpp%d usage=%u rop=%lx -> %d err=%lu\n", who(_ReturnAddress()), dck(d), x, y, w, h, sx, sy, sw, sh,
        bi->bmiHeader.biWidth, bi->bmiHeader.biHeight, bi->bmiHeader.biBitCount, u, r, v, GetLastError());
    return v;
}
static int (WINAPI *oSetDIBitsToDevice)(HDC, int, int, DWORD, DWORD, int, int, UINT, UINT, const void *, const BITMAPINFO *, UINT);
// Last full-screen (640x480) blit from rtlib32's screen buffer, replayed after palette animation (GTRACE_REPAINT).
static struct { HDC d; int x, y, sx, sy; UINT a, n; const void *bits; UINT u; struct { BITMAPINFOHEADER h; WORD idx[256]; } bi; } full;
static int WINAPI hSetDIBitsToDevice(HDC d, int x, int y, DWORD w, DWORD h, int sx, int sy, UINT a, UINT n, const void *bits, const BITMAPINFO *bi, UINT u) {
    int v = oSetDIBitsToDevice(d, x, y, w, h, sx, sy, a, n, bits, bi, u);
    if (w == 640 && h == 480 && u == DIB_PAL_COLORS && bi->bmiHeader.biBitCount == 8) {
        full.d = d; full.x = x; full.y = y; full.sx = sx; full.sy = sy; full.a = a; full.n = n; full.bits = bits; full.u = u;
        full.bi.h = bi->bmiHeader; memcpy(full.bi.idx, bi->bmiColors, sizeof full.bi.idx);
    }
    if (limit(3)) LOG("[%s] SetDIBitsToDevice %s %d,%d %lux%lu src %d,%d scan %u+%u bits=%p bi=%ldx%ld usage=%u -> %d\n", who(_ReturnAddress()), dck(d), x, y, w, h, sx, sy, a, n, bits,
        bi->bmiHeader.biWidth, bi->bmiHeader.biHeight, u, v);
    return v;
}
static void repaint_full(void) {
    if (full.bits && getenv("GTRACE_REPAINT"))
        oSetDIBitsToDevice(full.d, full.x, full.y, 640, 480, full.sx, full.sy, full.a, full.n, full.bits, (BITMAPINFO *)&full.bi, full.u);
}
static UINT (WINAPI *oRealizePalette)(HDC);
static UINT WINAPI hRealizePalette(HDC d) { UINT v = oRealizePalette(d); if (limit(4)) LOG("[%s] RealizePalette %s -> %u\n", who(_ReturnAddress()), dck(d), v); return v; }
static HPALETTE (WINAPI *oSelectPalette)(HDC, HPALETTE, BOOL);
static HPALETTE WINAPI hSelectPalette(HDC d, HPALETTE p, BOOL b) { HPALETTE v = oSelectPalette(d, p, b); if (limit(5)) LOG("[%s] SelectPalette %s pal=%p bk=%d -> %p\n", who(_ReturnAddress()), dck(d), p, b, v); return v; }
static HWND (WINAPI *oCreateWindowExA)(DWORD, LPCSTR, LPCSTR, DWORD, int, int, int, int, HWND, HMENU, HINSTANCE, LPVOID);
static HWND WINAPI hCreateWindowExA(DWORD ex, LPCSTR c, LPCSTR t, DWORD st, int x, int y, int w, int h, HWND p, HMENU m, HINSTANCE i, LPVOID l) {
    HWND v = oCreateWindowExA(ex, c, t, st, x, y, w, h, p, m, i, l);
    LOG("CreateWindowExA class=%s style=%lx %d,%d %dx%d parent=%p -> %p\n", HIWORD(c) ? c : "#atom", st, x, y, w, h, p, v);
    return v;
}
static HDC (WINAPI *oGetDC)(HWND);
static HDC WINAPI hGetDC(HWND w) { HDC v = oGetDC(w); if (limit(6)) LOG("GetDC hwnd=%p -> %p\n", w, v); return v; }
static BOOL (WINAPI *oShowWindow)(HWND, int);
static BOOL WINAPI hShowWindow(HWND w, int c) { BOOL v = oShowWindow(w, c); LOG("ShowWindow %p %d -> %d\n", w, c, v); return v; }


static BOOL (WINAPI *oAnimatePalette)(HPALETTE, UINT, UINT, const PALETTEENTRY *);
static BOOL WINAPI hAnimatePalette(HPALETTE p, UINT a, UINT n, const PALETTEENTRY *e) { BOOL v = oAnimatePalette(p, a, n, e); repaint_full(); if (limit(8)) LOG("[%s] AnimatePalette %p %u+%u -> %d\n", who(_ReturnAddress()), p, a, n, v); return v; }
static UINT (WINAPI *oSetDIBColorTable)(HDC, UINT, UINT, const RGBQUAD *);
static UINT WINAPI hSetDIBColorTable(HDC d, UINT a, UINT n, const RGBQUAD *c) { UINT v = oSetDIBColorTable(d, a, n, c); if (limit(9)) LOG("[%s] SetDIBColorTable %s %u+%u -> %u\n", who(_ReturnAddress()), dck(d), a, n, v); return v; }
static UINT (WINAPI *oSetPaletteEntries)(HPALETTE, UINT, UINT, const PALETTEENTRY *);
static UINT WINAPI hSetPaletteEntries(HPALETTE p, UINT a, UINT n, const PALETTEENTRY *e) { UINT v = oSetPaletteEntries(p, a, n, e); if (limit(10)) LOG("[%s] SetPaletteEntries %p %u+%u -> %u\n", who(_ReturnAddress()), p, a, n, v); return v; }
static BOOL (WINAPI *oInvalidateRect)(HWND, const RECT *, BOOL);
static BOOL WINAPI hInvalidateRect(HWND w, const RECT *r, BOOL e) { BOOL v = oInvalidateRect(w, r, e); if (limit(11)) LOG("[%s] InvalidateRect %p erase=%d\n", who(_ReturnAddress()), w, e); return v; }

static BOOL (WINAPI *oRedrawWindow)(HWND, const RECT *, HRGN, UINT);
static BOOL WINAPI hRedrawWindow(HWND w, const RECT *r, HRGN g, UINT f) { BOOL v = oRedrawWindow(w, r, g, f); if (limit(12)) LOG("[%s] RedrawWindow %p flags=%x\n", who(_ReturnAddress()), w, f); return v; }
static int (WINAPI *oFillRect)(HDC, const RECT *, HBRUSH);
static int WINAPI hFillRect(HDC d, const RECT *r, HBRUSH b) { int v = oFillRect(d, r, b); if (limit(13)) LOG("[%s] FillRect %s %ld,%ld-%ld,%ld\n", who(_ReturnAddress()), dck(d), r->left, r->top, r->right, r->bottom); return v; }
static BOOL (WINAPI *oPatBlt)(HDC, int, int, int, int, DWORD);
static BOOL WINAPI hPatBlt(HDC d, int x, int y, int w, int h, DWORD r) { BOOL v = oPatBlt(d, x, y, w, h, r); if (limit(14)) LOG("[%s] PatBlt %s %d,%d %dx%d rop=%lx\n", who(_ReturnAddress()), dck(d), x, y, w, h, r); return v; }
static LONG (WINAPI *oChangeDisplaySettingsA)(DEVMODEA *, DWORD);
static LONG WINAPI hChangeDisplaySettingsA(DEVMODEA *m, DWORD f) { LONG v = oChangeDisplaySettingsA(m, f); LOG("[%s] ChangeDisplaySettingsA %p f=%lx -> %ld\n", who(_ReturnAddress()), m, f, v); return v; }

static int (WINAPI *oDrawTextA)(HDC, LPCSTR, int, LPRECT, UINT);
static int WINAPI hDrawTextA(HDC d, LPCSTR s, int n, LPRECT r, UINT f) {
    int v = oDrawTextA(d, s, n, r, f);
    if (!(f & DT_CALCRECT) && limit(15)) {
        // rtlib32 text sprites: text color is PALETTEINDEX(i) when the "palette device" flag (*(DAT_10054788)+0x94cc) is set.
        BYTE *rt = (BYTE *)GetModuleHandleA("rtlib32.dll"); BYTE *g = rt ? *(BYTE **)(rt + 0x54788) : 0;
        COLORREF tc = GetTextColor(d); PALETTEENTRY pe = { 0 }; HPALETTE hp = (HPALETTE)GetCurrentObject(d, OBJ_PAL);
        if ((tc >> 24) == 1) GetPaletteEntries(hp, tc & 0xffff, 1, &pe);
        BITMAP bm = { 0 }; GetObjectA(GetCurrentObject(d, OBJ_BITMAP), sizeof bm, &bm);
        int lit = 0; for (int y = r->top; y < r->bottom; y++) for (int x = r->left; x < r->right; x++) lit += GetPixel(d, x, y) != 0;
        LOG("[%s] DrawTextA \"%.40s\" flag94cc=%d textcolor=%08lx palentry=%02x%02x%02x bmp=%ldx%ld@%dbpp lit=%d\n", who(_ReturnAddress()), s, g ? g[0x94cc] : -1, tc,
            pe.peRed, pe.peGreen, pe.peBlue, bm.bmWidth, bm.bmHeight, bm.bmBitsPixel, lit);
    }
    return v;
}

struct hk { const char *name; void *hook; void **orig; };
static struct hk hooks[] = {
    { "BitBlt", hBitBlt, (void **)&oBitBlt }, { "StretchBlt", hStretchBlt, (void **)&oStretchBlt },
    { "StretchDIBits", hStretchDIBits, (void **)&oStretchDIBits }, { "SetDIBitsToDevice", hSetDIBitsToDevice, (void **)&oSetDIBitsToDevice },
    { "RealizePalette", hRealizePalette, (void **)&oRealizePalette }, { "SelectPalette", hSelectPalette, (void **)&oSelectPalette },
    { "CreateWindowExA", hCreateWindowExA, (void **)&oCreateWindowExA }, { "GetDC", hGetDC, (void **)&oGetDC },
    { "ShowWindow", hShowWindow, (void **)&oShowWindow },
    { "AnimatePalette", hAnimatePalette, (void **)&oAnimatePalette }, { "SetDIBColorTable", hSetDIBColorTable, (void **)&oSetDIBColorTable },
    { "SetPaletteEntries", hSetPaletteEntries, (void **)&oSetPaletteEntries }, { "InvalidateRect", hInvalidateRect, (void **)&oInvalidateRect },
    { "RedrawWindow", hRedrawWindow, (void **)&oRedrawWindow }, { "FillRect", hFillRect, (void **)&oFillRect },
    { "PatBlt", hPatBlt, (void **)&oPatBlt }, { "DrawTextA", hDrawTextA, (void **)&oDrawTextA }, { "ChangeDisplaySettingsA", hChangeDisplaySettingsA, (void **)&oChangeDisplaySettingsA },
};

static void patch_module(HMODULE m);
// --- window messages, crash capture, CRT stream-table watch (rtlib32 __piob @+0x60ab8, _nstream @+0x61ac0) ---
static const char *msgname(UINT m) {
    switch (m) {
    case 0x0005: return "WM_SIZE"; case 0x0003: return "WM_MOVE"; case 0x0006: return "WM_ACTIVATE"; case 0x0007: return "WM_SETFOCUS";
    case 0x0008: return "WM_KILLFOCUS"; case 0x000F: return "WM_PAINT"; case 0x0010: return "WM_CLOSE"; case 0x0012: return "WM_QUIT";
    case 0x0014: return "WM_ERASEBKGND"; case 0x0018: return "WM_SHOWWINDOW"; case 0x001C: return "WM_ACTIVATEAPP"; case 0x0046: return "WM_WINDOWPOSCHANGING";
    case 0x0047: return "WM_WINDOWPOSCHANGED"; case 0x007E: return "WM_DISPLAYCHANGE"; case 0x0085: return "WM_NCPAINT"; case 0x0086: return "WM_NCACTIVATE";
    case 0x0002: return "WM_DESTROY"; case 0x0011: return "WM_QUERYENDSESSION"; case 0x0016: return "WM_ENDSESSION"; case 0x0112: return "WM_SYSCOMMAND";
    case 0x030F: return "WM_QUERYNEWPALETTE"; case 0x0310: return "WM_PALETTEISCHANGING"; case 0x0311: return "WM_PALETTECHANGED";
    case 0x0318: return "WM_PRINTCLIENT"; case 0x031A: return "WM_THEMECHANGED"; case 0x02E0: return "WM_DPICHANGED";
    } return 0;
}
static LONG mcount[0x400];
static LRESULT CALLBACK cwpret(int c, WPARAM w, LPARAM l) {
    CWPRETSTRUCT *s = (CWPRETSTRUCT *)l; const char *n = s->message < 0x400 ? msgname(s->message) : 0;
    if (c >= 0 && n && InterlockedIncrement(&mcount[s->message]) <= 300) {
        RECT ur = { 0 }; GetUpdateRect(s->hwnd, &ur, FALSE);
        LOG("msg %s hwnd=%p w=%lx l=%lx -> %lx upd=%ld,%ld-%ld,%ld\n", n, s->hwnd, (DWORD)s->wParam, (DWORD)s->lParam, (DWORD)s->lResult, ur.left, ur.top, ur.right, ur.bottom);
    }
    return CallNextHookEx(0, c, w, l);
}
static LRESULT CALLBACK getmsg(int c, WPARAM w, LPARAM l) {
    MSG *m = (MSG *)l; const char *n = m->message < 0x400 ? msgname(m->message) : 0;
    if (c >= 0 && w == PM_REMOVE && n && InterlockedIncrement(&mcount[m->message]) <= 300) LOG("posted %s hwnd=%p w=%lx l=%lx\n", n, m->hwnd, (DWORD)m->wParam, (DWORD)m->lParam);
    return CallNextHookEx(0, c, w, l);
}
static LONG CALLBACK veh(EXCEPTION_POINTERS *e) {
    DWORD code = e->ExceptionRecord->ExceptionCode;
    if (code != EXCEPTION_ACCESS_VIOLATION) return EXCEPTION_CONTINUE_SEARCH;
    CONTEXT *c = e->ContextRecord; BYTE *rt = (BYTE *)GetModuleHandleA("rtlib32.dll");
    LOG("EXCEPTION %08lx at %p [%s] rw=%lu addr=%p eax=%08lx ebx=%08lx ecx=%08lx edx=%08lx esi=%08lx edi=%08lx ebp=%08lx esp=%08lx\n", code, (void *)c->Eip,
        who((void *)c->Eip), (DWORD)e->ExceptionRecord->ExceptionInformation[0], (void *)e->ExceptionRecord->ExceptionInformation[1], c->Eax, c->Ebx, c->Ecx, c->Edx, c->Esi, c->Edi, c->Ebp, c->Esp);
    if (rt) LOG("  piob=%08lx nstream=%ld\n", *(DWORD *)(rt + 0x60ab8), *(LONG *)(rt + 0x61ac0));
    DWORD *sp = (DWORD *)c->Esp; MEMORY_BASIC_INFORMATION mi;
    for (int i = 0; i < 1024; i++) {
        if (IsBadReadPtr(sp + i, 4)) break;
        DWORD v = sp[i]; HMODULE m = 0;
        if (v > 0x10000 && GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (void *)v, &m) && m &&
            VirtualQuery((void *)v, &mi, sizeof mi) && (mi.Protect & (PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE)))
            LOG("  stack+%03x %08lx %s+%lx\n", i * 4, v, who((void *)v), v - (DWORD)(UINT_PTR)m);
    }
    return EXCEPTION_CONTINUE_SEARCH;
}
static BOOL CALLBACK findwin(HWND h, LPARAM l) {
    DWORD pid; GetWindowThreadProcessId(h, &pid); char cls[64];
    if (pid == GetCurrentProcessId() && IsWindowVisible(h) && GetClassNameA(h, cls, 64)) { *(HWND *)l = h; LOG("window %p class=%s\n", h, cls); return FALSE; }
    return TRUE;
}
static DWORD WINAPI worker(LPVOID x) {
    HWND w = 0;
    for (int i = 0; i < 100 && !w; i++) { EnumWindows(findwin, (LPARAM)&w); if (!w) Sleep(100); }
    if (w) {
        DWORD tid = GetWindowThreadProcessId(w, 0); HMODULE self; GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, (LPCSTR)worker, &self);
        HHOOK a = SetWindowsHookExA(WH_CALLWNDPROCRET, cwpret, self, tid), b = SetWindowsHookExA(WH_GETMESSAGE, getmsg, self, tid);
        LOG("hooks on tid %lu: %p %p\n", tid, a, b);
    }
    BYTE *rt = (BYTE *)GetModuleHandleA("rtlib32.dll"); DWORD lp = 1; LONG ln = -1;
    for (;;) {
        DWORD p = *(volatile DWORD *)(rt + 0x60ab8); LONG n = *(volatile LONG *)(rt + 0x61ac0);
        if (p != lp || n != ln) { LOG("crt piob=%08lx nstream=%ld\n", p, n); lp = p; ln = n; }
        static const char *mods[] = { "render.r32", "rwl20.dll", "rwdl8d20.dll", "netgn.r32" }; static HMODULE done[4];
        for (int i = 0; i < 4; i++) { HMODULE m = GetModuleHandleA(mods[i]); if (m && !done[i]) { done[i] = m; LOG("late module %s = %p\n", mods[i], m); patch_module(m); } }
        Sleep(50);
    }
}

static void patch_module(HMODULE m) {
    BYTE *b = (BYTE *)m; IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(b + ((IMAGE_DOS_HEADER *)b)->e_lfanew);
    IMAGE_DATA_DIRECTORY dd = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    for (IMAGE_IMPORT_DESCRIPTOR *d = (void *)(b + dd.VirtualAddress); d->Name; d++) {
        IMAGE_THUNK_DATA *ot = (void *)(b + (d->OriginalFirstThunk ? d->OriginalFirstThunk : d->FirstThunk)), *ft = (void *)(b + d->FirstThunk);
        HMODULE dll = GetModuleHandleA((char *)b + d->Name);
        for (; ot->u1.AddressOfData; ot++, ft++) {
            if (IMAGE_SNAP_BY_ORDINAL(ot->u1.Ordinal)) continue;
            const char *n = ((IMAGE_IMPORT_BY_NAME *)(b + ot->u1.AddressOfData))->Name;
            for (int i = 0; i < sizeof hooks / sizeof *hooks; i++) if (!strcmp(n, hooks[i].name)) {
                if (!*hooks[i].orig) *hooks[i].orig = (void *)GetProcAddress(dll, n);
                DWORD op; VirtualProtect(&ft->u1.Function, 4, PAGE_READWRITE, &op);
                ft->u1.Function = (DWORD)(UINT_PTR)hooks[i].hook; VirtualProtect(&ft->u1.Function, 4, op, &op);
            }
        }
    }
}

BOOL WINAPI DllMain(HINSTANCE h, DWORD r, LPVOID x) {
    if (r == DLL_PROCESS_ATTACH) {
        char p[MAX_PATH]; GetModuleFileNameA(h, p, MAX_PATH); strcpy(strrchr(p, '\\') + 1, "gtrace.log");
        diag = !!getenv("GTRACE_DIAG"); flush = !!getenv("GTRACE_FLUSH");
        lg = fopen(p, "w"); InitializeCriticalSection(&cs);
        const char *mods[] = { "smackw32.dll", "rtlib32.dll", "smacker.r32" };
        for (int i = 0; i < 3; i++) { HMODULE m = GetModuleHandleA(mods[i]); LOG("module %s = %p\n", mods[i], m); if (m) patch_module(m); }
        AddVectoredExceptionHandler(1, veh);
        CreateThread(0, 0, worker, 0, 0, 0);
    }
    return TRUE;
}
