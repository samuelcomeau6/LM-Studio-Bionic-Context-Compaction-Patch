 > [!Important] 
 > This patch is only guaranteed to work on the specific build mentioned. If you have a different build, use the script to create a new one targeting that build

# Bionic 1.1.6+3 - change the auto-compaction trigger ratio (default 15/16 = 0.9375).
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
  ```
    .\bionic-compaction-ratio-1.1.6-3.ps1                 #patch to 0.70
    .\bionic-compaction-ratio-1.1.6-3.ps1 -Ratio 0.65     #patch to 0.65
    .\bionic-compaction-ratio-1.1.6-3.ps1 -Restore        #undo
```
  (Prefix each with "powershell -ExecutionPolicy Bypass -File" if scripts are blocked.)

