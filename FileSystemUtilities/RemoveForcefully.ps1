#requires -RunAsAdministrator

$Target = 'F:\Backups\SwaggerDrive'
# If the actual folder is named SwaggerDrive, use:
# $Target = 'F:\Backups\SwaggerDrive'

$ErrorActionPreference = 'Stop'

# Normalize and validate the path.
$Target = [System.IO.Path]::GetFullPath($Target).TrimEnd('\')

$ProtectedPaths = @(
    'F:',
    'F:\',
    'F:\Backups',
    $env:SystemDrive,
    "$($env:SystemDrive)\"
)

if ($Target -in $ProtectedPaths -or $Target.Length -lt 10) {
    throw "Refusing to delete unsafe target path: $Target"
}

if (-not (Test-Path -LiteralPath $Target)) {
    Write-Host "The backup folder does not exist: $Target" -ForegroundColor Yellow
    exit 0
}

Write-Host ''
Write-Host 'PERMANENT DELETION TARGET:' -ForegroundColor Red
Write-Host $Target -ForegroundColor Yellow
Write-Host ''

$Confirmation = Read-Host 'Type DELETE to continue'

if ($Confirmation -cne 'DELETE') {
    Write-Host 'Deletion cancelled.'
    exit 0
}

Write-Host 'Taking ownership...' -ForegroundColor Cyan
& takeown.exe /F $Target /R /D Y
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Takeown returned exit code $LASTEXITCODE."
}

$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

Write-Host "Granting full control to $CurrentUser..." -ForegroundColor Cyan
& icacls.exe $Target /grant:r "${CurrentUser}:(OI)(CI)F" /T /C /Q
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Icacls returned exit code $LASTEXITCODE."
}

Write-Host 'Removing read-only, hidden, and system attributes...' -ForegroundColor Cyan
& attrib.exe -R -H -S $Target
& attrib.exe -R -H -S "$Target\*" /S /D

# Mirroring an empty directory into the backup is more reliable than
# Remove-Item for deeply nested directories and unusual attributes.
$EmptyDirectory = Join-Path $env:TEMP "EmptyForDeletion-$([guid]::NewGuid())"

try {
    New-Item -ItemType Directory -Path $EmptyDirectory -Force | Out-Null

    Write-Host 'Emptying the backup using Robocopy...' -ForegroundColor Cyan

    & robocopy.exe $EmptyDirectory $Target `
        /MIR `
        /XJ `
        /R:0 `
        /W:0 `
        /NFL `
        /NDL `
        /NJH `
        /NJS `
        /NP

    $RobocopyExitCode = $LASTEXITCODE

    # Robocopy codes below 8 are not fatal.
    if ($RobocopyExitCode -ge 8) {
        Write-Warning "Robocopy returned failure code $RobocopyExitCode. Attempting final deletion anyway."
    }

    Write-Host 'Removing the remaining directory...' -ForegroundColor Cyan

    # The extended-length path prefix helps with paths exceeding MAX_PATH.
    $ExtendedTarget = "\\?\$Target"
    & cmd.exe /D /C "rd /s /q `"$ExtendedTarget`""

    if (Test-Path -LiteralPath $Target) {
        throw @"
The directory still exists:

$Target

A file may be open or locked. Close Visual Studio, terminals, Explorer
windows, antivirus scans, and other applications using this directory,
then rerun the script or reboot and try again.
"@
    }

    Write-Host ''
    Write-Host 'Backup permanently deleted successfully.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $EmptyDirectory) {
        Remove-Item -LiteralPath $EmptyDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}