Write-Host "=== Windows ==="
Get-ComputerInfo |
    Select-Object WindowsProductName, WindowsVersion, OsBuildNumber, OsArchitecture

Write-Host "`n=== PowerShell ==="
$PSVersionTable

Write-Host "`n=== LongPathsEnabled ==="
Get-ItemPropertyValue `
    -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
    -Name LongPathsEnabled `
    -ErrorAction SilentlyContinue

Write-Host "`n=== Group Policy registry setting ==="
Get-ItemProperty `
    -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
    -Name LongPathsEnabled `
    -ErrorAction SilentlyContinue