# ==========================================================
# WSL Networking Auto-Recovery Loop (Fixed Logic)
# ==========================================================

# Ensure running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    pause
    exit
}

# --- CONFIGURATION ---
$adapter = "Ethernet" 
$ip      = "192.168.99.113"
$mask    = "255.255.255.0"
$gateway = "192.168.99.1"
$dns1    = "1.1.1.1"
$dns2    = "8.8.8.8"

$maxAttempts = 15
$attempt = 0
$success = $false

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "WSL Auto-Recovery Script Started" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

while (-not $success -and $attempt -lt $maxAttempts) {
    $attempt++
    Write-Host "--- Attempt $attempt of $maxAttempts ---" -ForegroundColor Yellow
    
    # 1. Shutdown WSL
    Write-Host "[1/6] Shutting down WSL..." -ForegroundColor Cyan
    wsl --shutdown
    Start-Sleep -Seconds 2
    
    # 2. Reset network stack (Modified to be less aggressive)
    Write-Host "[2/6] Flushing Network State..." -ForegroundColor Cyan
    # Only flushing neighbors and ARP usually helps without breaking the adapter completely
    netsh interface ip delete arpcache | Out-Null
    
    # 3. Restart HNS
    Write-Host "[3/6] Restarting Host Network Service..." -ForegroundColor Cyan
    try {
        Stop-Service hns -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Start-Service hns -ErrorAction Stop
    } catch {
        Write-Host "Warning: HNS restart encountered an issue, continuing..." -ForegroundColor Yellow
    }
    
    # 4. Re-apply static IP (Added checks)
    Write-Host "[4/6] Restoring static IP: $ip..." -ForegroundColor Cyan
    # Ensure adapter is up before configuring
    netsh interface set interface $adapter admin=enable 2>$null
    Start-Sleep -Seconds 1
    
    netsh interface ipv4 set address name=$adapter static $ip $mask $gateway 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "  > Warning: Failed to set IP. Adapter might be resetting." -ForegroundColor DarkGray }
    
    netsh interface ipv4 set dns name=$adapter static $dns1 2>$null
    netsh interface ipv4 add dns name=$adapter $dns2 index=2 2>$null
    
    # 5. Start WSL and capture output (Fixed Encoding)
    Write-Host "[5/6] Starting WSL and checking for errors..." -ForegroundColor Cyan
    
    # We capture output as a raw array, then sanitize it
    $rawOutput = wsl echo "WSL_STARTED" 2>&1
    
    # Convert to single string and remove Null bytes (common in WSL output)
    $cleanOutput = ($rawOutput | ForEach-Object { $_.ToString() }) -join "`n"
    $cleanOutput = $cleanOutput -replace "`0", "" 

    # 6. Check for errors - IMPROVED LOGIC
    Write-Host "[6/6] Analyzing WSL startup..." -ForegroundColor Cyan
    
    # We use -like with wildcards which is often more robust than -match for this
    $hasError = ($cleanOutput -like "*0x8007054f*") -or 
                ($cleanOutput -like "*Failed to configure network*") -or 
                ($cleanOutput -like "*falling back to networkingMode*") -or
                ($cleanOutput -like "*internal error*")

    if ($hasError) {
        Write-Host "ERROR DETECTED: WSL networking issue still present." -ForegroundColor Red
        Write-Host "Error details:" -ForegroundColor DarkGray
        Write-Host $cleanOutput -ForegroundColor DarkGray
        Write-Host "Retrying in 4 seconds..." -ForegroundColor Yellow
        Write-Host ""
        wsl --shutdown
        Start-Sleep -Seconds 4
        
    } else {
        # Double check: Did we actually get the success message?
        if ($cleanOutput -like "*WSL_STARTED*") {
            Write-Host "SUCCESS! WSL started cleanly." -ForegroundColor Green
            Write-Host "Output: $cleanOutput" -ForegroundColor DarkGray
            $success = $true
        } else {
            Write-Host "ERROR: WSL start was ambiguous. Retrying." -ForegroundColor Red
            Write-Host "Output: $cleanOutput" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

if ($success) {
    Write-Host "WSL is now running successfully!" -ForegroundColor Green
    Write-Host "Network configuration applied." -ForegroundColor Green
    Write-Host ""
    Write-Host "Press Ctrl+C to stop the script." -ForegroundColor DarkGray
    
    # Keep the script running to maintain WSL
    while ($true) {
        Start-Sleep -Seconds 30
        $check = wsl echo "alive" 2>&1
        if ($check -notmatch "alive") {
            Write-Host "WSL appears to have stopped. Exiting loop..." -ForegroundColor Red
            break
        }
    }
} else {
    Write-Host "FAILED: Could not resolve WSL networking after $maxAttempts attempts." -ForegroundColor Red
}
pause