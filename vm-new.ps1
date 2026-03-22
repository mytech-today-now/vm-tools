<#
.SYNOPSIS
    Creates a Hyper-V Generation 2 VM ready for Windows installation.

.DESCRIPTION
    Provisions a Generation 2 Hyper-V VM with a dynamic VHDX, configures
    networking (Default Switch for host + internet access), enables TPM 2.0
    and Secure Boot, and optionally attaches a Windows ISO as the first boot
    device.

    The VM name is auto-generated as <VMName>.## (e.g. vm.01, vm.02) by
    querying existing Hyper-V VMs.  All hardware settings (CPU, RAM, disk
    size) can be customised via parameters.

    Supports -WhatIf / -Confirm for safe dry-runs and -Verbose for extra
    detail.

    Run 'Get-Help .\vm-new.ps1 -Full' or '.\vm-new.ps1 -?' for full help.

.PARAMETER VMName
    Base name of the virtual machine.  The script appends a sequential
    number as <VMName>.## (e.g. vm.01, vm.02).  Default: "vm"

.PARAMETER VhdxSizeGB
    Size of the dynamic VHDX in GB.  Default: 60

.PARAMETER MemoryGB
    Startup RAM in GB (dynamic memory enabled).  Default: 8

.PARAMETER Processors
    Number of virtual CPUs.  Default: 2

.PARAMETER IsoPath
    Path to a Windows ISO.  The ISO is mounted as a DVD drive and set as
    the first boot device.  Default: F:\_downloads\Win11_25H2_English_x64.iso

.PARAMETER SwitchName
    Name of the Hyper-V virtual switch to use.  Default: "Default Switch"
    (the built-in NAT switch that provides host and internet connectivity).

.PARAMETER StoragePath
    Root path for VM storage.  VM config and VHD sub-directories are created
    beneath this path.  Saved to a persistent config file
    (~\.vm-tools\config.json) and reused on subsequent runs.
    Default: Hyper-V host defaults (typically C:\).

.PARAMETER ResetConfig
    Ignore the saved storage-path config and prompt interactively for a new
    location.  The new choice is saved for future runs.

.PARAMETER Log
    Enable JSONL logging to vm-new.jsonl in the script directory.  Without
    this switch no log file is created or written.

.EXAMPLE
    .\vm-new.ps1
    Creates "vm.01" (or next available) with all defaults.

.EXAMPLE
    .\vm-new.ps1 -VMName "lab"
    Creates "lab.01" (or next available lab.## name).

.EXAMPLE
    .\vm-new.ps1 -VMName "dev" -MemoryGB 16 -Processors 4 -VhdxSizeGB 120
    Creates "dev.01" with 16 GB RAM, 4 vCPUs, and a 120 GB disk.

.EXAMPLE
    .\vm-new.ps1 -IsoPath "D:\ISOs\Win11.iso"
    Creates a VM and mounts the specified Windows ISO as the boot device.

.EXAMPLE
    .\vm-new.ps1 -StoragePath "D:\VMs"
    Creates a VM and stores it under D:\VMs\Hyper-V (saves path for reuse).

.EXAMPLE
    .\vm-new.ps1 -ResetConfig
    Prompts for a new storage location, ignoring any previously saved path.

.EXAMPLE
    .\vm-new.ps1 -WhatIf
    Dry-run -- shows what would happen without making any changes.

.EXAMPLE
    .\vm-new.ps1 -Log
    Creates a VM with JSONL logging enabled (writes to vm-new.jsonl).

.EXAMPLE
    .\vm-new.ps1 -VMName "test" -Log -SwitchName "External Switch"
    Creates "test.01" on a custom switch with logging enabled.

.EXAMPLE
    irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-new.ps1 | iex; vm-new
    Downloads from GitHub and creates a VM with defaults (auto-elevates).

.EXAMPLE
    irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-new.ps1 | iex; vm-new -VMName "lab" -MemoryGB 16
    Downloads from GitHub and creates "lab.01" with 16 GB RAM.

.EXAMPLE
    irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-new.ps1 | iex; vm-new -Log
    Downloads from GitHub and creates a VM with JSONL logging enabled.

.EXAMPLE
    $h = @{ Authorization = "token $env:GITHUB_TOKEN"; Accept = 'application/vnd.github.v3.raw' }
    irm https://api.github.com/repos/mytech-today-now/vm-tools/contents/vm-new.ps1 -Headers $h | iex; vm-new -VMName "dev"
    Downloads from a PRIVATE GitHub repo and creates "dev.01".

.NOTES
    Author : myTech.Today
    Version: 1.2.0
    Requires: Hyper-V module, Administrator privileges
    Log file: <ScriptDir>\vm-new.jsonl (when -Log is used)
    Help    : Get-Help .\vm-new.ps1 -Full
              .\vm-new.ps1 -?

    Remote execution (irm | iex):
      The script auto-downloads itself and vm-config.ps1 to a temp folder,
      defines a global 'vm-new' function, and re-launches as a proper .ps1
      so that parameters, -WhatIf, -Confirm, and admin elevation all work.

      Public repo:
        irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-new.ps1 | iex
      Private repo:
        $env:GITHUB_TOKEN = 'ghp_YourPersonalAccessToken'
        $h = @{ Authorization = "token $env:GITHUB_TOKEN"; Accept = 'application/vnd.github.v3.raw' }
        irm https://api.github.com/repos/mytech-today-now/vm-tools/contents/vm-new.ps1 -Headers $h | iex

    Changelog v1.2.0:
    - Added -Log switch for opt-in JSONL logging

    Changelog v1.1.0:
    - Added persistent VM storage path selection (prompted on first run)
    - Added -StoragePath and -ResetConfig parameters
    - Shows existing Hyper-V VM status table before creation
    - Dot-sources shared vm-config.ps1 helper
#>

#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$VMName       = 'vm',
    [int]   $VhdxSizeGB   = 60,
    [int]   $MemoryGB     = 8,
    [int]   $Processors   = 2,
    [string]$IsoPath      = 'F:\_downloads\Win11_25H2_English_x64.iso',
    [string]$SwitchName   = 'Default Switch',
    [string]$StoragePath,
    [switch]$ResetConfig,
    [switch]$Log
)

# ---------------------------------------------------------------------------
# Remote-execution bootstrap
# ---------------------------------------------------------------------------
# When run via `irm <url> | iex`, $MyInvocation.MyCommand.Path is empty
# because there is no script file on disk.  In that case we download the
# script to a temp folder and re-launch it as a proper .ps1 so that all
# PowerShell features (#Requires, CmdletBinding, -WhatIf, -Confirm, params,
# $PSScriptRoot) work correctly.  The block also self-elevates to admin.
if (-not $MyInvocation.MyCommand.Path) {
    $scriptName = 'vm-new.ps1'
    $rawUrl     = 'https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-new.ps1'
    $tempDir    = Join-Path $env:TEMP 'vm-tools'
    if (-not (Test-Path $tempDir)) { New-Item -Path $tempDir -ItemType Directory -Force | Out-Null }
    $tempScript = Join-Path $tempDir $scriptName

    Write-Host "[*] Downloading $scriptName from GitHub..." -ForegroundColor Cyan
    Invoke-RestMethod -Uri $rawUrl -OutFile $tempScript
    Write-Host "[OK] Saved to $tempScript" -ForegroundColor Green

    # Also download the shared helper (vm-config.ps1) that vm-new.ps1 dot-sources
    $configUrl    = 'https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-config.ps1'
    $configScript = Join-Path $tempDir 'vm-config.ps1'
    Write-Host "[*] Downloading vm-config.ps1 from GitHub..." -ForegroundColor Cyan
    Invoke-RestMethod -Uri $configUrl -OutFile $configScript
    Write-Host "[OK] Saved to $configScript" -ForegroundColor Green

    # Define a global vm-new function that invokes the downloaded script,
    # self-elevating to admin if needed.
    $global:_vmNewScript = $tempScript
    function global:vm-new {
        $fwdArgs = @()
        foreach ($key in $PSBoundParameters.Keys) {
            $val = $PSBoundParameters[$key]
            if ($val -is [switch]) { if ($val) { $fwdArgs += "-$key" } }
            else { $fwdArgs += "-$key"; $fwdArgs += "$val" }
        }
        if ($args) { $fwdArgs += $args }

        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
                   ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($isAdmin) {
            Write-Host "[*] Running vm-new as Administrator..." -ForegroundColor Cyan
            & $global:_vmNewScript @fwdArgs
        } else {
            Write-Host "[*] Elevating to Administrator..." -ForegroundColor Yellow
            $psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
            $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $global:_vmNewScript) + $fwdArgs
            Start-Process $psExe -Verb RunAs -ArgumentList $allArgs -Wait
        }
    }

    Write-Host "[OK] vm-new function ready. Usage:" -ForegroundColor Green
    Write-Host "  vm-new -VMName 'lab' -Count 5" -ForegroundColor White
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
$script:LogFile      = Join-Path $PSScriptRoot 'vm-new.jsonl'
$script:CurrentRunId = [guid]::NewGuid().ToString()
$script:RunStamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:CurrentPhase = 'Init'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step { param([string]$M) Write-Host "[*] $M" -ForegroundColor Cyan;   Write-Log $M 'INFO'  }
function Write-Done { param([string]$M) Write-Host "[OK] $M" -ForegroundColor Green; Write-Log $M 'SUCCESS' }
function Write-Warn { param([string]$M) Write-Host "[!] $M" -ForegroundColor Yellow; Write-Log $M 'WARN'  }
function Write-Err  { param([string]$M) Write-Host "[X] $M" -ForegroundColor Red;    Write-Log $M 'ERROR' }
function Set-Phase  { param([string]$Name) $script:CurrentPhase = $Name }

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
        script     = 'vm-new.ps1'
        computer   = $env:COMPUTERNAME
        user       = $env:USERNAME
        whatIf     = [bool]$WhatIfPreference
    } | ConvertTo-Json -Compress -Depth 4
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
# Initialise log file (only when -Log)
# ---------------------------------------------------------------------------
if ($script:LogEnabled) {
    if (-not (Test-Path -LiteralPath $script:LogFile)) {
        New-Item -Path $script:LogFile -ItemType File -Force -WhatIf:$false | Out-Null
    }
}

Write-Log 'vm-new started'
Write-Log "VMName base: $VMName"
Write-Log "WhatIf: $([bool]$WhatIfPreference)"

# ---------------------------------------------------------------------------
# Show existing VMs and resolve storage paths
# ---------------------------------------------------------------------------
Show-VMStatus
$storagePaths = Resolve-VMStoragePaths -StoragePath $StoragePath -ResetConfig:$ResetConfig

# ---------------------------------------------------------------------------
# Auto-generate sequential VM name: <VMName>.##
# ---------------------------------------------------------------------------
Set-Phase 'Name assignment'
Write-Step "Determining next available name for '$VMName'..."
$existingVMs   = @(Get-VM -ErrorAction SilentlyContinue)
$escapedBase   = [regex]::Escape($VMName)
$namePattern   = "^${escapedBase}\.(\d+)$"

# Extract numbers from existing <VMName>.## names
$usedNumbers = @($existingVMs |
    Where-Object { $_.Name -match $namePattern } |
    ForEach-Object { [int]$Matches[1] })

# Find the next available number (start at 1)
$nextNumber = 1
if ($usedNumbers.Count -gt 0) {
    $nextNumber = ($usedNumbers | Measure-Object -Maximum).Maximum + 1
}

$VMName = '{0}.{1:D2}' -f $VMName, $nextNumber
Write-Done "Auto-assigned VM name: $VMName"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
Set-Phase 'Pre-flight'
Write-Step "Running pre-flight checks..."

# If a VM with this name already exists, prompt the user to confirm removal
$existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existingVM) {
    Write-Warn "A VM named '$VMName' already exists (State: $($existingVM.State))."
    $confirm = Read-Host "Do you want to remove the existing VM '$VMName' and recreate it? (Y/N)"
    if ($confirm -notin @('Y', 'y', 'Yes', 'yes')) {
        Write-Host "Aborted by user." -ForegroundColor Red
        exit 1
    }

    Write-Step "Removing existing VM '$VMName'..."
    if ($existingVM.State -eq 'Running' -or $existingVM.State -eq 'Paused') {
        Stop-VM -Name $VMName -Force -TurnOff
    }

    # Collect VHD paths before removing the VM
    $oldVhds = @(Get-VMHardDiskDrive -VMName $VMName |
        Select-Object -ExpandProperty Path)

    Remove-VM -Name $VMName -Force

    # Remove associated VHDX files
    foreach ($vhd in $oldVhds) {
        if (Test-Path -LiteralPath $vhd) {
            Remove-Item -LiteralPath $vhd -Force
            Write-Done "Removed VHDX: $vhd"
        }
    }

    Write-Done "Existing VM '$VMName' removed."
}

# Validate ISO path if supplied
if ($IsoPath -and -not (Test-Path -LiteralPath $IsoPath)) {
    throw "ISO path not found: $IsoPath"
}

# ---------------------------------------------------------------------------
# Resolve VM storage paths (from persistent config or user prompt)
# ---------------------------------------------------------------------------
$vmBasePath  = $storagePaths.VMPath
$vhdBasePath = $storagePaths.VHDPath

Write-Step "Using storage paths:"
Write-Host "  VM config path : $vmBasePath"
Write-Host "  VHD path       : $vhdBasePath"

$vhdxPath = Join-Path $vhdBasePath "$VMName.vhdx"

# Guard against overwriting an existing VHDX (may remain from a prior removal)
if (Test-Path -LiteralPath $vhdxPath) {
    Write-Warn "VHDX already exists at '$vhdxPath'. Removing stale file..."
    Remove-Item -LiteralPath $vhdxPath -Force
    Write-Done "Stale VHDX removed."
}

# ---------------------------------------------------------------------------
# Networking -- ensure the requested virtual switch is available
# ---------------------------------------------------------------------------
Set-Phase 'Networking'
Write-Step "Checking virtual switch '$SwitchName'..."

$existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue

if (-not $existingSwitch) {
    # "Default Switch" is created automatically by Hyper-V on Windows 10/11.
    # If it is missing (or the user asked for a different name) try to create
    # an Internal switch so the VM can at least talk to the host.  A full
    # External switch requires choosing a physical NIC, which we leave to
    # the user.
    Write-Warn "Switch '$SwitchName' not found."

    if ($SwitchName -eq 'Default Switch') {
        throw ("The built-in 'Default Switch' is missing. " +
               "Re-enable Hyper-V or specify -SwitchName with an existing switch name. " +
               "Run 'Get-VMSwitch' to list available switches.")
    }

    Write-Step "Creating internal virtual switch '$SwitchName'..."
    if ($PSCmdlet.ShouldProcess($SwitchName, 'Create internal virtual switch')) {
        New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
        Write-Done "Internal switch '$SwitchName' created."
        Write-Warn "An Internal switch allows host<->VM traffic only. For internet access, configure NAT or use 'Default Switch'."
    }
}
else {
    Write-Done "Switch '$SwitchName' found (Type: $($existingSwitch.SwitchType))."
}

# ---------------------------------------------------------------------------
# Create VHDX
# ---------------------------------------------------------------------------
Set-Phase 'Create VHDX'
$vhdxSizeBytes = [int64]$VhdxSizeGB * 1GB
Write-Step "Creating $VhdxSizeGB GB dynamic VHDX at '$vhdxPath'..."
if ($PSCmdlet.ShouldProcess($vhdxPath, 'Create dynamic VHDX')) {
    New-VHD -Path $vhdxPath -SizeBytes $vhdxSizeBytes -Dynamic | Out-Null
    Write-Done "VHDX created."
}

# ---------------------------------------------------------------------------
# Create Generation 2 VM
# ---------------------------------------------------------------------------
Set-Phase 'Create VM'
$memoryBytes = [int64]$MemoryGB * 1GB
Write-Step "Creating Generation 2 VM '$VMName'..."
if ($PSCmdlet.ShouldProcess($VMName, 'Create Generation 2 VM')) {
    New-VM -Name $VMName `
           -Path $vmBasePath `
           -MemoryStartupBytes $memoryBytes `
           -Generation 2 `
           -SwitchName $SwitchName `
           -NoVHD | Out-Null
    Write-Done "VM created."
}

# ---------------------------------------------------------------------------
# Configure VM hardware
# ---------------------------------------------------------------------------
Set-Phase 'Configure hardware'
Write-Step "Configuring VM hardware..."
if ($PSCmdlet.ShouldProcess($VMName, 'Set VM processor, memory, and security')) {
    # Processors
    Set-VMProcessor -VMName $VMName -Count $Processors

    # Dynamic memory (min 1 GB, max = startup, to keep behaviour predictable)
    Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true `
        -MinimumBytes 1GB -MaximumBytes $memoryBytes -StartupBytes $memoryBytes

    # Attach VHDX
    Add-VMHardDiskDrive -VMName $VMName -Path $vhdxPath

    # TPM 2.0 (required for Windows 11)
    Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector
    Enable-VMTPM -VMName $VMName

    # Enable guest services for file copy / integration
    Enable-VMIntegrationService -VMName $VMName -Name 'Guest Service Interface'

    # Secure Boot -- use the Windows template for Windows ISOs
    Set-VMFirmware -VMName $VMName -SecureBootTemplate 'MicrosoftWindows'

    Write-Done "Hardware configured: $Processors vCPUs, $MemoryGB GB RAM, TPM 2.0, Secure Boot."
}

# ---------------------------------------------------------------------------
# Attach ISO and set boot order (optional)
# ---------------------------------------------------------------------------
Set-Phase 'Attach ISO'
if ($IsoPath) {
    Write-Step "Attaching ISO '$IsoPath'..."
    if ($PSCmdlet.ShouldProcess($VMName, "Attach ISO $IsoPath")) {
        Add-VMDvdDrive -VMName $VMName -Path $IsoPath

        # Set boot order: DVD first, then HDD -- exclude network adapter to
        # prevent the VM from wasting time on "Start PXE over IPv4".
        $dvdDrive = Get-VMDvdDrive -VMName $VMName | Select-Object -First 1
        $hddDrive = Get-VMHardDiskDrive -VMName $VMName | Select-Object -First 1
        Set-VMFirmware -VMName $VMName -BootOrder $dvdDrive, $hddDrive

        Write-Done "ISO attached. Boot order: DVD > HDD (PXE/network boot removed)."
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Set-Phase 'Complete'
Write-Log 'vm-new finished' 'SUCCESS'
Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host "  VM '$VMName' is ready." -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Generation  : 2"
Write-Host "  Processors  : $Processors vCPUs"
Write-Host "  Memory      : $MemoryGB GB (dynamic)"
Write-Host "  Disk        : $vhdxPath ($VhdxSizeGB GB dynamic)"
Write-Host "  Network     : $SwitchName"
Write-Host "  TPM 2.0     : Enabled"
Write-Host "  Secure Boot : MicrosoftWindows"
if ($IsoPath) {
    Write-Host "  ISO         : $IsoPath (first boot device)"
}
Write-Host ""

if (-not $IsoPath) {
    Write-Warn "No ISO attached. Attach one before starting the VM:"
    Write-Host "  Add-VMDvdDrive -VMName '$VMName' -Path 'C:\Path\To\Windows11.iso'"
    Write-Host "  `$dvd = Get-VMDvdDrive -VMName '$VMName'"
    Write-Host "  Set-VMFirmware -VMName '$VMName' -FirstBootDevice `$dvd"
    Write-Host ""
}

Write-Host "Start the VM:"
Write-Host "  Start-VM -Name '$VMName'"
Write-Host "  vmconnect.exe localhost '$VMName'"
Write-Host ""
if ($script:LogEnabled) {
    Write-Host "View log:"
    Write-Host "  Get-Content '$($script:LogFile)' | ConvertFrom-Json"
} else {
    Write-Host "Enable JSONL logging with -Log:"
    Write-Host "  .\vm-new.ps1 -VMName '$VMName' -Log"
}
Write-Host ""