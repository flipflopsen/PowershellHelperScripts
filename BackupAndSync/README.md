# Backup & Sync

Scripts for verifying and comparing backups/mirrors made with Robocopy, and
a general-purpose folder diff tool.

## Scripts

### `check_synchronized.ps1`
Runs a real Robocopy mirror-style copy from `F:\Backups\SwaggerDriveBackup`
to `D:\` (multi-threaded, `/MT:64`, copies data/attributes/timestamps,
skips junctions). Use to actually (re)synchronize the backup to the
destination. Edit the source/destination paths at the top of the script
before running.

```powershell
.\check_synchronized.ps1
```

Exit code is Robocopy's `$LASTEXITCODE` (values 0–7 indicate success/no
error; 8+ indicate failures — see `robocopy /?`).

### `compare_sync.ps1`
Dry-run counterpart to `check_synchronized.ps1`. Uses Robocopy's `/L`
(list-only) flag to report what *would* be copied/changed between
`F:\Backups\SwaggerDriveBackup` and `D:\` without touching any files.
Use this first to confirm a sync is safe before running the real copy.

```powershell
.\compare_sync.ps1
```

### `FolderDiff.ps1`
Multi-threaded PowerShell folder comparison tool. Recursively compares two
folder trees by SHA-256 hash and reports files that are identical,
different, or only present in one folder. Supports symlink skipping, text
diff output, and exporting results to a file.

```powershell
.\FolderDiff.ps1 -Folder1 'C:\Data\Old' -Folder2 'C:\Data\New'
.\FolderDiff.ps1 -Folder1 'C:\A' -Folder2 'C:\B' -ShowTextDiff -ExportResults -OutputPath .\diff_results.txt
.\FolderDiff.ps1 -Folder1 'C:\A' -Folder2 'C:\B' -SkipSymlinks -DiffWorkers 8
```

**Parameters**
| Parameter | Description |
|---|---|
| `-Folder1` / `-Folder2` | (Required) The two folder trees to compare |
| `-ShowTextDiff` | Show line-by-line diff for differing text files |
| `-ExportResults` | Write results to `-OutputPath` |
| `-SkipSymlinks` | Skip reparse points/symlinks during traversal |
| `-Verbosity` | Verbose progress output |
| `-DiffWorkers` | Number of parallel worker threads (default 4) |
| `-OutputPath` | Output file for exported results (default `.\diff_results.txt`) |
