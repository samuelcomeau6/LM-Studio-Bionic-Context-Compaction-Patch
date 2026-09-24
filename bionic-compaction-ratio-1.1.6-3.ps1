<#
  Bionic 1.1.6+3 - change the auto-compaction trigger ratio (default 15/16 = 0.9375).
  Compaction fires when chat tokens >= loaded context * Ratio.

  WHEN TO RUN
    - Once after installing Bionic 1.1.6+3.
    - Again after every Bionic update (updates overwrite the patched files).
    - Any time you want a different ratio, or want to undo the patch.
    Always close Bionic first, including the tray icon.

  SYNTAX
    powershell -ExecutionPolicy Bypass -File .\bionic-compaction-ratio-1.1.6-3.ps1 [-Ratio <0.1-0.99>] [-Restore] [-AppDir <path>]

    -Ratio    Fraction of the loaded context at which compaction starts. Default 0.70.
    -Restore  Put the original files back (from the *.js.orig backups).
    -AppDir   Bionic's "resources\app" folder, only if auto-detect fails.

  EXAMPLES
    .\bionic-compaction-ratio-1.1.6-3.ps1                 # patch to 0.70
    .\bionic-compaction-ratio-1.1.6-3.ps1 -Ratio 0.65     # patch to 0.65
    .\bionic-compaction-ratio-1.1.6-3.ps1 -Restore        # undo
  (Prefix each with "powershell -ExecutionPolicy Bypass -File" if scripts are blocked.)
#>
param([double]$Ratio = 0.70, [switch]$Restore, [string]$AppDir)
$ErrorActionPreference = 'Stop'
if ($Ratio -le 0.1 -or $Ratio -ge 1) { throw "Ratio must be between 0.1 and 1." }

if (-not $AppDir) {
  $roots = @("$env:LOCALAPPDATA\Programs", $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ -and (Test-Path $_) }
  $hit = foreach ($r in $roots) { Get-ChildItem $r -Directory -ErrorAction SilentlyContinue |
           ForEach-Object { Join-Path $_.FullName 'resources\app' } |
           Where-Object { Test-Path (Join-Path $_ '.webpack-bionic\main\index.js') } }
  $AppDir = @($hit)[0]
  if (-not $AppDir) { throw "Bionic install not found. Pass -AppDir '<install>\resources\app'." }
}
$ver = (Get-Content (Join-Path $AppDir 'package.json') -Raw | ConvertFrom-Json).version
Write-Host "Bionic at $AppDir (version $ver)"
if ($ver -ne '1.1.6+3') { Write-Warning "Built for 1.1.6+3; anchors are checked before writing, nothing changes if they're missing." }
if (Get-Process -Name 'Bionic','LM Studio' -ErrorAction SilentlyContinue) { throw "Close Bionic first (including the tray icon)." }

$enc = [Text.Encoding]::GetEncoding(28591)   # Latin-1: byte-exact round trip
$r = $Ratio.ToString([Globalization.CultureInfo]::InvariantCulture)
$targets = @(
  @{ File = '.webpack-bionic\main\index.js';          Old = "'autoCompactionTriggerRatio':0xf/0x10"; New = "'autoCompactionTriggerRatio':$r"; Count = 2 },
  @{ File = '.webpack-bionic\renderer\main_window.js'; Old = "autoCompactionTriggerRatio:15/16";      New = "autoCompactionTriggerRatio:$r";   Count = 1 }
)

foreach ($t in $targets) {
  $path = Join-Path $AppDir $t.File; $bak = "$path.orig"
  if ($Restore) {
    if (Test-Path $bak) { Copy-Item $bak $path -Force; Write-Host "Restored $($t.File)" } else { Write-Host "No backup for $($t.File)" }
    continue
  }
  if (-not (Test-Path $bak)) { Copy-Item $path $bak }
  $src = [IO.File]::ReadAllText($bak, $enc)          # always patch from the pristine backup
  $n = ([regex]::Matches($src, [regex]::Escape($t.Old))).Count
  if ($n -ne $t.Count) { throw "$($t.File): expected $($t.Count) anchor(s), found $n. Wrong version? Nothing written." }
  [IO.File]::WriteAllText($path, $src.Replace($t.Old, $t.New), $enc)
  Write-Host "Patched $($t.File): 15/16 -> $r ($n site(s))"
}
if (-not $Restore) { Write-Host "Done. Backups: *.js.orig next to each file. Undo with -Restore." }
