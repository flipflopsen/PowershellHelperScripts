<#
.SYNOPSIS
  Intelligent PATH Cleanup - Removes unnecessary PATH entries with shim detection

.DESCRIPTION
  - Removes non-existent PATH entries
  - Detects and removes paths covered by shims (Scoop, Chocolatey, WinGet, etc.)
  - Removes duplicate entries
  - Creates backup before changes
  - WhatIf mode for safe previewing
  - Handles both User and Machine PATH

.PARAMETER Scope
  PATH scope: "User", "Machine", or "Both"

.PARAMETER WhatIf
  Preview changes without applying them

.PARAMETER Backup
  Create backup before changes (default: true)

.PARAMETER Force
  Skip confirmation prompts

.EXAMPLE
  .\Cleanup-Path.ps1 -WhatIf
  .\Cleanup-Path.ps1 -Scope User
  .\Cleanup-Path.ps1 -Scope Both -Force
#>

param(
    [ValidateSet("User", "Machine", "Both")]
    [string]$Scope = "User",
    
    [switch]$WhatIf = $false,
    [switch]$Backup = $true,
    [switch]$Force = $false
)

# Known shim directories and package managers
$shimDirectories = @(
    "$env:USERPROFILE\scoop\shims",
    "C:\ProgramData\chocolatey\bin",
    "$env:USERPROFILE\.cargo\bin",
    "$env:USERPROFILE\AppData\Local\Microsoft\WinGet\Links",
    "$env:USERPROFILE\AppData\Roaming\npm",
    "$env:USERPROFILE\.dotnet\tools",
    "$env:USERPROFILE\go\bin",
    "$env:USERPROFILE\AppData\Local\Programs\Python\Python*\Scripts",
    "$env:USERPROFILE\AppData\Roaming\Python\Python*\Scripts"
)

# System directories that should always be kept
$systemDirectories = @(
    "C:\Windows\system32",
    "C:\Windows",
    "C:\Windows\System32\Wbem",
    "C:\Windows\System32\WindowsPowerShell\v1.0",
    "C:\Windows\System32\OpenSSH"
)

# Function to create backup
function Backup-PathVariables {
    param([string]$BackupScope)
    
    $backup = @{
        Date = Get-Date
        UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        Scope = $BackupScope
        CleanupReason = "Intelligent PATH cleanup with shim detection"
    }
    
    $backupPath = "$env:USERPROFILE\Desktop\PATH_Cleanup_Backup_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
    $backup | ConvertTo-Json | Set-Content -Path $backupPath -Encoding UTF8
    Write-Host "✅ PATH backup saved to: $backupPath" -ForegroundColor Green
    return $backupPath
}

# Function to normalize path for comparison
function Normalize-PathEntry {
    param([string]$Path)
    
    if (-not $Path) { return "" }
    return $Path.TrimEnd('\', '/').ToLower()
}

# Function to find active shim directories
function Get-ActiveShimDirectories {
    $activeShims = @()
    
    foreach ($shimPath in $shimDirectories) {
        # Handle wildcard patterns
        if ($shimPath -like "*`**") {
            $parent = Split-Path $shimPath -Parent
            $pattern = Split-Path $shimPath -Leaf
            if (Test-Path $parent) {
                $matches = Get-ChildItem -Path $parent -Directory | Where-Object { $_.Name -like $pattern }
                foreach ($match in $matches) {
                    $fullPath = Join-Path $match.FullName "Scripts"
                    if (Test-Path $fullPath) {
                        $activeShims += $fullPath
                    }
                }
            }
        } else {
            if (Test-Path $shimPath) {
                $activeShims += $shimPath
            }
        }
    }
    
    return $activeShims
}

# Function to check if a path is covered by a shim
function Test-PathCoveredByShim {
    param(
        [string]$PathToCheck,
        [string[]]$ShimDirs
    )
    
    $normalizedPath = Normalize-PathEntry $PathToCheck
    
    foreach ($shimDir in $ShimDirs) {
        $normalizedShim = Normalize-PathEntry $shimDir
        
        # Check if the path is the same as or a subdirectory of a shim directory
        if ($normalizedPath -eq $normalizedShim) {
            return $true
        }
        
        # Check if the path might be redundant due to shim coverage
        # For example, if we have git.exe in a shim, we don't need C:\Program Files\Git\cmd
        if ($normalizedPath -like "*git*" -and $normalizedShim -like "*shim*") {
            if (Test-Path (Join-Path $shimDir "git.exe") -or Test-Path (Join-Path $shimDir "git.cmd")) {
                return $true
            }
        }
        
        # Check for Python paths when we have Python shims
        if ($normalizedPath -like "*python*" -and $normalizedShim -like "*shim*") {
            if (Test-Path (Join-Path $shimDir "python.exe") -or Test-Path (Join-Path $shimDir "python.cmd")) {
                return $true
            }
        }
        
        # Check for Node.js paths when we have Node shims
        if ($normalizedPath -like "*node*" -and $normalizedShim -like "*shim*") {
            if (Test-Path (Join-Path $shimDir "node.exe") -or Test-Path (Join-Path $shimDir "node.cmd")) {
                return $true
            }
        }
    }
    
    return $false
}

# Function to check if a path is a system directory
function Test-SystemDirectory {
    param([string]$Path)
    
    $normalizedPath = Normalize-PathEntry $Path
    
    foreach ($sysDir in $systemDirectories) {
        if ($normalizedPath -eq (Normalize-PathEntry $sysDir)) {
            return $true
        }
    }
    
    return $false
}

# Function to analyze and clean PATH entries
function Optimize-PathEntries {
    param(
        [string[]]$PathEntries,
        [string[]]$ActiveShims
    )
    
    $analysis = @{
        Original = $PathEntries.Count
        NonExistent = @()
        Duplicates = @()
        ShimCovered = @()
        SystemPaths = @()
        Kept = @()
    }
    
    $seen = @{}
    
    foreach ($entry in $PathEntries) {
        $trimmedEntry = $entry.Trim()
        
        # Skip empty entries
        if (-not $trimmedEntry) {
            continue
        }
        
        $normalizedEntry = Normalize-PathEntry $trimmedEntry
        
        # Check for duplicates
        if ($seen.ContainsKey($normalizedEntry)) {
            $analysis.Duplicates += $trimmedEntry
            continue
        }
        $seen[$normalizedEntry] = $true
        
        # Check if path exists
        if (-not (Test-Path $trimmedEntry)) {
            $analysis.NonExistent += $trimmedEntry
            continue
        }
        
        # Always keep system directories
        if (Test-SystemDirectory $trimmedEntry) {
            $analysis.SystemPaths += $trimmedEntry
            $analysis.Kept += $trimmedEntry
            continue
        }
        
        # Check if covered by shim
        if (Test-PathCoveredByShim $trimmedEntry $ActiveShims) {
            $analysis.ShimCovered += $trimmedEntry
            continue
        }
        
        # Keep this entry
        $analysis.Kept += $trimmedEntry
    }
    
    return $analysis
}

# Function to process PATH for a specific scope
function Optimize-PathVariable {
    param(
        [string]$PathVariable,
        [string]$ScopeName,
        [string[]]$ActiveShims
    )
    
    if (-not $PathVariable) {
        Write-Host "⚠️  No $ScopeName PATH found" -ForegroundColor Yellow
        return $null
    }
    
    # Split PATH into entries
    $entries = $PathVariable -split ';' | Where-Object { $_.Trim() -ne "" }
    
    # Analyze and clean entries
    $analysis = Optimize-PathEntries -PathEntries $entries -ActiveShims $ActiveShims
    
    # Display analysis results
    Write-Host "`n📊 $ScopeName PATH Analysis:" -ForegroundColor Cyan
    Write-Host "   • Original entries: $($analysis.Original)" -ForegroundColor White
    Write-Host "   • Non-existent paths: $($analysis.NonExistent.Count)" -ForegroundColor Red
    Write-Host "   • Duplicate entries: $($analysis.Duplicates.Count)" -ForegroundColor Yellow
    Write-Host "   • Shim-covered paths: $($analysis.ShimCovered.Count)" -ForegroundColor Magenta
    Write-Host "   • System paths kept: $($analysis.SystemPaths.Count)" -ForegroundColor Green
    Write-Host "   • Final entries: $($analysis.Kept.Count)" -ForegroundColor Green
    
    # Show detailed breakdown
    if ($analysis.NonExistent.Count -gt 0) {
        Write-Host "`n🗑️  Non-existent paths to remove:" -ForegroundColor Red
        $analysis.NonExistent | ForEach-Object { Write-Host "   • $_" -ForegroundColor DarkRed }
    }
    
    if ($analysis.Duplicates.Count -gt 0) {
        Write-Host "`n📋 Duplicate entries to remove:" -ForegroundColor Yellow
        $analysis.Duplicates | ForEach-Object { Write-Host "   • $_" -ForegroundColor DarkYellow }
    }
    
    if ($analysis.ShimCovered.Count -gt 0) {
        Write-Host "`n🔗 Shim-covered paths to remove:" -ForegroundColor Magenta
        $analysis.ShimCovered | ForEach-Object { Write-Host "   • $_" -ForegroundColor DarkMagenta }
    }
    
    if ($analysis.SystemPaths.Count -gt 0) {
        Write-Host "`n🛡️  System paths (kept):" -ForegroundColor Green
        $analysis.SystemPaths | ForEach-Object { Write-Host "   • $_" -ForegroundColor DarkGreen }
    }
    
    # Show final clean PATH
    Write-Host "`n✅ Optimized $ScopeName PATH:" -ForegroundColor Green
    $analysis.Kept | ForEach-Object { Write-Host "   • $_" -ForegroundColor Gray }
    
    # Calculate space savings
    $originalLength = $PathVariable.Length
    $newPath = $analysis.Kept -join ';'
    $newLength = $newPath.Length
    $savings = $originalLength - $newLength
    
    Write-Host "`n💾 Space savings: $savings characters ($originalLength → $newLength)" -ForegroundColor Cyan
    
    return @{
        CleanedPath = $newPath
        Analysis = $analysis
        Savings = $savings
    }
}

# Main execution
Write-Host "=== Intelligent PATH Cleanup ===" -ForegroundColor Cyan
Write-Host "🎯 Scope: $Scope" -ForegroundColor White
Write-Host "👀 WhatIf mode: $WhatIf" -ForegroundColor White

# Find active shim directories
Write-Host "`n🔍 Detecting active shim directories..." -ForegroundColor Yellow
$activeShims = Get-ActiveShimDirectories

if ($activeShims.Count -gt 0) {
    Write-Host "✅ Found $($activeShims.Count) active shim directories:" -ForegroundColor Green
    $activeShims | ForEach-Object { Write-Host "   • $_" -ForegroundColor Gray }
} else {
    Write-Host "⚠️  No active shim directories found" -ForegroundColor Yellow
}

# Create backup if not in WhatIf mode
if ($Backup -and -not $WhatIf) {
    $backupPath = Backup-PathVariables -BackupScope $Scope
}

$totalSavings = 0
$changesApplied = $false

# Process User PATH
if ($Scope -eq "User" -or $Scope -eq "Both") {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $userResult = Optimize-PathVariable -PathVariable $userPath -ScopeName "User" -ActiveShims $activeShims
    
    if ($userResult -and $userResult.CleanedPath -ne $userPath) {
        $totalSavings += $userResult.Savings
        
        if ($WhatIf) {
            Write-Host "[WHAT-IF] Would update User PATH" -ForegroundColor Yellow
        } else {
            [Environment]::SetEnvironmentVariable("Path", $userResult.CleanedPath, "User")
            Write-Host "✅ User PATH updated successfully" -ForegroundColor Green
            $changesApplied = $true
        }
    } else {
        Write-Host "✅ User PATH is already optimized" -ForegroundColor Green
    }
}

# Process Machine PATH
if ($Scope -eq "Machine" -or $Scope -eq "Both") {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $machineResult = Optimize-PathVariable -PathVariable $machinePath -ScopeName "Machine" -ActiveShims $activeShims
    
    if ($machineResult -and $machineResult.CleanedPath -ne $machinePath) {
        $totalSavings += $machineResult.Savings
        
        if ($WhatIf) {
            Write-Host "[WHAT-IF] Would update Machine PATH (requires admin)" -ForegroundColor Yellow
        } else {
            try {
                [Environment]::SetEnvironmentVariable("Path", $machineResult.CleanedPath, "Machine")
                Write-Host "✅ Machine PATH updated successfully" -ForegroundColor Green
                $changesApplied = $true
            } catch {
                Write-Host "❌ Failed to update Machine PATH (requires admin): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "✅ Machine PATH is already optimized" -ForegroundColor Green
    }
}

# Final summary
Write-Host "`n📊 CLEANUP SUMMARY:" -ForegroundColor Cyan
Write-Host "   • Total character savings: $totalSavings" -ForegroundColor Green
Write-Host "   • Active shims detected: $($activeShims.Count)" -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host "   • [WHAT-IF] No changes made in preview mode" -ForegroundColor Yellow
    Write-Host "   • Run without -WhatIf to apply changes" -ForegroundColor Gray
} else {
    if ($changesApplied) {
        Write-Host "   • PATH optimization completed successfully" -ForegroundColor Green
        Write-Host "   • Backup saved to: $backupPath" -ForegroundColor White
        Write-Host "   • 🔄 Restart terminal for changes to take effect" -ForegroundColor Yellow
    } else {
        Write-Host "   • No changes needed - PATH is already optimized" -ForegroundColor Green
    }
}

Write-Host "`n🛡️  BACKUP & RESTORE:" -ForegroundColor Cyan
Write-Host "   • To restore: Use the backup file created above" -ForegroundColor Yellow
Write-Host "   • Backup contains both User and Machine PATH" -ForegroundColor Gray

Write-Host "`n🎉 PATH cleanup complete!" -ForegroundColor Green
