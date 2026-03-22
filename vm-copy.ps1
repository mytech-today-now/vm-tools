<#
.SYNOPSIS
    Clones a Hyper-V VM by exporting and re-importing it with a new name.

.DESCRIPTION
    Stops the source VM (if running), exports it to a staging folder, imports
    the export as a copy with a new unique ID, renames the VM and its VHDX
    files to match the destination name, and removes any checkpoints from the
    clone so it starts with a clean, merged disk.  The original VM is restarted
    if it was running before the copy began.

    Multiple copies can be created in a single run with -Count.  The source VM
    is exported once and then imported N times.  Each copy is named using the
    next available sequential <VMName>.## name (e.g. vm.03, vm.04, ...).

    Checkpoint handling:
      - The source VM is exported with all its checkpoints intact.
      - After import the clone's checkpoints are removed (merged into the base
        disk) so the destination VM has a single clean VHDX.
      - The source VM's checkpoints are never modified.

    The export staging folder defaults to a 'VMExports' directory under the
    storage root configured in vm-config.json.  Override with -ExportPath.

    Supports -WhatIf / -Confirm for safe dry-runs and -Verbose for extra
    detail.

    Run 'Get-Help .\vm-copy.ps1 -Full' or '.\vm-copy.ps1 -?' for full help.

.PARAMETER SourceVMName
    Name of the existing VM to clone.  Default: vm.01

.PARAMETER VMName
    Base name for the destination VM(s).  The script appends a sequential
    number as <VMName>.## (e.g. vm.02, vm.03).  Default: derived from the
    source VM name (e.g. source "vm.01" -> base "vm").

.PARAMETER Count
    Number of copies to create.  Default: 1.  When greater than 1, names
    are auto-assigned sequentially (e.g. vm.03, vm.04, ...).

.PARAMETER ExportPath
    Temporary folder used for the export.  Cleaned up after import unless
    -KeepExport is specified.  By default a 'VMExports' folder is created
    under the storage root configured in vm-config.json (the parent of the
    VMPath).  Pass this parameter explicitly to override.

.PARAMETER KeepExport
    When set, the export folder is NOT deleted after a successful import.

.PARAMETER StoragePath
    Root path for VM storage.  VM config and VHD sub-directories are created
    beneath this path.  Saved to a persistent config file (~\.vm-tools\config.json)
    and reused on subsequent runs.  Default: Hyper-V host defaults (typically C:\).

.PARAMETER ResetConfig
    Ignore the saved storage-path config and prompt interactively for a new
    location.  The new choice is saved for future runs.

.PARAMETER Log
    Enable JSONL logging to vm-copy.jsonl in the script directory.  Without
    this switch no log file is created or written.

.PARAMETER Append
    When used with -Log, new log entries are appended to the existing JSONL
    log file.  By default the log file is purged at the start of each run.

.PARAMETER ShowLog
    Display the JSONL log and exit.  Combine with -Last, -Level, or -RunId
    to filter entries.

.PARAMETER Last
    When used with -ShowLog, return only the last N log entries.

.PARAMETER Level
    When used with -ShowLog, filter by log level (INFO, WARN, ERROR, DEBUG,
    SUCCESS).

.PARAMETER RunId
    When used with -ShowLog, filter by a specific run ID.

.EXAMPLE
    .\vm-copy.ps1 -SourceVMName "vm.01"
    Clones "vm.01" to the next available vm.## name (e.g. vm.02).

.EXAMPLE
    .\vm-copy.ps1 -SourceVMName "vm.01" -Count 5
    Creates 5 copies of "vm.01" (e.g. vm.02 through vm.06).

.EXAMPLE
    .\vm-copy.ps1 -SourceVMName "vm.01" -VMName "lab" -Count 3
    Clones "vm.01" into lab.01, lab.02, lab.03 (or next available).

.EXAMPLE
    .\vm-copy.ps1 -SourceVMName "vm.01" -WhatIf
    Dry-run -- shows what would happen without making any changes.

.EXAMPLE
    .\vm-copy.ps1 -SourceVMName "vm.01" -KeepExport
    Clones "vm.01" and keeps the export folder for manual inspection.

.EXAMPLE
    .\vm-copy.ps1 -SourceVMName "vm.01" -ExportPath "E:\Staging"
    Clones "vm.01" using a custom export staging folder.

.EXAMPLE
    .\vm-copy.ps1 -SourceVMName "vm.01" -StoragePath "D:\VMs"
    Clones "vm.01" and stores the new VM under D:\VMs\Hyper-V.

.EXAMPLE
    .\vm-copy.ps1 -SourceVMName "vm.01" -Log
    Clones "vm.01" with JSONL logging enabled.

.EXAMPLE
    .\vm-copy.ps1 -SourceVMName "vm.01" -Log -Append
    Clones "vm.01" and appends log entries to the existing log file.

.EXAMPLE
    .\vm-copy.ps1 -ShowLog
    Displays all log entries from previous runs.

.EXAMPLE
    .\vm-copy.ps1 -ShowLog -Last 20 -Level ERROR
    Shows the last 20 ERROR-level log entries.

.EXAMPLE
    .\vm-copy.ps1 -ShowLog -Level ERROR,WARN
    Shows all ERROR and WARN entries from the log.

.EXAMPLE
    irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-copy.ps1 | iex; vm-copy -SourceVMName "vm.01"
    Downloads from GitHub and clones "vm.01" (public repo, auto-elevates).

.EXAMPLE
    irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-copy.ps1 | iex; vm-copy -SourceVMName "vm.01" -VMName "lab" -Count 5
    Downloads from GitHub and creates 5 clones named lab.01 through lab.05.

.EXAMPLE
    irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-copy.ps1 | iex; vm-copy -SourceVMName "vm.01" -Log
    Downloads from GitHub and clones with JSONL logging enabled.

.EXAMPLE
    $h = @{ Authorization = "token $env:GITHUB_TOKEN"; Accept = 'application/vnd.github.v3.raw' }
    irm https://api.github.com/repos/mytech-today-now/vm-tools/contents/vm-copy.ps1 -Headers $h | iex; vm-copy -SourceVMName "vm.01" -Count 3
    Downloads from a PRIVATE GitHub repo and creates 3 clones.

.NOTES
    Author : myTech.Today
    Version: 1.4.0
    Requires: Hyper-V module, Administrator privileges
    Log file: <ScriptDir>\vm-copy.jsonl (when -Log is used)
    Help    : Get-Help .\vm-copy.ps1 -Full
              .\vm-copy.ps1 -?

    Remote execution (irm | iex):
      The script auto-downloads itself and vm-config.ps1 to a temp folder,
      defines a global 'vm-copy' function, and re-launches as a proper .ps1
      so that parameters, -WhatIf, -Confirm, and admin elevation all work.

      Public repo:
        irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-copy.ps1 | iex
      Private repo:
        $env:GITHUB_TOKEN = 'ghp_YourPersonalAccessToken'
        $h = @{ Authorization = "token $env:GITHUB_TOKEN"; Accept = 'application/vnd.github.v3.raw' }
        irm https://api.github.com/repos/mytech-today-now/vm-tools/contents/vm-copy.ps1 -Headers $h | iex

    Changelog v1.4.0:
    - Added -Log switch to make JSONL logging opt-in
    - ExportPath now defaults to <StorageRoot>\VMExports (from vm-config.json)

    Changelog v1.3.0:
    - Auto-clean leftover destination directories from previous failed runs

    Changelog v1.2.0:
    - Added persistent VM storage path selection (prompted on first run)
    - Added -StoragePath and -ResetConfig parameters

    Changelog v1.1.0:
    - Added disk-space pre-flight check before export/import
#>

#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High',
               DefaultParameterSetName = 'Copy')]
param(
    [Parameter(ParameterSetName = 'Copy', Position = 0)]
    [string]$SourceVMName = 'vm.01',

    [Parameter(ParameterSetName = 'Copy', Position = 1)]
    [string]$VMName,

    [Parameter(ParameterSetName = 'Copy')]
    [ValidateRange(1, 100)]
    [int]$Count = 1,

    [Parameter(ParameterSetName = 'Copy')]
    [string]$ExportPath,

    [Parameter(ParameterSetName = 'Copy')]
    [switch]$KeepExport,

    [Parameter(ParameterSetName = 'Copy')]
    [switch]$Log,

    [Parameter(ParameterSetName = 'Copy')]
    [switch]$Append,

    [Parameter(ParameterSetName = 'Copy')]
    [string]$StoragePath,

    [Parameter(ParameterSetName = 'Copy')]
    [switch]$ResetConfig,

    [Parameter(ParameterSetName = 'Log', Mandatory)]
    [switch]$ShowLog,

    [Parameter(ParameterSetName = 'Log')]
    [int]$Last,

    [Parameter(ParameterSetName = 'Log')]
    [string[]]$Level,

    [Parameter(ParameterSetName = 'Log')]
    [string]$RunId
)

# ---------------------------------------------------------------------------
# Remote-execution bootstrap
# ---------------------------------------------------------------------------
# When run via `irm <url> | iex`, $MyInvocation.MyCommand.Path is empty
# because there is no script file on disk.  In that case we download the
# script and its helper to a temp folder and create a global `vm-copy`
# function so the user can call:
#   irm <url> | iex; vm-copy -SourceVMName "x" -VMName "y" -Count 3
if (-not $MyInvocation.MyCommand.Path) {
    $scriptName = 'vm-copy.ps1'
    $rawUrl     = 'https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-copy.ps1'
    $tempDir    = Join-Path $env:TEMP 'vm-tools'
    if (-not (Test-Path $tempDir)) { New-Item -Path $tempDir -ItemType Directory -Force | Out-Null }
    $tempScript = Join-Path $tempDir $scriptName

    Write-Host "[*] Downloading $scriptName from GitHub..." -ForegroundColor Cyan
    Invoke-RestMethod -Uri $rawUrl -OutFile $tempScript
    Write-Host "[OK] Saved to $tempScript" -ForegroundColor Green

    # Also download the shared helper (vm-config.ps1) that vm-copy.ps1 dot-sources
    $configUrl    = 'https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-config.ps1'
    $configScript = Join-Path $tempDir 'vm-config.ps1'
    Write-Host "[*] Downloading vm-config.ps1 from GitHub..." -ForegroundColor Cyan
    Invoke-RestMethod -Uri $configUrl -OutFile $configScript
    Write-Host "[OK] Saved to $configScript" -ForegroundColor Green

    # Define a global vm-copy function that invokes the downloaded script,
    # self-elevating to admin if needed.
    $global:_vmCopyScript = $tempScript
    function global:vm-copy {
        $fwdArgs = @()
        foreach ($key in $PSBoundParameters.Keys) {
            $val = $PSBoundParameters[$key]
            if ($val -is [switch]) { if ($val) { $fwdArgs += "-$key" } }
            else { $fwdArgs += "-$key"; $fwdArgs += "$val" }
        }
        # Forward any remaining unbound args
        if ($args) { $fwdArgs += $args }

        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
                   ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($isAdmin) {
            Write-Host "[*] Running vm-copy as Administrator..." -ForegroundColor Cyan
            & $global:_vmCopyScript @fwdArgs
        } else {
            Write-Host "[*] Elevating to Administrator..." -ForegroundColor Yellow
            $psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
            $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $global:_vmCopyScript) + $fwdArgs
            Start-Process $psExe -Verb RunAs -ArgumentList $allArgs -Wait
        }
    }

    Write-Host "[OK] vm-copy function ready. Usage:" -ForegroundColor Green
    Write-Host "  vm-copy -SourceVMName 'vm.01' -VMName 'lab' -Count 5" -ForegroundColor White
    return
}
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Dot-source shared helpers (vm-config.ps1)
# ---------------------------------------------------------------------------
$configHelper = Join-Path $PSScriptRoot 'vm-config.ps1'
if (-not (Test-Path -LiteralPath $configHelper)) {
    throw "Required helper '$configHelper' not found. Ensure vm-config.ps1 is in the same directory."
}
. $configHelper

# ---------------------------------------------------------------------------
# Script-scoped state
# ---------------------------------------------------------------------------
$script:LogEnabled   = [bool]$Log
$script:LogFile      = Join-Path $PSScriptRoot 'vm-copy.jsonl'
$script:CurrentRunId = [guid]::NewGuid().ToString()
$script:RunStamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:CurrentPhase = 'Init'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step  { param([string]$M) Write-Host "[*] $M" -ForegroundColor Cyan;   Write-Log $M 'INFO'  }
function Write-Done  { param([string]$M) Write-Host "[OK] $M" -ForegroundColor Green; Write-Log $M 'SUCCESS' }
function Write-Warn  { param([string]$M) Write-Host "[!] $M" -ForegroundColor Yellow; Write-Log $M 'WARN'  }
function Write-Err   { param([string]$M) Write-Host "[X] $M" -ForegroundColor Red;    Write-Log $M 'ERROR' }
function Set-Phase   { param([string]$Name) $script:CurrentPhase = $Name }

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG','SUCCESS')]
        [string]$Level = 'INFO'
    )
    if (-not $script:LogEnabled) { return }
    $record = [ordered]@{
        timestamp  = (Get-Date).ToString('o')
        level      = $Level
        phase      = $script:CurrentPhase
        message    = $Message
        runId      = $script:CurrentRunId
        runStamp   = $script:RunStamp
        script     = 'vm-copy.ps1'
        computer   = $env:COMPUTERNAME
        user       = $env:USERNAME
        whatIf     = [bool]$WhatIfPreference
    } | ConvertTo-Json -Compress -Depth 4
    # Retry loop to handle transient file-lock / stream errors during rapid logging.
    # Uses FileStream with FileShare.ReadWrite so concurrent processes can coexist.
    $maxRetries = 5
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$record`n")
    for ($r = 1; $r -le $maxRetries; $r++) {
        try {
            $fs = [System.IO.FileStream]::new(
                $script:LogFile,
                [System.IO.FileMode]::Append,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::ReadWrite
            )
            try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
            break
        } catch {
            if ($r -eq $maxRetries) {
                Write-Warning "Write-Log: failed after $maxRetries attempts -- $_"
            } else {
                Start-Sleep -Milliseconds (100 * $r)
            }
        }
    }
}

# ---------------------------------------------------------------------------
# ShowLog mode -- display log entries and exit
# ---------------------------------------------------------------------------
if ($ShowLog) {
    # Validate -Level values (ValidateSet removed from param for PS 5.1 compat)
    $validLevels = @('INFO', 'WARN', 'ERROR', 'DEBUG', 'SUCCESS')
    if ($Level) {
        foreach ($l in $Level) {
            if ($l -notin $validLevels) {
                throw "Invalid -Level value '$l'. Valid values: $($validLevels -join ', ')"
            }
        }
    }

    if (-not (Test-Path -LiteralPath $script:LogFile)) {
        Write-Host "No log file found at: $script:LogFile" -ForegroundColor Yellow
        return
    }

    $entries = Get-Content -LiteralPath $script:LogFile |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { try { $_ | ConvertFrom-Json } catch { } }

    if ($RunId)  { $entries = @($entries | Where-Object { $_.runId -eq $RunId }) }
    if ($Level)  { $entries = @($entries | Where-Object { $_.level -in $Level }) }
    if ($Last -and $Last -gt 0) { $entries = @($entries | Select-Object -Last $Last) }

    if ($entries.Count -eq 0) {
        Write-Host 'No matching log entries found.' -ForegroundColor Yellow
    } else {
        foreach ($e in $entries) {
            $ts    = $e.timestamp
            $lvl   = $e.level.PadRight(7)
            $ph    = ($e.phase + '').PadRight(14)
            $msg   = $e.message
            $color = switch ($e.level) {
                'ERROR'   { 'Red' }
                'WARN'    { 'Yellow' }
                'SUCCESS' { 'Green' }
                'DEBUG'   { 'DarkGray' }
                default   { 'White' }
            }
            Write-Host "$ts  $lvl  $ph  $msg" -ForegroundColor $color
        }
    }
    return
}

# ---------------------------------------------------------------------------
# Build list of destination VM names
# ---------------------------------------------------------------------------
# Helper: find N sequential available <BaseName>.## names
function Get-NextVMNames {
    param(
        [string]$BaseName,
        [int]$Needed
    )
    $existingVMs   = @(Get-VM -ErrorAction SilentlyContinue)
    $usedNames     = @($existingVMs | ForEach-Object { $_.Name })
    $escapedBase   = [regex]::Escape($BaseName)
    $namePattern   = "^${escapedBase}\.(\d+)$"
    $usedNumbers   = @($existingVMs |
        Where-Object { $_.Name -match $namePattern } |
        ForEach-Object { [int]$Matches[1] })
    $next = 1
    if ($usedNumbers.Count -gt 0) {
        $next = ($usedNumbers | Measure-Object -Maximum).Maximum + 1
    }
    $names = [System.Collections.Generic.List[string]]::new()
    while ($names.Count -lt $Needed) {
        $candidate = '{0}.{1}' -f $BaseName, $next.ToString('00')
        if ($candidate -notin $usedNames -and $candidate -notin $names) {
            $names.Add($candidate)
        }
        $next++
    }
    return $names
}

# Derive the base name for destinations:
#   - If -VMName was explicitly provided, use it as the base name.
#   - Otherwise, strip the trailing .## from $SourceVMName (e.g. "vm.01" -> "vm").
if (-not $VMName) {
    if ($SourceVMName -match '^(.+)\.\d+$') {
        $VMName = $Matches[1]
    } else {
        $VMName = $SourceVMName
    }
}

$destNames = @(Get-NextVMNames -BaseName $VMName -Needed $Count)
Write-Host "[*] Auto-assigned $Count destination name(s): $($destNames -join ', ')" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Initialise log file -- purge unless -Append is specified (only when -Log)
# ---------------------------------------------------------------------------
if ($script:LogEnabled) {
    if (-not $Append -and (Test-Path -LiteralPath $script:LogFile)) {
        $purged = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                # Try delete first, fall back to truncate
                Remove-Item -LiteralPath $script:LogFile -Force -WhatIf:$false -ErrorAction Stop
                $purged = $true; break
            } catch {
                try {
                    # Truncate via FileStream with ReadWrite sharing to handle locked files
                    $fs = [System.IO.FileStream]::new(
                        $script:LogFile,
                        [System.IO.FileMode]::Truncate,
                        [System.IO.FileAccess]::Write,
                        [System.IO.FileShare]::ReadWrite
                    )
                    $fs.Dispose()
                    $purged = $true; break
                } catch {
                    Start-Sleep -Milliseconds (200 * $attempt)
                }
            }
        }
        if ($purged) {
            Write-Host "[*] Log file purged (use -Append to preserve)." -ForegroundColor DarkGray
        } else {
            Write-Host "[!] Could not purge log file (locked by another process) -- appending instead." -ForegroundColor Yellow
        }
    }
    if (-not (Test-Path -LiteralPath $script:LogFile)) {
        New-Item -Path $script:LogFile -ItemType File -Force -WhatIf:$false | Out-Null
    }
}

Write-Log 'vm-copy started'
Write-Log "Source: $SourceVMName"
Write-Log "Destinations ($Count): $($destNames -join ', ')"
Write-Log "WhatIf: $([bool]$WhatIfPreference)"

# ---------------------------------------------------------------------------
# Show existing VMs and resolve storage paths
# ---------------------------------------------------------------------------
Show-VMStatus
$storagePaths = Resolve-VMStoragePaths -StoragePath $StoragePath -ResetConfig:$ResetConfig

# Derive ExportPath from configured storage root when not explicitly provided
if (-not $ExportPath) {
    # VMPath is typically <root>\Hyper-V  -- go up one level to get the storage root
    $storageRoot = Split-Path -Path $storagePaths.VMPath -Parent
    $ExportPath  = Join-Path $storageRoot 'VMExports'
    Write-Step "Export path (from config): $ExportPath"
}
Write-Log "ExportPath: $ExportPath"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
Set-Phase 'Pre-flight'
Write-Step "Running pre-flight checks..."

$sourceVM = Get-VM -Name $SourceVMName -ErrorAction SilentlyContinue
if (-not $sourceVM) {
    Write-Err "Source VM '$SourceVMName' not found."
    throw "Source VM '$SourceVMName' does not exist."
}
Write-Done "Source VM '$SourceVMName' found (State: $($sourceVM.State))."

foreach ($name in $destNames) {
    if (Get-VM -Name $name -ErrorAction SilentlyContinue) {
        Write-Err "A VM named '$name' already exists."
        throw "Destination VM '$name' already exists. Choose a different name or remove it first."
    }
    Write-Done "Destination name '$name' is available."
}

# --- Disk space pre-flight check -------------------------------------------
$vmDisks      = @(Get-VMHardDiskDrive -VMName $SourceVMName -ErrorAction SilentlyContinue)
$sourceVHDSize = [long]0
foreach ($disk in $vmDisks) {
    if (Test-Path -LiteralPath $disk.Path) {
        $sourceVHDSize += (Get-Item -LiteralPath $disk.Path).Length
    }
}

if ($sourceVHDSize -gt 0) {
    $sizeGB       = [math]::Round($sourceVHDSize / 1GB, 2)
    Write-Step "Source VM disk size: $sizeGB GB"

    # Space needed: 1 export copy + N import copies
    $resolvedExport = Resolve-Path -Path $ExportPath -ErrorAction SilentlyContinue
    $exportDrive  = if ($resolvedExport) { $resolvedExport.Drive } else {
                        [System.IO.Path]::GetPathRoot($ExportPath).TrimEnd('\')
                    }
    $vhdDrive     = [System.IO.Path]::GetPathRoot($storagePaths.VHDPath).TrimEnd('\')

    # Normalise to drive letters for Get-PSDrive
    $exportDriveLetter = ($exportDrive -replace '[:\\]', '')
    $vhdDriveLetter    = ($vhdDrive    -replace '[:\\]', '')

    $spaceNeeded = @{}   # drive-letter -> bytes needed

    # Export needs 1× source size on the export drive
    if (-not $spaceNeeded.ContainsKey($exportDriveLetter)) { $spaceNeeded[$exportDriveLetter] = [long]0 }
    $spaceNeeded[$exportDriveLetter] += $sourceVHDSize

    # Each import copy needs ~1× source size on the VHD drive
    if (-not $spaceNeeded.ContainsKey($vhdDriveLetter)) { $spaceNeeded[$vhdDriveLetter] = [long]0 }
    $spaceNeeded[$vhdDriveLetter] += $sourceVHDSize * $Count

    $spaceOk = $true
    foreach ($drv in $spaceNeeded.Keys) {
        $psDrive = Get-PSDrive -Name $drv -ErrorAction SilentlyContinue
        if ($psDrive) {
            $freeBytes   = $psDrive.Free
            $freeGB      = [math]::Round($freeBytes / 1GB, 2)
            $neededGB    = [math]::Round($spaceNeeded[$drv] / 1GB, 2)
            # Add 10 % safety margin
            $neededWithMargin = [long]($spaceNeeded[$drv] * 1.10)

            if ($freeBytes -lt $neededWithMargin) {
                Write-Err "Drive ${drv}: needs ~${neededGB} GB (+10 % margin) but only ${freeGB} GB free."
                $spaceOk = $false
            } else {
                Write-Done "Drive ${drv}: ${freeGB} GB free, ~${neededGB} GB needed."
            }
        } else {
            Write-Warn "Could not query free space on drive '$drv' -- skipping check."
        }
    }

    if (-not $spaceOk) {
        throw "Insufficient disk space. Free up space or reduce -Count (currently $Count)."
    }
} else {
    Write-Warn "Could not determine source VM disk size -- skipping space check."
}

$wasRunning = $sourceVM.State -eq 'Running'

# ---------------------------------------------------------------------------
# Stop source VM (if running)
# ---------------------------------------------------------------------------
Set-Phase 'Stop source VM'
if ($wasRunning) {
    Write-Step "Stopping source VM '$SourceVMName'..."
    if ($PSCmdlet.ShouldProcess($SourceVMName, 'Stop VM')) {
        Stop-VM -Name $SourceVMName -Force
        Write-Done "VM stopped."
    }
} else {
    Write-Step "Source VM is already stopped -- skipping."
}

# ---------------------------------------------------------------------------
# Export (once -- reused for all copies)
# ---------------------------------------------------------------------------
Set-Phase 'Export'
$exportDest = Join-Path $ExportPath $SourceVMName
Write-Step "Exporting '$SourceVMName' to '$ExportPath'..."

if ($PSCmdlet.ShouldProcess($SourceVMName, "Export VM to $ExportPath")) {
    if (-not (Test-Path -LiteralPath $ExportPath)) {
        New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
    }
    # Remove stale export if present
    if (Test-Path -LiteralPath $exportDest) {
        Remove-Item -LiteralPath $exportDest -Recurse -Force
    }
    Export-VM -Name $SourceVMName -Path $ExportPath
    Write-Done "Export complete."
}

# Locate the .vmcx file inside the export (once, before the loop)
$vmcxSearch = Join-Path (Join-Path $exportDest 'Virtual Machines') '*.vmcx'
$vmcxFiles  = @(Get-Item -Path $vmcxSearch -ErrorAction SilentlyContinue)
$vmcxPath   = $null
if ($vmcxFiles.Count -eq 0) {
    if (-not $WhatIfPreference) {
        Write-Err "No .vmcx file found in '$vmcxSearch'."
        throw "Export appears incomplete -- no .vmcx file found."
    }
} else {
    $vmcxPath = $vmcxFiles[0].FullName
    Write-Log "vmcx path: $vmcxPath" 'DEBUG'
}

# Resolve VM storage paths (from persistent config or user prompt)
$defaultVMPath  = $storagePaths.VMPath
$defaultVHDPath = $storagePaths.VHDPath

# ---------------------------------------------------------------------------
# Import / checkpoint / rename loop -- one iteration per copy
# ---------------------------------------------------------------------------
$createdVMs = [System.Collections.Generic.List[string]]::new()

for ($i = 0; $i -lt $destNames.Count; $i++) {
    $currentDest = $destNames[$i]
    $copyLabel   = if ($destNames.Count -gt 1) { " [$($i+1)/$($destNames.Count)]" } else { '' }

    # --- Import --------------------------------------------------------
    Set-Phase 'Import'
    Write-Step "Importing copy as '$currentDest'...$copyLabel"

    $destVMPath   = Join-Path $defaultVMPath  $currentDest
    $destVHDPath  = Join-Path $defaultVHDPath $currentDest
    $destSnapPath = Join-Path $destVMPath 'Snapshots'

    Write-Log "Destination VM path  : $destVMPath" 'DEBUG'
    Write-Log "Destination VHD path : $destVHDPath" 'DEBUG'
    Write-Log "Destination snap path: $destSnapPath" 'DEBUG'

    # Remove leftover destination directories from a previous failed run
    foreach ($staleDir in @($destVMPath, $destVHDPath)) {
        if (Test-Path -LiteralPath $staleDir) {
            Write-Log "Removing stale directory: $staleDir" 'WARN'
            Write-Host "  [!] Removing leftover directory: $staleDir" -ForegroundColor Yellow
            Remove-Item -LiteralPath $staleDir -Recurse -Force
        }
    }

    if (-not $vmcxPath) {
        # WhatIf mode -- no export was created
        Write-Host "What if: Performing the operation ""Import VM"" on target ""$currentDest""."
    } elseif ($PSCmdlet.ShouldProcess($currentDest, "Import VM from $vmcxPath")) {
        $imported = Import-VM -Path $vmcxPath `
                              -Copy `
                              -GenerateNewId `
                              -VirtualMachinePath $destVMPath `
                              -VhdDestinationPath $destVHDPath `
                              -SnapshotFilePath   $destSnapPath

        if ($imported.Name -ne $currentDest) {
            Rename-VM -VM $imported -NewName $currentDest
        }
        Write-Done "VM '$currentDest' imported (ID: $($imported.Id))."
    }

    # --- Checkpoints ---------------------------------------------------
    Set-Phase 'Checkpoints'
    $destVM = Get-VM -Name $currentDest -ErrorAction SilentlyContinue
    if ($destVM) {
        $checkpoints = @(Get-VMSnapshot -VMName $currentDest -ErrorAction SilentlyContinue)
        if ($checkpoints.Count -gt 0) {
            Write-Step "Removing $($checkpoints.Count) checkpoint(s) from '$currentDest' (merging disks)...$copyLabel"
            if ($PSCmdlet.ShouldProcess($currentDest, "Remove $($checkpoints.Count) checkpoint(s)")) {
                Remove-VMSnapshot -VMName $currentDest -IncludeAllChildSnapshots
                Write-Done "Checkpoints removed."

                Write-Step "Waiting for disk merge to complete..."
                $timeout  = 300
                $elapsed  = 0
                $interval = 5
                do {
                    Start-Sleep -Seconds $interval
                    $elapsed += $interval
                    $currentDrives = @(Get-VMHardDiskDrive -VMName $currentDest)
                    $avhdxRemaining = @($currentDrives | Where-Object {
                        $_.Path -match '\.avhdx$'
                    })
                    if ($avhdxRemaining.Count -eq 0) { break }
                    Write-Log "Merge in progress ($elapsed s) -- $($avhdxRemaining.Count) AVHDX file(s) remaining" 'DEBUG'
                } while ($elapsed -lt $timeout)

                if ($avhdxRemaining.Count -gt 0) {
                    Write-Warn "Disk merge did not complete within $timeout seconds. AVHDX files may still be merging in the background."
                } else {
                    Write-Done "Disk merge complete."
                }
            }
        } else {
            Write-Step "No checkpoints found on '$currentDest' -- skipping merge."
        }

        # --- Rename disks ----------------------------------------------
        Set-Phase 'Rename disks'
        $drives = @(Get-VMHardDiskDrive -VMName $currentDest)
        $srcPattern = [regex]::Escape($SourceVMName)
        foreach ($drive in $drives) {
            $oldPath = $drive.Path
            $oldFile = [System.IO.Path]::GetFileName($oldPath)
            $newFile = $oldFile -replace $srcPattern, $currentDest
            if ($newFile -ne $oldFile) {
                $newPath = Join-Path ([System.IO.Path]::GetDirectoryName($oldPath)) $newFile
                Write-Step "Renaming disk: $oldFile -> $newFile"
                if ($PSCmdlet.ShouldProcess($oldPath, "Rename to $newFile")) {
                    Rename-Item -LiteralPath $oldPath -NewName $newFile
                    Set-VMHardDiskDrive -VMHardDiskDrive $drive -Path $newPath
                    Write-Done "Disk renamed."
                }
            }
        }
    }

    $createdVMs.Add($currentDest)
    Write-Log "Copy $($i+1)/$($destNames.Count) complete: $currentDest" 'SUCCESS'
}

# ---------------------------------------------------------------------------
# Restart source VM (if it was running)
# ---------------------------------------------------------------------------
Set-Phase 'Restart source'
if ($wasRunning) {
    Write-Step "Restarting source VM '$SourceVMName'..."
    if ($PSCmdlet.ShouldProcess($SourceVMName, 'Start VM')) {
        Start-VM -Name $SourceVMName
        Write-Done "Source VM restarted."
    }
}

# ---------------------------------------------------------------------------
# Cleanup export folder
# ---------------------------------------------------------------------------
Set-Phase 'Cleanup'
if (-not $KeepExport -and (Test-Path -LiteralPath $exportDest)) {
    Write-Step "Cleaning up export folder '$exportDest'..."
    if ($PSCmdlet.ShouldProcess($exportDest, 'Remove export folder')) {
        Remove-Item -LiteralPath $exportDest -Recurse -Force
        Write-Done "Export folder removed."
    }
} elseif ($KeepExport) {
    Write-Step "Keeping export folder at '$exportDest' (-KeepExport)."
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Set-Phase 'Complete'
Write-Log 'vm-copy finished' 'SUCCESS'

Write-Host ''
Write-Host ('=' * 60) -ForegroundColor Green
if ($createdVMs.Count -eq 1) {
    Write-Host "  VM '$($createdVMs[0])' cloned from '$SourceVMName'." -ForegroundColor Green
} else {
    Write-Host "  $($createdVMs.Count) VMs cloned from '$SourceVMName':" -ForegroundColor Green
    foreach ($vm in $createdVMs) {
        Write-Host "    - $vm" -ForegroundColor Green
    }
}
Write-Host ('=' * 60) -ForegroundColor Green
Write-Host ''
Write-Host "Start the clone(s):"
foreach ($vm in $createdVMs) {
    Write-Host "  Start-VM -Name '$vm'"
}
Write-Host ''
if ($script:LogEnabled) {
    Write-Host "View log:"
    Write-Host "  .\vm-copy.ps1 -ShowLog -Last 20"
    Write-Host "  .\vm-copy.ps1 -ShowLog -Last 10 -Level ERROR"
} else {
    Write-Host "Enable JSONL logging with -Log:"
    Write-Host "  .\vm-copy.ps1 -SourceVMName '$SourceVMName' -VMName '$VMName' -Count $Count -Log"
}
Write-Host ''
