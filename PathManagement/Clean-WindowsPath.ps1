param(
    [switch]$Apply,
    [switch]$KeepMissing
)

$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDirectory = Join-Path $env:USERPROFILE "PathBackup-$timestamp"

New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')

# Back up the exact original strings.
Set-Content -LiteralPath "$backupDirectory\User-Path.txt" `
    -Value $userPath -Encoding UTF8

Set-Content -LiteralPath "$backupDirectory\Machine-Path.txt" `
    -Value $machinePath -Encoding UTF8

# Back up individual entries in JSON.
[pscustomobject]@{
    Timestamp      = Get-Date
    UserPath       = $userPath
    MachinePath    = $machinePath
    UserEntries    = @($userPath -split ';')
    MachineEntries = @($machinePath -split ';')
} | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath "$backupDirectory\PathBackup.json" -Encoding UTF8

# Export the registry environment keys as an additional backup.
& reg.exe export 'HKCU\Environment' `
    "$backupDirectory\HKCU-Environment.reg" /y | Out-Null

& reg.exe export `
    'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' `
    "$backupDirectory\HKLM-Environment.reg" /y | Out-Null

$removed = [System.Collections.Generic.List[object]]::new()

function Add-Removal {
    param(
        [string]$Scope,
        [string]$Entry,
        [string]$Reason
    )

    $removed.Add([pscustomobject]@{
        Scope  = $Scope
        Entry  = $Entry
        Reason = $Reason
    })
}

function Normalize-PathEntry {
    param([string]$Entry)

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        return $null
    }

    $value = $Entry.Trim().Trim('"')
    $value = $value -replace '/', '\'

    # Fix the specifically malformed concatenation in the current PATH.
    $bunPath = Join-Path $env:USERPROFILE '.bun\bin'
    $badSuffix = 'C:\Program Files\WindowsApps'

    if ($value.StartsWith(
            $bunPath + $badSuffix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        $value = $bunPath
    }

    # Collapse repeated backslashes while preserving an initial UNC prefix.
    if ($value.StartsWith('\\')) {
        $tail = $value.Substring(2) -replace '\\+', '\'
        $value = '\\' + $tail
    }
    else {
        $value = $value -replace '\\+', '\'
    }

    # Remove unnecessary trailing slashes, but preserve drive roots.
    if ($value -notmatch '^[A-Za-z]:\\$') {
        $value = $value.TrimEnd('\')
    }

    return $value
}

function Clean-PathEntries {
    param(
        [string]$Scope,
        [string]$PathValue,
        [System.Collections.Generic.HashSet[string]]$BlockedEntries
    )

    $result = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($originalEntry in @($PathValue -split ';')) {
        $entry = Normalize-PathEntry -Entry $originalEntry

        if ([string]::IsNullOrWhiteSpace($entry)) {
            if (-not [string]::IsNullOrWhiteSpace($originalEntry)) {
                Add-Removal -Scope $Scope -Entry $originalEntry `
                    -Reason 'Empty after normalization'
            }

            continue
        }

        if (-not $seen.Add($entry)) {
            Add-Removal -Scope $Scope -Entry $originalEntry `
                -Reason "Duplicate in $Scope PATH"
            continue
        }

        if ($null -ne $BlockedEntries -and $BlockedEntries.Contains($entry)) {
            Add-Removal -Scope $Scope -Entry $originalEntry `
                -Reason 'Already present in Machine PATH'
            continue
        }

        # PATH should contain directories, not executable files.
        if (Test-Path -LiteralPath $entry -PathType Leaf -ErrorAction SilentlyContinue) {
            Add-Removal -Scope $Scope -Entry $originalEntry `
                -Reason 'PATH entry points to a file, not a directory'
            continue
        }

        # Header/include directories should use INCLUDE or tool configuration.
        if ($entry -match '\\vcpkg\\installed\$$^\$$+\\include$') {
            Add-Removal -Scope $Scope -Entry $originalEntry `
                -Reason 'Header/include directory does not belong in PATH'
            continue
        }

        if (-not $KeepMissing) {
            $expandedEntry = [Environment]::ExpandEnvironmentVariables($entry)

            if (-not (Test-Path -LiteralPath $expandedEntry -PathType Container `
                    -ErrorAction SilentlyContinue)) {
                Add-Removal -Scope $Scope -Entry $originalEntry `
                    -Reason 'Directory does not exist'
                continue
            }
        }

        $result.Add($entry)
    }

    return $result.ToArray()
}

# Clean the Machine PATH first.
$cleanMachineEntries = @(
    Clean-PathEntries -Scope 'Machine' -PathValue $machinePath
)

# Prevent exact Machine entries from also appearing in the User PATH.
$machineSet = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase
)

foreach ($entry in $cleanMachineEntries) {
    $null = $machineSet.Add($entry)
}

$cleanUserEntries = @(
    Clean-PathEntries `
        -Scope 'User' `
        -PathValue $userPath `
        -BlockedEntries $machineSet
)

$cleanMachinePath = $cleanMachineEntries -join ';'
$cleanUserPath = $cleanUserEntries -join ';'

$summary = [pscustomobject]@{
    Mode                = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
    BackupDirectory     = $backupDirectory
    OldMachineLength    = $machinePath.Length
    NewMachineLength    = $cleanMachinePath.Length
    OldMachineEntries   = @($machinePath -split ';').Count
    NewMachineEntries   = $cleanMachineEntries.Count
    OldUserLength       = $userPath.Length
    NewUserLength       = $cleanUserPath.Length
    OldUserEntries      = @($userPath -split ';').Count
    NewUserEntries      = $cleanUserEntries.Count
    TotalRemovedEntries = $removed.Count
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
$summary | Format-List

Write-Host "`n=== ENTRIES TO REMOVE ===" -ForegroundColor Yellow
$removed |
    Sort-Object Scope, Reason, Entry |
    Format-Table Scope, Reason, Entry -AutoSize -Wrap

$removed |
    Export-Csv -LiteralPath "$backupDirectory\RemovedEntries.csv" `
    -NoTypeInformation -Encoding UTF8

Set-Content -LiteralPath "$backupDirectory\Clean-Machine-Path.txt" `
    -Value $cleanMachinePath -Encoding UTF8

Set-Content -LiteralPath "$backupDirectory\Clean-User-Path.txt" `
    -Value $cleanUserPath -Encoding UTF8

if (-not $Apply) {
    Write-Host "`nNo changes were made." -ForegroundColor Green
    Write-Host "Review the report, then run:" -ForegroundColor Green
    Write-Host "  .\Clean-WindowsPath.ps1 -Apply" -ForegroundColor White
    Write-Host ""
    Write-Host "To retain currently missing directories, use:" `
        -ForegroundColor Green
    Write-Host "  .\Clean-WindowsPath.ps1 -Apply -KeepMissing" `
        -ForegroundColor White
    return
}

[Environment]::SetEnvironmentVariable(
    'Path',
    $cleanMachinePath,
    [EnvironmentVariableTarget]::Machine
)

[Environment]::SetEnvironmentVariable(
    'Path',
    $cleanUserPath,
    [EnvironmentVariableTarget]::User
)

# Update this PowerShell process too.
$env:Path = @($cleanMachinePath, $cleanUserPath) |
    Where-Object { $_ } |
    Join-String -Separator ';'

Write-Host "`nPATH was updated successfully." -ForegroundColor Green
Write-Host "Backup: $backupDirectory" -ForegroundColor Green
Write-Host "Close and reopen terminals and applications." -ForegroundColor Yellow