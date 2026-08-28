<#
.SYNOPSIS
  Remove Non-Existent PATH Entries - Cleans up PATH by removing directories that no longer exist

.DESCRIPTION
  - Scans PATH entries and removes any that don't exist on disk
  - Creates backup before changes
  - WhatIf mode for safe previewing
  - Handles both User and Machine PATH
  - Preserves order of existing entries

.PARAMETER Scope
  PATH scope: "User", "Machine", or "Both"

.PARAMETER WhatIf
  Preview changes without applying them

.PARAMETER Backup
  Create backup before changes (default: true)

.PARAMETER Force
  Skip confirmation prompts

.EXAMPLE
  .\Remove-NonExistentPaths.ps1 -WhatIf
  .\Remove-NonExistentPaths.ps1 -Scope User
  .\Remove-NonExistentPaths.ps1 -Scope Both -Force
#>

param(
    [ValidateSet("User", "Machine", "Both")]
    [string]$Scope = "User",
    
    [switch]$WhatIf = $false,
    [switch]$Backup = $true,
    [switch]$Force = $false
)

# Function to create backup
function Backup-PathVariables {
    param([string]$BackupScope)
    
    $backup = @{
        Date = Get-Date
        UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        Scope = $BackupScope
        CleanupType = "Non-existent path removal"
    }
    
    $backupPath = "$env:USERPROFILE\Desktop\PATH_NonExistent_Backup_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
    $backup | ConvertTo-Json | Set-Content -Path $backupPath -Encoding UTF8
    Write-Host "✅ PATH backup saved to: $backupPath" -ForegroundColor Green
    return $backupPath
}

# Function to clean non-existent paths
function Remove-NonExistentPaths {
    param(
        [string]$PathVariable,
        [string]$ScopeName
    )
    
    if (-not $PathVariable) {
        Write-Host "⚠️  No $ScopeName PATH found" -ForegroundColor Yellow
        return $null
    }
    
    # Split PATH into entries and remove empty ones
    $allEntries = $PathVariable -split ';' | Where-Object { $_.Trim() -ne "" }
    
    $existingPaths = @()
    $nonExistentPaths = @()
    
    Write-Host "`n🔍 Checking $ScopeName PATH entries..." -ForegroundColor Yellow
    
    foreach ($entry in $allEntries) {
        $trimmedEntry = $entry.Trim()
        
        if (Test-Path $trimmedEntry) {
            $existingPaths += $trimmedEntry
            Write-Host "✅ $trimmedEntry" -ForegroundColor Green
        } else {
            $nonExistentPaths += $trimmedEntry
            Write-Host "❌ $trimmedEntry" -ForegroundColor Red
        }
    }
    
    # Display analysis
    Write-Host "`n📊 $ScopeName PATH Analysis:" -ForegroundColor Cyan
    Write-Host "   • Total entries: $($allEntries.Count)" -ForegroundColor White
    Write-Host "   • Existing paths: $($existingPaths.Count)" -ForegroundColor Green
    Write-Host "   • Non-existent paths: $($nonExistentPaths.Count)" -ForegroundColor Red
    
    if ($nonExistentPaths.Count -gt 0) {
        Write-Host "`n🗑️  Non-existent paths to remove:" -ForegroundColor Red
        $nonExistentPaths | ForEach-Object { Write-Host "   • $_" -ForegroundColor DarkRed }
    }
    
    if ($existingPaths.Count -gt 0) {
        Write-Host "`n✅ Paths to keep:" -ForegroundColor Green
        $existingPaths | ForEach-Object { Write-Host "   • $_" -ForegroundColor DarkGreen }
    }
    
    # Calculate savings
    $originalLength = $PathVariable.Length
    $cleanedPath = $existingPaths -join ';'
    $newLength = $cleanedPath.Length
    $savings = $originalLength - $newLength
    
    Write-Host "`n💾 Space savings: $savings characters ($originalLength → $newLength)" -ForegroundColor Cyan
    
    return @{
        CleanedPath = $cleanedPath
        NonExistentCount = $nonExistentPaths.Count
        ExistingCount = $existingPaths.Count
        Savings = $savings
        NonExistentPaths = $nonExistentPaths
    }
}

# Main execution
Write-Host "=== Non-Existent PATH Entry Remover ===" -ForegroundColor Cyan
Write-Host "🎯 Scope: $Scope" -ForegroundColor White
Write-Host "👀 WhatIf mode: $WhatIf" -ForegroundColor White

# Create backup if not in WhatIf mode
if ($Backup -and -not $WhatIf) {
    $backupPath = Backup-PathVariables -BackupScope $Scope
}

$totalRemoved = 0
$totalSavings = 0
$changesApplied = $false

# Process User PATH
if ($Scope -eq "User" -or $Scope -eq "Both") {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $userResult = Remove-NonExistentPaths -PathVariable $userPath -ScopeName "User"
    
    if ($userResult -and $userResult.NonExistentCount -gt 0) {
        $totalRemoved += $userResult.NonExistentCount
        $totalSavings += $userResult.Savings
        
        if ($WhatIf) {
            Write-Host "`n[WHAT-IF] Would remove $($userResult.NonExistentCount) non-existent entries from User PATH" -ForegroundColor Yellow
        } else {
            # Confirm before applying changes
            if (-not $Force -and $userResult.NonExistentCount -gt 0) {
                $confirm = Read-Host "`nRemove $($userResult.NonExistentCount) non-existent entries from User PATH? (y/N)"
                if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                    Write-Host "❌ User PATH update cancelled" -ForegroundColor Yellow
                } else {
                    [Environment]::SetEnvironmentVariable("Path", $userResult.CleanedPath, "User")
                    Write-Host "✅ User PATH updated - removed $($userResult.NonExistentCount) non-existent entries" -ForegroundColor Green
                    $changesApplied = $true
                }
            } else {
                [Environment]::SetEnvironmentVariable("Path", $userResult.CleanedPath, "User")
                Write-Host "✅ User PATH updated - removed $($userResult.NonExistentCount) non-existent entries" -ForegroundColor Green
                $changesApplied = $true
            }
        }
    } else {
        Write-Host "✅ User PATH has no non-existent entries" -ForegroundColor Green
    }
}

# Process Machine PATH
if ($Scope -eq "Machine" -or $Scope -eq "Both") {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $machineResult = Remove-NonExistentPaths -PathVariable $machinePath -ScopeName "Machine"
    
    if ($machineResult -and $machineResult.NonExistentCount -gt 0) {
        $totalRemoved += $machineResult.NonExistentCount
        $totalSavings += $machineResult.Savings
        
        if ($WhatIf) {
            Write-Host "`n[WHAT-IF] Would remove $($machineResult.NonExistentCount) non-existent entries from Machine PATH (requires admin)" -ForegroundColor Yellow
        } else {
            # Confirm before applying changes
            if (-not $Force -and $machineResult.NonExistentCount -gt 0) {
                $confirm = Read-Host "`nRemove $($machineResult.NonExistentCount) non-existent entries from Machine PATH? (y/N)"
                if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                    Write-Host "❌ Machine PATH update cancelled" -ForegroundColor Yellow
                } else {
                    try {
                        [Environment]::SetEnvironmentVariable("Path", $machineResult.CleanedPath, "Machine")
                        Write-Host "✅ Machine PATH updated - removed $($machineResult.NonExistentCount) non-existent entries" -ForegroundColor Green
                        $changesApplied = $true
                    } catch {
                        Write-Host "❌ Failed to update Machine PATH (requires admin): $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            } else {
                try {
                    [Environment]::SetEnvironmentVariable("Path", $machineResult.CleanedPath, "Machine")
                    Write-Host "✅ Machine PATH updated - removed $($machineResult.NonExistentCount) non-existent entries" -ForegroundColor Green
                    $changesApplied = $true
                } catch {
                    Write-Host "❌ Failed to update Machine PATH (requires admin): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    } else {
        Write-Host "✅ Machine PATH has no non-existent entries" -ForegroundColor Green
    }
}

# Final summary
Write-Host "`n📊 CLEANUP SUMMARY:" -ForegroundColor Cyan
Write-Host "   • Total non-existent entries: $totalRemoved" -ForegroundColor Red
Write-Host "   • Total character savings: $totalSavings" -ForegroundColor Green

if ($WhatIf) {
    Write-Host "   • [WHAT-IF] No changes made in preview mode" -ForegroundColor Yellow
    Write-Host "   • Run without -WhatIf to apply changes" -ForegroundColor Gray
} else {
    if ($changesApplied) {
        Write-Host "   • PATH cleanup completed successfully" -ForegroundColor Green
        Write-Host "   • Backup saved to: $backupPath" -ForegroundColor White
        Write-Host "   • 🔄 Restart terminal for changes to take effect" -ForegroundColor Yellow
    } else {
        if ($totalRemoved -eq 0) {
            Write-Host "   • No cleanup needed - all PATH entries exist" -ForegroundColor Green
        } else {
            Write-Host "   • No changes applied" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n🛡️  BACKUP & RESTORE:" -ForegroundColor Cyan
if ($Backup -and -not $WhatIf) {
    Write-Host "   • Backup file: $backupPath" -ForegroundColor Yellow
    Write-Host "   • To restore: Import backup and set environment variables" -ForegroundColor Gray
}

Write-Host "`n🎉 Non-existent path cleanup complete!" -ForegroundColor Green
