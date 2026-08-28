# Custom Development Tools Shim Creator
# Creates a unified shim directory for Java and development tools to reduce PATH clutter

param(
    [string]$ShimDirectory = "C:\Users\$env:USERNAME\DevShims",
    [switch]$WhatIf = $false,
    [switch]$Force = $false
)

# Development tools to look for and create shims
$devTools = @{
    # Java tools
    "java.exe" = @("Java Runtime", "JRE/JDK")
    "javac.exe" = @("Java Compiler", "JDK")
    "javaw.exe" = @("Java Runtime (Windowed)", "JRE/JDK")
    "jar.exe" = @("Java Archive Tool", "JDK")
    "javadoc.exe" = @("Java Documentation", "JDK")
    "javap.exe" = @("Java Disassembler", "JDK")
    "jcmd.exe" = @("Java Command", "JDK")
    "jconsole.exe" = @("Java Console", "JDK")
    "jdb.exe" = @("Java Debugger", "JDK")
    "jdeps.exe" = @("Java Dependencies", "JDK")
    "jhat.exe" = @("Java Heap Analysis", "JDK")
    "jinfo.exe" = @("Java Info", "JDK")
    "jmap.exe" = @("Java Memory Map", "JDK")
    "jps.exe" = @("Java Process Status", "JDK")
    "jstack.exe" = @("Java Stack Trace", "JDK")
    "jstat.exe" = @("Java Statistics", "JDK")
    "keytool.exe" = @("Java Key Tool", "JDK")
    
    # Build tools
    "mvn.cmd" = @("Maven", "Build Tool")
    "mvn.exe" = @("Maven", "Build Tool")
    "gradle.exe" = @("Gradle", "Build Tool")
    "gradle.bat" = @("Gradle", "Build Tool")
    "ant.exe" = @("Apache Ant", "Build Tool")
    "ant.bat" = @("Apache Ant", "Build Tool")
    "sbt.exe" = @("SBT Scala Build", "Build Tool")
    "lein.exe" = @("Leiningen", "Build Tool")
    
    # .NET tools
    "dotnet.exe" = @(".NET Runtime", "Microsoft")
    "msbuild.exe" = @("MSBuild", "Microsoft")
    "nuget.exe" = @("NuGet Package Manager", "Microsoft")
    "devenv.exe" = @("Visual Studio", "Microsoft")
    "vstest.console.exe" = @("Visual Studio Test", "Microsoft")
    
    # Python tools
    "python.exe" = @("Python Interpreter", "Python")
    "pip.exe" = @("Python Package Manager", "Python")
    "pipenv.exe" = @("Python Virtual Environment", "Python")
    "poetry.exe" = @("Python Dependency Manager", "Python")
    "conda.exe" = @("Conda Package Manager", "Python")
    
    # Node.js tools
    "node.exe" = @("Node.js Runtime", "JavaScript")
    "npm.cmd" = @("Node Package Manager", "JavaScript")
    "yarn.cmd" = @("Yarn Package Manager", "JavaScript")
    "pnpm.exe" = @("PNPM Package Manager", "JavaScript")
    
    # Git and VCS
    "git.exe" = @("Git Version Control", "VCS")
    "gh.exe" = @("GitHub CLI", "VCS")
    "git-lfs.exe" = @("Git Large File Storage", "VCS")
    "svn.exe" = @("Subversion", "VCS")
    
    # Rust tools
    "rustc.exe" = @("Rust Compiler", "Rust")
    "cargo.exe" = @("Rust Package Manager", "Rust")
    "rustup.exe" = @("Rust Toolchain Manager", "Rust")
    
    # Go tools
    "go.exe" = @("Go Compiler", "Go")
    "gofmt.exe" = @("Go Formatter", "Go")
    
    # Database tools
    "mysql.exe" = @("MySQL Client", "Database")
    "psql.exe" = @("PostgreSQL Client", "Database")
    "sqlcmd.exe" = @("SQL Server Client", "Database")
    
    # Cloud tools
    "az.exe" = @("Azure CLI", "Cloud")
    "aws.exe" = @("AWS CLI", "Cloud")
    "kubectl.exe" = @("Kubernetes CLI", "Cloud")
    "docker.exe" = @("Docker", "Containers")
    "helm.exe" = @("Helm", "Kubernetes")
    
    # Development utilities
    "cmake.exe" = @("CMake Build System", "Build Tool")
    "ninja.exe" = @("Ninja Build System", "Build Tool")
    "make.exe" = @("Make Build Tool", "Build Tool")
    "code.exe" = @("VS Code", "Editor")
    "vim.exe" = @("Vim Editor", "Editor")
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
REM Custom shim for $ToolName
REM Target: $TargetPath
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
# Custom PowerShell shim for $ToolName
# Target: $TargetPath
& "$TargetPath" @args
"@
    
    Set-Content -Path $ShimPath -Value $shimContent -Encoding UTF8
}

# Function to find tools in PATH
function Find-DevTools {
    Write-Host "=== Scanning PATH for Development Tools ===" -ForegroundColor Cyan
    
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $allPaths = ($userPath + ";" + $machinePath) -split ';' | Where-Object { $_.Trim() -ne "" }
    
    $foundTools = @()
    $pathsToRemove = @()
    
    foreach ($path in $allPaths) {
        $normalizedPath = $path.TrimEnd('\', '/')
        
        if (-not (Test-Path $normalizedPath)) {
            continue
        }
        
        $toolsInPath = @()
        foreach ($tool in $devTools.Keys) {
            $toolPath = Join-Path $normalizedPath $tool
            if (Test-Path $toolPath) {
                $toolInfo = $devTools[$tool]
                $foundTools += [PSCustomObject]@{
                    ToolName = $tool
                    ToolDescription = $toolInfo[0]
                    Category = $toolInfo[1]
                    FullPath = $toolPath
                    PathDirectory = $normalizedPath
                    FileSize = (Get-Item $toolPath).Length
                    LastModified = (Get-Item $toolPath).LastWriteTime
                }
                $toolsInPath += $tool
            }
        }
        
        # If this path contains dev tools, mark it for potential removal
        if ($toolsInPath.Count -gt 0) {
            $pathsToRemove += [PSCustomObject]@{
                Path = $normalizedPath
                ToolCount = $toolsInPath.Count
                Tools = $toolsInPath -join ", "
                Scope = if ($userPath -like "*$normalizedPath*") { "User" } else { "Machine" }
            }
        }
    }
    
    return @{
        FoundTools = $foundTools
        PathsToRemove = $pathsToRemove
    }
}

# Function to create shim directory and shims
function New-ShimDirectory {
    param(
        [string]$ShimDir,
        [array]$Tools,
        [bool]$DryRun = $false
    )
    
    Write-Host "`n=== Creating Shim Directory ===" -ForegroundColor Cyan
    
    if ($DryRun) {
        Write-Host "[WHAT-IF] Would create directory: $ShimDir" -ForegroundColor Yellow
    } else {
        if (-not (Test-Path $ShimDir)) {
            New-Item -Path $ShimDir -ItemType Directory -Force | Out-Null
            Write-Host "Created shim directory: $ShimDir" -ForegroundColor Green
        } else {
            Write-Host "Shim directory already exists: $ShimDir" -ForegroundColor Yellow
        }
    }
    
    $shimCount = 0
    $grouped = $Tools | Group-Object ToolName
    
    foreach ($group in $grouped) {
        $toolName = $group.Name
        $instances = $group.Group | Sort-Object LastModified -Descending
        $latest = $instances[0]  # Use the most recently modified version
        
        # Determine shim file extension and create appropriate shim
        $baseShimName = [System.IO.Path]::GetFileNameWithoutExtension($toolName)
        $shimExtension = if ($toolName -like "*.cmd" -or $toolName -like "*.bat") { ".cmd" } else { ".cmd" }
        $shimPath = Join-Path $ShimDir "$baseShimName$shimExtension"
        $ps1ShimPath = Join-Path $ShimDir "$baseShimName.ps1"
        
        if ($DryRun) {
            Write-Host "[WHAT-IF] Would create shim: $shimPath -> $($latest.FullPath)" -ForegroundColor Yellow
            if ($instances.Count -gt 1) {
                Write-Host "    [WHAT-IF] Multiple versions found, would use latest: $($latest.LastModified)" -ForegroundColor Magenta
                foreach ($alt in $instances[1..($instances.Count-1)]) {
                    Write-Host "    [WHAT-IF] Alternative: $($alt.FullPath)" -ForegroundColor DarkGray
                }
            }
        } else {
            # Create CMD shim
            New-CmdShim -ShimPath $shimPath -TargetPath $latest.FullPath -ToolName $latest.ToolDescription
            
            # Create PowerShell shim as well
            New-PowerShellShim -ShimPath $ps1ShimPath -TargetPath $latest.FullPath -ToolName $latest.ToolDescription
            
            Write-Host "Created shim: $baseShimName -> $($latest.FullPath)" -ForegroundColor Green
            
            if ($instances.Count -gt 1) {
                Write-Host "  └─ Multiple versions found, using latest: $($latest.LastModified)" -ForegroundColor Yellow
            }
            
            $shimCount++
        }
    }
    
    return $shimCount
}

# Function to generate PATH cleanup suggestions
function Get-PathCleanupSuggestions {
    param(
        [array]$PathsToRemove,
        [string]$ShimDir
    )
    
    Write-Host "`n=== PATH Cleanup Suggestions ===" -ForegroundColor Cyan
    
    $userPathsToRemove = ($PathsToRemove | Where-Object { $_.Scope -eq "User" }).Path
    $machinePathsToRemove = ($PathsToRemove | Where-Object { $_.Scope -eq "Machine" }).Path
    
    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $currentMachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    
    # Clean User PATH
    if ($userPathsToRemove.Count -gt 0) {
        $cleanedUserPath = $currentUserPath
        foreach ($pathToRemove in $userPathsToRemove) {
            $cleanedUserPath = $cleanedUserPath -replace [regex]::Escape($pathToRemove + ";"), ""
            $cleanedUserPath = $cleanedUserPath -replace [regex]::Escape(";" + $pathToRemove), ""
            $cleanedUserPath = $cleanedUserPath -replace "^" + [regex]::Escape($pathToRemove) + "$", ""
        }
        
        # Add shim directory if not already present
        if ($cleanedUserPath -notlike "*$ShimDir*") {
            $cleanedUserPath = "$ShimDir;" + $cleanedUserPath
        }
        
        Write-Host "`nCleaned User PATH (with shim directory added):" -ForegroundColor Green
        Write-Host $cleanedUserPath -ForegroundColor White
        Write-Host "`nTo apply User PATH changes:" -ForegroundColor Yellow
        Write-Host "[Environment]::SetEnvironmentVariable('Path', '$cleanedUserPath', 'User')" -ForegroundColor Cyan
    }
    
    # Clean Machine PATH
    if ($machinePathsToRemove.Count -gt 0) {
        $cleanedMachinePath = $currentMachinePath
        foreach ($pathToRemove in $machinePathsToRemove) {
            $cleanedMachinePath = $cleanedMachinePath -replace [regex]::Escape($pathToRemove + ";"), ""
            $cleanedMachinePath = $cleanedMachinePath -replace [regex]::Escape(";" + $pathToRemove), ""
            $cleanedMachinePath = $cleanedMachinePath -replace "^" + [regex]::Escape($pathToRemove) + "$", ""
        }
        
        Write-Host "`nCleaned Machine PATH:" -ForegroundColor Green
        Write-Host $cleanedMachinePath -ForegroundColor White
        Write-Host "`nTo apply Machine PATH changes (requires admin):" -ForegroundColor Yellow
        Write-Host "[Environment]::SetEnvironmentVariable('Path', '$cleanedMachinePath', 'Machine')" -ForegroundColor Cyan
    }
    
    return @{
        CleanedUserPath = $cleanedUserPath
        CleanedMachinePath = $cleanedMachinePath
        PathsRemoved = $PathsToRemove.Count
    }
}

# Main execution
Write-Host "=== Custom Development Tools Shim Creator ===" -ForegroundColor Cyan
Write-Host "Target shim directory: $ShimDirectory" -ForegroundColor White

# Find all development tools in PATH
$analysis = Find-DevTools

Write-Host "`nFound $($analysis.FoundTools.Count) development tools in $($analysis.PathsToRemove.Count) directories" -ForegroundColor Green

# Display found tools by category
$analysis.FoundTools | Group-Object Category | Sort-Object Name | ForEach-Object {
    Write-Host "`n$($_.Name) Tools:" -ForegroundColor Magenta
    $_.Group | Sort-Object ToolName | ForEach-Object {
        $size = if ($_.FileSize -gt 1MB) { "{0:N1} MB" -f ($_.FileSize / 1MB) } else { "{0:N0} KB" -f ($_.FileSize / 1KB) }
        Write-Host "  $($_.ToolName) - $($_.ToolDescription) ($size)" -ForegroundColor White
        Write-Host "    Path: $($_.FullPath)" -ForegroundColor DarkGray
    }
}

# Display paths that contain dev tools
Write-Host "`n=== Paths Containing Development Tools ===" -ForegroundColor Cyan
$analysis.PathsToRemove | Sort-Object ToolCount -Descending | ForEach-Object {
    Write-Host "$($_.Path) [$($_.Scope)]" -ForegroundColor White
    Write-Host "  └─ $($_.ToolCount) tools: $($_.Tools)" -ForegroundColor Gray
}

if ($WhatIf) {
    Write-Host "`n=== WHAT-IF MODE ===" -ForegroundColor Yellow
    $shimCount = New-ShimDirectory -ShimDir $ShimDirectory -Tools $analysis.FoundTools -DryRun $true
    Write-Host "[WHAT-IF] Would create $shimCount shims in $ShimDirectory" -ForegroundColor Yellow
} else {
    # Create shims
    $shimCount = New-ShimDirectory -ShimDir $ShimDirectory -Tools $analysis.FoundTools -DryRun $false
    
    # Generate cleanup suggestions
    $cleanup = Get-PathCleanupSuggestions -PathsToRemove $analysis.PathsToRemove -ShimDir $ShimDirectory
    
    Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
    Write-Host "✅ Created $shimCount shims in: $ShimDirectory" -ForegroundColor Green
    Write-Host "📁 Found tools in $($analysis.PathsToRemove.Count) directories" -ForegroundColor White
    Write-Host "🧹 Suggested removal of $($cleanup.PathsRemoved) PATH entries" -ForegroundColor Yellow
    
    # Export detailed report
    $reportPath = "$env:USERPROFILE\Desktop\DevTools_Shim_Report_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
    $analysis.FoundTools | Export-Csv -Path $reportPath -NoTypeInformation
    Write-Host "📊 Detailed report exported to: $reportPath" -ForegroundColor Green
    
    Write-Host "`n=== NEXT STEPS ===" -ForegroundColor Cyan
    Write-Host "1. Test the shims by opening a new PowerShell session" -ForegroundColor White
    Write-Host "2. Verify tools work: java -version, mvn -version, etc." -ForegroundColor White
    Write-Host "3. Apply the PATH cleanup commands above" -ForegroundColor White
    Write-Host "4. Restart your terminal to use the cleaned PATH" -ForegroundColor White
    
    if (-not $Force) {
        Write-Host "`n⚠️  Review the changes before applying PATH modifications!" -ForegroundColor Yellow
        Write-Host "Use -WhatIf to preview changes, -Force to skip confirmations" -ForegroundColor Gray
    }
}
