# Examples

## Table of Contents

- [Index only](#index-only)
- [Backup using an existing index](#backup-using-an-existing-index)
- [Backup with interactive index creation when the index is missing](#backup-with-interactive-index-creation-when-the-index-is-missing)
- [Backup with automatic index creation when the index is missing](#backup-with-automatic-index-creation-when-the-index-is-missing)
- [Always generate a new index and create the backup](#always-generate-a-new-index-and-create-the-backup)
- [Verify a backup](#verify-a-backup)
- [Verify with an explicit thread count](#verify-with-an-explicit-thread-count)
- [Restore a backup](#restore-a-backup)
- [Restore with an explicit thread count](#restore-with-an-explicit-thread-count)
- [Verify and restore](#verify-and-restore)
- [SevenZip Compression Examples](#sevenzip-compression-examples)
  - [SevenZip with Store compression](#sevenzip-with-store-compression)
  - [SevenZip with Fast compression](#sevenzip-with-fast-compression)
  - [SevenZip with Balanced compression](#sevenzip-with-balanced-compression)
  - [SevenZip with Maximum compression](#sevenzip-with-maximum-compression)
  - [SevenZip with Store compression and solid mode](#sevenzip-with-store-compression-and-solid-mode)
  - [SevenZip with Fast compression and solid mode](#sevenzip-with-fast-compression-and-solid-mode)
  - [SevenZip with Balanced compression and solid mode](#sevenzip-with-balanced-compression-and-solid-mode)
  - [SevenZip with Maximum compression and solid mode](#sevenzip-with-maximum-compression-and-solid-mode)
- [ZIP Compression Examples](#zip-compression-examples)
  - [ZIP with Store compression](#zip-with-store-compression)
  - [ZIP with Fast compression](#zip-with-fast-compression)
  - [ZIP with Balanced compression](#zip-with-balanced-compression)
  - [ZIP with Maximum compression](#zip-with-maximum-compression)
- [Thread Examples](#thread-examples)
  - [Single-threaded backup](#single-threaded-backup)
  - [Use eight threads](#use-eight-threads)
  - [Use all logical processors](#use-all-logical-processors)
  - [Reserve two logical processors](#reserve-two-logical-processors)
- [Archive Hash Examples](#archive-hash-examples)
  - [Create a backup without an archive hash](#create-a-backup-without-an-archive-hash)
  - [Create a backup with a SHA-256 archive hash](#create-a-backup-with-a-sha-256-archive-hash)
- [Existing Archive Examples](#existing-archive-examples)
  - [Refuse to replace an existing archive](#refuse-to-replace-an-existing-archive)
  - [Replace an existing archive](#replace-an-existing-archive)
  - [Replace an existing archive and calculate its hash](#replace-an-existing-archive-and-calculate-its-hash)
- [Missing Source File Examples](#missing-source-file-examples)
  - [Terminate if indexed files are missing](#terminate-if-indexed-files-are-missing)
  - [Continue if indexed files are missing](#continue-if-indexed-files-are-missing)
  - [Automatically create a missing index and tolerate missing files](#automatically-create-a-missing-index-and-tolerate-missing-files)
- [Explicit 7-Zip Path Examples](#explicit-7-zip-path-examples)
  - [Use an explicitly installed `7z.exe`](#use-an-explicitly-installed-7zexe)
  - [Use a standalone `7zz.exe`](#use-a-standalone-7zzexe)
- [Network Examples](#network-examples)
  - [Local source and network destination](#local-source-and-network-destination)
  - [Network source and local destination](#network-source-and-local-destination)
  - [Network source and network destination](#network-source-and-network-destination)
- [Generated Backup Name Examples](#generated-backup-name-examples)
  - [Date-based backup name](#date-based-backup-name)
  - [Timestamped backup name](#timestamped-backup-name)
- [Automation Examples](#automation-examples)
  - [Noninteractive backup](#noninteractive-backup)
  - [Noninteractive backup followed by verification](#noninteractive-backup-followed-by-verification)
  - [Generate all valid archive combinations](#generate-all-valid-archive-combinations)
- [Behavioral Matrix](#behavioral-matrix)
  - [Mode Behavior](#mode-behavior)
  - [Archive Combination Matrix](#archive-combination-matrix)
  - [Switch Behavior Matrix](#switch-behavior-matrix)
  - [Output Matrix](#output-matrix)

## Index only

```powershell
.\DriveArchive.ps1 `
    -Mode Index `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup"
```

## Backup using an existing index

```powershell
.\DriveArchive.ps1 `
    -Mode Backup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -ArchiveFormat SevenZip `
    -Compression Store `
    -Threads 16
```

## Backup with interactive index creation when the index is missing

```powershell
.\DriveArchive.ps1 `
    -Mode Backup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -ArchiveFormat SevenZip `
    -Compression Balanced `
    -Threads 16
```

## Backup with automatic index creation when the index is missing

```powershell
.\DriveArchive.ps1 `
    -Mode Backup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -ArchiveFormat SevenZip `
    -Compression Balanced `
    -Threads 16 `
    -CreateIndexIfMissing
```

## Always generate a new index and create the backup

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -ArchiveFormat SevenZip `
    -Compression Balanced `
    -Threads 16
```

## Verify a backup

```powershell
.\DriveArchive.ps1 `
    -Mode Verify `
    -BackupFolder "D:\Backups\LilDev\LilDevBackup"
```

## Verify with an explicit thread count

```powershell
.\DriveArchive.ps1 `
    -Mode Verify `
    -BackupFolder "D:\Backups\LilDev\LilDevBackup" `
    -Threads 16
```

## Restore a backup

```powershell
.\DriveArchive.ps1 `
    -Mode Restore `
    -BackupFolder "D:\Backups\LilDev\LilDevBackup" `
    -RestoreDestination "L:\Restored"
```

## Restore with an explicit thread count

```powershell
.\DriveArchive.ps1 `
    -Mode Restore `
    -BackupFolder "D:\Backups\LilDev\LilDevBackup" `
    -RestoreDestination "L:\Restored" `
    -Threads 16
```

## Verify and restore

```powershell
$backupFolder = "D:\Backups\LilDev\LilDevBackup"
$restoreDestination = "L:\Restored"

try {
    .\DriveArchive.ps1 `
        -Mode Verify `
        -BackupFolder $backupFolder `
        -Threads 16

    .\DriveArchive.ps1 `
        -Mode Restore `
        -BackupFolder $backupFolder `
        -RestoreDestination $restoreDestination `
        -Threads 16
}
catch {
    Write-Error "Verification or restoration failed: $_"
    throw
}
```

# SevenZip Compression Examples

## SevenZip with Store compression

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDev-SevenZip-Store" `
    -ArchiveFormat SevenZip `
    -Compression Store `
    -Threads 16
```

## SevenZip with Fast compression

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDev-SevenZip-Fast" `
    -ArchiveFormat SevenZip `
    -Compression Fast `
    -Threads 16
```

## SevenZip with Balanced compression

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDev-SevenZip-Balanced" `
    -ArchiveFormat SevenZip `
    -Compression Balanced `
    -Threads 16
```

## SevenZip with Maximum compression

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDev-SevenZip-Maximum" `
    -ArchiveFormat SevenZip `
    -Compression Maximum `
    -Threads 16
```

## SevenZip with Store compression and solid mode

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDev-SevenZip-Store-Solid" `
    -ArchiveFormat SevenZip `
    -Compression Store `
    -Threads 16 `
    -Solid
```

## SevenZip with Fast compression and solid mode

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDev-SevenZip-Fast-Solid" `
    -ArchiveFormat SevenZip `
    -Compression Fast `
    -Threads 16 `
    -Solid
```

## SevenZip with Balanced compression and solid mode

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDev-SevenZip-Balanced-Solid" `
    -ArchiveFormat SevenZip `
    -Compression Balanced `
    -Threads 16 `
    -Solid
```

## SevenZip with Maximum compression and solid mode

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDev-SevenZip-Maximum-Solid" `
    -ArchiveFormat SevenZip `
    -Compression Maximum `
    -Threads 16 `
    -Solid
```

# ZIP Compression Examples

## ZIP with Store compression

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDev-Zip-Store" `
    -ArchiveFormat Zip `
    -Compression Store `
    -Threads 16
```

## ZIP with Fast compression

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDev-Zip-Fast" `
    -ArchiveFormat Zip `
    -Compression Fast `
    -Threads 16
```

## ZIP with Balanced compression

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDev-Zip-Balanced" `
    -ArchiveFormat Zip `
    -Compression Balanced `
    -Threads 16
```

## ZIP with Maximum compression

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDev-Zip-Maximum" `
    -ArchiveFormat Zip `
    -Compression Maximum `
    -Threads 16
```

# Thread Examples

## Single-threaded backup

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -Threads 1
```

## Use eight threads

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -Threads 8
```

## Use all logical processors

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -Threads ([Environment]::ProcessorCount)
```

## Reserve two logical processors

```powershell
$threads = [Math]::Max(
    1,
    [Environment]::ProcessorCount - 2
)

.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -Threads $threads
```

# Archive Hash Examples

## Create a backup without an archive hash

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -ArchiveFormat SevenZip `
    -Compression Balanced
```

## Create a backup with a SHA-256 archive hash

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -ArchiveFormat SevenZip `
    -Compression Balanced `
    -HashArchive
```

# Existing Archive Examples

## Refuse to replace an existing archive

```powershell
.\DriveArchive.ps1 `
    -Mode Backup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup"
```

## Replace an existing archive

```powershell
.\DriveArchive.ps1 `
    -Mode Backup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -Force
```

## Replace an existing archive and calculate its hash

```powershell
.\DriveArchive.ps1 `
    -Mode Backup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -Force `
    -HashArchive
```

# Missing Source File Examples

## Terminate if indexed files are missing

```powershell
.\DriveArchive.ps1 `
    -Mode Backup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup"
```

## Continue if indexed files are missing

```powershell
.\DriveArchive.ps1 `
    -Mode Backup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -AllowMissingFiles
```

## Automatically create a missing index and tolerate missing files

```powershell
.\DriveArchive.ps1 `
    -Mode Backup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -CreateIndexIfMissing `
    -AllowMissingFiles
```

# Explicit 7-Zip Path Examples

## Use an explicitly installed `7z.exe`

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -SevenZipPath "C:\Program Files\7-Zip\7z.exe"
```

## Use a standalone `7zz.exe`

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -SevenZipPath "C:\Tools\7-Zip\7zz.exe"
```

# Network Examples

## Local source and network destination

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "\\backup-server\archives\LilDev" `
    -BackupName "LilDevBackup" `
    -ArchiveFormat SevenZip `
    -Compression Fast `
    -Threads 16 `
    -HashArchive
```

## Network source and local destination

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "\\file-server\LilDev" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName "LilDevBackup" `
    -ArchiveFormat SevenZip `
    -Compression Balanced `
    -Threads 16 `
    -HashArchive
```

## Network source and network destination

```powershell
.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "\\source-server\LilDev" `
    -OutputRoot "\\backup-server\archives\LilDev" `
    -BackupName "LilDevBackup" `
    -ArchiveFormat SevenZip `
    -Compression Fast `
    -Threads 8 `
    -HashArchive
```

# Generated Backup Name Examples

## Date-based backup name

```powershell
$backupName = "LilDev-{0}" -f (Get-Date -Format "yyyy-MM-dd")

.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName $backupName `
    -ArchiveFormat SevenZip `
    -Compression Balanced `
    -Threads 16
```

## Timestamped backup name

```powershell
$backupName = "LilDev-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")

.\DriveArchive.ps1 `
    -Mode IndexAndBackup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName $backupName `
    -ArchiveFormat SevenZip `
    -Compression Balanced `
    -Threads 16 `
    -HashArchive
```

# Automation Examples

## Noninteractive backup

```powershell
$backupName = "LilDev-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")

.\DriveArchive.ps1 `
    -Mode Backup `
    -Source "L:\" `
    -OutputRoot "D:\Backups\LilDev" `
    -BackupName $backupName `
    -ArchiveFormat SevenZip `
    -Compression Fast `
    -Threads 16 `
    -CreateIndexIfMissing `
    -HashArchive
```

## Noninteractive backup followed by verification

```powershell
$backupName = "LilDev-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")
$outputRoot = "D:\Backups\LilDev"
$backupFolder = Join-Path $outputRoot $backupName

try {
    .\DriveArchive.ps1 `
        -Mode Backup `
        -Source "L:\" `
        -OutputRoot $outputRoot `
        -BackupName $backupName `
        -ArchiveFormat SevenZip `
        -Compression Fast `
        -Threads 16 `
        -CreateIndexIfMissing `
        -HashArchive

    .\DriveArchive.ps1 `
        -Mode Verify `
        -BackupFolder $backupFolder `
        -Threads 16
}
catch {
    Write-Error "Backup or verification failed: $_"
    throw
}
```

## Generate all valid archive combinations

```powershell
$source = "L:\"
$outputRoot = "D:\Backups\LilDev"
$threads = 16

$combinations = @(
    @{ Format = "SevenZip"; Compression = "Store";    Solid = $false }
    @{ Format = "SevenZip"; Compression = "Fast";     Solid = $false }
    @{ Format = "SevenZip"; Compression = "Balanced"; Solid = $false }
    @{ Format = "SevenZip"; Compression = "Maximum";  Solid = $false }
    @{ Format = "SevenZip"; Compression = "Store";    Solid = $true  }
    @{ Format = "SevenZip"; Compression = "Fast";     Solid = $true  }
    @{ Format = "SevenZip"; Compression = "Balanced"; Solid = $true  }
    @{ Format = "SevenZip"; Compression = "Maximum";  Solid = $true  }
    @{ Format = "Zip";      Compression = "Store";    Solid = $false }
    @{ Format = "Zip";      Compression = "Fast";     Solid = $false }
    @{ Format = "Zip";      Compression = "Balanced"; Solid = $false }
    @{ Format = "Zip";      Compression = "Maximum";  Solid = $false }
)

foreach ($combination in $combinations) {
    $solidName = if ($combination.Solid) {
        "Solid"
    }
    else {
        "NonSolid"
    }

    $backupName = "{0}-{1}-{2}" -f `
        $combination.Format, `
        $combination.Compression, `
        $solidName

    $parameters = @{
        Mode          = "IndexAndBackup"
        Source        = $source
        OutputRoot    = $outputRoot
        BackupName    = $backupName
        ArchiveFormat = $combination.Format
        Compression   = $combination.Compression
        Threads       = $threads
        HashArchive   = $true
    }

    if ($combination.Solid) {
        $parameters.Solid = $true
    }

    .\DriveArchive.ps1 @parameters
}
```

# Behavioral Matrix

## Mode Behavior

| Mode | Existing index | Missing index | Index action | Archive action | Interactive prompt |
|---|---|---|---|---|---|
| `Index` | Replaced | Created | Generates a complete index | No archive created | No |
| `Backup` | Used | User confirmation required | Reuses existing index or generates one after confirmation | Creates archive | Only when index is missing |
| `Backup -CreateIndexIfMissing` | Used | Created automatically | Reuses existing index or generates one | Creates archive | No |
| `IndexAndBackup` | Replaced | Created | Always generates a new complete index | Creates archive | No |
| `Verify` | Required | Fails | Reads and validates index | Tests archive integrity | No |
| `Restore` | Required | Fails | Reads index and reconstructs empty directories | Extracts archive | No |

## Archive Combination Matrix

| Archive format | Compression | Without `-Solid` | With `-Solid` |
|---|---|---:|---:|
| `SevenZip` | `Store` | Valid | Valid |
| `SevenZip` | `Fast` | Valid | Valid |
| `SevenZip` | `Balanced` | Valid | Valid |
| `SevenZip` | `Maximum` | Valid | Valid |
| `Zip` | `Store` | Valid | Invalid |
| `Zip` | `Fast` | Valid | Invalid |
| `Zip` | `Balanced` | Valid | Invalid |
| `Zip` | `Maximum` | Valid | Invalid |

## Switch Behavior Matrix

| Switch | Existing index | Missing index | Existing archive | Missing indexed source files | Archive hash |
|---|---|---|---|---|---|
| No optional switch | Used | Prompts | Fails | Fails | Not generated |
| `-CreateIndexIfMissing` | Used | Created automatically | Fails | Fails | Not generated |
| `-Force` | Used | Prompts | Replaced | Fails | Not generated |
| `-AllowMissingFiles` | Used | Prompts | Fails | Missing files omitted | Not generated |
| `-HashArchive` | Used | Prompts | Fails | Fails | Generated |
| `-CreateIndexIfMissing -Force` | Used | Created automatically | Replaced | Fails | Not generated |
| `-CreateIndexIfMissing -AllowMissingFiles` | Used | Created automatically | Fails | Missing files omitted | Not generated |
| `-CreateIndexIfMissing -HashArchive` | Used | Created automatically | Fails | Fails | Generated |
| `-Force -AllowMissingFiles -HashArchive` | Used | Prompts | Replaced | Missing files omitted | Generated |
| `-CreateIndexIfMissing -Force -AllowMissingFiles -HashArchive` | Used | Created automatically | Replaced | Missing files omitted | Generated |

## Output Matrix

| Mode | `.backup` | `.FileIndex.index` | `.metadata` |
|---|---:|---:|---:|
| `Index` | No | Yes | Yes |
| `Backup` | Yes | Yes | Yes |
| `Backup -CreateIndexIfMissing` | Yes | Yes | Yes |
| `IndexAndBackup` | Yes | Yes | Yes |
| `Verify` | Unchanged | Unchanged | Unchanged |
| `Restore` | Unchanged | Unchanged | Unchanged |