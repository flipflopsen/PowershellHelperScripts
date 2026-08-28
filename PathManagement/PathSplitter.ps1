<#
.SYNOPSIS
  PATH Categorizer - Splits PATH into organized category-specific environment variables

.DESCRIPTION
  - Analyzes PATH entries and categorizes them (DEV, TOOL, SYSTEM, USER, etc.)
  - Creates new environment variables PATH_DEV, PATH_TOOL, etc.
  - Removes categorized entries from main PATH
  - Appends category variables to main PATH for seamless operation
  - Creates backup before changes
  - WhatIf mode for safe previewing

.PARAMETER WhatIf
  Preview changes without applying them

.PARAMETER Backup
  Create backup before changes (default: true)

.PARAMETER Force
  Skip confirmation prompts

.EXAMPLE
  .\Categorize-Path.ps1 -WhatIf
  .\Categorize-Path.ps1 -Force
#>

param(
    [switch]$WhatIf = $false,
    [switch]$Backup = $true,
    [switch]$Force = $false
)

# Define path categories with keywords and priorities
$pathCategories = @{
    'SYSTEM' = @{
        Keywords = @('C:\\windows', 'windows\\system32', 'windows\\syswow64', 'windows\\wbem', 'windows\\system32\\windowspowershell', 'windows\\system32\\openssh')
        Priority = 1
        Description = 'Core Windows system directories'
    }
    'DEV' = @{
        Keywords = @('git', 'python', 'node', 'java', 'dotnet', 'go', 'rust', 'maven', 'gradle', 'cargo', 'npm', 'pip', 'conda', 'yarn', 'pnpm', 'composer', 'gem', 'bundler')
        Priority = 2
        Description = 'Development tools and programming languages'
    }
    'TOOL' = @{
        Keywords = @('docker', 'kubectl', 'helm', 'aws', 'az', 'gcloud', 'terraform', 'vagrant', 'ansible', 'packer', 'cmake', 'ninja', 'make', 'curl', 'wget', '7z')
        Priority = 3
        Description = 'System administration and DevOps tools'
    }
    'PKG' = @{
        Keywords = @('scoop', 'chocolatey', 'winget', 'vcpkg', 'nuget')
        Priority = 4
        Description = 'Package managers and their shims'
    }
    'EDITOR' = @{
        Keywords = @('code', 'vim', 'emacs', 'notepad++', 'sublime', 'atom', 'jetbrains')
        Priority = 5
        Description = 'Text editors and IDEs'
    }
    'MEDIA' = @{
        Keywords = @('ffmpeg', 'imagemagick', 'gimp', 'blender', 'obs')
        Priority = 6
        Description = 'Media processing and creative tools'
    }
    'USER' = @{
        Keywords = @('users\\.*\\appdata', 'users\.*\.local', 'users\.*\bin', 'users\.*\scoop', 'users\.*\.cargo', 'users\.*\.dotnet')
        Priority = 7
        Description = 'User-specific application directories'
    }
    'OTHER' = @{
        Keywords = @()
        Priority = 99
        Description = 'Uncategorized paths'
    }
}

# Function to create backup
function Backup-PathVariables {
    $backup = @{
        Date = Get-Date
        OriginalUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        OriginalMachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        Operation = "PATH Categorization"
    }
    
    $backupPath = "A:\Scripts\WinPathStuff\Backups\PATH_Categorization_Backup_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
    $backup | ConvertTo-Json | Set-Content -Path $backupPath -Encoding UTF8
    Write-Host "✅ PATH backup saved to: $backupPath" -ForegroundColor Green
    return $backupPath
}

# Function to categorize a single path entry
function Get-PathCategory {
    param([string]$PathEntry)
    
    $lowerPath = $PathEntry.ToLower()
    
    # Check each category (except OTHER) in priority order
    $sortedCategories = $pathCategories.GetEnumerator() | Where-Object { $_.Key -ne 'OTHER' } | Sort-Object { $_.Value.Priority }
    
    foreach ($category in $sortedCategories) {
        foreach ($keyword in $category.Value.Keywords) {
            if ($lowerPath -like "*$($keyword.ToLower().Replace('\.*\', '*'))*") {
                return $category.Key
            }
        }
    }
    
    return 'OTHER'
}

# Function to analyze and categorize PATH entries
function Invoke-PathCategorization {
    param([string]$PathVariable)
    
    if (-not $PathVariable) {
        return @{}
    }
    
    # Split PATH into entries
    $entries = $PathVariable -split ';' | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }
    
    # Categorize each entry
    $categorized = @{}
    foreach ($category in $pathCategories.Keys) {
        $categorized[$category] = @()
    }
    
    foreach ($entry in $entries) {
        $category = Get-PathCategory $entry
        $categorized[$category] += $entry
    }
    
    return $categorized
}

# Function to create category environment variables
function New-CategoryEnvironmentVariables {
    param(
        [hashtable]$CategorizedPaths,
        [bool]$DryRun = $false
    )
    
    $createdVars = @()
    
    foreach ($category in $CategorizedPaths.Keys) {
        if ($CategorizedPaths[$category].Count -gt 0 -and $category -ne 'SYSTEM') {
            $varName = "PATH_$category"
            $varValue = $CategorizedPaths[$category] -join ';'
            
            if ($DryRun) {
                Write-Host "[WHAT-IF] Would create $varName with $($CategorizedPaths[$category].Count) entries" -ForegroundColor Yellow
            } else {
                [Environment]::SetEnvironmentVariable($varName, $varValue, "User")
                Write-Host "✅ Created $varName with $($CategorizedPaths[$category].Count) entries" -ForegroundColor Green
                $createdVars += $varName
            }
        }
    }
    
    return $createdVars
}

# Function to create new main PATH
function New-OptimizedPath {
    param(
        [hashtable]$CategorizedPaths,
        [string[]]$CategoryVars
    )
    
    # Start with SYSTEM paths (keep in main PATH)
    $newPath = @()
    if ($CategorizedPaths['SYSTEM'].Count -gt 0) {
        $newPath += $CategorizedPaths['SYSTEM']
    }
    
    # Add references to category environment variables
    foreach ($varName in $CategoryVars) {
        $newPath += "%$varName%"
    }
    
    return $newPath -join ';'
}

# Main execution
Write-Host "=== PATH Categorizer and Splitter ===" -ForegroundColor Cyan
Write-Host "👀 WhatIf mode: $WhatIf" -ForegroundColor White

# Get current User PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")

if (-not $userPath) {
    Write-Host "❌ No User PATH found" -ForegroundColor Red
    exit
}

# Create backup
if ($Backup -and -not $WhatIf) {
    $backupPath = Backup-PathVariables
}

Write-Host "`n🔍 Analyzing PATH entries..." -ForegroundColor Yellow

# Categorize PATH entries
$categorizedPaths = Invoke-PathCategorization -PathVariable $userPath

# Display categorization results
Write-Host "`n📊 CATEGORIZATION RESULTS:" -ForegroundColor Cyan
$totalEntries = 0
foreach ($category in ($pathCategories.Keys | Sort-Object { $pathCategories[$_].Priority })) {
    $count = $categorizedPaths[$category].Count
    $totalEntries += $count
    
    if ($count -gt 0) {
        $description = $pathCategories[$category].Description
        Write-Host "`n📁 $category ($count entries) - $description" -ForegroundColor Magenta
        $categorizedPaths[$category] | ForEach-Object { Write-Host "   • $_" -ForegroundColor Gray }
    }
}

Write-Host "`n📈 Total entries analyzed: $totalEntries" -ForegroundColor Green

# Create category environment variables
Write-Host "`n🏗️  Creating category environment variables..." -ForegroundColor Yellow
$createdVars = New-CategoryEnvironmentVariables -CategorizedPaths $categorizedPaths -DryRun $WhatIf

# Create new optimized PATH
$newMainPath = New-OptimizedPath -CategorizedPaths $categorizedPaths -CategoryVars $createdVars

Write-Host "`n📋 NEW MAIN PATH STRUCTURE:" -ForegroundColor Green
if ($WhatIf) {
    Write-Host "[WHAT-IF] New main PATH would be:" -ForegroundColor Yellow
}
($newMainPath -split ';') | ForEach-Object { 
    if ($_ -like "%PATH_*%") {
        Write-Host "   • $_ (references category variable)" -ForegroundColor Cyan
    } else {
        Write-Host "   • $_" -ForegroundColor Gray
    }
}

# Apply changes to main PATH
if (-not $WhatIf) {
    if (-not $Force) {
        Write-Host "`n⚠️  This will restructure your PATH environment variables." -ForegroundColor Yellow
        Write-Host "   • Create $($createdVars.Count) new PATH_* variables" -ForegroundColor White
        Write-Host "   • Replace main PATH with category references" -ForegroundColor White
        $confirm = Read-Host "Proceed with PATH restructuring? (y/N)"
        
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "❌ Operation cancelled by user" -ForegroundColor Yellow
            exit
        }
    }
    
    # Update main PATH
    [Environment]::SetEnvironmentVariable("Path", $newMainPath, "User")
    Write-Host "`n✅ User PATH updated with category structure" -ForegroundColor Green
}

# Display category variable details
Write-Host "`n📊 CATEGORY VARIABLES CREATED:" -ForegroundColor Cyan
foreach ($category in $pathCategories.Keys) {
    if ($categorizedPaths[$category].Count -gt 0 -and $category -ne 'SYSTEM') {
        $varName = "PATH_$category"
        Write-Host "`n🔹 $varName" -ForegroundColor Blue
        Write-Host "   Entries: $($categorizedPaths[$category].Count)" -ForegroundColor White
        Write-Host "   Description: $($pathCategories[$category].Description)" -ForegroundColor Gray
        if ($WhatIf) {
            Write-Host "   [WHAT-IF] Value: $($categorizedPaths[$category] -join ';')" -ForegroundColor Yellow
        }
    }
}

# Final summary
Write-Host "`n📊 CATEGORIZATION SUMMARY:" -ForegroundColor Cyan
Write-Host "   • Categories created: $($createdVars.Count)" -ForegroundColor Green
Write-Host "   • System paths kept in main PATH: $($categorizedPaths['SYSTEM'].Count)" -ForegroundColor Blue
Write-Host "   • Total entries organized: $totalEntries" -ForegroundColor White

if ($WhatIf) {
    Write-Host "`n[WHAT-IF] No changes made in preview mode" -ForegroundColor Yellow
    Write-Host "Run without -WhatIf to apply the PATH restructuring" -ForegroundColor Gray
} else {
    Write-Host "`n✅ PATH categorization completed successfully!" -ForegroundColor Green
    Write-Host "🔄 Restart your terminal for changes to take effect" -ForegroundColor Yellow
    Write-Host "📁 Backup saved to: $backupPath" -ForegroundColor White
}

# Show how to manage categories
Write-Host "`n🛠️  MANAGING CATEGORIES:" -ForegroundColor Cyan
Write-Host "   • View category: `$env:PATH_DEV -split ';'" -ForegroundColor Yellow
Write-Host "   • Add to category: `$env:PATH_DEV += ';C:\NewTool\bin'" -ForegroundColor Yellow
Write-Host "   • Remove category: Remove-Item Env:PATH_DEV" -ForegroundColor Yellow
Write-Host "   • Restore from backup: Use the JSON backup file" -ForegroundColor Yellow

Write-Host "`n🎉 PATH categorization complete!" -ForegroundColor Green
