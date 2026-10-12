param([string]$Dir, [string]$Out, [int]$Wait = 15, [int]$Shots = 3, [string]$Compat = "", [string]$Keys = "", [switch]$Focus)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
New-Item -ItemType Directory -Force $Out | Out-Null
if ($Compat) { $env:__COMPAT_LAYER = $Compat }
$p = Start-Process -FilePath "$Dir\G-NOME.EXE" -ArgumentList "G-Nome.BIN" -WorkingDirectory $Dir -PassThru
"pid $($p.Id)"
for ($i = 1; $i -le $Shots; $i++) {
  Start-Sleep -Seconds $Wait
  $p.Refresh()
  if ($p.HasExited) { "exited code $($p.ExitCode) before shot $i"; break }
  [W]::EnumWindows({ param($h, $l)
    $wp = 0; [void][W]::GetWindowThreadProcessId($h, [ref]$wp)
    if ($wp -eq $p.Id) {
      $t = New-Object Text.StringBuilder 256; $c = New-Object Text.StringBuilder 256
      [void][W]::GetWindowText($h, $t, 256); [void][W]::GetClassName($h, $c, 256)
      $r = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r)
      Write-Host "win '$t' class=$c vis=$([W]::IsWindowVisible($h)) rect=$($r.L),$($r.T),$($r.R),$($r.B)"
    }; $true }, [IntPtr]::Zero) | Out-Null
  $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  "screen $($b.Width)x$($b.Height)"
  $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
  $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
  $bmp.Save("$Out\shot$i.png"); $g.Dispose(); $bmp.Dispose()
  if ($i -eq 1) { $p.Modules | % { $_.ModuleName } | ? { $_ -match 'r32|rw|smack|rtlib|ddraw|dplay|dsound|winmm|apphelp|AcLayers|AcGenral' } | % { "mod $_" } }
  $gh = $p.MainWindowHandle
  if ($gh -ne [IntPtr]::Zero) {
    $pb = New-Object Drawing.Bitmap 640, 480; $pg = [Drawing.Graphics]::FromImage($pb); $dc = $pg.GetHdc()
    $ok = [W]::PrintWindow($gh, $dc, 2); $pg.ReleaseHdc($dc); $pb.Save("$Out\pw$i.png"); $pg.Dispose(); $pb.Dispose(); "printwindow $ok"
    if ($Focus -and $i -eq 1) { [W]::keybd_event(0x12,0,0,[UIntPtr]::Zero); [W]::keybd_event(0x12,0,2,[UIntPtr]::Zero); [void][W]::SetForegroundWindow($gh); "focused" }
    "foreground=$([W]::GetForegroundWindow() -eq $gh)"
    if ($Keys) { [void][W]::SetForegroundWindow($gh); Start-Sleep -Milliseconds 300; [Windows.Forms.SendKeys]::SendWait($Keys); "sent $Keys" }
  }
  "cpu $($p.TotalProcessorTime) ws $([int]($p.WorkingSet64/1MB))MB threads $($p.Threads.Count)"
}
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; "killed" }
