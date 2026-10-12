// gnomefix: ddraw.dll proxy that makes G-Nome (7th Level, 1997) run well on modern Windows.
//
// RTLIB32.DLL statically imports DirectDrawCreate (used only to change the display mode),
// so placing this DLL in the game directory gets it loaded before the game draws anything.
// On load we patch the import tables of the game's modules (and of plugins as they load).
//
// Rendering fixes (always on):
// 1. Palette fades. RTLIB fades with AnimatePalette. On a real 8-bit display that recolors
//    pixels already on screen; under Windows 8+'s 8-bit emulation (and on true-color
//    screens) pixels keep their draw-time color, so art drawn during a fade stays black.
//    RTLIB composes every frame in one persistent 640x480 buffer and blits dirty rects from
//    it, so we remember its last full-screen blit and replay it after each AnimatePalette.
// 2. Text sprites. RTLIB draws text with DrawTextA into a screen-compatible bitmap and reads
//    it back with GetDIBits(DIB_PAL_COLORS). Both steps go through RGB using the current,
//    possibly faded-to-black, palette, so text created during a fade (HUD weapon names)
//    vanishes. We render the text into a private mask and write the exact indices Win9x
//    produced (text color, or 255 for the white-on-black path; 0 elsewhere).
//
// Options, from [gnomefix] in 7THLEVEL.INI (the game's own INI):
//   DrawDistance=100   percent; scales the far clip plane and fog distance set by missions
//   Display=0          0 = original 640x480 full-screen mode switch
//                      1 = window, 2 = borderless full screen (desktop resolution)
//   Scale=0            Display=1/2: integer zoom of the 640x480 image; 0 = largest that fits
//   Stretch=0          Display=2: 1 = fill the screen keeping 4:3 (non-integer zoom)
//   Smooth=0           1 = filtered (HALFTONE) instead of sharp pixel scaling
//   IdleSleep=1        wait for input instead of spinning when the game is idle (saves a CPU core)
//
// Windowed mode gives the game a 640x480 off-screen "virtual screen" DC instead of its
// window DC, reports a 640x480 screen through GetSystemMetrics (RTLIB centres its
// coordinate system on it) and a 640x480x8 palette device through GetDeviceCaps /
// GetSystemPaletteEntries (so every module takes its original 8-bit code path), turns the
// DirectDraw mode switch into a no-op, and presents the virtual screen scaled into the
// window from a background thread. Mouse messages, cursor positions and paint/invalidate
// rectangles are translated between the two.
#include <windows.h>
#include <intrin.h>

#define VW 640
#define VH 480

static struct { int drawdist, display, scale, stretch, smooth, idlesleep; } cfg;

static void logf(const char *fmt, ...) {
    char p[MAX_PATH], b[512]; va_list a; DWORD n;
    if (!GetTempPathA(MAX_PATH, p)) return;
    lstrcatA(p, "gnomefix.log");
    va_start(a, fmt); n = wvsprintfA(b, fmt, a); va_end(a);
    HANDLE h = CreateFileA(p, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, 0, OPEN_ALWAYS, 0, 0);
    if (h != INVALID_HANDLE_VALUE) { WriteFile(h, b, n, &n, 0); CloseHandle(h); }
}

static void load_config(void) {
    cfg.drawdist = GetPrivateProfileIntA("gnomefix", "DrawDistance", 100, "7THLEVEL.INI");
    cfg.display = GetPrivateProfileIntA("gnomefix", "Display", 0, "7THLEVEL.INI");
    cfg.scale = GetPrivateProfileIntA("gnomefix", "Scale", 0, "7THLEVEL.INI");
    cfg.stretch = GetPrivateProfileIntA("gnomefix", "Stretch", 0, "7THLEVEL.INI");
    cfg.smooth = GetPrivateProfileIntA("gnomefix", "Smooth", 0, "7THLEVEL.INI");
    cfg.idlesleep = GetPrivateProfileIntA("gnomefix", "IdleSleep", 1, "7THLEVEL.INI");
    if (cfg.drawdist < 10) cfg.drawdist = 10;
    if (cfg.display < 0 || cfg.display > 2) cfg.display = 0;
    logf("gnomefix: DrawDistance=%d Display=%d Scale=%d Stretch=%d Smooth=%d IdleSleep=%d\r\n",
         cfg.drawdist, cfg.display, cfg.scale, cfg.stretch, cfg.smooth, cfg.idlesleep);
}

// ===================================================================== rendering fixes
static int (WINAPI *oSetDIBitsToDevice)(HDC, int, int, DWORD, DWORD, int, int, UINT, UINT, const void *, const BITMAPINFO *, UINT);

static BOOL (WINAPI *oAnimatePalette)(HPALETTE, UINT, UINT, const PALETTEENTRY *);
static struct { HDC dc; int x, y, sx, sy; UINT start, lines; const void *bits; struct { BITMAPINFOHEADER h; WORD idx[256]; } bi; } full;

static int WINAPI hSetDIBitsToDevice(HDC dc, int x, int y, DWORD w, DWORD h, int sx, int sy, UINT start, UINT lines,
                                     const void *bits, const BITMAPINFO *bi, UINT usage) {
    if (w == VW && h == VH && usage == DIB_PAL_COLORS && bi->bmiHeader.biBitCount == 8) {
        full.dc = dc; full.x = x; full.y = y; full.sx = sx; full.sy = sy; full.start = start; full.lines = lines; full.bits = bits;
        full.bi.h = bi->bmiHeader; CopyMemory(full.bi.idx, bi->bmiColors, sizeof full.bi.idx);
    }
    return oSetDIBitsToDevice(dc, x, y, w, h, sx, sy, start, lines, bits, bi, usage);
}

static BOOL WINAPI hAnimatePalette(HPALETTE pal, UINT first, UINT n, const PALETTEENTRY *e) {
    BOOL r = oAnimatePalette(pal, first, n, e);
    if (full.bits)
        oSetDIBitsToDevice(full.dc, full.x, full.y, VW, VH, full.sx, full.sy, full.start, full.lines, full.bits,
                           (const BITMAPINFO *)&full.bi, DIB_PAL_COLORS);
    return r;
}

static int (WINAPI *oDrawTextA)(HDC, LPCSTR, int, LPRECT, UINT);
static int (WINAPI *oGetDIBits)(HDC, HBITMAP, UINT, UINT, LPVOID, LPBITMAPINFO, UINT);
static struct text { HBITMAP bmp; int w, h; BYTE color; BYTE *mask; } texts[16];
static int ntext;

static int WINAPI hDrawTextA(HDC dc, LPCSTR s, int n, LPRECT rc, UINT fmt) {
    int r = oDrawTextA(dc, s, n, rc, fmt);
    COLORREF tc = GetTextColor(dc);
    HBITMAP bmp = (HBITMAP)GetCurrentObject(dc, OBJ_BITMAP); BITMAP bm;
    // RTLIB's text-sprite path: PALETTEINDEX(c) text on a palette device, white text otherwise.
    if ((fmt & DT_CALCRECT) || GetObjectType(dc) != OBJ_MEMDC || !GetObjectA(bmp, sizeof bm, &bm) ||
        ((tc >> 24) != 1 && tc != RGB(255, 255, 255)))
        return r;
    BITMAPINFO bi = { { sizeof(BITMAPINFOHEADER), bm.bmWidth, -bm.bmHeight, 1, 32, BI_RGB } };
    DWORD *px; HDC mdc = CreateCompatibleDC(0);
    HBITMAP mbmp = CreateDIBSection(mdc, &bi, DIB_RGB_COLORS, (void **)&px, 0, 0);
    LOGFONTA lf; HFONT font = 0;
    if (GetObjectA(GetCurrentObject(dc, OBJ_FONT), sizeof lf, &lf)) { lf.lfQuality = NONANTIALIASED_QUALITY; font = CreateFontIndirectA(&lf); }
    if (mdc && mbmp) {
        HGDIOBJ ob = SelectObject(mdc, mbmp), of = font ? SelectObject(mdc, font) : 0;
        RECT mr = *rc;
        SetTextColor(mdc, RGB(255, 255, 255)); SetBkMode(mdc, TRANSPARENT);
        oDrawTextA(mdc, s, n, &mr, fmt);
        GdiFlush();
        struct text *t = &texts[ntext++ % 16];
        if (t->mask) HeapFree(GetProcessHeap(), 0, t->mask);
        t->bmp = bmp; t->w = bm.bmWidth; t->h = bm.bmHeight; t->color = (tc >> 24) == 1 ? (BYTE)(tc & 0xff) : 255;
        t->mask = HeapAlloc(GetProcessHeap(), 0, (SIZE_T)t->w * t->h);
        if (t->mask) for (int i = 0; i < t->w * t->h; i++) t->mask[i] = (px[i] & 0x808080) != 0;
        if (of) SelectObject(mdc, of);
        SelectObject(mdc, ob);
    }
    if (font) DeleteObject(font);
    if (mbmp) DeleteObject(mbmp);
    if (mdc) DeleteDC(mdc);
    return r;
}

static int WINAPI hGetDIBits(HDC dc, HBITMAP bmp, UINT start, UINT lines, LPVOID bits, LPBITMAPINFO bi, UINT usage) {
    int r = oGetDIBits(dc, bmp, start, lines, bits, bi, usage);
    if (!bits || bi->bmiHeader.biBitCount != 8 || start != 0) return r;
    for (int k = 0; k < 16; k++) {
        struct text *t = &texts[k];
        if (t->bmp != bmp || !t->mask) continue;
        if (bi->bmiHeader.biWidth == t->w && (int)lines == t->h) {
            int stride = (t->w + 3) & ~3, bottomup = bi->bmiHeader.biHeight > 0;
            for (int y = 0; y < t->h; y++) {
                BYTE *row = (BYTE *)bits + (bottomup ? t->h - 1 - y : y) * stride;
                for (int x = 0; x < t->w; x++) row[x] = t->mask[y * t->w + x] ? t->color : 0;
            }
        }
        HeapFree(GetProcessHeap(), 0, t->mask); t->mask = 0; t->bmp = 0;
        break;
    }
    return r;
}

// ===================================================================== draw distance
// RENDER.R32 natives called by mission scripts (cdecl, first arg is the script context).
static int (__cdecl *oSetCameraClipping)(void *, int, int);
static int (__cdecl *oSetFogDepthColor)(void *, int, int, int, int);
static int __cdecl hSetCameraClipping(void *ctx, int nearz, int farz) {
    logf("gnomefix: SetCameraClipping near=%d far=%d -> %d\r\n", nearz, farz, MulDiv(farz, cfg.drawdist, 100));
    return oSetCameraClipping(ctx, nearz, MulDiv(farz, cfg.drawdist, 100));
}
static int __cdecl hSetFogDepthColor(void *ctx, int dist, int r, int g, int b) {
    logf("gnomefix: SetFogDepthColor dist=%d rgb=%d,%d,%d -> %d\r\n", dist, r, g, b, dist > 0 ? MulDiv(dist, cfg.drawdist, 100) : dist);
    return oSetFogDepthColor(ctx, dist > 0 ? MulDiv(dist, cfg.drawdist, 100) : dist, r, g, b);
}

static FARPROC (WINAPI *oGetProcAddress)(HMODULE, LPCSTR);
static FARPROC WINAPI hGetProcAddress(HMODULE m, LPCSTR name) {
    FARPROC f = oGetProcAddress(m, name);
    if (!f || !HIWORD(name) || cfg.drawdist == 100) return f;
    if (!lstrcmpA(name, "SetCameraClipping")) { oSetCameraClipping = (void *)f; return (FARPROC)hSetCameraClipping; }
    if (!lstrcmpA(name, "SetFogDepthColor")) { oSetFogDepthColor = (void *)f; return (FARPROC)hSetFogDepthColor; }
    return f;
}

// ===================================================================== windowed mode
static HWND gamewnd;          // RTLIB's VIEW_CLASS window
static HDC vdc;               // virtual 640x480 screen handed to the game
static DWORD *vbits;
static volatile LONG vpaint;  // game is between BeginPaint/EndPaint on the window

// Placement of the 640x480 image inside the window client area.
static void layout(RECT *dst) {
    RECT c; GetClientRect(gamewnd, &c);
    int cw = c.right, ch = c.bottom, w, h;
    if (cfg.display == 2 && cfg.stretch) {
        if (cw * VH > ch * VW) { h = ch; w = MulDiv(ch, VW, VH); } else { w = cw; h = MulDiv(cw, VH, VW); }
    } else {
        int k = cfg.scale;
        if (k <= 0) { k = cw / VW < ch / VH ? cw / VW : ch / VH; }
        if (k < 1) k = 1;
        w = VW * k; h = VH * k;
    }
    dst->left = (cw - w) / 2; dst->top = (ch - h) / 2; dst->right = dst->left + w; dst->bottom = dst->top + h;
}
static POINT to_virtual(POINT p) {   // window client -> virtual screen
    RECT d; layout(&d);
    POINT v = { MulDiv(p.x - d.left, VW, d.right - d.left), MulDiv(p.y - d.top, VH, d.bottom - d.top) };
    if (v.x < 0) v.x = 0; if (v.x >= VW) v.x = VW - 1;
    if (v.y < 0) v.y = 0; if (v.y >= VH) v.y = VH - 1;
    return v;
}
static POINT to_client(POINT v) {    // virtual screen -> window client
    RECT d; layout(&d);
    POINT p = { d.left + MulDiv(v.x, d.right - d.left, VW), d.top + MulDiv(v.y, d.bottom - d.top, VH) };
    return p;
}
static RECT rect_to_client(const RECT *r) {
    POINT a = { r->left, r->top }, b = { r->right, r->bottom };
    a = to_client(a); b = to_client(b);
    RECT o = { a.x, a.y, b.x, b.y }; return o;
}

static void present(HDC wdc) {
    RECT c, d; GetClientRect(gamewnd, &c); layout(&d);
    BITMAPINFO bi = { { sizeof(BITMAPINFOHEADER), VW, -VH, 1, 32, BI_RGB } };
    if (d.top > 0) { PatBlt(wdc, 0, 0, c.right, d.top, BLACKNESS); PatBlt(wdc, 0, d.bottom, c.right, c.bottom - d.bottom, BLACKNESS); }
    if (d.left > 0) { PatBlt(wdc, 0, d.top, d.left, d.bottom - d.top, BLACKNESS); PatBlt(wdc, d.right, d.top, c.right - d.right, d.bottom - d.top, BLACKNESS); }
    SetStretchBltMode(wdc, cfg.smooth ? HALFTONE : COLORONCOLOR);
    if (cfg.smooth) SetBrushOrgEx(wdc, 0, 0, 0);
    StretchDIBits(wdc, d.left, d.top, d.right - d.left, d.bottom - d.top, 0, 0, VW, VH, vbits, &bi, DIB_RGB_COLORS, SRCCOPY);
}

static DWORD WINAPI presenter(LPVOID x) {
    for (;;) {
        Sleep(15);
        if (!IsWindow(gamewnd)) { if (gamewnd) break; continue; }
        if (IsIconic(gamewnd)) continue;
        HDC wdc = GetDC(gamewnd);
        if (wdc) { present(wdc); ReleaseDC(gamewnd, wdc); }
    }
    return 0;
}

static HDC virtual_dc(HDC like) {
    if (!vdc) {
        BITMAPINFO bi = { { sizeof(BITMAPINFOHEADER), VW, -VH, 1, 32, BI_RGB } };
        vdc = CreateCompatibleDC(like);
        HBITMAP b = CreateDIBSection(vdc, &bi, DIB_RGB_COLORS, (void **)&vbits, 0, 0);
        SelectObject(vdc, b);
        CreateThread(0, 0, presenter, 0, 0, 0);
    }
    return vdc;
}

// --- fake DirectDraw: RTLIB only sets the cooperative level and display mode ---
typedef struct FakeDD { void **vtbl; LONG ref; } FakeDD;
static HRESULT WINAPI dd_QI(FakeDD *t, REFIID i, void **o) { *o = 0; return E_NOINTERFACE; }
static ULONG WINAPI dd_AddRef(FakeDD *t) { return InterlockedIncrement(&t->ref); }
static ULONG WINAPI dd_Release(FakeDD *t) { LONG r = InterlockedDecrement(&t->ref); if (!r) HeapFree(GetProcessHeap(), 0, t); return r; }
static HRESULT WINAPI dd_Compact(FakeDD *t) { return S_OK; }
static HRESULT WINAPI dd_3(FakeDD *t, void *a, void *b, void *c) { return E_NOTIMPL; }       // CreateClipper
static HRESULT WINAPI dd_4(FakeDD *t, void *a, void *b, void *c, void *d) { return E_NOTIMPL; } // CreatePalette
typedef HRESULT (WINAPI *ENUMMODES)(void *desc, void *ctx);
static HRESULT WINAPI dd_EnumDisplayModes(FakeDD *t, DWORD fl, void *desc, void *ctx, ENUMMODES cb) {
    DWORD d[27] = { 108, 0x1006 /*HEIGHT|WIDTH|PIXELFORMAT*/, VH, VW };   // DDSURFACEDESC
    d[18] = 32; d[19] = 0x60 /*DDPF_RGB|DDPF_PALETTEINDEXED8*/; d[21] = 8;    // ddpfPixelFormat
    cb(d, ctx); return S_OK;
}
static HRESULT WINAPI dd_1(FakeDD *t, void *a) { return E_NOTIMPL; }
static HRESULT WINAPI dd_2(FakeDD *t, void *a, void *b) { return E_NOTIMPL; }
static HRESULT WINAPI dd_0(FakeDD *t) { return S_OK; }
static HRESULT WINAPI dd_GetCaps(FakeDD *t, void *a, void *b) { return E_NOTIMPL; }
static HRESULT WINAPI dd_SetCoop(FakeDD *t, HWND w, DWORD fl) { return S_OK; }
static HRESULT WINAPI dd_SetMode(FakeDD *t, DWORD w, DWORD h, DWORD bpp) { return S_OK; }
static HRESULT WINAPI dd_WaitVB(FakeDD *t, DWORD fl, HANDLE e) { return S_OK; }
static void *fake_vtbl[] = {
    dd_QI, dd_AddRef, dd_Release, dd_Compact, dd_3 /*CreateClipper*/, dd_4 /*CreatePalette*/,
    dd_3 /*CreateSurface*/, dd_2 /*DuplicateSurface*/, dd_EnumDisplayModes, dd_4 /*EnumSurfaces*/,
    dd_0 /*FlipToGDISurface*/, dd_GetCaps, dd_1 /*GetDisplayMode*/, dd_2 /*GetFourCCCodes*/,
    dd_1 /*GetGDISurface*/, dd_1 /*GetMonitorFrequency*/, dd_1 /*GetScanLine*/, dd_1 /*GetVerticalBlankStatus*/,
    dd_1 /*Initialize*/, dd_0 /*RestoreDisplayMode*/, dd_SetCoop, dd_SetMode, dd_WaitVB,
};

// --- USER/GDI hooks for the game window ---
static HWND (WINAPI *oCreateWindowExA)(DWORD, LPCSTR, LPCSTR, DWORD, int, int, int, int, HWND, HMENU, HINSTANCE, LPVOID);
static HWND WINAPI hCreateWindowExA(DWORD ex, LPCSTR cls, LPCSTR title, DWORD style, int x, int y, int w, int h,
                                    HWND parent, HMENU menu, HINSTANCE inst, LPVOID param) {
    if (gamewnd || parent || !HIWORD(cls) || lstrcmpiA(cls, "VIEW_CLASS"))
        return oCreateWindowExA(ex, cls, title, style, x, y, w, h, parent, menu, inst, param);
    MONITORINFO mi = { sizeof mi }; GetMonitorInfoA(MonitorFromPoint((POINT){ 0, 0 }, MONITOR_DEFAULTTOPRIMARY), &mi);
    if (cfg.display == 2) {
        style = WS_POPUP | WS_VISIBLE | WS_CLIPCHILDREN;
        x = mi.rcMonitor.left; y = mi.rcMonitor.top; w = mi.rcMonitor.right - x; h = mi.rcMonitor.bottom - y;
    } else {
        int k = cfg.scale, aw = mi.rcWork.right - mi.rcWork.left, ah = mi.rcWork.bottom - mi.rcWork.top;
        style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_VISIBLE | WS_CLIPCHILDREN;
        RECT r = { 0, 0, VW, VH }; AdjustWindowRectEx(&r, style, FALSE, ex);
        int fw = r.right - r.left - VW, fh = r.bottom - r.top - VH;
        if (k <= 0) { k = (aw - fw) / VW < (ah - fh) / VH ? (aw - fw) / VW : (ah - fh) / VH; if (k < 1) k = 1; }
        cfg.scale = k;
        w = VW * k + fw; h = VH * k + fh;
        x = mi.rcWork.left + (aw - w) / 2; y = mi.rcWork.top + (ah - h) / 2;
    }
    gamewnd = oCreateWindowExA(ex, cls, title, style, x, y, w, h, parent, menu, inst, param);
    logf("gnomefix: game window %p at %d,%d %dx%d (scale %d)\r\n", gamewnd, x, y, w, h, cfg.scale);
    return gamewnd;
}

static HDC (WINAPI *oGetDC)(HWND);
static HDC WINAPI hGetDC(HWND w) {
    HDC d = oGetDC(w);
    if (w && w == gamewnd && d) { HDC v = virtual_dc(d); ReleaseDC(w, d); return v; }
    return d;
}
static int (WINAPI *oReleaseDC)(HWND, HDC);
static int WINAPI hReleaseDC(HWND w, HDC d) { return d == vdc && vdc ? 1 : oReleaseDC(w, d); }

static HDC (WINAPI *oBeginPaint)(HWND, PAINTSTRUCT *);
static HDC WINAPI hBeginPaint(HWND w, PAINTSTRUCT *ps) {
    HDC d = oBeginPaint(w, ps);
    if (w != gamewnd || !d) return d;
    // The game paints into the virtual screen; the presenter shows it.
    ps->hdc = virtual_dc(d); SetRect(&ps->rcPaint, 0, 0, VW, VH);
    InterlockedExchange(&vpaint, (LONG)(UINT_PTR)d);
    return ps->hdc;
}
static BOOL (WINAPI *oEndPaint)(HWND, const PAINTSTRUCT *);
static BOOL WINAPI hEndPaint(HWND w, const PAINTSTRUCT *ps) {
    if (w == gamewnd && ps->hdc == vdc) {
        PAINTSTRUCT real = *ps; real.hdc = (HDC)(UINT_PTR)InterlockedExchange(&vpaint, 0);
        present(real.hdc);
        return oEndPaint(w, &real);
    }
    return oEndPaint(w, ps);
}
static BOOL (WINAPI *oGetUpdateRect)(HWND, LPRECT, BOOL);
static BOOL WINAPI hGetUpdateRect(HWND w, LPRECT r, BOOL e) {
    BOOL v = oGetUpdateRect(w, r, e);
    if (w == gamewnd && r && v) SetRect(r, 0, 0, VW, VH);
    return v;
}
static BOOL (WINAPI *oInvalidateRect)(HWND, const RECT *, BOOL);
static BOOL WINAPI hInvalidateRect(HWND w, const RECT *r, BOOL e) {
    if (w == gamewnd && r) { RECT c = rect_to_client(r); return oInvalidateRect(w, &c, e); }
    return oInvalidateRect(w, r, e);
}
static BOOL (WINAPI *oValidateRect)(HWND, const RECT *);
static BOOL WINAPI hValidateRect(HWND w, const RECT *r) {
    if (w == gamewnd && r) { RECT c = rect_to_client(r); return oValidateRect(w, &c); }
    return oValidateRect(w, r);
}
static BOOL (WINAPI *oGetClientRect)(HWND, LPRECT);
static BOOL WINAPI hGetClientRect(HWND w, LPRECT r) {
    if (w == gamewnd) { SetRect(r, 0, 0, VW, VH); return TRUE; }
    return oGetClientRect(w, r);
}
// The game assumes its window covers the screen, so for it screen == client coordinates.
static BOOL (WINAPI *oScreenToClient)(HWND, LPPOINT);
static BOOL WINAPI hScreenToClient(HWND w, LPPOINT p) { return w == gamewnd ? TRUE : oScreenToClient(w, p); }
static BOOL (WINAPI *oClientToScreen)(HWND, LPPOINT);
static BOOL WINAPI hClientToScreen(HWND w, LPPOINT p) { return w == gamewnd ? TRUE : oClientToScreen(w, p); }
static BOOL (WINAPI *oGetCursorPos)(LPPOINT);
static BOOL WINAPI hGetCursorPos(LPPOINT p) {
    BOOL v = oGetCursorPos(p);
    if (v && gamewnd) { oScreenToClient(gamewnd, p); *p = to_virtual(*p); }
    return v;
}
static BOOL (WINAPI *oSetCursorPos)(int, int);
static BOOL WINAPI hSetCursorPos(int x, int y) {
    if (!gamewnd) return oSetCursorPos(x, y);
    POINT p = { x, y }; p = to_client(p); oClientToScreen(gamewnd, &p);
    return oSetCursorPos(p.x, p.y);
}
static int (WINAPI *oGetSystemMetrics)(int);
static int WINAPI hGetSystemMetrics(int i) {
    // RenderWare's driver sizes its buffers from the FULLSCREEN metrics.
    if (i == SM_CXSCREEN || i == SM_CXFULLSCREEN) return VW;
    if (i == SM_CYSCREEN || i == SM_CYFULLSCREEN) return VH;
    return oGetSystemMetrics(i);
}
// RTLIB and RenderWare's display drivers (RWDL8?20) are shown the 640x480x8 palette device
// the game originally switched to. The drivers refuse anything else, and RTLIB's true-colour
// path never draws the 3D view (RENDER.R32's "external draw" region) into its compose buffer.
static int (WINAPI *oGetDeviceCaps)(HDC, int);
static int WINAPI hGetDeviceCaps(HDC dc, int i) {
    switch (i) {
    case HORZRES: return VW;
    case VERTRES: return VH;
    case BITSPIXEL: return 8;
    case PLANES: return 1;
    case NUMCOLORS: return 20;
    case SIZEPALETTE: return 256;
    case NUMRESERVED: return 20;
    case COLORRES: return 18;
    case RASTERCAPS: return oGetDeviceCaps(dc, i) | RC_PALETTE;
    }
    return oGetDeviceCaps(dc, i);
}
static UINT (WINAPI *oGetSystemPaletteEntries)(HDC, UINT, UINT, LPPALETTEENTRY);
static UINT WINAPI hGetSystemPaletteEntries(HDC dc, UINT first, UINT n, LPPALETTEENTRY pe) {
    // On the original 8-bit screen the hardware palette held the static colors (default
    // palette, entries 0-9 and 246-255) plus the game palette realized by RTLIB. RenderWare
    // maps textures to these colors, so report RTLIB's target palette: its sprite object
    // (rtlib32 global +0x60428) keeps a LOGPALETTE at +0x1424 that fades are computed from.
    PALETTEENTRY def[20], *game = 0;
    BYTE *rt = (BYTE *)GetModuleHandleA("rtlib32.dll"), *spr = rt ? *(BYTE **)(rt + 0x60428) : 0;
    if (spr && *(DWORD *)(spr + 0x1424) == 0x01000300) game = (PALETTEENTRY *)(spr + 0x1428);
    GetPaletteEntries((HPALETTE)GetStockObject(DEFAULT_PALETTE), 0, 20, def);
    if (!pe) return 256;
    for (UINT k = 0; k < n && first + k < 256; k++) {
        UINT i = first + k; PALETTEENTRY z = { 0 };
        pe[k] = i < 10 ? def[i] : i >= 246 ? def[i - 236] : game ? game[i] : z;
        pe[k].peFlags = 0;
    }
    return n;
}

static BOOL (WINAPI *oShowWindow)(HWND, int);
static BOOL WINAPI hShowWindow(HWND w, int cmd) {
    if (w == gamewnd && (cmd == SW_MAXIMIZE || cmd == SW_SHOWMAXIMIZED)) cmd = SW_SHOWNORMAL;
    return oShowWindow(w, cmd);
}
static BOOL (WINAPI *oSetWindowPos)(HWND, HWND, int, int, int, int, UINT);
static BOOL WINAPI hSetWindowPos(HWND w, HWND after, int x, int y, int cx, int cy, UINT fl) {
    if (w == gamewnd) fl |= SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER;
    return oSetWindowPos(w, after, x, y, cx, cy, fl);
}
// G-NOME.EXE's main loop is PeekMessage -> dispatch, else run one idle tick (RtService), with
// no wait, so it pins a CPU core. When its queue is empty, wait up to 1 ms for input instead;
// with a 1 ms timer period that still allows ~1000 idle ticks/s (the game renders ~35 fps).
static HMODULE exe;
static BOOL (WINAPI *oPeekMessageA)(LPMSG, HWND, UINT, UINT, UINT);
static BOOL WINAPI hPeekMessageA(LPMSG m, HWND w, UINT a, UINT b, UINT rm) {
    BOOL v = oPeekMessageA(m, w, a, b, rm);
    if (!v && cfg.idlesleep) {
        HMODULE caller = 0;
        GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           (LPCSTR)_ReturnAddress(), &caller);
        if (caller == exe) MsgWaitForMultipleObjects(0, 0, FALSE, 1, QS_ALLINPUT);
        return v;
    }
    if (v && cfg.display && m->hwnd == gamewnd && m->message >= WM_MOUSEMOVE && m->message <= WM_MBUTTONDBLCLK) {
        POINT p = { (short)LOWORD(m->lParam), (short)HIWORD(m->lParam) };
        p = to_virtual(p);
        m->lParam = MAKELPARAM(p.x, p.y);
        m->pt = p;
    }
    return v;
}

// ===================================================================== import patching
static HMODULE (WINAPI *oLoadLibraryA)(LPCSTR);
static HMODULE WINAPI hLoadLibraryA(LPCSTR name);

// ALL: every game module; RT: rtlib32 only; RW: RenderWare modules only; WIN: windowed mode only
enum { ALL = 1, RT = 2, WIN = 4, RW = 8 };
static const struct { int where; const char *dll, *name; void *hook; void **orig; } hooks[] = {
    { RT, "gdi32.dll", "SetDIBitsToDevice", hSetDIBitsToDevice, (void **)&oSetDIBitsToDevice },
    { RT, "gdi32.dll", "AnimatePalette", hAnimatePalette, (void **)&oAnimatePalette },
    { RT, "gdi32.dll", "GetDIBits", hGetDIBits, (void **)&oGetDIBits },
    { RT, "user32.dll", "DrawTextA", hDrawTextA, (void **)&oDrawTextA },
    { RT, "kernel32.dll", "GetProcAddress", hGetProcAddress, (void **)&oGetProcAddress },
    { ALL, "kernel32.dll", "LoadLibraryA", hLoadLibraryA, (void **)&oLoadLibraryA },
    { RT | WIN, "user32.dll", "CreateWindowExA", hCreateWindowExA, (void **)&oCreateWindowExA },
    { ALL | WIN, "user32.dll", "GetDC", hGetDC, (void **)&oGetDC },
    { ALL | WIN, "user32.dll", "ReleaseDC", hReleaseDC, (void **)&oReleaseDC },
    { ALL | WIN, "user32.dll", "BeginPaint", hBeginPaint, (void **)&oBeginPaint },
    { ALL | WIN, "user32.dll", "EndPaint", hEndPaint, (void **)&oEndPaint },
    { ALL | WIN, "user32.dll", "GetUpdateRect", hGetUpdateRect, (void **)&oGetUpdateRect },
    { ALL | WIN, "user32.dll", "InvalidateRect", hInvalidateRect, (void **)&oInvalidateRect },
    { ALL | WIN, "user32.dll", "ValidateRect", hValidateRect, (void **)&oValidateRect },
    { ALL | WIN, "user32.dll", "GetClientRect", hGetClientRect, (void **)&oGetClientRect },
    { ALL | WIN, "user32.dll", "ScreenToClient", hScreenToClient, (void **)&oScreenToClient },
    { ALL | WIN, "user32.dll", "ClientToScreen", hClientToScreen, (void **)&oClientToScreen },
    { ALL | WIN, "user32.dll", "GetCursorPos", hGetCursorPos, (void **)&oGetCursorPos },
    { ALL | WIN, "user32.dll", "SetCursorPos", hSetCursorPos, (void **)&oSetCursorPos },
    { ALL | WIN, "user32.dll", "GetSystemMetrics", hGetSystemMetrics, (void **)&oGetSystemMetrics },
    { ALL | WIN, "user32.dll", "ShowWindow", hShowWindow, (void **)&oShowWindow },
    { ALL | WIN, "user32.dll", "SetWindowPos", hSetWindowPos, (void **)&oSetWindowPos },
    { ALL, "user32.dll", "PeekMessageA", hPeekMessageA, (void **)&oPeekMessageA },
    { RW | RT | WIN, "gdi32.dll", "GetDeviceCaps", hGetDeviceCaps, (void **)&oGetDeviceCaps },
    { RW | RT | WIN, "gdi32.dll", "GetSystemPaletteEntries", hGetSystemPaletteEntries, (void **)&oGetSystemPaletteEntries },
};
static const char *game_modules[] = {
    "g-nome.exe", "rtlib32.dll", "render.r32", "smacker.r32", "smackw32.dll", "netgn.r32",
    "rwl20.dll", "rwdl8a20.dll", "rwdl8b20.dll", "rwdl8c20.dll", "rwdl8d20.dll",
};
static int patch_imports(HMODULE m, int kind) {
    BYTE *b = (BYTE *)m; int n = 0;
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(b + ((IMAGE_DOS_HEADER *)b)->e_lfanew);
    IMAGE_DATA_DIRECTORY dd = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    for (IMAGE_IMPORT_DESCRIPTOR *d = (void *)(b + dd.VirtualAddress); d->Name; d++) {
        if (!d->OriginalFirstThunk) continue;
        IMAGE_THUNK_DATA *ot = (void *)(b + d->OriginalFirstThunk), *ft = (void *)(b + d->FirstThunk);
        for (; ot->u1.AddressOfData; ot++, ft++) {
            if (IMAGE_SNAP_BY_ORDINAL(ot->u1.Ordinal)) continue;
            const char *name = (const char *)((IMAGE_IMPORT_BY_NAME *)(b + ot->u1.AddressOfData))->Name;
            for (int i = 0; i < sizeof hooks / sizeof *hooks; i++) {
                if (!(hooks[i].where & (ALL | kind))) continue;
                if ((hooks[i].where & WIN) && !cfg.display) continue;
                if (lstrcmpA(name, hooks[i].name) || lstrcmpiA((char *)b + d->Name, hooks[i].dll)) continue;
                if (!*hooks[i].orig) *hooks[i].orig = (void *)GetProcAddress(GetModuleHandleA(hooks[i].dll), name);
                if (ft->u1.Function == (DWORD)(UINT_PTR)hooks[i].hook) continue;
                DWORD op; VirtualProtect(&ft->u1.Function, 4, PAGE_READWRITE, &op);
                ft->u1.Function = (DWORD)(UINT_PTR)hooks[i].hook; VirtualProtect(&ft->u1.Function, 4, op, &op);
                n++;
            }
        }
    }
    return n;
}

static void patch_game_modules(void) {
    for (int i = 0; i < sizeof game_modules / sizeof *game_modules; i++) {
        // Re-checked on every load: RenderWare unloads and reloads drivers at the same address.
        HMODULE m = GetModuleHandleA(game_modules[i]);
        int n = m ? patch_imports(m, i == 1 ? RT : i >= 6 ? RW : 0) : 0;
        if (n) logf("gnomefix: %s @%p: %d imports patched\r\n", game_modules[i], m, n);
    }
}

static HMODULE WINAPI hLoadLibraryA(LPCSTR name) {
    HMODULE m = oLoadLibraryA(name);
    if (m) patch_game_modules();
    return m;
}

// ===================================================================== DirectDraw exports
static HMODULE sysddraw;
static FARPROC sys(const char *name) {
    if (!sysddraw) {
        char p[MAX_PATH]; GetSystemDirectoryA(p, MAX_PATH); lstrcatA(p, "\\ddraw.dll");
        sysddraw = LoadLibraryA(p);
    }
    return sysddraw ? GetProcAddress(sysddraw, name) : 0;
}

HRESULT WINAPI DirectDrawCreate(GUID *g, void **dd, IUnknown *u) {
    patch_game_modules();
    if (cfg.display) {
        FakeDD *f = HeapAlloc(GetProcessHeap(), 0, sizeof *f);
        if (!f) return E_OUTOFMEMORY;
        f->vtbl = fake_vtbl; f->ref = 1; *dd = f;
        return S_OK;
    }
    HRESULT (WINAPI *f)(GUID *, void **, IUnknown *) = (void *)sys("DirectDrawCreate");
    return f ? f(g, dd, u) : E_FAIL;
}
HRESULT WINAPI DirectDrawCreateEx(GUID *g, void **dd, REFIID iid, IUnknown *u) {
    HRESULT (WINAPI *f)(GUID *, void **, REFIID, IUnknown *) = (void *)sys("DirectDrawCreateEx");
    return f ? f(g, dd, iid, u) : E_FAIL;
}
HRESULT WINAPI DirectDrawEnumerateA(void *cb, void *ctx) {
    HRESULT (WINAPI *f)(void *, void *) = (void *)sys("DirectDrawEnumerateA");
    return f ? f(cb, ctx) : E_FAIL;
}
HRESULT WINAPI DirectDrawCreateClipper(DWORD fl, void **c, IUnknown *u) {
    HRESULT (WINAPI *f)(DWORD, void **, IUnknown *) = (void *)sys("DirectDrawCreateClipper");
    return f ? f(fl, c, u) : E_FAIL;
}

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID r) {
    // The game modules' imports are bound before dependency initializers run, so patching
    // works here; LoadLibraryA and DirectDrawCreate re-run it for later plugins.
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(h);
        load_config();
        if (cfg.display) GdiSetBatchLimit(1);   // keep the virtual screen current for the presenter
        exe = GetModuleHandleA(0);
        if (cfg.idlesleep) timeBeginPeriod(1);
        patch_game_modules();
    }
    return TRUE;
}
