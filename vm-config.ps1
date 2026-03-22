<#
.SYNOPSIS
    Shared helpers for vm-tools: persistent storage-path config and VM status display.

.DESCRIPTION
    Dot-source this file from vm-new.ps1 and vm-copy.ps1 to get:
      - Get-VMToolsConfig / Save-VMToolsConfig  -- read/write persistent JSON config
      - Resolve-VMStoragePaths  -- prompt user for VM/VHD paths (or use saved values)
      - Show-VMStatus           -- display current Hyper-V VMs (replaces vm-admin.ps1)

    Config file: $env:USERPROFILE\.vm-tools\config.json

.NOTES
    Author : myTech.Today
    Version: 1.0.0
#>

# ---------------------------------------------------------------------------
# Config file location
# ---------------------------------------------------------------------------
$script:VMToolsConfigDir  = Join-Path $env:USERPROFILE '.vm-tools'
$script:VMToolsConfigFile = Join-Path $script:VMToolsConfigDir 'config.json'

# ---------------------------------------------------------------------------
# Get-VMToolsConfig -- read persistent config (returns hashtable)
# ---------------------------------------------------------------------------
function Get-VMToolsConfig {
    if (Test-Path -LiteralPath $script:VMToolsConfigFile) {
        try {
            $json = Get-Content -LiteralPath $script:VMToolsConfigFile -Raw | ConvertFrom-Json
            $ht = @{}
            foreach ($prop in $json.PSObject.Properties) { $ht[$prop.Name] = $prop.Value }
            return $ht
        } catch {
            Write-Warning "Could not read config file '$($script:VMToolsConfigFile)': $_"
        }
    }
    return @{}
}

# ---------------------------------------------------------------------------
# Save-VMToolsConfig -- write persistent config
# ---------------------------------------------------------------------------
function Save-VMToolsConfig {
    param([hashtable]$Config)
    if (-not (Test-Path -LiteralPath $script:VMToolsConfigDir)) {
        New-Item -Path $script:VMToolsConfigDir -ItemType Directory -Force | Out-Null
    }
    $Config['LastUpdated'] = (Get-Date -Format 'o')
    $Config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:VMToolsConfigFile -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Resolve-VMStoragePaths -- returns @{ VMPath; VHDPath } from config, param,
#   or interactive prompt.  Saves choice to config for next run.
#
#   -StoragePath <path>   : override root; VM/VHD sub-dirs placed under it
#   -ResetConfig          : ignore saved config and prompt again
# ---------------------------------------------------------------------------
function Resolve-VMStoragePaths {
    param(
        [string]$StoragePath,
        [switch]$ResetConfig
    )

    $vmHost      = Get-VMHost
    $defaultVM   = $vmHost.VirtualMachinePath
    $defaultVHD  = $vmHost.VirtualHardDiskPath

    # --- If explicit -StoragePath, derive both paths from it ---------------
    if ($StoragePath) {
        $vmPath  = Join-Path $StoragePath 'Hyper-V'
        $vhdPath = Join-Path $StoragePath 'Hyper-V\Virtual Hard Disks'
        $cfg = Get-VMToolsConfig
        $cfg['VMPath']  = $vmPath
        $cfg['VHDPath'] = $vhdPath
        Save-VMToolsConfig $cfg
        Write-Host "[OK] Storage paths set from -StoragePath:" -ForegroundColor Green
        Write-Host "     VM config : $vmPath"
        Write-Host "     VHD files : $vhdPath"
        return @{ VMPath = $vmPath; VHDPath = $vhdPath }
    }

    # --- Check saved config ------------------------------------------------
    if (-not $ResetConfig) {
        $cfg = Get-VMToolsConfig
        if ($cfg['VMPath'] -and $cfg['VHDPath']) {
            Write-Host "[*] Using saved storage paths:" -ForegroundColor Cyan
            Write-Host "    VM config : $($cfg['VMPath'])"
            Write-Host "    VHD files : $($cfg['VHDPath'])"
            $change = Read-Host "    Press ENTER to keep, or type a new root path"
            if ([string]::IsNullOrWhiteSpace($change)) {
                return @{ VMPath = $cfg['VMPath']; VHDPath = $cfg['VHDPath'] }
            }
            # User typed a new path -- treat like -StoragePath
            $vmPath  = Join-Path $change 'Hyper-V'
            $vhdPath = Join-Path $change 'Hyper-V\Virtual Hard Disks'
            $cfg['VMPath']  = $vmPath
            $cfg['VHDPath'] = $vhdPath
            Save-VMToolsConfig $cfg
            Write-Host "[OK] Storage paths updated." -ForegroundColor Green
            Write-Host "     VM config : $vmPath"
            Write-Host "     VHD files : $vhdPath"
            return @{ VMPath = $vmPath; VHDPath = $vhdPath }
        }
    }

    # --- First run or -ResetConfig: prompt ---------------------------------
    Write-Host ""
    Write-Host "[*] VM Storage Location" -ForegroundColor Cyan
    Write-Host "    Current Hyper-V defaults:" -ForegroundColor Gray
    Write-Host "      VM config : $defaultVM"
    Write-Host "      VHD files : $defaultVHD"
    Write-Host ""
    $input_path = Read-Host "    Enter a root path for VM storage (or press ENTER for defaults)"

    if ([string]::IsNullOrWhiteSpace($input_path)) {
        $vmPath  = $defaultVM
        $vhdPath = $defaultVHD
    } else {
        $vmPath  = Join-Path $input_path 'Hyper-V'
        $vhdPath = Join-Path $input_path 'Hyper-V\Virtual Hard Disks'
    }

    $cfg = Get-VMToolsConfig
    $cfg['VMPath']  = $vmPath
    $cfg['VHDPath'] = $vhdPath
    Save-VMToolsConfig $cfg
    Write-Host "[OK] Storage paths saved for future runs." -ForegroundColor Green
    Write-Host "     VM config : $vmPath"
    Write-Host "     VHD files : $vhdPath"
    return @{ VMPath = $vmPath; VHDPath = $vhdPath }
}

# ---------------------------------------------------------------------------
# Show-VMStatus -- display all Hyper-V VMs in a table (replaces vm-admin.ps1)
# ---------------------------------------------------------------------------
function Show-VMStatus {
    $vms = @(Get-VM -ErrorAction SilentlyContinue)
    if ($vms.Count -eq 0) {
        Write-Host "[*] No Hyper-V VMs found on this host." -ForegroundColor Yellow
        return
    }
    Write-Host ""
    Write-Host "[*] Current Hyper-V VMs ($($vms.Count)):" -ForegroundColor Cyan
    $vms | Sort-Object Name |
        Format-Table -AutoSize @(
            @{L='Name';       E={$_.Name}},
            @{L='State';      E={$_.State}},
            @{L='CPUs';       E={$_.ProcessorCount}},
            @{L='Memory(MB)'; E={[math]::Round($_.MemoryAssigned/1MB)}},
            @{L='Uptime';     E={if($_.Uptime.TotalSeconds -gt 0){$_.Uptime.ToString('hh\:mm\:ss')}else{'-'}}}
        ) | Out-Host
}

