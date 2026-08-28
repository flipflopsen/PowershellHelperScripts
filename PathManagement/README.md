# PATH Management

Scripts for inspecting, cleaning, sorting, categorizing, backing up, and
restoring the Windows `PATH` environment variable (User and Machine scopes),
plus tools for consolidating executables into shim directories to reduce
PATH clutter.

> ⚠️ These scripts modify a core system setting. Always run with `-WhatIf`
> first, review the output/backup, and only then re-run with `-Apply` /
> without `-WhatIf`. Machine-scope changes require an elevated (Administrator)
> PowerShell session.

## Scripts

### `PathVarInfo.ps1`
Prints diagnostic info about the current system: Windows version, PowerShell
version, and whether `LongPathsEnabled` is set (both the raw registry value
and the Group Policy value). Useful before doing any PATH surgery.

```powershell
.\PathVarInfo.ps1
```

### `Analyze_Path.ps1`
Read-only analyzer. Scans the current `PATH`, flags known shim/package-manager
directories (Scoop, Chocolatey, WinGet, Cargo, npm, .NET tools, etc.), checks
for common developer tools, and reports which system directories should
always be kept. Use it to understand your PATH before cleaning it.

```powershell
.\Analyze_Path.ps1
```

### `PathSplitter.ps1`
"PATH Categorizer" — splits the monolithic `PATH` into category-specific
environment variables (`PATH_DEV`, `PATH_TOOL`, `PATH_SYSTEM`, etc.), removes
the categorized entries from the main `PATH`, and re-appends the category
variables so tools keep working. Creates a backup first.

```powershell
.\PathSplitter.ps1 -WhatIf
.\PathSplitter.ps1 -Force
```

### `PathRemover.ps1`
"Remove Non-Existent PATH Entries" — removes PATH entries whose target
directory no longer exists on disk. Preserves order of remaining entries and
backs up before changing anything.

```powershell
.\PathRemover.ps1 -WhatIf
.\PathRemover.ps1 -Scope User
.\PathRemover.ps1 -Scope Both -Force
```

### `sort_path.ps1`
"PATH Sorter" — reorders PATH entries (alphabetically, by category, or by
path type), removes duplicates/empty entries, and backs up first.

```powershell
.\sort_path.ps1 -SortBy Category -Scope User
.\sort_path.ps1 -SortBy Alphabetical -WhatIf
```

### `Clean-WindowsPath.ps1`
Full PATH cleanup: normalizes entries (fixes malformed concatenations,
collapses repeated slashes, trims trailing slashes), removes duplicates
(including User entries duplicated in Machine), removes entries that point
to files instead of directories, removes stale include/header directories,
and (unless `-KeepMissing` is set) removes entries whose directory no longer
exists. Backs up the current User/Machine PATH (plain text, JSON, and `.reg`
exports) before making any change, and only writes changes when `-Apply` is
passed.

```powershell
# Preview only (default) — writes a report + backup, makes no changes
.\Clean-WindowsPath.ps1

# Apply the cleanup
.\Clean-WindowsPath.ps1 -Apply

# Apply, but keep entries whose directories don't currently exist
.\Clean-WindowsPath.ps1 -Apply -KeepMissing
```

### `Shim_Path_Analyzer.ps1`
"Intelligent PATH Cleanup" analyzer — detects PATH entries that are
non-existent, duplicated, or already covered by known shim directories
(Scoop, Chocolatey, WinGet, etc.), so they can be safely removed.

```powershell
.\Shim_Path_Analyzer.ps1 -WhatIf
.\Shim_Path_Analyzer.ps1 -Scope User
.\Shim_Path_Analyzer.ps1 -Scope Both -Force
```

### `Shim_Fixer.ps1`
Custom development-tools shim creator focused on Java/JDK and build tools
(Maven, Gradle, Ant, SBT, Leiningen, etc.). Creates a unified shim directory
so these tools' actual install directories don't need to stay on PATH.

```powershell
.\Shim_Fixer.ps1 -ShimDirectory "C:\Users\$env:USERNAME\DevShims" -WhatIf
```

### `Universal-PathShims.ps1` / `ShimPathAnalyzerFull.ps1`
Full "Dynamic PATH Executables Analyzer and Universal Shim Creator". Scans
every directory on PATH, finds all executables (with configurable
exclusions for system tools/directories), and creates a single universal
shim directory to replace many PATH entries. Supports backup/restore of the
PATH before/after changes, and a safe `-WhatIf` preview mode.
`Universal-PathShims.ps1` is the documented/comment-based-help version;
`ShimPathAnalyzerFull.ps1` is an earlier variant of the same tool.

```powershell
.\Universal-PathShims.ps1 -WhatIf
.\Universal-PathShims.ps1 -ShimDirectory 'C:\Shims' -Backup -UpdatePath
.\Universal-PathShims.ps1 -Restore -BackupDirectory 'C:\Shims\Backup-20260101'
```

### `Protect-WindowsPath.ps1`
Standalone backup/restore utility for the persistent (registry-level) User
and Machine PATH values, independent of any cleanup operation.

```powershell
.\Protect-WindowsPath.ps1 -Mode Backup
.\Protect-WindowsPath.ps1 -Mode Backup -BackupRoot 'D:\Backups'
.\Protect-WindowsPath.ps1 -Mode Restore -BackupDirectory 'D:\Backups\WindowsPath-20260820-153000'
```

> Restoring the Machine PATH requires an elevated PowerShell session. Close
> and reopen terminals/applications after any restore.
