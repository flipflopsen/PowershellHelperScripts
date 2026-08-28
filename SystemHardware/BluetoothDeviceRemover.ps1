# Bluetooth Device Manager Script
param(
    [string]$DeviceName,
    [switch]$ListOnly,
    [switch]$RemoveAll,
    [switch]$WhatIf
)

# Function to list Bluetooth devices
function Get-BluetoothDevices {
    return Get-PnpDevice | Where-Object {$_.Class -eq "Bluetooth" -or $_.Class -eq "BluetoothLE"}
}

# List devices
if ($ListOnly -or -not $DeviceName) {
    Write-Host "=== Bluetooth Devices ===" -ForegroundColor Cyan
    $devices = Get-BluetoothDevices
    $devices | Format-Table @{
        Name = "Device Name"
        Expression = {$_.Name}
        Width = 40
    }, @{
        Name = "Status"
        Expression = {$_.Status}
        Width = 15
    }, @{
        Name = "Instance ID"
        Expression = {$_.InstanceId}
        Width = 50
    }
    
    Write-Host "Total Bluetooth devices found: $($devices.Count)" -ForegroundColor Green
    exit
}

# Remove specific device
if ($DeviceName) {
    $devices = Get-BluetoothDevices | Where-Object {$_.Name -like "*$DeviceName*"}
    
    if ($devices.Count -eq 0) {
        Write-Host "❌ No Bluetooth device found matching '$DeviceName'" -ForegroundColor Red
        exit
    }
    
    Write-Host "Found $($devices.Count) matching device(s):" -ForegroundColor Yellow
    $devices | ForEach-Object { Write-Host "  • $($_.Name)" -ForegroundColor White }
    
    if ($WhatIf) {
        Write-Host "[WHAT-IF] Would remove the above devices" -ForegroundColor Yellow
        exit
    }
    
    $confirm = Read-Host "Remove these devices? (y/N)"
    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        foreach ($device in $devices) {
            try {
                $device | Remove-PnpDevice -Confirm:$false
                Write-Host "✅ Removed: $($device.Name)" -ForegroundColor Green
            } catch {
                Write-Host "❌ Failed to remove: $($device.Name) - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

# Remove all Bluetooth devices (dangerous)
if ($RemoveAll) {
    Write-Host "⚠️  WARNING: This will remove ALL Bluetooth devices!" -ForegroundColor Red
    $confirm = Read-Host "Are you absolutely sure? Type 'REMOVE ALL' to confirm"
    
    if ($confirm -eq "REMOVE ALL") {
        $devices = Get-BluetoothDevices
        foreach ($device in $devices) {
            try {
                $device | Remove-PnpDevice -Confirm:$false
                Write-Host "✅ Removed: $($device.Name)" -ForegroundColor Green
            } catch {
                Write-Host "❌ Failed to remove: $($device.Name)" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "❌ Operation cancelled" -ForegroundColor Yellow
    }
}
