param(
    [Parameter(Mandatory=$true)]
    [string]$Folder1,
    
    [Parameter(Mandatory=$true)]
    [string]$Folder2,
    
    [switch]$ShowTextDiff,
    [switch]$ExportResults,
    [switch]$SkipSymlinks,
    [switch]$Verbosity,
    [int]$DiffWorkers = 4,
    [string]$OutputPath = ".\diff_results.txt"
)

# Thread-safe collections
$script:syncHash = [hashtable]::Synchronized(@{})
$script:syncHash.Files1 = [hashtable]::Synchronized(@{})
$script:syncHash.Files2 = [hashtable]::Synchronized(@{})
$script:syncHash.DiffQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:syncHash.Results = [hashtable]::Synchronized(@{
    OnlyInFolder1 = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    OnlyInFolder2 = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    Different = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    Identical = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    Errors = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
})

function Get-FileHash256($FilePath) {
    try {
        if (-not (Test-Path $FilePath -PathType Leaf)) {
            return $null
        }
        return (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
    }
    catch {
        return $null
    }
}

function Test-IsSymlink($Path) {
    try {
        $item = Get-Item $Path -ErrorAction Stop
        return ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
    }
    catch {
        return $false
    }
}

function Get-SafeChildItems($Path, $SkipSymlinks = $false) {
    $results = @()
    $errors = @()
    
    try {
        if (-not (Test-Path $Path)) {
            $errors += "Path does not exist: $Path"
            return @{Items = $results; Errors = $errors}
        }
        
        $items = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue
        
        foreach ($item in $items) {
            try {
                if ($SkipSymlinks -and (Test-IsSymlink $item.FullName)) {
                    continue
                }
                
                if ($item.PSIsContainer) {
                    $subResult = Get-SafeChildItems $item.FullName $SkipSymlinks
                    $results += $subResult.Items
                    $errors += $subResult.Errors
                } else {
                    $results += $item
                }
            }
            catch {
                $errors += "Error accessing: $($item.FullName) - $($_.Exception.Message)"
            }
        }
    }
    catch {
        $errors += "Error accessing directory: $Path - $($_.Exception.Message)"
    }
    
    return @{Items = $results; Errors = $errors}
}

# Indexing function to run in parallel
$IndexFolderScriptBlock = {
    param($FolderPath, $FolderKey, $SyncHash, $SkipSymlinks, $Verbosity)
    
    # Import required functions into the runspace
    function Get-FileHash256($FilePath) {
        try {
            if (-not (Test-Path $FilePath -PathType Leaf)) {
                return $null
            }
            return (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
        }
        catch {
            return $null
        }
    }
    
    function Test-IsSymlink($Path) {
        try {
            $item = Get-Item $Path -ErrorAction Stop
            return ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
        }
        catch {
            return $false
        }
    }
    
    function Get-SafeChildItems($Path, $SkipSymlinks = $false) {
        $results = @()
        $errors = @()
        
        try {
            if (-not (Test-Path $Path)) {
                $errors += "Path does not exist: $Path"
                return @{Items = $results; Errors = $errors}
            }
            
            $items = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue
            
            foreach ($item in $items) {
                try {
                    if ($SkipSymlinks -and (Test-IsSymlink $item.FullName)) {
                        continue
                    }
                    
                    if ($item.PSIsContainer) {
                        $subResult = Get-SafeChildItems $item.FullName $SkipSymlinks
                        $results += $subResult.Items
                        $errors += $subResult.Errors
                    } else {
                        $results += $item
                    }
                }
                catch {
                    $errors += "Error accessing: $($item.FullName) - $($_.Exception.Message)"
                }
            }
        }
        catch {
            $errors += "Error accessing directory: $Path - $($_.Exception.Message)"
        }
        
        return @{Items = $results; Errors = $errors}
    }
    
    # Index the folder
    Write-Host "Indexing $FolderKey..." -ForegroundColor Yellow
    $result = Get-SafeChildItems $FolderPath $SkipSymlinks
    
    # Add errors to shared collection
    foreach ($error in $result.Errors) {
        $SyncHash.Results.Errors.Add($error) | Out-Null
    }
    
    # Process files and add to shared collection
    foreach ($file in $result.Items) {
        try {
            $relativePath = $file.FullName.Substring($FolderPath.Length + 1)
            $fileInfo = @{
                FullPath = $file.FullName
                Size = $file.Length
                LastWrite = $file.LastWriteTime
                Hash = Get-FileHash256 $file.FullName
            }
            
            $SyncHash.$FolderKey[$relativePath] = $fileInfo
        }
        catch {
            $SyncHash.Results.Errors.Add("Error processing file from $FolderKey`: $($file.FullName) - $($_.Exception.Message)") | Out-Null
        }
    }
    
    Write-Host "Completed indexing $FolderKey - Found $($SyncHash.$FolderKey.Count) files" -ForegroundColor Green
}

# Diff worker function
$DiffWorkerScriptBlock = {
    param($SyncHash, $ShowTextDiff, $Verbose)
    
    function Get-TextDiff($File1, $File2) {
        try {
            $content1 = Get-Content -Path $File1 -ErrorAction Stop
            $content2 = Get-Content -Path $File2 -ErrorAction Stop
            
            $diff = Compare-Object -ReferenceObject $content1 -DifferenceObject $content2 -IncludeEqual
            
            $diffText = @()
            $line1 = 1
            $line2 = 1
            
            foreach ($line in $diff) {
                switch ($line.SideIndicator) {
                    '<=' { 
                        $diffText += "      $($line1.ToString().PadLeft(4)): - $($line.InputObject)"
                        $line1++
                    }
                    '=>' { 
                        $diffText += "      $($line2.ToString().PadLeft(4)): + $($line.InputObject)"
                        $line2++
                    }
                    '==' {
                        #$diffText += "      $($line1.ToString().PadLeft(4)): =="
                        $line1++
                        $line2++
                    }
                }
            }
            return $diffText -join "`n"
        }
        catch {
            return "Error reading file contents: $($_.Exception.Message)"
        }
    }
    
    # Process diffs from the queue
    while ($true) {
        $diffTask = $null
        if ($SyncHash.DiffQueue.TryDequeue([ref]$diffTask)) {
            try {
                $file1Info = $diffTask.File1Info
                $file2Info = $diffTask.File2Info
                $relativePath = $diffTask.RelativePath
                
                if ($file1Info.Hash -and $file2Info.Hash) {
                    if ($file1Info.Hash -ne $file2Info.Hash) {
                        $diffResult = [PSCustomObject]@{
                            RelativePath = $relativePath
                            Path1 = $file1Info.FullPath
                            Path2 = $file2Info.FullPath
                            Size1 = $file1Info.Size
                            Size2 = $file2Info.Size
                            LastWrite1 = $file1Info.LastWrite
                            LastWrite2 = $file2Info.LastWrite
                            Hash1 = $file1Info.Hash
                            Hash2 = $file2Info.Hash
                        }
                        
                        # Add text diff if requested
                        if ($ShowTextDiff) {
                            $ext = [System.IO.Path]::GetExtension($relativePath).ToLower()
                            $textExtensions = @('.txt', '.ps1', '.py', '.js', '.html', '.css', '.xml', '.json', '.md', '.log', '.config', '.ini', '.csv')
                            if ($textExtensions -contains $ext) {
                                $diffResult | Add-Member -NotePropertyName 'TextDiff' -NotePropertyValue (Get-TextDiff $file1Info.FullPath $file2Info.FullPath)
                            }
                        }
                        
                        $SyncHash.Results.Different.Add($diffResult) | Out-Null
                    } else {
                        $identicalResult = [PSCustomObject]@{
                            RelativePath = $relativePath
                            Path1 = $file1Info.FullPath
                            Path2 = $file2Info.FullPath
                            Size = $file1Info.Size
                            LastWrite1 = $file1Info.LastWrite
                            LastWrite2 = $file2Info.LastWrite
                        }
                        $SyncHash.Results.Identical.Add($identicalResult) | Out-Null
                    }
                }
            }
            catch {
                $SyncHash.Results.Errors.Add("Error processing diff for $($diffTask.RelativePath): $($_.Exception.Message)") | Out-Null
            }
        } else {
            Start-Sleep -Milliseconds 50
            # Check if indexing is complete and queue is empty
            if ($SyncHash.IndexingComplete -and $SyncHash.DiffQueue.Count -eq 0) {
                break
            }
        }
    }
}

function Compare-FoldersParallel($Path1, $Path2) {
    Write-Host "Starting parallel folder comparison..." -ForegroundColor Yellow
    Write-Host "  Folder 1: $Path1" -ForegroundColor Cyan
    Write-Host "  Folder 2: $Path2" -ForegroundColor Cyan
    Write-Host "  Diff Workers: $DiffWorkers" -ForegroundColor Cyan
    
    if ($SkipSymlinks) {
        Write-Host "  Symlinks will be skipped" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # Create runspace pool for indexing
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, 2)
    $runspacePool.Open()
    
    # Start indexing jobs
    $indexJob1 = [powershell]::Create()
    $indexJob1.RunspacePool = $runspacePool
    $indexJob1.AddScript($IndexFolderScriptBlock).AddArgument($Path1).AddArgument("Files1").AddArgument($script:syncHash).AddArgument($SkipSymlinks).AddArgument($Verbosity) | Out-Null
    $indexHandle1 = $indexJob1.BeginInvoke()
    
    $indexJob2 = [powershell]::Create()
    $indexJob2.RunspacePool = $runspacePool
    $indexJob2.AddScript($IndexFolderScriptBlock).AddArgument($Path2).AddArgument("Files2").AddArgument($script:syncHash).AddArgument($SkipSymlinks).AddArgument($Verbosity) | Out-Null
    $indexHandle2 = $indexJob2.BeginInvoke()
    
    # Wait for indexing to complete
    Write-Host "Waiting for indexing to complete..." -ForegroundColor Yellow
    $indexJob1.EndInvoke($indexHandle1)
    $indexJob2.EndInvoke($indexHandle2)
    
    # Clean up indexing jobs
    $indexJob1.Dispose()
    $indexJob2.Dispose()
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    Write-Host "Indexing completed. Processing file differences..." -ForegroundColor Yellow
    
    # Find files only in each folder
    $files1Keys = @($script:syncHash.Files1.Keys)
    $files2Keys = @($script:syncHash.Files2.Keys)
    
    foreach ($file in $files1Keys) {
        if (-not $script:syncHash.Files2.ContainsKey($file)) {
            $result = [PSCustomObject]@{
                RelativePath = $file
                AbsolutePath = $script:syncHash.Files1[$file].FullPath
                Size = $script:syncHash.Files1[$file].Size
                LastWrite = $script:syncHash.Files1[$file].LastWrite
            }
            $script:syncHash.Results.OnlyInFolder1.Add($result) | Out-Null
        }
    }
    
    foreach ($file in $files2Keys) {
        if (-not $script:syncHash.Files1.ContainsKey($file)) {
            $result = [PSCustomObject]@{
                RelativePath = $file
                AbsolutePath = $script:syncHash.Files2[$file].FullPath
                Size = $script:syncHash.Files2[$file].Size
                LastWrite = $script:syncHash.Files2[$file].LastWrite
            }
            $script:syncHash.Results.OnlyInFolder2.Add($result) | Out-Null
        }
    }
    
    # Queue files that exist in both folders for diff processing
    foreach ($file in $files1Keys) {
        if ($script:syncHash.Files2.ContainsKey($file)) {
            $diffTask = @{
                RelativePath = $file
                File1Info = $script:syncHash.Files1[$file]
                File2Info = $script:syncHash.Files2[$file]
            }
            $script:syncHash.DiffQueue.Enqueue($diffTask)
        }
    }
    
    Write-Host "Queued $($script:syncHash.DiffQueue.Count) files for diff processing" -ForegroundColor Yellow
    
    # Create runspace pool for diff workers
    $diffRunspacePool = [runspacefactory]::CreateRunspacePool(1, $DiffWorkers)
    $diffRunspacePool.Open()
    
    # Start diff worker jobs
    $diffJobs = @()
    for ($i = 0; $i -lt $DiffWorkers; $i++) {
        $diffJob = [powershell]::Create()
        $diffJob.RunspacePool = $diffRunspacePool
        $diffJob.AddScript($DiffWorkerScriptBlock).AddArgument($script:syncHash).AddArgument($ShowTextDiff).AddArgument($Verbosity) | Out-Null
        $diffHandle = $diffJob.BeginInvoke()
        $diffJobs += @{Job = $diffJob; Handle = $diffHandle}
    }
    
    # Signal that indexing is complete
    $script:syncHash.IndexingComplete = $true
    
    # Wait for all diff jobs to complete
    foreach ($jobInfo in $diffJobs) {
        $jobInfo.Job.EndInvoke($jobInfo.Handle)
        $jobInfo.Job.Dispose()
    }
    
    # Clean up diff runspace pool
    $diffRunspacePool.Close()
    $diffRunspacePool.Dispose()
    
    Write-Host "Diff processing completed" -ForegroundColor Green
    
    # Convert synchronized collections to regular arrays for output
    $finalResults = @{
        OnlyInFolder1 = @($script:syncHash.Results.OnlyInFolder1)
        OnlyInFolder2 = @($script:syncHash.Results.OnlyInFolder2)
        Different = @($script:syncHash.Results.Different)
        Identical = @($script:syncHash.Results.Identical)
        Errors = @($script:syncHash.Results.Errors)
    }
    
    return $finalResults
}

function Show-Results($Results) {
    Write-Host "`n=== COMPARISON RESULTS ===" -ForegroundColor Yellow
    
    if ($Results.Errors.Count -gt 0) {
        Write-Host "`nErrors encountered during comparison ($($Results.Errors.Count) errors):" -ForegroundColor Red
        foreach ($error in $Results.Errors) {
            Write-Host "  ! $error" -ForegroundColor Red
        }
    }
    
    if ($Results.OnlyInFolder1.Count -gt 0) {
        Write-Host "`nFiles only in Folder 1 ($($Results.OnlyInFolder1.Count) files):" -ForegroundColor Red
        $Results.OnlyInFolder1 | ForEach-Object {
            Write-Host "  - $($_.AbsolutePath)" -ForegroundColor Red
        }
    }
    
    if ($Results.OnlyInFolder2.Count -gt 0) {
        Write-Host "`nFiles only in Folder 2 ($($Results.OnlyInFolder2.Count) files):" -ForegroundColor Green
        $Results.OnlyInFolder2 | ForEach-Object {
            Write-Host "  + $($_.AbsolutePath)" -ForegroundColor Green
        }
    }
    
    if ($Results.Different.Count -gt 0) {
        Write-Host "`nFiles with different content ($($Results.Different.Count) files):" -ForegroundColor Magenta
        $Results.Different | ForEach-Object {
            Write-Host "  ≠ $($_.RelativePath)" -ForegroundColor Magenta
            Write-Host "    Folder 1: $($_.Path1) (Size: $($_.Size1), Modified: $($_.LastWrite1))" -ForegroundColor Cyan
            Write-Host "    Folder 2: $($_.Path2) (Size: $($_.Size2), Modified: $($_.LastWrite2))" -ForegroundColor Cyan
            
            if ($ShowTextDiff -and $_.TextDiff) {
                Write-Host "    TEXT DIFFERENCES:" -ForegroundColor Yellow
                Write-Host "    $("=" * 76)" -ForegroundColor Gray
                Write-Host $_.TextDiff -ForegroundColor White
                Write-Host "    $("=" * 76)" -ForegroundColor Gray
            } elseif ($ShowTextDiff) {
                # Generate text diff with line numbers for console output
                $ext = [System.IO.Path]::GetExtension($_.RelativePath).ToLower()
                $textExtensions = @('.txt', '.ps1', '.py', '.js', '.html', '.css', '.xml', '.json', '.md', '.log', '.config', '.ini', '.csv')
                
                if ($textExtensions -contains $ext) {
                    Write-Host "    TEXT DIFFERENCES:" -ForegroundColor Yellow
                    Write-Host "    $("=" * 76)" -ForegroundColor Gray
                    try {
                        $content1 = Get-Content -Path $_.Path1 -ErrorAction Stop
                        $content2 = Get-Content -Path $_.Path2 -ErrorAction Stop
                        
                        $diff = Compare-Object -ReferenceObject $content1 -DifferenceObject $content2 -IncludeEqual
                        
                        $line1 = 1
                        $line2 = 1
                        
                        foreach ($line in $diff) {
                            switch ($line.SideIndicator) {
                                '<=' { 
                                    Write-Host "    $($line1.ToString().PadLeft(4)): - $($line.InputObject)" -ForegroundColor Red
                                    $line1++
                                }
                                '=>' { 
                                    Write-Host "    $($line2.ToString().PadLeft(4)): + $($line.InputObject)" -ForegroundColor Green
                                    $line2++
                                }
                                '==' { 
                                    #Write-Host "    $($line1.ToString().PadLeft(4)): ==" -ForegroundColor DarkGray
                                    $line1++
                                    $line2++
                                }
                            }
                        }
                    }
                    catch {
                        Write-Host "    Error reading file contents: $($_.Exception.Message)" -ForegroundColor Red
                    }
                    Write-Host "    $("=" * 76)" -ForegroundColor Gray
                } else {
                    Write-Host "    [Binary file - skipping text diff]" -ForegroundColor Yellow
                }
            }
        }
    }
    
    Write-Host "`n=== SUMMARY ===" -ForegroundColor Yellow
    Write-Host "Identical files: $($Results.Identical.Count)" -ForegroundColor White
    Write-Host "Only in Folder 1: $($Results.OnlyInFolder1.Count)" -ForegroundColor Red
    Write-Host "Only in Folder 2: $($Results.OnlyInFolder2.Count)" -ForegroundColor Green
    Write-Host "Different content: $($Results.Different.Count)" -ForegroundColor Magenta
    Write-Host "Errors encountered: $($Results.Errors.Count)" -ForegroundColor Red
    Write-Host "Total files compared: $(($Results.Identical.Count + $Results.Different.Count))" -ForegroundColor White
}



function Export-Results($Results, $OutputPath) {
    $output = @()
    $output += "=== FOLDER COMPARISON RESULTS ==="
    $output += "Generated: $(Get-Date)"
    $output += "Folder 1: $Folder1"
    $output += "Folder 2: $Folder2"
    $output += ""
    
    if ($Results.Errors.Count -gt 0) {
        $output += "ERRORS ENCOUNTERED:"
        foreach ($error in $Results.Errors) {
            $output += "  ! $error"
        }
        $output += ""
    }
    
    if ($Results.OnlyInFolder1.Count -gt 0) {
        $output += "FILES ONLY IN FOLDER 1:"
        $Results.OnlyInFolder1 | ForEach-Object {
            $output += "  - $($_.AbsolutePath)"
        }
        $output += ""
    }
    
    if ($Results.OnlyInFolder2.Count -gt 0) {
        $output += "FILES ONLY IN FOLDER 2:"
        $Results.OnlyInFolder2 | ForEach-Object {
            $output += "  + $($_.AbsolutePath)"
        }
        $output += ""
    }
    
    if ($Results.Different.Count -gt 0) {
        $output += "FILES WITH DIFFERENT CONTENT:"
        foreach ($diffFile in $Results.Different) {
            $output += "  ≠ $($diffFile.RelativePath)"
            $output += "    Folder 1: $($diffFile.Path1) (Size: $($diffFile.Size1))"
            $output += "    Folder 2: $($diffFile.Path2) (Size: $($diffFile.Size2))"
            
            if ($ShowTextDiff) {
                $ext = [System.IO.Path]::GetExtension($diffFile.RelativePath).ToLower()
                $textExtensions = @('.txt', '.ps1', '.py', '.js', '.html', '.css', '.xml', '.json', '.md', '.log', '.config', '.ini', '.csv')
                
                if ($textExtensions -contains $ext) {
                    $output += "    TEXT DIFFERENCES:"
                    $output += "    " + ("=" * 76)
                    
                    if ($diffFile.TextDiff) {
                        # Use pre-computed text diff with side indicators only for unchanged lines
                        $output += $diffFile.TextDiff
                    } else {
                        # Generate text diff with side indicators only for unchanged lines
                        try {
                            $content1 = Get-Content -Path $diffFile.Path1 -ErrorAction Stop
                            $content2 = Get-Content -Path $diffFile.Path2 -ErrorAction Stop
                            
                            $diff = Compare-Object -ReferenceObject $content1 -DifferenceObject $content2 -IncludeEqual
                            
                            $line1 = 1
                            $line2 = 1
                            
                            foreach ($line in $diff) {
                                switch ($line.SideIndicator) {
                                    '<=' { 
                                        $output += "      $($line1.ToString().PadLeft(4)): - $($line.InputObject)"
                                        $line1++
                                    }
                                    '=>' { 
                                        $output += "      $($line2.ToString().PadLeft(4)): + $($line.InputObject)"
                                        $line2++
                                    }
                                    '==' { 
                                        #$output += "      $($line1.ToString().PadLeft(4)): =="
                                        $line1++
                                        $line2++
                                    }
                                }
                            }
                        }
                        catch {
                            $output += "      [Error reading file contents: $($_.Exception.Message)]"
                        }
                    }
                    $output += "    " + ("=" * 76)
                } else {
                    $output += "    [Binary file - skipping text diff]"
                }
            }
            $output += ""
        }
    }
    
    $output += "SUMMARY:"
    $output += "Identical files: $($Results.Identical.Count)"
    $output += "Only in Folder 1: $($Results.OnlyInFolder1.Count)"
    $output += "Only in Folder 2: $($Results.OnlyInFolder2.Count)"
    $output += "Different content: $($Results.Different.Count)"
    $output += "Errors encountered: $($Results.Errors.Count)"
    
    $output | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "`nResults exported to: $OutputPath" -ForegroundColor Green
}



# Main execution
try {
    $Path1 = (Resolve-Path $Folder1).Path
    $Path2 = (Resolve-Path $Folder2).Path
    
    $results = Compare-FoldersParallel $Path1 $Path2
    Show-Results $results
    
    if ($ExportResults) {
        Export-Results $results $OutputPath
    }
}
catch {
    Write-Error "Error: $($_.Exception.Message)"
}
