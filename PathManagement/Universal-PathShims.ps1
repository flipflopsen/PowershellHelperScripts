<#
.SYNOPSIS
  Dynamic PATH Executables Analyzer and Universal Shim Creator with Backup/Restore and Safe Update

.DESCRIPTION
  - Scans your PATH for all executables.
  - Suggests and creates a single shim directory for all tools.
  - Backs up User and Machine PATH before changes.
  - Allows restoring from backup.
  - Optionally updates PATH with the cleaned version.
  - Safe WhatIf mode for previewing all actions.

.PARAMETER ShimDirectory
  Directory to store universal shims.

.PARAMETER WhatIf
  Preview all actions, make no changes.

.PARAMETER UpdatePath
  If set, will update your PATH with the cleaned version.

.PARAMETER Backup
  Create a backup of current PATH variables.

.PARAMETER Restore
  Restore PATH variables from a specified backup.

.PARAMETER Force
  Skip confirmation prompts.

.PARAMETER IncludeSystemTools
  Include system tools in analysis (normally excluded for safety).

.PARAMETER ExcludeDirectories
  Array of directories to exclude from analysis.

.PARAMETER ExcludeExecutables
  Array of executables to exclude from shim creation.

.EXAMPLE
  .\Universal-PathShims.ps1 -WhatIf
  .\Universal-PathShims.ps1 -UpdatePath
  .\Universal-PathShims.ps1 -Restore "C:\Users\Lance\Desktop\PATH_Backup_2025-07-09_13-45-00.json"
#>

param(
    [string]$ShimDirectory = "C:\Users\$env:USERNAME\UniversalShims",
    [switch]$WhatIf = $false,
    [switch]$UpdatePath = $false,
    [switch]$Backup = $false,
    [string]$Restore = "",
    [switch]$Force = $false,
    [switch]$IncludeSystemTools = $false,
    [string[]]$ExcludeDirectories = @(),
    [string[]]$ExcludeExecutables = @()
)

# Default exclusions for system executables that shouldn't be shimmed
$defaultSystemExclusions = @(
    "svchost.exe", "explorer.exe", "winlogon.exe", "csrss.exe", "dwm.exe",
    "taskmgr.exe", "services.exe", "lsass.exe", "smss.exe", "wininit.exe",
    "taskhost.exe", "dllhost.exe", "rundll32.exe", "mmc.exe", "notepad.exe",
    "calc.exe", "mspaint.exe", "write.exe", "wordpad.exe"
)

# System directories that should be excluded unless explicitly included
$systemDirectories = @(
    "C:\Windows\system32",
    "C:\Windows\SysWOW64", 
    "C:\Windows\System32\Wbem",
    "C:\Windows\System32\WindowsPowerShell\v1.0",
    "C:\Windows\System32\OpenSSH"
)

# Function to create PATH backup
function Backup-PathVariables {
    $backup = @{
        Date = Get-Date
        UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
    }
    $backupPath = "$env:USERPROFILE\Desktop\PATH_Backup_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
    $backup | ConvertTo-Json | Set-Content -Path $backupPath -Encoding UTF8
    Write-Host "✅ PATH backup saved to: $backupPath" -ForegroundColor Green
    return $backupPath
}

# Function to restore PATH from backup
function Restore-PathVariables {
    param([string]$BackupFile)
    
    if (-not (Test-Path $BackupFile)) {
        Write-Host "❌ Backup file not found: $BackupFile" -ForegroundColor Red
        return $false
    }
    
    try {
        $backup = Get-Content $BackupFile -Raw | ConvertFrom-Json
        Write-Host "📁 Restoring PATH from backup created: $($backup.Date)" -ForegroundColor Yellow
        Write-Host "   Computer: $($backup.ComputerName), User: $($backup.UserName)" -ForegroundColor Gray
        
        if (-not $Force) {
            $confirm = Read-Host "Are you sure you want to restore PATH? (y/N)"
            if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                Write-Host "❌ Restore cancelled by user" -ForegroundColor Yellow
                return $false
            }
        }
        
        [Environment]::SetEnvironmentVariable("Path", $backup.UserPath, "User")
        [Environment]::SetEnvironmentVariable("Path", $backup.MachinePath, "Machine")
        Write-Host "✅ PATH restored from backup successfully" -ForegroundColor Green
        Write-Host "🔄 Please restart your terminal for changes to take effect" -ForegroundColor Yellow
        return $true
    } catch {
        Write-Host "❌ Error restoring backup: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to normalize paths for comparison
function Normalize-Path($p) {
    if (-not $p) { return "" }
    return ($p.TrimEnd('\','/')).ToLowerInvariant()
}

# Function to check if a directory should be excluded
function Should-ExcludeDirectory($path) {
    $normalizedPath = Normalize-Path $path
    
    # Check user-specified exclusions
    foreach ($exclude in $ExcludeDirectories) {
        if ($normalizedPath -like "*$(Normalize-Path $exclude)*") {
            return $true
        }
    }
    
    # Check system directories unless explicitly included
    if (-not $IncludeSystemTools) {
        foreach ($sysDir in $systemDirectories) {
            if ($normalizedPath -eq (Normalize-Path $sysDir)) {
                return $true
            }
        }
    }
    
    return $false
}

# Function to check if an executable should be excluded
function Should-ExcludeExecutable($executableName) {
    $lowerName = $executableName.ToLower()
    
    # Check user-specified exclusions
    if ($ExcludeExecutables -contains $lowerName) {
        return $true
    }
    
    # Check default system exclusions unless explicitly included
    if (-not $IncludeSystemTools -and $defaultSystemExclusions -contains $lowerName) {
        return $true
    }
    
    return $false
}

# Function to create a CMD shim
function New-CmdShim {
    param(
        [string]$ShimPath,
        [string]$TargetPath,
        [string]$ToolName
    )
    
    $shimContent = @"
@echo off
REM Universal shim for $ToolName
REM Target: $TargetPath
REM Generated: $(Get-Date)
"$TargetPath" %*
"@
    
    Set-Content -Path $ShimPath -Value $shimContent -Encoding ASCII
}

# Function to create a PowerShell shim
function New-PowerShellShim {
    param(
        [string]$ShimPath,
        [string]$TargetPath,
        [string]$ToolName
    )
    
    $shimContent = @"
# Universal PowerShell shim for $ToolName
# Target: $TargetPath
# Generated: $(Get-Date)
& "$TargetPath" @args
"@
    
    Set-Content -Path $ShimPath -Value $shimContent -Encoding UTF8
}

# Function to get executable info
function Get-ExecutableInfo($filePath) {
    try {
        $file = Get-Item $filePath -ErrorAction SilentlyContinue
        if (-not $file) { return $null }
        
        $versionInfo = $null
        try {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($filePath)
        } catch {
            # Some files don't have version info
        }
        
        return [PSCustomObject]@{
            Name = $file.Name
            FullPath = $file.FullName
            Directory = $file.DirectoryName
            Size = $file.Length
            LastModified = $file.LastWriteTime
            Created = $file.CreationTime
            Version = if ($versionInfo) { $versionInfo.FileVersion } else { "Unknown" }
            Description = if ($versionInfo) { $versionInfo.FileDescription } else { "No description" }
            Company = if ($versionInfo) { $versionInfo.CompanyName } else { "Unknown" }
        }
    } catch {
        return $null
    }
}

# Function to find all executables in PATH
function Find-AllExecutables {
    Write-Host "=== Scanning Entire PATH for Executables ===" -ForegroundColor Cyan
    
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $allPaths = ($userPath + ";" + $machinePath) -split ';' | Where-Object { $_.Trim() -ne "" }
    
    # Executable file extensions to look for
    $executableExtensions = @('.exe', '.cmd', '.bat', '.ps1', '.com', '.msi')
    
    $foundExecutables = @{}
    $skippedDirectories = @()
    $processedDirs = 0
    $totalDirs = $allPaths.Count
    
    foreach ($path in $allPaths) {
        $normalizedPath = $path.TrimEnd('\', '/')
        $processedDirs++
        
        Write-Progress -Activity "Scanning PATH directories" -Status "Processing $normalizedPath" -PercentComplete (($processedDirs / $totalDirs) * 100)
        
        if (-not (Test-Path $normalizedPath)) {
            Write-Host "⚠️  Path not found: $normalizedPath" -ForegroundColor Yellow
            continue
        }
        
        if (Should-ExcludeDirectory $normalizedPath) {
            $skippedDirectories += $normalizedPath
            Write-Host "⏭️  Skipped system directory: $normalizedPath" -ForegroundColor Gray
            continue
        }
        
        try {
            $files = Get-ChildItem -Path $normalizedPath -File -ErrorAction SilentlyContinue
            $executablesInDir = 0
            
            foreach ($file in $files) {
                if ($executableExtensions -contains $file.Extension.ToLower()) {
                    $executablesInDir++
                    
                    if (Should-ExcludeExecutable $file.Name) {
                        continue
                    }
                    
                    $toolName = $file.Name.ToLower()
                    
                    if (-not $foundExecutables.ContainsKey($toolName)) {
                        $foundExecutables[$toolName] = @()
                    }
                    
                    $execInfo = Get-ExecutableInfo $file.FullName
                    if ($execInfo) {
                        $foundExecutables[$toolName] += $execInfo
                    }
                }
            }
            
            if ($executablesInDir -gt 0) {
                Write-Host "📁 $normalizedPath - Found $executablesInDir executables" -ForegroundColor Green
            }
            
        } catch {
            Write-Host "❌ Error accessing: $normalizedPath - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Progress -Activity "Scanning PATH directories" -Completed
    
    return @{
        Executables = $foundExecutables
        SkippedDirectories = $skippedDirectories
        ProcessedDirectories = $processedDirs
    }
}

# Function to create shims with conflict resolution
function New-UniversalShims {
    param(
        [hashtable]$Executables,
        [string]$ShimDir,
        [bool]$DryRun = $false
    )
    
    Write-Host "`n=== Creating Universal Shims ===" -ForegroundColor Cyan
    
    if ($DryRun) {
        Write-Host "[WHAT-IF] Shim creation preview mode" -ForegroundColor Yellow
    } else {
        if (-not (Test-Path $ShimDir)) {
            New-Item -Path $ShimDir -ItemType Directory -Force | Out-Null
            Write-Host "✅ Created shim directory: $ShimDir" -ForegroundColor Green
        } else {
            Write-Host "📁 Shim directory exists: $ShimDir" -ForegroundColor Yellow
        }
    }
    
    $shimCount = 0
    $conflictCount = 0
    $conflicts = @()
    
    foreach ($toolName in ($Executables.Keys | Sort-Object)) {
        $instances = $Executables[$toolName] | Sort-Object LastModified -Descending
        $selected = $instances[0]  # Use most recently modified
        
        # Remove file extension for shim name
        $baseShimName = [System.IO.Path]::GetFileNameWithoutExtension($toolName)
        $shimCmdPath = Join-Path $ShimDir "$baseShimName.cmd"
        $shimPs1Path = Join-Path $ShimDir "$baseShimName.ps1"
        
        if ($instances.Count -gt 1) {
            $conflictCount++
            $conflicts += [PSCustomObject]@{
                ToolName = $baseShimName
                SelectedPath = $selected.FullPath
                AlternativeCount = $instances.Count - 1
                Alternatives = ($instances[1..($instances.Count-1)] | ForEach-Object { $_.FullPath }) -join "; "
            }
        }
        
        if ($DryRun) {
            Write-Host "[WHAT-IF] $baseShimName -> $($selected.FullPath)" -ForegroundColor Yellow
            if ($instances.Count -gt 1) {
                Write-Host "    [CONFLICT] $($instances.Count) versions found" -ForegroundColor Magenta
            }
        } else {
            try {
                New-CmdShim -ShimPath $shimCmdPath -TargetPath $selected.FullPath -ToolName $baseShimName
                New-PowerShellShim -ShimPath $shimPs1Path -TargetPath $selected.FullPath -ToolName $baseShimName
                
                Write-Host "✅ $baseShimName -> $($selected.FullPath)" -ForegroundColor Green
                if ($instances.Count -gt 1) {
                    Write-Host "    ⚠️  Conflict resolved: chose newest of $($instances.Count) versions" -ForegroundColor Yellow
                }
                
                $shimCount++
            } catch {
                Write-Host "❌ Failed to create shim for $baseShimName`: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    
    return @{
        ShimCount = $shimCount
        ConflictCount = $conflictCount
        Conflicts = $conflicts
    }
}

# Function to generate PATH cleanup analysis
function Get-PathCleanupAnalysis {
    param(
        [hashtable]$Executables,
        [string]$ShimDir
    )
    
    Write-Host "`n=== PATH Cleanup Analysis ===" -ForegroundColor Cyan
    
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    
    $pathsWithExecutables = @{}
    
    # Group executables by their directories
    foreach ($toolName in $Executables.Keys) {
        foreach ($instance in $Executables[$toolName]) {
            $dir = $instance.Directory
            if (-not $pathsWithExecutables.ContainsKey($dir)) {
                $pathsWithExecutables[$dir] = @()
            }
            $pathsWithExecutables[$dir] += $instance.Name
        }
    }
    
    $userPathsToRemove = @()
    $machinePathsToRemove = @()
    
    foreach ($dir in $pathsWithExecutables.Keys) {
        $toolCount = $pathsWithExecutables[$dir].Count
        $isUserPath = $userPath -like "*$dir*"
        $isMachinePath = $machinePath -like "*$dir*"
        
        Write-Host "📁 $dir" -ForegroundColor White
        Write-Host "   └─ $toolCount executables: $($pathsWithExecutables[$dir] -join ', ')" -ForegroundColor Gray
        
        if ($isUserPath) {
            $userPathsToRemove += $dir
        }
        if ($isMachinePath) {
            $machinePathsToRemove += $dir
        }
    }
    
    # Generate cleaned PATH suggestions
    $cleanedUserPath = $userPath
    $cleanedMachinePath = $machinePath
    
    foreach ($path in $userPathsToRemove) {
        $cleanedUserPath = $cleanedUserPath -replace [regex]::Escape($path + ";"), ""
        $cleanedUserPath = $cleanedUserPath -replace [regex]::Escape(";" + $path), ""
        $cleanedUserPath = $cleanedUserPath -replace "^" + [regex]::Escape($path) + "$", ""
    }
    
    foreach ($path in $machinePathsToRemove) {
        $cleanedMachinePath = $cleanedMachinePath -replace [regex]::Escape($path + ";"), ""
        $cleanedMachinePath = $cleanedMachinePath -replace [regex]::Escape(";" + $path), ""
        $cleanedMachinePath = $cleanedMachinePath -replace "^" + [regex]::Escape($path) + "$", ""
    }
    
    # Add shim directory to user PATH if not present
    if ($cleanedUserPath -notlike "*$ShimDir*") {
        $cleanedUserPath = "$ShimDir;" + $cleanedUserPath
    }
    
    return @{
        UserPathsToRemove = $userPathsToRemove
        MachinePathsToRemove = $machinePathsToRemove
        CleanedUserPath = $cleanedUserPath
        CleanedMachinePath = $cleanedMachinePath
        DirectoriesWithExecutables = $pathsWithExecutables.Count
    }
}

# Main execution starts here
Write-Host "=== Dynamic PATH Executables Analyzer and Universal Shim Creator ===" -ForegroundColor Cyan

# Handle restore operation
if ($Restore) {
    $success = Restore-PathVariables -BackupFile $Restore
    if ($success) {
        Write-Host "🎉 PATH restore completed successfully!" -ForegroundColor Green
    }
    return
}

# Handle backup-only operation
if ($Backup -and -not $WhatIf) {
    $backupPath = Backup-PathVariables
    Write-Host "🎉 PATH backup completed successfully!" -ForegroundColor Green
    return
}

Write-Host "🎯 Target shim directory: $ShimDirectory" -ForegroundColor White
Write-Host "🔍 Include system tools: $IncludeSystemTools" -ForegroundColor White
Write-Host "📝 WhatIf mode: $WhatIf" -ForegroundColor White
Write-Host "🔄 Update PATH: $UpdatePath" -ForegroundColor White

if ($ExcludeDirectories.Count -gt 0) {
    Write-Host "⏭️  Excluded directories: $($ExcludeDirectories -join ', ')" -ForegroundColor Gray
}

if ($ExcludeExecutables.Count -gt 0) {
    Write-Host "⏭️  Excluded executables: $($ExcludeExecutables -join ', ')" -ForegroundColor Gray
}

# Find all executables
$analysis = Find-AllExecutables

Write-Host "`n📊 DISCOVERY SUMMARY:" -ForegroundColor Cyan
Write-Host "   • Found $($analysis.Executables.Count) unique executables" -ForegroundColor Green
Write-Host "   • Processed $($analysis.ProcessedDirectories) directories" -ForegroundColor White
Write-Host "   • Skipped $($analysis.SkippedDirectories.Count) system directories" -ForegroundColor Yellow

# Display top executables by conflict count
$conflictAnalysis = @()
foreach ($toolName in $analysis.Executables.Keys) {
    $instances = $analysis.Executables[$toolName]
    if ($instances.Count -gt 1) {
        $conflictAnalysis += [PSCustomObject]@{
            Tool = $toolName
            Versions = $instances.Count
            Paths = ($instances | ForEach-Object { $_.Directory }) -join "; "
        }
    }
}

if ($conflictAnalysis.Count -gt 0) {
    Write-Host "`n⚠️  CONFLICTS DETECTED:" -ForegroundColor Yellow
    $conflictAnalysis | Sort-Object Versions -Descending | Select-Object -First 10 | ForEach-Object {
        Write-Host "   • $($_.Tool): $($_.Versions) versions" -ForegroundColor Red
    }
    if ($conflictAnalysis.Count -gt 10) {
        Write-Host "   • ... and $($conflictAnalysis.Count - 10) more conflicts" -ForegroundColor Gray
    }
}

# Create shims
$shimResult = New-UniversalShims -Executables $analysis.Executables -ShimDir $ShimDirectory -DryRun $WhatIf

if (-not $WhatIf) {
    # Generate cleanup analysis
    $cleanup = Get-PathCleanupAnalysis -Executables $analysis.Executables -ShimDir $ShimDirectory
    
    Write-Host "`n=== CLEANUP SUGGESTIONS ===" -ForegroundColor Cyan
    
    if ($UpdatePath) {
        Write-Host "🔄 Updating PATH variables..." -ForegroundColor Yellow
        $backupPath = Backup-PathVariables
        
        try {
            [Environment]::SetEnvironmentVariable('Path', $cleanup.CleanedUserPath, 'User')
            if ($cleanup.CleanedMachinePath -and $cleanup.MachinePathsToRemove.Count -gt 0) {
                [Environment]::SetEnvironmentVariable('Path', $cleanup.CleanedMachinePath, 'Machine')
            }
            Write-Host "✅ PATH updated successfully!" -ForegroundColor Green
            Write-Host "📁 Backup saved to: $backupPath" -ForegroundColor White
            Write-Host "🔄 Please restart your terminal for changes to take effect" -ForegroundColor Yellow
        } catch {
            Write-Host "❌ Error updating PATH: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "🔄 You can restore from backup: $backupPath" -ForegroundColor Yellow
        }
    } else {
        if ($cleanup.CleanedUserPath) {
            Write-Host "`n🧹 Cleaned User PATH (with shim directory):" -ForegroundColor Green
            Write-Host $cleanup.CleanedUserPath -ForegroundColor White
            Write-Host "`nTo apply User PATH cleanup:" -ForegroundColor Yellow
            Write-Host "[Environment]::SetEnvironmentVariable('Path', '$($cleanup.CleanedUserPath)', 'User')" -ForegroundColor Cyan
        }
        
        if ($cleanup.CleanedMachinePath -and $cleanup.MachinePathsToRemove.Count -gt 0) {
            Write-Host "`n🧹 Cleaned Machine PATH:" -ForegroundColor Green
            Write-Host $cleanup.CleanedMachinePath -ForegroundColor White
            Write-Host "`nTo apply Machine PATH cleanup (requires admin):" -ForegroundColor Yellow
            Write-Host "[Environment]::SetEnvironmentVariable('Path', '$($cleanup.CleanedMachinePath)', 'Machine')" -ForegroundColor Cyan
        }
    }
    
    # Export detailed reports
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $reportDir = "$env:USERPROFILE\Desktop"
    
    # Export executable inventory
    $allExecutables = @()
    foreach ($toolName in $analysis.Executables.Keys) {
        foreach ($instance in $analysis.Executables[$toolName]) {
            $allExecutables += $instance | Add-Member -NotePropertyName "ToolName" -NotePropertyValue $toolName -PassThru
        }
    }
    $executableReport = "$reportDir\Universal_Executables_Inventory_$timestamp.csv"
    $allExecutables | Export-Csv -Path $executableReport -NoTypeInformation
    
    # Export conflicts report
    if ($shimResult.Conflicts.Count -gt 0) {
        $conflictReport = "$reportDir\Executable_Conflicts_Report_$timestamp.csv"
        $shimResult.Conflicts | Export-Csv -Path $conflictReport -NoTypeInformation
        Write-Host "⚠️  Conflicts report: $conflictReport" -ForegroundColor Yellow
    }
    
    Write-Host "`n📊 FINAL SUMMARY:" -ForegroundColor Cyan
    Write-Host "   ✅ Created $($shimResult.ShimCount) universal shims" -ForegroundColor Green
    Write-Host "   ⚠️  Resolved $($shimResult.ConflictCount) version conflicts" -ForegroundColor Yellow
    Write-Host "   📁 Can remove $($cleanup.DirectoriesWithExecutables) PATH entries" -ForegroundColor Blue
    Write-Host "   📊 Detailed inventory: $executableReport" -ForegroundColor White
    
    Write-Host "`n🚀 NEXT STEPS:" -ForegroundColor Cyan
    if (-not $UpdatePath) {
        Write-Host "   1. Test shims in a new PowerShell session" -ForegroundColor White
        Write-Host "   2. Verify critical tools work correctly" -ForegroundColor White
        Write-Host "   3. Run with -UpdatePath to apply changes" -ForegroundColor White
        Write-Host "   4. Or apply PATH cleanup commands manually" -ForegroundColor White
    } else {
        Write-Host "   1. Restart your terminal to use the cleaned PATH" -ForegroundColor White
        Write-Host "   2. Test that all tools work correctly" -ForegroundColor White
        Write-Host "   3. If issues occur, restore from backup" -ForegroundColor White
    }
    
    Write-Host "`n🛡️  BACKUP & RESTORE:" -ForegroundColor Cyan
    Write-Host "   • To restore: .\Universal-PathShims.ps1 -Restore '<backup-file-path>'" -ForegroundColor Yellow
    Write-Host "   • To backup only: .\Universal-PathShims.ps1 -Backup" -ForegroundColor Yellow
    
} else {
    Write-Host "`n[WHAT-IF] Summary of planned changes:" -ForegroundColor Yellow
    Write-Host "   • Would create $($analysis.Executables.Count) shims in $ShimDirectory" -ForegroundColor Yellow
    Write-Host "   • Would resolve $($conflictAnalysis.Count) version conflicts" -ForegroundColor Yellow
    Write-Host "   • No actual changes made in WhatIf mode" -ForegroundColor Gray
    Write-Host "`n   Run without -WhatIf to apply changes" -ForegroundColor White
}

Write-Host "`n🎉 Universal PATH analysis complete!" -ForegroundColor Green
