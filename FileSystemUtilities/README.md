# File System Utilities

Utility scripts for filesystem cleanup that go beyond what `Remove-Item`
can reliably handle (locked handles, deep nesting, unusual attributes,
ACL/ownership issues).

## Scripts

### `RemoveForcefully.ps1`
Permanently and forcefully deletes a target directory (hardcoded to
`F:\Backups\SwaggerDrive` — edit `$Target` before use) even when it has
read-only/hidden/system attributes, restrictive ACLs, or deeply nested
paths that exceed `MAX_PATH`. It:

1. Validates the target isn't a protected/root-level path.
2. Takes ownership (`takeown`) and grants full control (`icacls`).
3. Strips read-only/hidden/system attributes recursively.
4. Mirrors an empty folder over the target with Robocopy `/MIR` to empty it.
5. Removes the now-empty directory using an extended-length path (`\\?\`)
   via `cmd.exe /C rd /s /q`.

Requires an elevated (Administrator) PowerShell session (`#requires
-RunAsAdministrator`). Prompts for a typed `DELETE` confirmation before doing
anything destructive — **there is no undo**.

```powershell
.\RemoveForcefully.ps1
```

> ⚠️ Edit the `$Target` variable at the top of the script to point at the
> directory you actually want removed before running it.
