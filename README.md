# Scripts

A collection of Windows PowerShell utility scripts, organized by category.
Each folder contains its own `README.md` with a description and usage
examples for the scripts inside.

## Categories

| Folder | Description |
|---|---|
| [`PathManagement/`](PathManagement/README.md) | Analyze, clean, sort, categorize, shim, backup, and restore the Windows `PATH` environment variable |
| [`BackupAndSync/`](BackupAndSync/README.md) | Robocopy-based backup verification/sync and a general folder-diff tool |
| [`FileSystemUtilities/`](FileSystemUtilities/README.md) | Forceful/robust directory deletion for stubborn files and folders |
| [`WSL/`](WSL/README.md) | Inspect WSL disk images and recover WSL networking |
| [`Networking/`](Networking/README.md) | Scaffolding for a network bridge / MITM proxy development project |
| [`SystemHardware/`](SystemHardware/README.md) | Manage Bluetooth devices via PnP |

## General usage notes

* All scripts are PowerShell (`.ps1`) and were written/tested on Windows.
* Scripts that modify system state (PATH, PnP devices, filesystem) support
  `-WhatIf` and/or prompt for confirmation where available — **always
  preview before applying changes**.
* Scripts touching Machine-scope settings (e.g. Machine `PATH`, device
  removal, forceful deletion) require an elevated (Administrator)
  PowerShell session.
* Several scripts contain hardcoded paths (backup source/destination
  directories, target directories, network adapter settings) that are
  specific to the original author's machine — **review and edit these
  values at the top of the script before running them on another machine**.

## Requirements

* Windows PowerShell 5.1+ or PowerShell 7+
* Administrator privileges for scripts that modify system-level state
* Robocopy (built into Windows) for `BackupAndSync` scripts
* WSL installed for scripts in `WSL/`
