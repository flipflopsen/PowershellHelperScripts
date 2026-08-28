#Requires -Version 7.2

<#
.SYNOPSIS
    Creates, verifies, and restores indexed compressed drive backups.

.DESCRIPTION
    Modes:

      Index
          Generates an editable textual index and metadata, but no archive.

      Backup
          Creates an archive from an existing index.

      IndexAndBackup
          Generates a new index and immediately creates the archive.

      Verify
          Tests the archive using 7-Zip.

      Restore
          Extracts the archive and recreates indexed empty directories.

    Output structure:

      <OutputRoot>\<BackupName>\
          <BackupName>.backup
          <BackupName>.FileIndex.index
          <BackupName>.metadata

    In Index mode, the .backup file is not created.

.INDEX FORMAT
    Each index entry consists of an entry type, a TAB, and a path relative
    to the source root:

      D<TAB>directory\path
      F<TAB>directory\path\file.ext

    Lines beginning with '#' and blank lines are ignored.

    To exclude one file:
      Delete its F line.

    To exclude an entire directory:
      Delete its D line. All descendants become ineffective even if their
      subordinate lines remain in the index.

    The archive contains only indexed files. Indexed directories are used
    during restoration to recreate empty directories.

.LIMITATIONS
    This is a file-content archive, not a filesystem image. It does not
    preserve partition tables, boot sectors, filesystem journals, NTFS ACLs,
    alternate data streams, EFS state, hard-link relationships, or all
    reparse-point semantics.

    Reparse points are skipped deliberately to avoid traversing junctions
    into other volumes or creating recursive traversal.

    Files locked for exclusive access cannot be archived consistently.
    For a live system volume, create and archive a VSS snapshot instead.

.EXAMPLE
    .\DriveArchive.ps1 `
        -Mode Index `
        -Source "D:\" `
        -OutputRoot "E:\Backups" `
        -BackupName "Data-2026-08-25"

.EXAMPLE
    # Edit the generated index, then:
    .\DriveArchive.ps1 `
        -Mode Backup `
        -Source "D:\" `
        -OutputRoot "E:\Backups" `
        -BackupName "Data-2026-08-25" `
        -ArchiveFormat SevenZip `
        -Compression Balanced `
        -Threads 16

.EXAMPLE
    .\DriveArchive.ps1 `
        -Mode IndexAndBackup `
        -Source "D:\" `
        -OutputRoot "\\server\backup" `
        -BackupName "Workstation-Data" `
        -Compression Fast `
        -Threads 12

.EXAMPLE
    .\DriveArchive.ps1 `
        -Mode Restore `
        -BackupFolder "E:\Backups\Data-2026-08-25" `
        -RestoreDestination "D:\Recovered" `
        -Threads 16

.EXAMPLE
    .\DriveArchive.ps1 `
        -Mode Verify `
        -BackupFolder "E:\Backups\Data-2026-08-25"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(
        "Index",
        "Backup",
        "IndexAndBackup",
        "Restore",
        "Verify"
    )]
    [string]$Mode,

    # Required by Index, Backup, and IndexAndBackup.
    [string]$Source,

    # Required by Index, Backup, and IndexAndBackup.
    [string]$OutputRoot,

    # Required by Index, Backup, and IndexAndBackup.
    [ValidatePattern('^[^<>:"/\\|?*\x00-\x1F]+$')]
    [string]$BackupName,

    # Required by Restore and Verify.
    [string]$BackupFolder,

    # Required by Restore.
    [string]$RestoreDestination,

    [ValidateSet("SevenZip", "Zip")]
    [string]$ArchiveFormat = "SevenZip",

    [ValidateSet("Store", "Fast", "Balanced", "Maximum")]
    [string]$Compression = "Balanced",

    [ValidateRange(1, 256)]
    [int]$Threads = [Math]::Max(1, [Environment]::ProcessorCount),

    # SevenZip only. Improves compression ratio, but decreases random-access
    # extraction and damage recoverability.
    [switch]$Solid,

    # Computing this hash requires reading the completed archive in full.
    [switch]$HashArchive,

    # Allow replacement of an existing archive.
    [switch]$Force,

    # Continue when files that existed in the index are now missing.
    [switch]$AllowMissingFiles,

    # In Backup mode, automatically generate a complete index when the expected
    # index is absent. Without this switch, an interactive confirmation prompt
    # is displayed.
    [switch]$CreateIndexIfMissing,

    # Explicit path to 7z.exe or 7zz.exe.
    [string]$SevenZipPath,

    # Suppress PowerShell progress displays. Useful for unattended execution,
    # redirected output, and log-oriented environments.
    [switch]$NoProgress,

    # Progress rendering is throttled because frequent Write-Progress calls can
    # materially reduce indexing performance.
    [ValidateRange(100, 10000)]
    [int]$ProgressIntervalMilliseconds = 250
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:EnumerationErrors = [System.Collections.Generic.List[string]]::new()

$script:DefaultExcludedDirectoryNames =
    [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

[void]$script:DefaultExcludedDirectoryNames.Add(
    "System Volume Information"
)

[void]$script:DefaultExcludedDirectoryNames.Add(
    '$RECYCLE.BIN'
)

function Test-IsDefaultExcludedDirectory {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$Directory
    )

    return $script:DefaultExcludedDirectoryNames.Contains(
        $Directory.Name
    )
}

function Get-SevenZipExecutable {
    param(
        [string]$ExplicitPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            throw "The specified 7-Zip executable does not exist: $ExplicitPath"
        }

        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    foreach ($candidate in @("7z.exe", "7zz.exe", "7z", "7zz")) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue

        if ($null -ne $command) {
            return $command.Source
        }
    }

    $commonPaths = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )

    foreach ($candidate in $commonPaths) {
        if (
            -not [string]::IsNullOrWhiteSpace($candidate) -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)
        ) {
            return $candidate
        }
    }

    throw @"
7-Zip was not found. Install 7-Zip or provide -SevenZipPath.

For example:

    winget install --id 7zip.7zip --exact
"@
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory)]
        [string]$Executable,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [string]$WorkingDirectory,

        [switch]$SuppressOutput
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $SuppressOutput.IsPresent
    $startInfo.RedirectStandardError = $SuppressOutput.IsPresent

    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    foreach ($argument in $ArgumentList) {
        $null = $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo

    Write-Verbose (
        "Executing: {0} {1}" -f
        $Executable,
        ($ArgumentList -join " ")
    )

    if (-not $process.Start()) {
        throw "Failed to start native process: $Executable"
    }

    $standardOutput = $null
    $standardError = $null

    if ($SuppressOutput) {
        $standardOutput = $process.StandardOutput.ReadToEnd()
        $standardError = $process.StandardError.ReadToEnd()
    }

    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()

    return [PSCustomObject]@{
        ExitCode = $exitCode
        StdOut   = $standardOutput
        StdErr   = $standardError
    }
}

function Get-NormalizedDirectoryPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$MustExist
    )

    if ($MustExist -and -not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Directory does not exist: $Path"
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)

    if (
        $fullPath.Length -gt 3 -and
        $fullPath.EndsWith(
            [System.IO.Path]::DirectorySeparatorChar.ToString()
        )
    ) {
        $fullPath = $fullPath.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    }

    return $fullPath
}

function Test-IsReparsePoint {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    return (
        $Item.Attributes -band
        [System.IO.FileAttributes]::ReparsePoint
    ) -ne 0
}

function Get-RelativeArchivePath {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$FullPath
    )

    $relative = [System.IO.Path]::GetRelativePath($Root, $FullPath)

    # Normalize index and archive paths to Windows-style separators.
    return $relative.Replace(
        [System.IO.Path]::AltDirectorySeparatorChar,
        [System.IO.Path]::DirectorySeparatorChar
    )
}

function Test-SafeRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $false
    }

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        return $false
    }

    if ($RelativePath.IndexOf([char]0) -ge 0) {
        return $false
    }

    $components = $RelativePath -split '[\\/]'

    foreach ($component in $components) {
        if (
            [string]::IsNullOrEmpty($component) -or
            $component -eq "." -or
            $component -eq ".."
        ) {
            return $false
        }
    }

    return $true
}

function Get-ParentRelativePaths {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    $result = [System.Collections.Generic.List[string]]::new()
    $parent = [System.IO.Path]::GetDirectoryName($RelativePath)

    while (-not [string]::IsNullOrWhiteSpace($parent)) {
        $result.Add($parent)
        $parent = [System.IO.Path]::GetDirectoryName($parent)
    }

    return $result
}

function Write-BackupIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$IndexPath,

        # Directories listed here are excluded completely. This is primarily
        # used to prevent the backup directory from being indexed when it is
        # located below SourceRoot.
        [string[]]$ExcludedDirectoryPaths = @(),

        [bool]$DisplayProgress = $true,

        [ValidateRange(100, 10000)]
        [int]$ProgressIntervalMilliseconds = 250
    )

    $script:EnumerationErrors.Clear()

    $sourceDirectory = [System.IO.DirectoryInfo]::new($SourceRoot)

    if (-not $sourceDirectory.Exists) {
        throw "Source directory does not exist: $SourceRoot"
    }

    $temporaryIndex = "$IndexPath.tmp"

    [System.IO.File]::Delete($temporaryIndex)

    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)

    # SequentialScan and a large buffer reduce unnecessary kernel transitions
    # when writing indexes containing millions of entries.
    $fileStream = [System.IO.FileStream]::new(
        $temporaryIndex,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None,
        4MB,
        [System.IO.FileOptions]::SequentialScan
    )

    $writer = [System.IO.StreamWriter]::new(
        $fileStream,
        $utf8WithoutBom,
        4MB,
        $false
    )

    $excludedFullPaths =
        [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

    foreach ($excludedPath in $ExcludedDirectoryPaths) {
        if ([string]::IsNullOrWhiteSpace($excludedPath)) {
            continue
        }

        $normalizedExcludedPath = Get-NormalizedDirectoryPath `
            -Path $excludedPath

        [void]$excludedFullPaths.Add($normalizedExcludedPath)
    }

    $enumerationOptions = [System.IO.EnumerationOptions]::new()
    $enumerationOptions.RecurseSubdirectories = $false
    $enumerationOptions.IgnoreInaccessible = $false
    $enumerationOptions.ReturnSpecialDirectories = $false
    $enumerationOptions.AttributesToSkip = [System.IO.FileAttributes]0
    $enumerationOptions.MatchType = [System.IO.MatchType]::Simple

    $directoryQueue =
        [System.Collections.Generic.Queue[System.IO.DirectoryInfo]]::new()

    $directoryQueue.Enqueue($sourceDirectory)

    $directoryCount = 0L
    $fileCount = 0L
    $totalBytes = 0L
    $excludedDirectoryCount = 0L
    $reparsePointCount = 0L
    $visitedEntryCount = 0L
    $progressId = 10
    $progressStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastProgressUpdateMilliseconds = -$ProgressIntervalMilliseconds

    if ($DisplayProgress) {
        Write-Progress `
            -Id $progressId `
            -Activity "Indexing $SourceRoot" `
            -Status "Initializing filesystem traversal..." `
            -CurrentOperation $SourceRoot
    }

    $completed = $false

    try {
        $writer.WriteLine("# Cosverse indexed archive file list")
        $writer.WriteLine("# Version: 1")
        $writer.WriteLine(
            "# GeneratedUtc: $([DateTime]::UtcNow.ToString('o'))"
        )
        $writer.WriteLine("# Source: $SourceRoot")
        $writer.WriteLine("#")
        $writer.WriteLine("# D<TAB>relative directory path")
        $writer.WriteLine("# F<TAB>relative file path")
        $writer.WriteLine("#")
        $writer.WriteLine("# Delete an F line to exclude that file.")
        $writer.WriteLine(
            "# Delete a D line to exclude that directory and its subtree."
        )
        $writer.WriteLine(
            "# Do not convert relative paths to absolute paths."
        )
        $writer.WriteLine("")

        while ($directoryQueue.Count -gt 0) {
            $currentDirectory = $directoryQueue.Dequeue()

            try {
                $entries = $currentDirectory.EnumerateFileSystemInfos(
                    "*",
                    $enumerationOptions
                )

                foreach ($entry in $entries) {
                    $visitedEntryCount++

                    if (
                        $DisplayProgress -and
                        (
                            $progressStopwatch.ElapsedMilliseconds -
                            $lastProgressUpdateMilliseconds
                        ) -ge $ProgressIntervalMilliseconds
                    ) {
                        $lastProgressUpdateMilliseconds =
                            $progressStopwatch.ElapsedMilliseconds

                        $elapsedSeconds = [Math]::Max(
                            0.001,
                            $progressStopwatch.Elapsed.TotalSeconds
                        )

                        $entriesPerSecond = [long](
                            $visitedEntryCount / $elapsedSeconds
                        )

                        $statusFormat = (
                            '{0:N0} files | {1:N0} directories | {2:N2} GiB | ' +
                            '{3:N0} queued | {4:N0} entries/s'
                        )

                        $status = $statusFormat -f @(
                            $fileCount
                            $directoryCount
                            ($totalBytes / 1GB)
                            $directoryQueue.Count
                            $entriesPerSecond
                        )

                        Write-Progress `
                            -Id $progressId `
                            -Activity "Indexing $SourceRoot" `
                            -Status $status `
                            -CurrentOperation $currentDirectory.FullName
                    }
                    try {
                        $isDirectory =
                            $entry -is [System.IO.DirectoryInfo]

                        # Apply name-based exclusions before reading attributes,
                        # writing the index entry, or enqueueing the directory.
                        if (
                            $isDirectory -and
                            $script:DefaultExcludedDirectoryNames.Contains(
                                $entry.Name
                            )
                        ) {
                            $excludedDirectoryCount++

                            Write-Verbose (
                                "Skipping protected directory: {0}" -f
                                $entry.FullName
                            )

                            continue
                        }

                        if (
                            $isDirectory -and
                            $excludedFullPaths.Contains(
                                (
                                    Get-NormalizedDirectoryPath `
                                        -Path $entry.FullName
                                )
                            )
                        ) {
                            $excludedDirectoryCount++

                            Write-Verbose (
                                "Skipping explicitly excluded directory: {0}" -f
                                $entry.FullName
                            )

                            continue
                        }

                        # Attribute access can itself fail, so it remains
                        # inside the per-entry exception boundary.
                        if (Test-IsReparsePoint -Item $entry) {
                            $reparsePointCount++

                            Write-Verbose (
                                "Skipping reparse point: {0}" -f
                                $entry.FullName
                            )

                            continue
                        }

                        $relativePath = Get-RelativeArchivePath `
                            -Root $SourceRoot `
                            -FullPath $entry.FullName

                        if (-not (Test-SafeRelativePath $relativePath)) {
                            $message = (
                                "Skipped unsafe path: {0}" -f
                                $entry.FullName
                            )

                            $script:EnumerationErrors.Add($message)
                            Write-Warning $message
                            continue
                        }

                        if ($isDirectory) {
                            $writer.Write("D`t")
                            $writer.WriteLine($relativePath)

                            $directoryCount++
                            $directoryQueue.Enqueue(
                                [System.IO.DirectoryInfo]$entry
                            )
                        }
                        else {
                            # Obtain and validate all metadata before modifying the index or counters.
                            # This prevents partially recorded entries if metadata access fails.
                            $fileLength = 0L

                            if ($entry -is [System.IO.FileInfo]) {
                                $fileLength = [long]$entry.Length

                                # File lengths are non-negative. Check explicitly because PowerShell
                                # has no C#-style checked arithmetic expression.
                                if ($fileLength -gt ([long]::MaxValue - $totalBytes)) {
                                    throw (
                                        "The cumulative indexed size exceeds the Int64 maximum " +
                                        "of {0:N0} bytes." -f [long]::MaxValue
                                    )
                                }
                            }

                            $writer.Write("F`t")
                            $writer.WriteLine($relativePath)

                            $fileCount++
                            $totalBytes = [long]($totalBytes + $fileLength)
                        }
                    }
                    catch {
                        $message = (
                            "Cannot index '{0}': {1}" -f
                            $entry.FullName,
                            $_.Exception.Message
                        )

                        $script:EnumerationErrors.Add($message)
                        Write-Warning $message
                    }
                }
            }
            catch {
                $message = (
                    "Cannot enumerate directory '{0}': {1}" -f
                    $currentDirectory.FullName,
                    $_.Exception.Message
                )

                $script:EnumerationErrors.Add($message)
                Write-Warning $message
            }
        }

        $writer.Flush()
        $fileStream.Flush($true)
        $completed = $true
    }
    finally {
        $progressStopwatch.Stop()
        $writer.Dispose()

        if ($DisplayProgress) {
            Write-Progress `
                -Id $progressId `
                -Activity "Indexing $SourceRoot" `
                -Completed
        }
    }

    if (-not $completed) {
        [System.IO.File]::Delete($temporaryIndex)
        throw "Index generation did not complete."
    }

    # The completed temporary file replaces the index only after all buffered
    # data has been flushed to the filesystem.
    [System.IO.File]::Move(
        $temporaryIndex,
        $IndexPath,
        $true
    )

    return [PSCustomObject]@{
        DirectoryCount         = $directoryCount
        FileCount              = $fileCount
        TotalBytes             = $totalBytes
        ErrorCount             = $script:EnumerationErrors.Count
        ExcludedDirectoryCount = $excludedDirectoryCount
        ReparsePointCount      = $reparsePointCount
        VisitedEntryCount      = $visitedEntryCount
        ElapsedSeconds         = [Math]::Round(
            $progressStopwatch.Elapsed.TotalSeconds,
            3
        )
        AverageEntriesPerSecond = if (
            $progressStopwatch.Elapsed.TotalSeconds -gt 0
        ) {
            [long](
                $visitedEntryCount /
                $progressStopwatch.Elapsed.TotalSeconds
            )
        }
        else {
            0L
        }
        Traversal = "BreadthFirstQueue"
    }
}

function Read-BackupIndex {
    param(
        [Parameter(Mandatory)]
        [string]$IndexPath
    )

    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        throw "Backup index does not exist: $IndexPath"
    }

    $directories = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $files = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $lineNumber = 0

    foreach ($line in [System.IO.File]::ReadLines($IndexPath)) {
        $lineNumber++

        if (
            [string]::IsNullOrWhiteSpace($line) -or
            $line.StartsWith("#")
        ) {
            continue
        }

        $parts = $line.Split("`t", 2)

        if ($parts.Count -ne 2) {
            throw "Invalid index syntax at line $lineNumber."
        }

        $entryType = $parts[0].Trim().ToUpperInvariant()
        $relativePath = $parts[1]

        if (-not (Test-SafeRelativePath $relativePath)) {
            throw (
                "Unsafe relative path at index line {0}: {1}" -f
                $lineNumber,
                $relativePath
            )
        }

        switch ($entryType) {
            "D" {
                $null = $directories.Add($relativePath)
            }

            "F" {
                $null = $files.Add($relativePath)
            }

            default {
                throw (
                    "Unsupported entry type '{0}' at index line {1}." -f
                    $entryType,
                    $lineNumber
                )
            }
        }
    }

    # A file or directory is effective only if every indexed ancestor remains.
    # Consequently, deleting one D line excludes its complete subtree.
    $effectiveDirectories = [System.Collections.Generic.List[string]]::new()

    foreach ($directory in $directories) {
        $included = $true

        foreach ($parent in Get-ParentRelativePaths $directory) {
            if (-not $directories.Contains($parent)) {
                $included = $false
                break
            }
        }

        if ($included) {
            $effectiveDirectories.Add($directory)
        }
    }

    $effectiveFiles = [System.Collections.Generic.List[string]]::new()

    foreach ($file in $files) {
        $included = $true

        foreach ($parent in Get-ParentRelativePaths $file) {
            if (-not $directories.Contains($parent)) {
                $included = $false
                break
            }
        }

        if ($included) {
            $effectiveFiles.Add($file)
        }
    }

    return [PSCustomObject]@{
        Directories = $effectiveDirectories
        Files       = $effectiveFiles
    }
}

function Get-Sha256 {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Write-Metadata {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    $temporaryPath = "$Path.tmp"
    $json = $Data | ConvertTo-Json -Depth 8

    [System.IO.File]::WriteAllText(
        $temporaryPath,
        $json,
        [System.Text.UTF8Encoding]::new($false)
    )

    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-CompressionArguments {
    param(
        [Parameter(Mandatory)]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Format,

        [Parameter(Mandatory)]
        [int]$ThreadCount,

        [switch]$UseSolidCompression
    )

    $arguments = [System.Collections.Generic.List[string]]::new()

    switch ($Level) {
        "Store"    { $arguments.Add("-mx=0") }
        "Fast"     { $arguments.Add("-mx=1") }
        "Balanced" { $arguments.Add("-mx=5") }
        "Maximum"  { $arguments.Add("-mx=9") }
    }

    $arguments.Add("-mmt=$ThreadCount")

    if ($Format -eq "SevenZip") {
        if ($UseSolidCompression) {
            $arguments.Add("-ms=on")
        }
        else {
            $arguments.Add("-ms=off")
        }
    }
    elseif ($UseSolidCompression) {
        throw "-Solid is supported only with -ArchiveFormat SevenZip."
    }

    return $arguments
}

function New-IndexedArchive {
    param(
        [Parameter(Mandatory)]
        [string]$SevenZip,

        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$IndexPath,

        [Parameter(Mandatory)]
        [string]$ArchivePath
    )

    if (
        [System.IO.File]::Exists($ArchivePath) -and
        -not $Force
    ) {
        throw "Archive already exists. Use -Force to replace it: $ArchivePath"
    }

    $index = Read-BackupIndex -IndexPath $IndexPath

    if ($index.Files.Count -eq 0) {
        throw "The effective index contains no files."
    }

    $temporaryList = Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        ("archive-list-{0}.txt" -f [Guid]::NewGuid().ToString("N"))

    $temporaryArchive = "$ArchivePath.partial"

    Remove-Item `
        -LiteralPath $temporaryArchive `
        -Force `
        -ErrorAction SilentlyContinue

    $validFiles = [System.Collections.Generic.List[string]]::new()
    $missingFiles = [System.Collections.Generic.List[string]]::new()

    try {
        foreach ($relativeFile in $index.Files) {
            $absoluteFile = [System.IO.Path]::GetFullPath(
                [System.IO.Path]::Combine($SourceRoot, $relativeFile)
            )

            if ([System.IO.File]::Exists($absoluteFile)) {
                $validFiles.Add($relativeFile)
            }
            else {
                $missingFiles.Add($relativeFile)
            }
        }

        if ($missingFiles.Count -gt 0) {
            $message = (
                "{0} indexed files are no longer present. First entries: {1}" -f
                $missingFiles.Count,
                (($missingFiles | Select-Object -First 10) -join "; ")
            )

            if (-not $AllowMissingFiles) {
                throw "$message Use -AllowMissingFiles to continue."
            }

            Write-Warning $message
        }

        if ($validFiles.Count -eq 0) {
            throw "None of the indexed files currently exists."
        }

        [System.IO.File]::WriteAllLines(
            $temporaryList,
            $validFiles,
            [System.Text.UTF8Encoding]::new($false)
        )

        $typeArgument = if ($ArchiveFormat -eq "SevenZip") {
            "-t7z"
        }
        else {
            "-tzip"
        }

        $arguments = [System.Collections.Generic.List[string]]::new()
        $arguments.Add("a")
        $arguments.Add($typeArgument)
        $arguments.Add("-scsUTF-8")
        $arguments.Add("-spd")
        $arguments.Add("-y")
        $arguments.Add("-bso1")
        $arguments.Add("-bse1")

        if (-not $NoProgress) {
            $arguments.Add("-bsp1")
        }
        else {
            $arguments.Add("-bsp0")
        }

        foreach (
            $argument in Get-CompressionArguments `
                -Level $Compression `
                -Format $ArchiveFormat `
                -ThreadCount $Threads `
                -UseSolidCompression:$Solid
        ) {
            $arguments.Add($argument)
        }

        $arguments.Add($temporaryArchive)
        $arguments.Add("@$temporaryList")

        Write-Host "Creating archive with $($validFiles.Count) files..."

        $result = Invoke-NativeProcess `
            -Executable $SevenZip `
            -ArgumentList $arguments `
            -WorkingDirectory $SourceRoot

        # 7-Zip: 0 = success, 1 = warning, >= 2 = error/fatal.
        if ($result.ExitCode -gt 1) {
            throw "7-Zip archive creation failed with exit code $($result.ExitCode)."
        }

        if (-not (Test-Path -LiteralPath $temporaryArchive -PathType Leaf)) {
            throw "7-Zip did not produce the expected temporary archive."
        }

        Move-Item `
            -LiteralPath $temporaryArchive `
            -Destination $ArchivePath `
            -Force

        return [PSCustomObject]@{
            IndexedFileCount = $index.Files.Count
            ArchivedFileCount = $validFiles.Count
            MissingFileCount = $missingFiles.Count
            DirectoryCount = $index.Directories.Count
            ArchiveBytes = (Get-Item -LiteralPath $ArchivePath).Length
        }
    }
    finally {
        Remove-Item `
            -LiteralPath $temporaryList `
            -Force `
            -ErrorAction SilentlyContinue

        Remove-Item `
            -LiteralPath $temporaryArchive `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

function Read-Metadata {
    param(
        [Parameter(Mandatory)]
        [string]$MetadataPath
    )

    if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) {
        throw "Metadata file does not exist: $MetadataPath"
    }

    return Get-Content -LiteralPath $MetadataPath -Raw |
        ConvertFrom-Json
}

function Test-BackupArchive {
    param(
        [Parameter(Mandatory)]
        [string]$SevenZip,

        [Parameter(Mandatory)]
        [string]$ArchivePath,

        [Parameter(Mandatory)]
        [string]$Format
    )

    $typeArgument = if ($Format -eq "SevenZip") {
        "-t7z"
    }
    else {
        "-tzip"
    }

    $progressArgument = if ($NoProgress) {
        "-bsp0"
    }
    else {
        "-bsp1"
    }

    $result = Invoke-NativeProcess `
        -Executable $SevenZip `
        -ArgumentList @(
            "t",
            $typeArgument,
            "-mmt=$Threads",
            $progressArgument,
            "-y",
            $ArchivePath
        )

    if ($result.ExitCode -gt 1) {
        throw "Archive verification failed with exit code $($result.ExitCode)."
    }
}

function Restore-BackupArchive {
    param(
        [Parameter(Mandatory)]
        [string]$SevenZip,

        [Parameter(Mandatory)]
        [string]$ArchivePath,

        [Parameter(Mandatory)]
        [string]$IndexPath,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$Format
    )

    $null = New-Item `
        -ItemType Directory `
        -Path $Destination `
        -Force

    $typeArgument = if ($Format -eq "SevenZip") {
        "-t7z"
    }
    else {
        "-tzip"
    }

    $progressArgument = if ($NoProgress) {
        "-bsp0"
    }
    else {
        "-bsp1"
    }

    $arguments = @(
        "x",
        $typeArgument,
        "-mmt=$Threads",
        $progressArgument,
        "-y",
        "-o$Destination",
        $ArchivePath
    )

    $result = Invoke-NativeProcess `
        -Executable $SevenZip `
        -ArgumentList $arguments

    if ($result.ExitCode -gt 1) {
        throw "Archive extraction failed with exit code $($result.ExitCode)."
    }

    # Files implicitly recreate their parent directories. This additional pass
    # recreates directories that were empty when the archive was created.
    $index = Read-BackupIndex -IndexPath $IndexPath

    foreach (
        $relativeDirectory in
        $index.Directories |
            Sort-Object { ($_ -split '[\\/]').Count }
    ) {
        $directoryPath = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::Combine(
                $Destination,
                $relativeDirectory
            )
        )

        $null = New-Item `
            -ItemType Directory `
            -Path $directoryPath `
            -Force
    }
}

function Confirm-MissingIndexCreation {
    param(
        [Parameter(Mandatory)]
        [string]$ExpectedIndexPath,

        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [switch]$AutomaticallyConfirm
    )

    Write-Warning @"
The expected backup index does not exist:

    $ExpectedIndexPath

Backup mode normally uses an existing, potentially edited index. Continuing
will generate a complete index from the current source and then create the
archive.

Source:

    $SourceRoot

The resulting archive remains a standard 7z or ZIP archive and can be
extracted manually with 7-Zip independently of this script.
"@

    if ($AutomaticallyConfirm) {
        Write-Warning (
            "Automatic index creation was authorized by " +
            "-CreateIndexIfMissing."
        )

        return $true
    }

    $yesChoice = [System.Management.Automation.Host.ChoiceDescription]::new(
        "&Yes",
        "Generate a complete index and continue with the backup."
    )

    $noChoice = [System.Management.Automation.Host.ChoiceDescription]::new(
        "&No",
        "Cancel the backup without creating an index or archive."
    )

    $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
        $yesChoice,
        $noChoice
    )

    try {
        $selection = $Host.UI.PromptForChoice(
            "Missing backup index",
            (
                "Generate a complete index from the current source and " +
                "continue with the backup?"
            ),
            $choices,
            1
        )
    }
    catch {
        throw @"
The index is missing and the current PowerShell host cannot display an
interactive confirmation prompt.

For unattended execution, explicitly authorize automatic index creation:

    -CreateIndexIfMissing
"@
    }

    return $selection -eq 0
}

$requiresSevenZip = $Mode -in @(
    "Backup",
    "IndexAndBackup",
    "Restore",
    "Verify"
)

$sevenZip = if ($requiresSevenZip) {
    Get-SevenZipExecutable -ExplicitPath $SevenZipPath
}
else {
    $null
}

if ($Mode -in @("Index", "Backup", "IndexAndBackup")) {
    if ([string]::IsNullOrWhiteSpace($Source)) {
        throw "-Source is required for mode $Mode."
    }

    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        throw "-OutputRoot is required for mode $Mode."
    }

    if ([string]::IsNullOrWhiteSpace($BackupName)) {
        throw "-BackupName is required for mode $Mode."
    }

    $sourceRoot = Get-NormalizedDirectoryPath -Path $Source -MustExist
    $outputRootPath = Get-NormalizedDirectoryPath -Path $OutputRoot
    $backupDirectory = Join-Path $outputRootPath $BackupName

    $null = New-Item `
        -ItemType Directory `
        -Path $backupDirectory `
        -Force

    $archivePath = Join-Path $backupDirectory "$BackupName.backup"
    $indexPath = Join-Path $backupDirectory "$BackupName.FileIndex.index"
    $metadataPath = Join-Path $backupDirectory "$BackupName.metadata"

    $indexStatistics = $null
    $archiveStatistics = $null

    if ($Mode -in @("Index", "IndexAndBackup")) {
        Write-Host "Indexing source: $sourceRoot"

        $indexStatistics = Write-BackupIndex `
            -SourceRoot $sourceRoot `
            -IndexPath $indexPath `
            -ExcludedDirectoryPaths @($backupDirectory) `
            -DisplayProgress:(-not $NoProgress) `
            -ProgressIntervalMilliseconds $ProgressIntervalMilliseconds

        Write-Host (
            "Indexed {0:N0} files, {1:N0} directories, {2:N0} bytes." -f
            $indexStatistics.FileCount,
            $indexStatistics.DirectoryCount,
            $indexStatistics.TotalBytes
        )

        if ($indexStatistics.ExcludedDirectoryCount -gt 0) {
            Write-Verbose (
                "Excluded {0:N0} protected or configured directories." -f
                $indexStatistics.ExcludedDirectoryCount
            )
        }

        if ($indexStatistics.ReparsePointCount -gt 0) {
            Write-Verbose (
                "Skipped {0:N0} filesystem reparse points." -f
                $indexStatistics.ReparsePointCount
            )
        }

        if ($indexStatistics.ErrorCount -gt 0) {
            Write-Warning (
                "{0:N0} filesystem entries could not be indexed. " +
                "Consult EnumerationErrors in the metadata file." -f
                $indexStatistics.ErrorCount
            )
        }
    }

    if (
        $Mode -eq "Backup" -and
        -not (Test-Path -LiteralPath $indexPath -PathType Leaf)
    ) {
        $continueWithGeneratedIndex = Confirm-MissingIndexCreation `
            -ExpectedIndexPath $indexPath `
            -SourceRoot $sourceRoot `
            -AutomaticallyConfirm:$CreateIndexIfMissing

        if (-not $continueWithGeneratedIndex) {
            throw "Backup cancelled because no index was available."
        }

        Write-Host ""
        Write-Host "Generating a complete source index..."
        Write-Host "Source: $sourceRoot"
        Write-Host "Index:  $indexPath"
        Write-Host ""

        $indexStatistics = Write-BackupIndex `
            -SourceRoot $sourceRoot `
            -IndexPath $indexPath `
            -ExcludedDirectoryPaths @($backupDirectory) `
            -DisplayProgress:(-not $NoProgress) `
            -ProgressIntervalMilliseconds $ProgressIntervalMilliseconds

        Write-Host (
            "Indexed {0:N0} files, {1:N0} directories, and {2:N0} bytes." -f
            $indexStatistics.FileCount,
            $indexStatistics.DirectoryCount,
            $indexStatistics.TotalBytes
        )

        if ($indexStatistics.ExcludedDirectoryCount -gt 0) {
            Write-Verbose (
                "Excluded {0:N0} protected or configured directories." -f
                $indexStatistics.ExcludedDirectoryCount
            )
        }

        if ($indexStatistics.ReparsePointCount -gt 0) {
            Write-Verbose (
                "Skipped {0:N0} filesystem reparse points." -f
                $indexStatistics.ReparsePointCount
            )
        }

        if ($indexStatistics.ErrorCount -gt 0) {
            Write-Warning (
                "{0:N0} filesystem entries could not be indexed. " +
                "Consult EnumerationErrors in the metadata file." -f
                $indexStatistics.ErrorCount
            )
        }
    }

    if ($Mode -in @("Backup", "IndexAndBackup")) {
        $archiveStatistics = New-IndexedArchive `
            -SevenZip $sevenZip `
            -SourceRoot $sourceRoot `
            -IndexPath $indexPath `
            -ArchivePath $archivePath
    }

    $metadata = [ordered]@{
        SchemaVersion = 1
        BackupName = $BackupName
        Status = if ($Mode -eq "Index") {
            "IndexedOnly"
        }
        else {
            "Complete"
        }
        Source = $sourceRoot
        CreatedUtc = [DateTime]::UtcNow.ToString("o")
        ArchivePresent = Test-Path -LiteralPath $archivePath -PathType Leaf
        ArchiveFile = "$BackupName.backup"
        IndexFile = "$BackupName.FileIndex.index"
        MetadataFile = "$BackupName.metadata"
        ArchiveFormat = $ArchiveFormat
        Compression = $Compression
        CompressionThreads = $Threads
        SolidCompression = $Solid.IsPresent
        IndexSha256 = Get-Sha256 -Path $indexPath
        ArchiveSha256 = if (
            $HashArchive -and
            (Test-Path -LiteralPath $archivePath -PathType Leaf)
        ) {
            Get-Sha256 -Path $archivePath
        }
        else {
            $null
        }
        IndexStatistics = $indexStatistics
        ArchiveStatistics = $archiveStatistics
        EnumerationErrors = @($script:EnumerationErrors)
        Preservation = [ordered]@{
            FileContents = $true
            RelativePaths = $true
            EmptyDirectories = $true
            BasicFileTimestamps = "Archive-format-dependent"
            NtfsAcl = $false
            AlternateDataStreams = $false
            HardLinks = $false
            ReparsePoints = $false
            EfsState = $false
        }
    }

    Write-Metadata -Path $metadataPath -Data $metadata

    Write-Host ""
    Write-Host "Backup directory: $backupDirectory"
    Write-Host "Index:            $indexPath"
    Write-Host "Metadata:         $metadataPath"

    if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
        Write-Host "Archive:          $archivePath"
    }
    else {
        Write-Host "Archive:          not created (index-only mode)"
    }

    [PSCustomObject]$metadata
    return
}

if ($Mode -in @("Restore", "Verify")) {
    if ([string]::IsNullOrWhiteSpace($BackupFolder)) {
        throw "-BackupFolder is required for mode $Mode."
    }

    $backupDirectory = Get-NormalizedDirectoryPath `
        -Path $BackupFolder `
        -MustExist

    $metadataCandidates = @(
        Get-ChildItem `
            -LiteralPath $backupDirectory `
            -Filter "*.metadata" `
            -File
    )

    if ($metadataCandidates.Count -ne 1) {
        throw (
            "Expected exactly one .metadata file in '{0}', but found {1}." -f
            $backupDirectory,
            $metadataCandidates.Count
        )
    }

    $metadataPath = $metadataCandidates[0].FullName
    $metadata = Read-Metadata -MetadataPath $metadataPath

    $archivePath = Join-Path $backupDirectory $metadata.ArchiveFile
    $indexPath = Join-Path $backupDirectory $metadata.IndexFile

    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw "Backup archive does not exist: $archivePath"
    }

    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        throw "Backup index does not exist: $indexPath"
    }

    $currentIndexHash = Get-Sha256 -Path $indexPath

    if ($currentIndexHash -ne $metadata.IndexSha256) {
        Write-Warning @"
The index SHA-256 differs from the value recorded in metadata. The index may
have been edited after archive creation. Archive extraction remains possible,
but empty-directory reconstruction may differ from the original backup.
"@
    }

    if (-not [string]::IsNullOrWhiteSpace($metadata.ArchiveSha256)) {
        Write-Host "Validating archive SHA-256..."
        $currentArchiveHash = Get-Sha256 -Path $archivePath

        if ($currentArchiveHash -ne $metadata.ArchiveSha256) {
            throw "Archive SHA-256 validation failed."
        }
    }

    if ($Mode -eq "Verify") {
        Write-Host "Testing archive integrity..."

        Test-BackupArchive `
            -SevenZip $sevenZip `
            -ArchivePath $archivePath `
            -Format $metadata.ArchiveFormat

        Write-Host "Archive verification completed successfully."

        [PSCustomObject]@{
            BackupFolder = $backupDirectory
            Archive = $archivePath
            Verified = $true
            ArchiveFormat = $metadata.ArchiveFormat
        }

        return
    }

    if ([string]::IsNullOrWhiteSpace($RestoreDestination)) {
        throw "-RestoreDestination is required for Restore mode."
    }

    $restorePath = Get-NormalizedDirectoryPath -Path $RestoreDestination

    Write-Host "Restoring archive to: $restorePath"

    Restore-BackupArchive `
        -SevenZip $sevenZip `
        -ArchivePath $archivePath `
        -IndexPath $indexPath `
        -Destination $restorePath `
        -Format $metadata.ArchiveFormat

    Write-Host "Restore completed successfully."

    [PSCustomObject]@{
        BackupFolder = $backupDirectory
        Archive = $archivePath
        RestoreDestination = $restorePath
        Restored = $true
    }
}