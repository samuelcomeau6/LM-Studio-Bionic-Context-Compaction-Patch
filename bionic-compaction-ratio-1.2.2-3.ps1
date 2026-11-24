<#
  Bionic 1.2.2+3 - change the auto-compaction trigger ratio (default 0.9375 = 15/16).
  Compaction fires when chat tokens >= loaded context * Ratio.

  Updated for Bionic 1.2.x, where the old "autoCompactionTriggerRatio" key no longer
  exists: the ratio now sits inline in one obfuscated expression in main\index.js,
      Math.max(1, floor(0.9375 * budget))
  so this script patches that literal (verified to occur exactly once per install).
  The old named-key anchors from 1.1.x builds are kept as fallback candidates, so the
  script still works there too. Anchor counts are verified before anything is written.

  WHEN TO RUN
    - Once after installing Bionic 1.2.2+3.
    - Again after every Bionic update (updates overwrite the patched files).
    - Any time you want a different ratio, or to undo the patch.
    Always close Bionic first, including the tray icon (-Scan is read-only and can run while open).

  SYNTAX
    powershell -ExecutionPolicy Bypass -File .\bionic-compaction-ratio-1.2.2-3.ps1 [-Ratio <0.1-0.99>] [-Restore] [-Scan] [-AppDir <path>]

    -Ratio    Fraction of the loaded context at which compaction starts. Default 0.70.
              Re-patching always rewrites from the pristine backup, so changing the
              ratio later just works and stays idempotent within one app build.
    -Restore  Put the original files back (from the *.js.orig backups). Refuses to
              restore a backup that predates the currently installed version.
    -Scan     Read-only: report which anchors are found, where and how many. Never writes.
    -AppDir   Bionic's "resources\app" folder, only if auto-detect fails.

  EXAMPLES
    .\bionic-compaction-ratio-1.2.2-3.ps1                 # patch to 0.70
    .\bionic-compaction-ratio-1.2.2-3.ps1 -Ratio 0.65     # patch to 0.65
    .\bionic-compaction-ratio-1.2.2-3.ps1 -Restore        # undo
    .\bionic-compaction-ratio-1.2.2-3.ps1 -Scan           # diagnose a version this script doesn't know yet
  (Prefix each with "powershell -ExecutionPolicy Bypass -File" if scripts are blocked.)
#>
param([double]$Ratio = 0.70, [switch]$Restore, [switch]$Scan, [string]$AppDir)
$ErrorActionPreference = 'Stop'
if ($Ratio -le 0.1 -or $Ratio -ge 1) { throw "Ratio must be between 0.1 and 1." }
if ($Restore -and $Scan) { throw "-Restore and -Scan are mutually exclusive." }

# --- locate the install -------------------------------------------------------
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
if ($ver -ne '1.2.2+3') { Write-Warning "Tested on 1.2.2+3; anchors are checked before writing, so nothing changes if they're missing." }

$enc = [Text.Encoding]::GetEncoding(28591)   # Latin-1: byte-exact round trip
$r = $Ratio.ToString([Globalization.CultureInfo]::InvariantCulture)

# Candidate anchors per file, in priority order; the first exact-count match wins.
# Required=$true  -> a match is mandatory (this is where the trigger lives).
# Required=$false -> legacy site; patch it if present, otherwise just note it.
$files = [ordered]@{
  '.webpack-bionic\main\index.js' = @{ Required = $true; Candidates = @(
    @{ Old = '(0.9375*';                             New = "($r*";                        Count = 1 },   # 1.2.x: inline literal in the obfuscated budget expression
    @{ Old = "'autoCompactionTriggerRatio':0xf/0x10"; New = "'autoCompactionTriggerRatio:$r'"; Count = 2 }  # 1.1.x: named key, two sites
  ) }
  '.webpack-bionic\renderer\main_window.js' = @{ Required = $false; Candidates = @(
    @{ Old = 'autoCompactionTriggerRatio:15/16';      New = "autoCompactionTriggerRatio:$r";       Count = 1 }   # 1.1.x renderer site (absent on 1.2.x)
  ) }
}

# --- guards ---------------------------------------------------------------------
# Assumes the running install shows up under these process names; if a future rename
# broke this, patching would proceed against a running app (changes apply on next launch).
if (-not $Scan -and (Get-Process -Name 'Bionic','LM Studio' -ErrorAction SilentlyContinue)) { throw "Close Bionic first (including the tray icon). Use -Scan to inspect it while running." }

# In patch mode, fail early if a required file is missing so nothing gets half-patched.
if (-not $Scan -and -not $Restore) {
  $missing = @($files.Keys | Where-Object { $files[$_].Required -and -not (Test-Path (Join-Path $AppDir $_)) })
  if ($missing.Count -gt 0) { throw "Required file(s) missing from this install: $($missing -join ', '). Nothing was written. Use -Scan to see what is present." }
}

$failures = @(); $patched = 0
foreach ($file in $files.Keys) {
  $path = Join-Path $AppDir $file; $bak = "$path.orig"; $stamp = "$bak.ver"
  $info = $files[$file]

  if ($Restore) {
    if (Test-Path $bak) {
      $stampedVer = $(if (Test-Path $stamp) { (Get-Content $stamp -Raw).Trim() } else { $null })
      if ($stampedVer -and $stampedVer -ne $ver) {
        throw "Refusing to restore $($file): '$(Split-Path $bak -Leaf)' was made from version '$stampedVer' but the install is now $ver. Restoring it would replace current app code with an older build's copy. If that backup is no longer needed, delete both files: $bak and $stamp."
      }
      if (-not $stampedVer) { Write-Warning "$($file): backup '$(Split-Path $bak -Leaf)' has no version stamp; restoring it as-is." }
      Copy-Item $bak $path -Force
      Write-Host "Restored $($file)"
    }
    elseif (Test-Path $path) { Write-Host "No backup for $($file); left as-is." }
    else                     { Write-Host "$($file): nothing to restore." }
    continue
  }

  if (-not (Test-Path $path)) {
    if ($info.Required -and -not $Scan) { $failures += "$($file): not present" }
    $note = if ($info.Required -and -not $Scan) { 'Will report failure at the end.' } else { '' }
    Write-Host "Skipping $($file): not present in this install. $note"
    continue
  }

  # Patch mode rewrites from the pristine backup, so it is idempotent within one build.
  # Backups carry a version stamp (<file>.orig.ver); after an app update the stale
  # backup is refreshed from the freshly shipped file instead of being reused.
  $srcPath = $path
  if (-not $Scan) {
    $stampedVer = $(if (Test-Path $stamp) { (Get-Content $stamp -Raw).Trim() } else { $null })
    if (-not (Test-Path $bak)) {
      Copy-Item $path $bak; Set-Content -LiteralPath $stamp -Value $ver -Encoding ASCII
    }
    elseif ($stampedVer -and $stampedVer -ne $ver) {
      Write-Warning "$($file): backup predates this build (stamped '$stampedVer', install is $ver). Refreshing it from the freshly shipped file."
      Copy-Item $path $bak -Force; Set-Content -LiteralPath $stamp -Value $ver -Encoding ASCII
    }
    elseif (-not $stampedVer) {
      # Unstamped backup (older script or manual): safe to keep only if it matches the live file.
      if ((Get-FileHash $bak).Hash -eq (Get-FileHash $path).Hash) {
        Set-Content -LiteralPath $stamp -Value $ver -Encoding ASCII
        Write-Warning "$($file): stamped existing backup as version $ver."
      }
      else {
        Write-Warning "$($file): unstamped backup differs from the current file (likely an app update). Refreshing it from the freshly shipped file."
        Copy-Item $path $bak -Force; Set-Content -LiteralPath $stamp -Value $ver -Encoding ASCII
      }
    }
    $srcPath = $bak
  }

  $src = [IO.File]::ReadAllText($srcPath, $enc)

  $pick = $null; $counts = @{}
  foreach ($c in $info.Candidates) {
    $n = ([regex]::Matches($src, [regex]::Escape($c.Old))).Count
    $counts[$c.Old] = $n
    if (-not $pick -and $n -eq $c.Count) { $pick = $c }
  }

  foreach ($c in $info.Candidates) {
    $mark = 'not found'
    if ($pick -and $c.Old -eq $pick.Old) { $mark = 'MATCH' } elseif ($counts[$c.Old] -gt 0) { $mark = 'present, wrong count' }
    Write-Host ("[{0}] '{1}' : found {2} (want {3}) - {4}" -f $file, $c.Old, $counts[$c.Old], $c.Count, $mark)
  }

  if (-not $pick) {
    if ($info.Required -and -not $Scan) {
      $failures += "$($file): expected $($($info.Candidates | ForEach-Object Count) -join '/')(0.9375*) anchor(s), found 0"
      Write-Warning "$($file): no known anchor matched; nothing written for this file."
    }
    elseif (-not $Scan) {
      Write-Host "Note: $($file) present but carries no known compaction anchor (normal on current builds); left alone."
    }
    continue
  }

  if ($Scan) { Write-Host "[$file] would replace '$($pick.Old)' with '$($pick.New)' at $($pick.Count) site(s). Nothing was written." }
  else       { [IO.File]::WriteAllText($path, $src.Replace($pick.Old, $pick.New), $enc); $patched++; Write-Host "Patched $($file): '$($pick.Old)' -> '$($pick.New)' ($($pick.Count) site(s))" }
}

# --- finish ---------------------------------------------------------------------
if ($Restore) {
  Write-Host 'Done restoring. Backups (*.js.orig plus their .orig.ver version stamps) are kept until you delete them.'
}
elseif (-not $Scan) {
  if (($failures.Count -gt 0) -or ($patched -eq 0)) {
    throw "No patch applied: $(if ($failures.Count -gt 0) {"$($failures -join '; ')"} else {'no file matched a known anchor'}). Re-run with -Scan to diagnose."
  }
  Write-Host "Done. Patched $patched file(s). Backups: *.js.orig next to each patched file (plus a .orig.ver version stamp). Undo with -Restore."
}
else {
  Write-Host 'Scan complete; nothing was written.'
}
