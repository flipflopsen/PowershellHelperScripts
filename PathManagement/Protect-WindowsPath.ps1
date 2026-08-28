<#
.SYNOPSIS
    Backs up or restores the persistent Windows PATH configuration.

.EXAMPLE
    .\Protect-WindowsPath.ps1 -Mode Backup

.EXAMPLE
    .\Protect-WindowsPath.ps1 -Mode Backup -BackupRoot 'D:\Backups'

.EXAMPLE
    .\Protect-WindowsPath.ps1 -Mode Restore `
        -BackupDirectory 'D:\Backups\WindowsPath-20260820-153000'

.NOTES
    Restoring the Machine PATH requires an elevated PowerShell session.
    Close and reopen terminals after restoring.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Backup', 'Restore')]
    [string]$Mode,

    [string]$BackupRoot = "$env:USERPROFILE\WindowsPathBackups",

    [string]$BackupDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$UserRegistryPath = 'Environment'
$MachineRegistryPath =
    'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Get-RegistryPathValue {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('User', 'Machine')]
        [string]$Scope
    )

    if ($Scope -eq 'User') {
        $baseKey = [Microsoft.Win32.Registry]::CurrentUser
        $registryPath = $UserRegistryPath
    }
    else {
        $baseKey = [Microsoft.Win32.Registry]::LocalMachine
        $registryPath = $MachineRegistryPath
    }

    $key = $baseKey.OpenSubKey($registryPath, $false)

    if ($null -eq $key) {
        throw "Could not open the $Scope environment registry key."
    }

    try {
        $valueNames = $key.GetValueNames()
        $pathExists = $valueNames -contains 'Path'

        if (-not $pathExists) {
            return [pscustomobject]@{
                Scope      = $Scope
                Exists     = $false
                Value      = $null
                ValueKind  = $null
                Length     = 0
                EntryCount = 0
            }
        }

        # Do not expand strings such as %USERPROFILE%.
        $value = $key.GetValue(
            'Path',
            $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
        )

        $valueKind = $key.GetValueKind('Path').ToString()

        return [pscustomobject]@{
            Scope      = $Scope
            Exists     = $true
            Value      = [string]$value
            ValueKind  = $valueKind
            Length     = ([string]$value).Length
            EntryCount = @(([string]$value) -split ';').Count
        }
    }
    finally {
        $key.Dispose()
    }
}

function Set-RegistryPathValue {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('User', 'Machine')]
        [string]$Scope,

        [Parameter(Mandatory)]
        [bool]$Exists,

        [AllowNull()]
        [string]$Value,

        [AllowNull()]
        [string]$ValueKind
    )

    if ($Scope -eq 'User') {
        $baseKey = [Microsoft.Win32.Registry]::CurrentUser
        $registryPath = $UserRegistryPath
    }
    else {
        $baseKey = [Microsoft.Win32.Registry]::LocalMachine
        $registryPath = $MachineRegistryPath
    }

    $key = $baseKey.OpenSubKey($registryPath, $true)

    if ($null -eq $key) {
        throw "Could not open the $Scope environment registry key for writing."
    }

    try {
        if (-not $Exists) {
            if ($key.GetValueNames() -contains 'Path') {
                $key.DeleteValue('Path', $false)
            }

            return
        }

        $kind = switch ($ValueKind) {
            'String' {
                [Microsoft.Win32.RegistryValueKind]::String
            }
            'ExpandString' {
                [Microsoft.Win32.RegistryValueKind]::ExpandString
            }
            default {
                # PATH is normally REG_SZ or REG_EXPAND_SZ.
                [Microsoft.Win32.RegistryValueKind]::ExpandString
            }
        }

        $key.SetValue('Path', [string]$Value, $kind)
    }
    finally {
        $key.Dispose()
    }
}

function Send-EnvironmentChangeNotification {
    $source = @'
using System;
using System.Runtime.InteropServices;

public static class EnvironmentBroadcaster
{
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint message,
        UIntPtr wParam,
        string lParam,
        uint flags,
        uint timeout,
        out UIntPtr result
    );

    public static void Broadcast()
    {
        const int HWND_BROADCAST = 0xffff;
        const uint WM_SETTINGCHANGE = 0x001A;
        const uint SMTO_ABORTIFHUNG = 0x0002;

        UIntPtr result;

        SendMessageTimeout(
            new IntPtr(HWND_BROADCAST),
            WM_SETTINGCHANGE,
            UIntPtr.Zero,
            "Environment",
            SMTO_ABORTIFHUNG,
            5000,
            out result
        );
    }
}
'@

    if (-not ('EnvironmentBroadcaster' -as [type])) {
        Add-Type -TypeDefinition $source
    }

    [EnvironmentBroadcaster]::Broadcast()
}

function Export-RegistrySafetyCopies {
    param(
        [Parameter(Mandatory)]
        [string]$Destination
    )

    $userRegFile = Join-Path $Destination 'HKCU-Environment.reg'
    $machineRegFile = Join-Path $Destination 'HKLM-Environment.reg'

    & reg.exe export 'HKCU\Environment' $userRegFile /y | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'The HKCU registry export failed.'
    }

    & reg.exe export `
        'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' `
        $machineRegFile /y | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'The HKLM registry export failed.'
    }
}

function New-PathBackup {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    }

    $destination = Join-Path $BackupRoot "WindowsPath-$timestamp"
    New-Item -ItemType Directory -Path $destination -Force | Out-Null

    $userPath = Get-RegistryPathValue -Scope User
    $machinePath = Get-RegistryPathValue -Scope Machine

    $backup = [ordered]@{
        FormatVersion = 1
        Created        = (Get-Date).ToString('o')
        ComputerName   = $env:COMPUTERNAME
        UserName       = [Environment]::UserName
        Windows        = (Get-CimInstance Win32_OperatingSystem).Caption
        WindowsBuild   = (Get-CimInstance Win32_OperatingSystem).BuildNumber
        PowerShell     = $PSVersionTable.PSVersion.ToString()
        UserPath       = $userPath
        MachinePath    = $machinePath

        # This is informational. It is not used during restoration.
        ProcessPath = [ordered]@{
            Value      = $env:Path
            Length     = if ($null -eq $env:Path) { 0 } else { $env:Path.Length }
            EntryCount = if ($null -eq $env:Path) {
                0
            }
            else {
                @($env:Path -split ';').Count
            }
        }
    }

    $jsonFile = Join-Path $destination 'WindowsPathBackup.json'

    $backup |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $jsonFile -Encoding UTF8

    # Human-readable copies.
    Set-Content `
        -LiteralPath (Join-Path $destination 'UserPath.txt') `
        -Value $userPath.Value `
        -Encoding UTF8

    Set-Content `
        -LiteralPath (Join-Path $destination 'MachinePath.txt') `
        -Value $machinePath.Value `
        -Encoding UTF8

    $userPath.Value -split ';' |
        Set-Content `
            -LiteralPath (Join-Path $destination 'UserPath-Entries.txt') `
            -Encoding UTF8

    $machinePath.Value -split ';' |
        Set-Content `
            -LiteralPath (Join-Path $destination 'MachinePath-Entries.txt') `
            -Encoding UTF8

    Export-RegistrySafetyCopies -Destination $destination

    # Create a hash after the main backup file is complete.
    Get-FileHash -LiteralPath $jsonFile -Algorithm SHA256 |
        Select-Object Algorithm, Hash, Path |
        Export-Clixml -LiteralPath (Join-Path $destination 'BackupHash.xml')

    Write-Host ''
    Write-Host 'PATH backup created successfully.' -ForegroundColor Green
    Write-Host "Backup directory: $destination" -ForegroundColor Cyan

    [pscustomobject]@{
        Scope      = 'User'
        Length     = $userPath.Length
        EntryCount = $userPath.EntryCount
        ValueKind  = $userPath.ValueKind
    }

    [pscustomobject]@{
        Scope      = 'Machine'
        Length     = $machinePath.Length
        EntryCount = $machinePath.EntryCount
        ValueKind  = $machinePath.ValueKind
    }

    Write-Host ''
    Write-Host 'Restore command:' -ForegroundColor Yellow
    Write-Host (
        ".\Protect-WindowsPath.ps1 -Mode Restore " +
        "-BackupDirectory `"$destination`""
    ) -ForegroundColor White
}

function Restore-PathBackup {
    if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
        throw 'Specify -BackupDirectory when using Restore mode.'
    }

    $resolvedBackupDirectory = (
        Resolve-Path -LiteralPath $BackupDirectory
    ).Path

    $jsonFile = Join-Path `
        $resolvedBackupDirectory `
        'WindowsPathBackup.json'

    $hashFile = Join-Path $resolvedBackupDirectory 'BackupHash.xml'

    if (-not (Test-Path -LiteralPath $jsonFile -PathType Leaf)) {
        throw "Backup file not found: $jsonFile"
    }

    if (-not (Test-IsAdministrator)) {
        throw @'
Restore mode must be run from PowerShell as Administrator because the
Machine PATH is stored under HKEY_LOCAL_MACHINE.
'@
    }

    if (Test-Path -LiteralPath $hashFile -PathType Leaf) {
        $expectedHash = Import-Clixml -LiteralPath $hashFile
        $actualHash = Get-FileHash -LiteralPath $jsonFile -Algorithm SHA256

        if ($expectedHash.Hash -ne $actualHash.Hash) {
            throw 'Backup integrity check failed. The JSON file has changed.'
        }

        Write-Host 'Backup integrity check passed.' -ForegroundColor Green
    }
    else {
        Write-Warning 'No backup hash was found; integrity cannot be verified.'
    }

    $backup = Get-Content -LiteralPath $jsonFile -Raw |
        ConvertFrom-Json

    if ($backup.FormatVersion -ne 1) {
        throw "Unsupported backup format: $($backup.FormatVersion)"
    }

    Write-Host ''
    Write-Host 'Backup information:' -ForegroundColor Cyan

    [pscustomobject]@{
        Created             = $backup.Created
        Computer            = $backup.ComputerName
        User                = $backup.UserName
        BackupUserLength    = $backup.UserPath.Length
        BackupMachineLength = $backup.MachinePath.Length
    } | Format-List

    $currentUser = Get-RegistryPathValue -Scope User
    $currentMachine = Get-RegistryPathValue -Scope Machine

    Write-Host 'Current versus backup:' -ForegroundColor Cyan

    @(
        [pscustomobject]@{
            Scope         = 'User'
            CurrentLength = $currentUser.Length
            BackupLength  = $backup.UserPath.Length
        }
        [pscustomobject]@{
            Scope         = 'Machine'
            CurrentLength = $currentMachine.Length
            BackupLength  = $backup.MachinePath.Length
        }
    ) | Format-Table -AutoSize

    # Make another backup immediately before restoring.
    $preRestoreRoot = Join-Path `
        $resolvedBackupDirectory `
        'BeforeRestore'

    $script:BackupRoot = $preRestoreRoot

    Write-Host 'Creating a safety backup of the current PATH...' `
        -ForegroundColor Yellow

    New-PathBackup

    $description = "Restore User and Machine PATH from $resolvedBackupDirectory"

    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, $description)) {
        return
    }

    Set-RegistryPathValue `
        -Scope User `
        -Exists ([bool]$backup.UserPath.Exists) `
        -Value ([string]$backup.UserPath.Value) `
        -ValueKind ([string]$backup.UserPath.ValueKind)

    Set-RegistryPathValue `
        -Scope Machine `
        -Exists ([bool]$backup.MachinePath.Exists) `
        -Value ([string]$backup.MachinePath.Value) `
        -ValueKind ([string]$backup.MachinePath.ValueKind)

    Send-EnvironmentChangeNotification

    $restoredUser = Get-RegistryPathValue -Scope User
    $restoredMachine = Get-RegistryPathValue -Scope Machine

    if (
        $restoredUser.Value -cne [string]$backup.UserPath.Value -or
        $restoredMachine.Value -cne [string]$backup.MachinePath.Value
    ) {
        throw 'The post-restore verification failed.'
    }

    Write-Host ''
    Write-Host 'PATH restoration completed and verified.' `
        -ForegroundColor Green

    Write-Host (
        'Close and reopen terminals, editors, and other applications ' +
        'to receive the restored PATH.'
    ) -ForegroundColor Yellow

    Write-Host (
        'Signing out and back in is recommended for all applications.'
    ) -ForegroundColor Yellow
}

switch ($Mode) {
    'Backup' {
        New-PathBackup
    }

    'Restore' {
        Restore-PathBackup
    }
}