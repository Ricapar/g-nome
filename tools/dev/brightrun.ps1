param([string]$Dir, [string]$Inject = "", [hashtable]$EnvVars = @{}, [int]$Seconds = 10, [string]$Save = "")
# Launch the game, optionally inject a DLL, then report screen brightness once per second.
Add-Type -AssemblyName System.Drawing
foreach ($k in $EnvVars.Keys) { Set-Item "Env:$k" $EnvVars[$k] }
$p = Start-Process "$Dir\G-NOME.EXE" -ArgumentList G-Nome.BIN -WorkingDirectory $Dir -PassThru
foreach ($k in $EnvVars.Keys) { Remove-Item "Env:$k" }
if ($Inject) { Start-Sleep -Milliseconds 1500; & "$PSScriptRoot\inject.exe" $p.Id $Inject | Out-Null }
$line = @()
for ($i = 1; $i -le $Seconds; $i++) {
  Start-Sleep -Milliseconds 900
  $b = New-Object Drawing.Bitmap 640, 480; $g = [Drawing.Graphics]::FromImage($b)
  $g.CopyFromScreen(0, 0, 0, 0, (New-Object Drawing.Size 640, 480))
  $mx = 0; for ($y = 0; $y -lt 480; $y += 6) { for ($x = 0; $x -lt 640; $x += 6) { $c = $b.GetPixel($x, $y); $s = $c.R + $c.G + $c.B; if ($s -gt $mx) { $mx = $s } } }
  $line += $mx
  if ($Save) { $b.Save((Join-Path $Save "f$i.png")) }
  $g.Dispose(); $b.Dispose()
}
Stop-Process -Id $p.Id -Force
"maxbright per second: " + ($line -join ' ')
