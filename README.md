# Bionic 1.2.2+3 - change the auto-compaction trigger ratio (default 0.9375 = 15/16)

PowerShell patch that lowers when Bionic automatically compacts long sessions. Compaction fires when chat tokens >= loaded context * Ratio; by default that's at **93.75%** of your loaded context. This script rewrites the ratio constant in the shipped bundle so compaction starts earlier (e.g. 70%).

> [!Important]
> This patch is only guaranteed to work on the specific build mentioned. If you have a different build, run the script with `-Scan` to see which anchors are present; if none match, the script will not write anything and you can file an issue (or extend the candidate list yourself — see [How it works](#how-it-works)).

## When to run

- Once after installing Bionic **1.2.2+3**.
- Again after every Bionic update (updates overwrite the patched files).
- Any time you want a different ratio, or to undo the patch.
- Always close Bionic first, including the tray icon (`-Scan` is read-only and can run while it's open).

## Usage

```powershell
# syntax
powershell -ExecutionPolicy Bypass -File .\bionic-compaction-ratio-1.2.2-3.ps1 [-Ratio <0.1-0.99>] [-Restore] [-Scan] [-AppDir <path>]

    -Ratio     Fraction of the loaded context at which compaction starts. Default 0.70.
              Re-patching with a different value always applies to pristine code,
              so changing the ratio later stays clean (idempotent within one app build).
    -Restore   Put the original files back (from the *.js.orig backups). Refuses to
              restore a backup made from an older app version.
    -Scan      Read-only: report which anchors are found, where and how many. Never writes.
    -AppDir    Bionic's "resources\app" folder, only if auto-detect fails.

# examples
.\bionic-compaction-ratio-1.2.2-3.ps1                 # patch to 0.70
.\bionic-compaction-ratio-1.2.2-3.ps1 -Ratio 0.65     # patch to 0.65
.\bionic-compaction-ratio-1.2.2-3.ps1 -Restore        # undo
.\bionic-compaction-ratio-1.2.2-3.ps1 -Scan           # diagnose, never writes
```

(If scripts are blocked on your machine, prefix each command with `powershell -ExecutionPolicy Bypass -File`.)

The install location is auto-detected (Program Files / Program Files (x86) / LocalAppData\Programs). You only need `-AppDir` if detection fails.

## Backups and undo

Each patched file gets a pristine backup next to it, e.g. `index.js.orig`, plus a small `index.js.orig.ver` file recording the app version the backup was made from. Re-running the patch always rewrites from that backup, so passing `-Ratio 0.65` after `-Ratio 0.70` applies cleanly with no drift (idempotent within one app build). After a Bionic update, the script notices the stale stamp and refreshes the backup from the freshly shipped file instead of reusing old code. Run `-Restore` to put everything back; it refuses to restore a backup that predates the installed version, so an update can never silently roll your install back an app build. Backups are kept until you delete them.

## How it works

In Bionic **1.2.x** the main bundle is string-obfuscated (`_0x...` identifiers, property names looked up dynamically), so there's no longer a literal `autoCompactionTriggerRatio` key to search for. The ratio constant survived as an inline literal in exactly one spot of `.webpack-bionic\main\index.js`:

```js
Math.max(1, floor(0.9375 * budget))   // compaction trigger: tokens >= this count
```

The script replaces the minimal stable span `(0.9375*` with `(<Ratio>*`. It never anchors on obfuscated `_0x...` names (they are randomized per build), and it verifies each candidate anchor's exact occurrence count **before** writing anything — if nothing matches exactly as expected, no file is modified. The old 1.1.x named-key anchors (`'autoCompactionTriggerRatio':0xf/0x10`, `autoCompactionTriggerRatio:15/16`) are kept as fallback candidates so the script still works on that line of builds too.

## Troubleshooting

| Symptom | What it means / fix |
| --- | --- |
| `No patch applied` / no known anchor matched, nothing written | Your build differs from 1.2.2+3 in the relevant spot. The run now exits non-zero instead of reporting success. Run `-Scan`, note which file/candidate is missing, and open an issue with that output attached. |
| "Refusing to restore ... was made from version X but the install is now Y" | A backup is left over from an earlier app build; restoring it would downgrade the shipped code. If you no longer need it, delete `file.js.orig` and its `.orig.ver` stamp and retry.
| "Close Bionic first (including the tray icon)" | The patch refuses to modify a running install. Quit fully — check the system tray — then retry. Use `-Scan` while it's open. |
| Version warning ("Tested on 1.2.2+3") | Informational only: you're on another version. Anchor-count checks still protect correctness; nothing changes unless an anchor matches exactly. |
