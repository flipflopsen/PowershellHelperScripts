# System & Hardware

Scripts for managing Windows hardware devices.

## Scripts

### `BluetoothDeviceRemover.ps1`
Lists and removes paired/known Bluetooth devices via `Get-PnpDevice` /
`Remove-PnpDevice`.

```powershell
# List all Bluetooth devices (default action if no other switch is given)
.\BluetoothDeviceRemover.ps1 -ListOnly

# Remove device(s) matching a name (prompts for confirmation)
.\BluetoothDeviceRemover.ps1 -DeviceName "Sony"

# Preview what would be removed without removing anything
.\BluetoothDeviceRemover.ps1 -DeviceName "Sony" -WhatIf

# Remove ALL Bluetooth devices (requires typing REMOVE ALL to confirm)
.\BluetoothDeviceRemover.ps1 -RemoveAll
```

**Parameters**
| Parameter | Description |
|---|---|
| `-DeviceName` | Substring to match against device names for removal |
| `-ListOnly` | List devices only, take no action |
| `-RemoveAll` | Remove every Bluetooth device (double confirmation required) |
| `-WhatIf` | Preview removal of matched devices without removing them |

> ⚠️ `-RemoveAll` is destructive and will unpair every Bluetooth device on
> the system.
