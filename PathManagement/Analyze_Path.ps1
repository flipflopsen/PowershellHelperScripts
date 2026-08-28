# Advanced PATH Analyzer and Cleanup Assistant
# This script analyzes your PATH environment variable to help you clean it up safely

# Configuration: Known shim and package manager directories
$shimDirs = @(
    "$env:USERPROFILE\scoop\shims",
    "C:\ProgramData\chocolatey\bin",
    "$env:USERPROFILE\.cargo\bin",
    "$env:USERPROFILE\AppData\Local\Microsoft\WinGet\Packages",
    "$env:USERPROFILE\AppData\Local\Microsoft\WinGet\Links",
    "$env:USERPROFILE\AppData\Roaming\npm",
    "$env:USERPROFILE\.dotnet\tools"
)

# Common executables to check for (indicates usefulness of the directory)
$commonTools = @(
    "python.exe", "pip.exe", "conda.exe", "poetry.exe",
    "git.exe", "gh.exe", "git-lfs.exe",
    "node.exe", "npm.cmd", "yarn.cmd", "pnpm.exe",
    "docker.exe", "kubectl.exe", "helm.exe",
    "az.exe", "aws.exe", "gcloud.exe",
    "choco.exe", "scoop.exe", "winget.exe",
    "powershell.exe", "pwsh.exe", "cmd.exe",
    "eza.exe", "ls.exe", "cat.exe", "grep.exe",
    "code.exe", "notepad++.exe", "vim.exe",
    "java.exe", "javac.exe", "mvn.cmd", "gradle.exe",
    "dotnet.exe", "nuget.exe", "msbuild.exe",
    "cmake.exe", "ninja.exe", "make.exe",
    "7z.exe", "curl.exe", "wget.exe"
)

# System directories that should always be kept
$systemDirs = @(
    "C:\Windows\system32",
    "C:\Windows",
    "C:\Windows\System32\Wbem",
    "C:\Windows\System32\WindowsPowerShell\v1.0",
    "C:\Windows\System32\OpenSSH"
)

# Function to normalize paths for comparison
function Normalize-Path($p) {
    if (-not $p) { return "" }
    return ($p.TrimEnd('\','/')).ToLowerInvariant()
}

# Function to check if a directory is a system directory
function Is-SystemDirectory($path) {
    $normalized = Normalize-Path $path
    return $systemDirs | ForEach-Object { Normalize-Path $_ } | Where-Object { $normalized -eq $_ }
}

# Function to get file count in directory (for size assessment)
function Get-DirectoryInfo($path) {
    try {
        if (Test-Path $path) {
            $files = Get-ChildItem -Path $path -File -ErrorAction SilentlyContinue
            return @{
                FileCount = $files.Count
                HasExecutables = ($files | Where-Object { $_.Extension -in @('.exe', '.cmd', '.bat', '.ps1') }).Count -gt 0
            }
        }
    } catch {
        return @{ FileCount = 0; HasExecutables = $false }
    }
    return @{ FileCount = 0; HasExecutables = $false }
}

Write-Host "=== Advanced PATH Analysis Starting ===" -ForegroundColor Cyan
Write-Host "Analyzing your PATH environment variable..." -ForegroundColor Yellow

# Get PATH entries from both User and Machine scope
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")

$allEntries = @()
$userEntries = if ($userPath) { $userPath -split ';' | Where-Object { $_.Trim() } } else { @() }
$machineEntries = if ($machinePath) { $machinePath -split ';' | Where-Object { $_.Trim() } } else { @() }

# Track which scope each entry comes from
foreach ($entry in $userEntries) {
    $allEntries += [PSCustomObject]@{ Path = $entry; Scope = "User" }
}
foreach ($entry in $machineEntries) {
    $allEntries += [PSCustomObject]@{ Path = $entry; Scope = "Machine" }
}

# Analysis results
$results = @()
$normalizedPaths = @{}
$duplicateCount = 0

Write-Host "Found $($allEntries.Count) PATH entries to analyze..." -ForegroundColor Green

foreach ($pathObj in $allEntries) {
    $entry = $pathObj.Path
    $scope = $pathObj.Scope
    $norm = Normalize-Path $entry
    
    # Skip empty entries
    if (-not $norm) { continue }
    
    # Check basic properties
    $exists = Test-Path $entry
    $isSystem = Is-SystemDirectory $entry
    $isShim = $shimDirs | ForEach-Object { Normalize-Path $_ } | Where-Object { $norm -eq $_ }
    $isDuplicate = $normalizedPaths.ContainsKey($norm)
    
    if ($isDuplicate) { $duplicateCount++ }
    $normalizedPaths[$norm] = $true
    
    # Get directory info
    $dirInfo = Get-DirectoryInfo $entry
    
    # Check for specific tools
    $toolsFound = @()
    if ($exists) {
        foreach ($tool in $commonTools) {
            $toolPath = Join-Path $entry $tool
            if (Test-Path $toolPath) {
                $toolsFound += $tool
            }
        }
    }
    
    # Determine recommendation
    $recommendation = "Keep"
    $reason = "Default"
    
    if (-not $exists) {
        $recommendation = "REMOVE"
        $reason = "Directory does not exist"
    } elseif ($isDuplicate) {
        $recommendation = "REMOVE"
        $reason = "Duplicate entry"
    } elseif ($isSystem) {
        $recommendation = "Keep"
        $reason = "System directory"
    } elseif ($isShim) {
        $recommendation = "Keep"
        $reason = "Package manager shim directory"
    } elseif ($toolsFound.Count -eq 0 -and -not $dirInfo.HasExecutables) {
        $recommendation = "REVIEW"
        $reason = "No executables found"
    } elseif ($toolsFound.Count -gt 0) {
        $recommendation = "Keep"
        $reason = "Contains useful tools: $($toolsFound -join ', ')"
    } elseif ($dirInfo.HasExecutables) {
        $recommendation = "REVIEW"
        $reason = "Contains executables (unknown tools)"
    } else {
        $recommendation = "REVIEW"
        $reason = "Manual verification needed"
    }
    
    $results += [PSCustomObject]@{
        'Path' = $entry
        'Scope' = $scope
        'Exists' = if ($exists) { 'Yes' } else { 'No' }
        'IsSystem' = if ($isSystem) { 'Yes' } else { 'No' }
        'IsShim' = if ($isShim) { 'Yes' } else { 'No' }
        'IsDuplicate' = if ($isDuplicate) { 'Yes' } else { 'No' }
        'FileCount' = $dirInfo.FileCount
        'ToolsFound' = if ($toolsFound.Count -gt 0) { $toolsFound -join ', ' } else { 'None' }
        'Recommendation' = $recommendation
        'Reason' = $reason
    }
}

# Display summary statistics
Write-Host "`n=== ANALYSIS SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total PATH entries: $($results.Count)" -ForegroundColor White
Write-Host "Entries that don't exist: $(($results | Where-Object { $_.Exists -eq 'No' }).Count)" -ForegroundColor Red
Write-Host "Duplicate entries: $duplicateCount" -ForegroundColor Yellow
Write-Host "System directories: $(($results | Where-Object { $_.IsSystem -eq 'Yes' }).Count)" -ForegroundColor Green
Write-Host "Shim directories: $(($results | Where-Object { $_.IsShim -eq 'Yes' }).Count)" -ForegroundColor Green

$removeCount = ($results | Where-Object { $_.Recommendation -eq 'REMOVE' }).Count
$reviewCount = ($results | Where-Object { $_.Recommendation -eq 'REVIEW' }).Count
$keepCount = ($results | Where-Object { $_.Recommendation -eq 'Keep' }).Count

Write-Host "`nRecommendations:" -ForegroundColor Cyan
Write-Host "  REMOVE: $removeCount entries" -ForegroundColor Red
Write-Host "  REVIEW: $reviewCount entries" -ForegroundColor Yellow
Write-Host "  KEEP: $keepCount entries" -ForegroundColor Green

# Display detailed results
Write-Host "`n=== DETAILED ANALYSIS ===" -ForegroundColor Cyan
$results | Sort-Object Recommendation, Path | Format-Table -AutoSize

# Generate cleaned PATH suggestions
Write-Host "`n=== CLEANUP SUGGESTIONS ===" -ForegroundColor Cyan

$keepEntries = $results | Where-Object { $_.Recommendation -eq 'Keep' }
$userKeep = ($keepEntries | Where-Object { $_.Scope -eq 'User' }).Path -join ';'
$machineKeep = ($keepEntries | Where-Object { $_.Scope -eq 'Machine' }).Path -join ';'

if ($userKeep) {
    Write-Host "`nCleaned User PATH:" -ForegroundColor Green
    Write-Host $userKeep -ForegroundColor White
    Write-Host "`nTo set cleaned User PATH, run:" -ForegroundColor Yellow
    Write-Host "[Environment]::SetEnvironmentVariable('Path', '$userKeep', 'User')" -ForegroundColor Cyan
}

if ($machineKeep) {
    Write-Host "`nCleaned Machine PATH:" -ForegroundColor Green
    Write-Host $machineKeep -ForegroundColor White
    Write-Host "`nTo set cleaned Machine PATH (requires admin), run:" -ForegroundColor Yellow
    Write-Host "[Environment]::SetEnvironmentVariable('Path', '$machineKeep', 'Machine')" -ForegroundColor Cyan
}

# Export detailed results
$exportPath = "$env:USERPROFILE\Desktop\PATH_Analysis_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
$results | Export-Csv -Path $exportPath -NoTypeInformation
Write-Host "`nDetailed results exported to: $exportPath" -ForegroundColor Green

Write-Host "`n=== NEXT STEPS ===" -ForegroundColor Cyan
Write-Host "1. Review entries marked as 'REVIEW' manually" -ForegroundColor White
Write-Host "2. Backup your current PATH before making changes" -ForegroundColor White
Write-Host "3. Test the cleaned PATH in a new PowerShell session" -ForegroundColor White
Write-Host "4. Use the provided commands to set the cleaned PATH" -ForegroundColor White

Write-Host "`nAnalysis complete!" -ForegroundColor Green
