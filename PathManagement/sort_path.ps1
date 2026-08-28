<#
.SYNOPSIS
  PATH Sorter - Organizes PATH entries in a clean, logical order

.DESCRIPTION
  - Sorts PATH entries alphabetically or by category
  - Removes duplicates and empty entries
  - Creates backup before changes
  - Supports WhatIf mode for safe previewing
  - Handles both User and Machine PATH

.PARAMETER SortBy
  Sorting method: "Alphabetical", "Category", or "PathType"

.PARAMETER Scope
  PATH scope: "User", "Machine", or "Both"

.PARAMETER WhatIf
  Preview changes without applying them

.PARAMETER Backup
  Create backup before changes (default: true)

.EXAMPLE
  .\Sort-Path.ps1 -SortBy Category -Scope User
  .\Sort-Path.ps1 -SortBy Alphabetical -WhatIf
#>

param(
    [ValidateSet("Alphabetical", "Category", "PathType")]
    [string]$SortBy = "Category",
    
    [ValidateSet("User", "Machine", "Both")]
    [string]$Scope = "User",
    
    [switch]$WhatIf = $false,
    [switch]$Backup = $true
)

# Function to create backup
function Backup-PathVariables {
    param([string]$BackupScope)
    
    $backup = @{
        Date = Get-Date
        UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        Scope = $BackupScope
    }
    
    $backupPath = "$env:USERPROFILE\Desktop\PATH_Sort_Backup_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
    $backup | ConvertTo-Json | Set-Content -Path $backupPath -Encoding UTF8
    Write-Host "✅ PATH backup saved to: $backupPath" -ForegroundColor Green
    return $backupPath
}

# Function to normalize path entries
function Normalize-PathEntry {
    param([string]$Entry)
    
    $normalized = $Entry.Trim().TrimEnd('\', '/')
    
    # Convert to proper case for common directories
    $normalized = $normalized -replace '\\system32\\', '\System32\'
    $normalized = $normalized -replace '\\program files\\', '\Program Files\'
    $normalized = $normalized -replace '\\program files \(x86\)\\', '\Program Files (x86)\'
    
    return $normalized
}

# Function to categorize path entries
function Get-PathCategory {
    param([string]$Path)
    
    $lowerPath = $Path.ToLower()
    
    # System paths (highest priority)
    if ($lowerPath -match '^c:\\windows\\system32' -or $lowerPath -match '^c:\\windows\\syswow64') {
        return "1-System-Core"
    }
    if ($lowerPath -match '^c:\\windows\\') {
        return "2-System-Windows"
    }
    
    # Program Files
    if ($lowerPath -match '^c:\\program files\\') {
        return "3-Program-Files"
    }
    if ($lowerPath -match '^c:\\program files \(x86\)\\') {
        return "4-Program-Files-x86"
    }
    
    # Development tools
    if ($lowerPath -match 'git|python|node|java|dotnet|go|rust|maven|gradle') {
        return "5-Development-Tools"
    }
    
    # User directories
    if ($lowerPath -match '^c:\\users\\') {
        return "6-User-Directories"
    }
    
    # Package managers
    if ($lowerPath -match 'chocolatey|scoop|winget|npm|cargo|pip') {
        return "7-Package-Managers"
    }
    
    # Other drives
    if ($lowerPath -match '^[d-z]:') {
        return "8-Other-Drives"
    }
    
    # Everything else
    return "9-Other"
}

# Function to get path type for sorting
function Get-PathType {
    param([string]$Path)
    
    $lowerPath = $Path.ToLower()
    
    if ($lowerPath -match '^c:\\windows\\') { return "Windows" }
    if ($lowerPath -match '^c:\\program files\\') { return "Program Files" }
    if ($lowerPath -match '^c:\\program files \(x86\)\\') { return "Program Files (x86)" }
    if ($lowerPath -match '^c:\\users\\') { return "User" }
    if ($lowerPath -match '^c:\\programdata\\') { return "ProgramData" }
    if ($lowerPath -match '^[d-z]:') { return "Other Drives" }
    
    return "Other"
}

# Function to sort path entries
function Sort-PathEntries {
    param(
        [string[]]$Entries,
        [string]$Method
    )
    
    switch ($Method) {
        "Alphabetical" {
            return $Entries | Sort-Object { $_.ToLower() }
        }
        
        "Category" {
            return $Entries | Sort-Object { 
                $category = Get-PathCategory $_
                "$category|$($_.ToLower())"
            }
        }
        
        "PathType" {
            $grouped = $Entries | Group-Object { Get-PathType $_ }
            $sortedGroups = @()
            
            # Define order of path types
            $typeOrder = @("Windows", "Program Files", "Program Files (x86)", "ProgramData", "User", "Other Drives", "Other")
            
            foreach ($type in $typeOrder) {
                $group = $grouped | Where-Object { $_.Name -eq $type }
                if ($group) {
                    $sortedGroups += $group.Group | Sort-Object { $_.ToLower() }
                }
            }
            
            return $sortedGroups
        }
    }
}

# Function to process PATH
function Sort-PathVariable {
    param(
        [string]$PathVariable,
        [string]$ScopeName
    )
    
    if (-not $PathVariable) {
        Write-Host "⚠️  No $ScopeName PATH found" -ForegroundColor Yellow
        return $null
    }
    
    # Split and clean entries
    $entries = $PathVariable -split ';' | Where-Object { $_.Trim() -ne "" }
    
    # Remove duplicates while preserving original entries for normalization
    $seen = @{}
    $uniqueEntries = @()
    $duplicates = @()
    
    foreach ($entry in $entries) {
        $normalized = Normalize-PathEntry $entry
        $key = $normalized.ToLower()
        
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $uniqueEntries += $normalized
        } else {
            $duplicates += $entry
        }
    }
    
    # Sort the unique entries
    $sortedEntries = Sort-PathEntries -Entries $uniqueEntries -Method $SortBy
    
    # Join back to string
    $sortedPath = $sortedEntries -join ';'
    
    # Display results
    Write-Host "`n📊 $ScopeName PATH Analysis:" -ForegroundColor Cyan
    Write-Host "   • Original entries: $($entries.Count)" -ForegroundColor White
    Write-Host "   • Unique entries: $($uniqueEntries.Count)" -ForegroundColor Green
    Write-Host "   • Duplicates removed: $($duplicates.Count)" -ForegroundColor Red
    Write-Host "   • Sorting method: $SortBy" -ForegroundColor Yellow
    
    if ($duplicates.Count -gt 0) {
        Write-Host "`n🗑️  Removed duplicates:" -ForegroundColor Red
        $duplicates | ForEach-Object { Write-Host "   • $_" -ForegroundColor DarkRed }
    }
    
    Write-Host "`n📋 Sorted $ScopeName PATH:" -ForegroundColor Green
    if ($SortBy -eq "Category") {
        $currentCategory = ""
        foreach ($entry in $sortedEntries) {
            $category = Get-PathCategory $entry
            if ($category -ne $currentCategory) {
                $currentCategory = $category
                $displayCategory = $category -replace '^\d-', '' -replace '-', ' '
                Write-Host "   [$displayCategory]" -ForegroundColor Magenta
            }
            Write-Host "   • $entry" -ForegroundColor Gray
        }
    } elseif ($SortBy -eq "PathType") {
        $currentType = ""
        foreach ($entry in $sortedEntries) {
            $type = Get-PathType $entry
            if ($type -ne $currentType) {
                $currentType = $type
                Write-Host "   [$type]" -ForegroundColor Magenta
            }
            Write-Host "   • $entry" -ForegroundColor Gray
        }
    } else {
        $sortedEntries | ForEach-Object { Write-Host "   • $_" -ForegroundColor Gray }
    }
    
    return $sortedPath
}

# Main execution
Write-Host "=== PATH Sorter ===" -ForegroundColor Cyan
Write-Host "🎯 Sorting method: $SortBy" -ForegroundColor White
Write-Host "📂 Scope: $Scope" -ForegroundColor White
Write-Host "👀 WhatIf mode: $WhatIf" -ForegroundColor White

# Create backup if not in WhatIf mode
if ($Backup -and -not $WhatIf) {
    $backupPath = Backup-PathVariables -BackupScope $Scope
}

# Process User PATH
if ($Scope -eq "User" -or $Scope -eq "Both") {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $sortedUserPath = Sort-PathVariable -PathVariable $userPath -ScopeName "User"
    
    if ($sortedUserPath -and -not $WhatIf) {
        [Environment]::SetEnvironmentVariable("Path", $sortedUserPath, "User")
        Write-Host "✅ User PATH sorted and updated" -ForegroundColor Green
    }
}

# Process Machine PATH
if ($Scope -eq "Machine" -or $Scope -eq "Both") {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $sortedMachinePath = Sort-PathVariable -PathVariable $machinePath -ScopeName "Machine"
    
    if ($sortedMachinePath -and -not $WhatIf) {
        try {
            [Environment]::SetEnvironmentVariable("Path", $sortedMachinePath, "Machine")
            Write-Host "✅ Machine PATH sorted and updated" -ForegroundColor Green
        } catch {
            Write-Host "❌ Failed to update Machine PATH (requires admin): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Final summary
Write-Host "`n📊 SUMMARY:" -ForegroundColor Cyan
if ($WhatIf) {
    Write-Host "   • [WHAT-IF] No changes made in preview mode" -ForegroundColor Yellow
    Write-Host "   • Run without -WhatIf to apply changes" -ForegroundColor Gray
} else {
    Write-Host "   • PATH sorting completed successfully" -ForegroundColor Green
    Write-Host "   • Backup saved to: $backupPath" -ForegroundColor White
    Write-Host "   • 🔄 Restart terminal for changes to take effect" -ForegroundColor Yellow
}

Write-Host "`n🎉 PATH sorting complete!" -ForegroundColor Green
