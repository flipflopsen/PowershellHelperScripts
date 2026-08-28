# WSL (Windows Subsystem for Linux)

Scripts for inspecting and troubleshooting WSL, particularly around disk
images and networking.

## Scripts

### `get_vhdx_of_wsl.ps1`
Reads the `HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss` registry
key to list every installed WSL distribution, its base install path, the
expected location of its `ext4.vhdx` virtual disk file, and whether that
file currently exists.

```powershell
.\get_vhdx_of_wsl.ps1
```

### `WslMirroredNEtworkModeFixWhenHavingStaticIp.ps1`
Auto-recovery loop for WSL networking failures that occur when the host
network adapter has a static IP configured together with WSL "mirrored"
networking mode (common `0x8007054f` / "Failed to configure network" /
"falling back to networkingMode" errors). On each attempt it:

1. Shuts down WSL (`wsl --shutdown`).
2. Flushes the ARP cache.
3. Restarts the Host Network Service (`hns`).
4. Re-applies the configured static IP/gateway/DNS to the target adapter.
5. Starts WSL and inspects its output for known error signatures.
6. Retries (up to `$maxAttempts`, default 15) until WSL starts cleanly, then
   idles in a keep-alive loop checking WSL is still responsive.

Must be run as Administrator. Edit `$adapter`, `$ip`, `$mask`, `$gateway`,
`$dns1`, `$dns2` at the top of the script to match your network before
running.

```powershell
.\WslMirroredNEtworkModeFixWhenHavingStaticIp.ps1
```
