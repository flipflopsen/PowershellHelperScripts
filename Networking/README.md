# Networking

Scripts related to network tooling projects.

## Scripts

### `NetworkBridgeMITM.ps1`
Project scaffolder — generates a full Visual Studio solution for a
"Network Bridge" MITM (man-in-the-middle) proxy tool. Creates the solution
file, a `Models`/`Core`/`UI` project layout under `src/`, a `lib/WinDivert`
folder for the WinDivert packet-capture driver, a `docs` folder, and
generates starter `.csproj` and `.cs` files (including a
`PhysicalNetworkInterface` model). It does not itself run a MITM proxy — it
bootstraps the source tree for building one.

```powershell
.\NetworkBridgeMITM.ps1 -ProjectName "NetworkBridge" -BaseDir "."
```

**Parameters**
| Parameter | Description |
|---|---|
| `-ProjectName` | Name of the solution/project to scaffold (default `NetworkBridge`) |
| `-BaseDir` | Directory in which to create the project folder (default current directory) |

> ⚠️ This tool is intended for legitimate network diagnostics/development
> (e.g. building your own traffic-inspection tooling on networks you own or
> are authorized to test). Do not use it to intercept traffic without
> authorization.
