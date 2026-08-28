# Find-CodeProjects

`Find-CodeProjects.ps1` detects programming projects from a DriveArchive index and optionally extracts relevant source files into a clean staging directory.

The source filesystem is never modified.

## Features

- Detects projects across common programming languages and build systems.
- Uses repository and project markers such as `.git`, `*.sln`, `*.csproj`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `pom.xml`, `CMakeLists.txt`, and `Makefile`.
- Extracts source code, project metadata, documentation, and CI configuration.
- Excludes dependencies, build outputs, caches, binaries, VCS internals, and known sensitive files.
- Supports custom filename and folder exclusions through `exclusions.txt`.
- Preserves project-relative directory structures.
- Generates CSV and JSON reports.

## Requirements

- PowerShell 7.2 or newer.
- A DriveArchive index using:

```text
F<TAB>relative\file\path.ext
D<TAB>relative\directory
```

- Access to the original indexed source for extraction.

## Exclusions

Create `exclusions.txt` beside the script:

```yaml
FilenameParts:
  - unity

FolderParts:
  - Cybersec
  - Security
```

Matching is case-insensitive and uses literal substrings:

- `FilenameParts` applies only to filenames.
- `FolderParts` applies to directory components.
- Matching paths are excluded from detection, scanning, and reports.

For example, `Security\Tools\vds6\Makefile` is completely excluded because its path contains the folder `Security`.

## Analyze

Detect projects and generate reports without copying files:

```powershell
.\Find-CodeProjects.ps1 `
    -Mode Analyze `
    -IndexPath "D:\Backup\Drive.index.txt" `
    -SourceRoot "L:\" `
    -OutputRoot "D:\CodeRecovery"
```

## Extract

Copy relevant files into an isolated staging directory:

```powershell
.\Find-CodeProjects.ps1 `
    -Mode Extract `
    -IndexPath "D:\Backup\Drive.index.txt" `
    -SourceRoot "L:\" `
    -OutputRoot "D:\CodeRecovery"
```

Preview extraction without copying:

```powershell
.\Find-CodeProjects.ps1 `
    -Mode Extract `
    -IndexPath "D:\Backup\Drive.index.txt" `
    -SourceRoot "L:\" `
    -OutputRoot "D:\CodeRecovery" `
    -WhatIf
```

## Important options

| Option | Description |
|---|---|
| `-Mode` | `Analyze` or `Extract`; default: `Analyze` |
| `-MinimumProjectScore` | Higher values reduce false positives; default: `3` |
| `-ExclusionsPath` | Custom path to `exclusions.txt` |
| `-RunName` | Assigns a deterministic output-directory name |
| `-Force` | Replaces an existing run directory |
| `-NoProgress` | Disables progress output |
| `-WhatIf` | Previews extraction operations |

## Output

```text
CodeDiscovery_YYYYMMDD_HHMMSS\
├── ExtractedProjects\       # Extract mode only
│   ├── ProjectName--hash\
│   └── _Unclassified\
└── Reports\
    ├── projects.csv
    ├── files.csv
    └── summary.json
```

- `projects.csv`: detected projects, scores, evidence, and file counts.
- `files.csv`: classified files and extraction status.
- `summary.json`: run configuration, counts, exclusions, and report paths.

## Security

Detection and secret exclusion are heuristic. Before publishing extracted projects, review them for credentials, private keys, API tokens, personal data, proprietary content, and licensing restrictions.