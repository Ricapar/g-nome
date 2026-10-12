param([string]$Dir, [string]$Out, [string[]]$Steps, [int]$MaxSeconds = 180)
# Launch G-Nome (windowed gnomefix mode) and drive it.
# Steps: "wait:<sec>", "key:<name>" (SPACE, ESC, ENTER, UP, DOWN, LEFT, RIGHT, A-Z, 0-9, F1..),
#        "hold:<name>:<ms>", "click:<x>,<y>" (game 640x480 coords), "shot:<name>", "move:<x>,<y>"
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class D {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@
New-Item -ItemType Directory -Force $Out | Out-Null
$vk = @{ SPACE = 0x20; ESC = 0x1B; ENTER = 0x0D; UP = 0x26; DOWN = 0x28; LEFT = 0x25; RIGHT = 0x27; TAB = 0x09; CTRL = 0x11; SHIFT = 0x10; ALT = 0x12 }
function VK($n) { if ($vk.ContainsKey($n)) { $vk[$n] } elseif ($n -match '^F(\d+)$') { 0x6F + [int]$Matches[1] } else { [int][char]$n.ToUpper() } }
function Key($n, $ms = 60) {
  $v = VK $n; $sc = [D]::MapVirtualKey($v, 0)
  [D]::keybd_event([byte]$v, [byte]$sc, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds $ms
  [D]::keybd_event([byte]$v, [byte]$sc, 2, [UIntPtr]::Zero)
}
# Map game coordinates to screen using the scaled image placement (integer scale, centred).
function ToScreen($x, $y) {
  $r = New-Object D+RECT; [void][D]::GetClientRect($script:h, [ref]$r)
  $k = [Math]::Max(1, [Math]::Min([int][Math]::Floor($r.R / 640), [int][Math]::Floor($r.B / 480)))
  $p = New-Object D+POINT; $p.X = [int](($r.R - 640 * $k) / 2 + $x * $k + $k / 2); $p.Y = [int](($r.B - 480 * $k) / 2 + $y * $k + $k / 2)
  [void][D]::ClientToScreen($script:h, [ref]$p); $p
}
function Shot($name) {
  $r = New-Object D+RECT; [void][D]::GetClientRect($script:h, [ref]$r)
  $p = New-Object D+POINT; [void][D]::ClientToScreen($script:h, [ref]$p)
  $b = New-Object Drawing.Bitmap $r.R, $r.B; $g = [Drawing.Graphics]::FromImage($b)
  $g.CopyFromScreen($p.X, $p.Y, 0, 0, (New-Object Drawing.Size $r.R, $r.B))
  # Save at 640x480 to keep images small.
  $s = New-Object Drawing.Bitmap 640, 480; $gs = [Drawing.Graphics]::FromImage($s)
  $gs.InterpolationMode = 'NearestNeighbor'; $gs.DrawImage($b, 0, 0, 640, 480)
  $s.Save("$Out\$name.png"); $gs.Dispose(); $s.Dispose(); $g.Dispose(); $b.Dispose()
  $proc.Refresh()
  "shot $name  t={0:N1}s cpu={1:N1}s" -f ((Get-Date) - $t0).TotalSeconds, $proc.TotalProcessorTime.TotalSeconds
}
$proc = Start-Process "$Dir\G-NOME.EXE" -ArgumentList G-Nome.BIN -WorkingDirectory $Dir -PassThru
$t0 = Get-Date
$script:h = [IntPtr]::Zero
while ($script:h -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 20) { Start-Sleep -Milliseconds 250; $proc.Refresh(); $script:h = $proc.MainWindowHandle }
"window $($script:h) after {0:N1}s" -f ((Get-Date) - $t0).TotalSeconds
foreach ($s in $Steps) {
  $proc.Refresh(); if ($proc.HasExited) { "game exited (code $($proc.ExitCode)) before step '$s'"; break }
  if (((Get-Date) - $t0).TotalSeconds -gt $MaxSeconds) { "time limit reached"; break }
  [void][D]::SetForegroundWindow($script:h)
  $a, $arg = $s -split ':', 2
  switch ($a) {
    'wait' { Start-Sleep -Milliseconds ([double]$arg * 1000) }
    'key' { Key $arg }
    'hold' { $n, $ms = $arg -split ':'; Key $n ([int]$ms) }
    'move' { $x, $y = $arg -split ','; $p = ToScreen ([int]$x) ([int]$y); [void][D]::SetCursorPos($p.X, $p.Y) }
    'click' {
      $x, $y = $arg -split ','; $p = ToScreen ([int]$x) ([int]$y); [void][D]::SetCursorPos($p.X, $p.Y); Start-Sleep -Milliseconds 150
      [D]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [D]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
    }
    'shot' { Shot $arg }
  }
}
$proc.Refresh()
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force; "closed game after {0:N0}s" -f ((Get-Date) - $t0).TotalSeconds }
