# vm-tools

Hyper-V virtual machine provisioning and cloning tools for Windows.

**Version:** 1.4.0 · **License:** MIT · **Author:** [myTech.Today](https://github.com/mytech-today-now)

## Quick Start

### Run directly from GitHub (no clone required)

```powershell
# Set execution policy (one-time)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted
```

```powershell
# Create a new VM with defaults (vm.01)
irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-new.ps1 | iex; vm-new

# Create a VM named "dev.01" with 16 GB RAM
irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-new.ps1 | iex; vm-new -VMName "dev" -MemoryGB 16

# Clone vm.01 into 5 copies named lab.01–lab.05
irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-copy.ps1 | iex; vm-copy -SourceVMName "vm.01" -VMName "lab" -Count 5

# Clone with JSONL logging enabled
irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-copy.ps1 | iex; vm-copy -SourceVMName "vm.01" -Log
```

The scripts auto-download dependencies (`vm-config.ps1`) to a temp folder and self-elevate to Administrator.

### Run locally

```powershell
git clone https://github.com/mytech-today-now/vm-tools.git
cd vm-tools

.\vm-new.ps1                                          # Create vm.01
.\vm-new.ps1 -VMName "dev" -MemoryGB 16               # Create dev.01 with 16 GB RAM
.\vm-copy.ps1 -SourceVMName "vm.01"                   # Clone to vm.02
.\vm-copy.ps1 -SourceVMName "vm.01" -Count 3          # Clone to vm.02, vm.03, vm.04
.\vm-copy.ps1 -SourceVMName "vm.01" -VMName "lab"     # Clone to lab.01
.\vm-copy.ps1 -SourceVMName "vm.01" -Log              # Clone with logging
```

## Scripts

### vm-new.ps1 (v1.2.0)

Creates a Hyper-V Generation 2 VM with TPM 2.0, Secure Boot, Default Switch networking, and an optional Windows ISO.

```powershell
.\vm-new.ps1                                           # Creates vm.01 (or next available)
.\vm-new.ps1 -VMName "dev"                             # Creates dev.01
.\vm-new.ps1 -VMName "test" -MemoryGB 16 -Processors 4  # Custom hardware
.\vm-new.ps1 -StoragePath "D:\VMs"                     # Store under D:\VMs\Hyper-V
.\vm-new.ps1 -ResetConfig                              # Re-prompt for storage location
.\vm-new.ps1 -Log                                      # Enable JSONL logging
.\vm-new.ps1 -WhatIf                                   # Dry run

# Remote execution (irm | iex)
irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-new.ps1 | iex; vm-new
irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-new.ps1 | iex; vm-new -VMName "lab" -MemoryGB 16
```

| Parameter      | Default                                    | Description                                |
|---------------|--------------------------------------------|--------------------------------------------|
| `-VMName`      | `vm`                                       | Base name — appends `.##` suffix           |
| `-VhdxSizeGB`  | `60`                                       | Dynamic VHDX size in GB                    |
| `-MemoryGB`    | `8`                                        | Startup RAM in GB (dynamic memory)         |
| `-Processors`  | `2`                                        | Virtual CPU count                          |
| `-IsoPath`     | `F:\_downloads\Win11_25H2_English_x64.iso` | Windows ISO to mount as boot device        |
| `-SwitchName`  | `Default Switch`                           | Hyper-V virtual switch                     |
| `-StoragePath` | *(Hyper-V defaults)*                       | Root path for VM storage (persisted)       |
| `-ResetConfig` | off                                        | Re-prompt for storage location             |
| `-Log`         | off                                        | Enable JSONL logging to `vm-new.jsonl`     |

### vm-copy.ps1 (v1.4.0)

Clones a Hyper-V VM by exporting and re-importing with full disk isolation. Removes checkpoints from the clone and merges to a single clean VHDX.

```powershell
.\vm-copy.ps1 -SourceVMName "vm.01"                        # Clone to vm.02
.\vm-copy.ps1 -SourceVMName "vm.01" -Count 5               # Clone to vm.02–vm.06
.\vm-copy.ps1 -SourceVMName "vm.01" -VMName "lab" -Count 3  # Clone to lab.01–lab.03
.\vm-copy.ps1 -SourceVMName "vm.01" -KeepExport            # Keep export for inspection
.\vm-copy.ps1 -SourceVMName "vm.01" -ExportPath "E:\Staging"  # Custom staging folder
.\vm-copy.ps1 -SourceVMName "vm.01" -StoragePath "D:\VMs"   # Store clones under D:\VMs
.\vm-copy.ps1 -SourceVMName "vm.01" -Log                    # Enable JSONL logging
.\vm-copy.ps1 -SourceVMName "vm.01" -WhatIf                 # Dry run

# Remote execution (irm | iex)
irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-copy.ps1 | iex; vm-copy -SourceVMName "vm.01"
irm https://raw.githubusercontent.com/mytech-today-now/vm-tools/main/vm-copy.ps1 | iex; vm-copy -SourceVMName "vm.01" -VMName "lab" -Count 5
```

| Parameter        | Default              | Description                                    |
|-----------------|----------------------|------------------------------------------------|
| `-SourceVMName`  | `vm.01`              | VM to clone                                    |
| `-VMName`        | *(from source)*      | Base name for destination — appends `.##`      |
| `-Count`         | `1`                  | Number of copies (1–100)                       |
| `-ExportPath`    | *(from config)*      | Staging folder — defaults to `<StorageRoot>\VMExports` |
| `-KeepExport`    | off                  | Keep the export folder after import            |
| `-StoragePath`   | *(Hyper-V defaults)* | Root path for VM storage (persisted)           |
| `-ResetConfig`   | off                  | Re-prompt for storage location                 |
| `-Log`           | off                  | Enable JSONL logging to `vm-copy.jsonl`        |
| `-Append`        | off                  | Append to log instead of purging               |

#### Log viewer

```powershell
.\vm-copy.ps1 -ShowLog                          # All entries
.\vm-copy.ps1 -ShowLog -Last 20                 # Last 20 entries
.\vm-copy.ps1 -ShowLog -Last 10 -Level ERROR    # Last 10 errors
.\vm-copy.ps1 -ShowLog -RunId "abc-123"         # Specific run
```

### vm-config.ps1

Shared helper dot-sourced by both scripts. Provides:

- **`Resolve-VMStoragePaths`** — Resolves VM and VHD storage paths from a persistent config file (`~\.vm-tools\config.json`), prompting on first run.
- **`Show-VMStatus`** — Displays a table of existing Hyper-V VMs before operations.

This file is auto-downloaded when using `irm | iex` remote execution.

## Naming Convention

Both scripts use the `<BaseName>.##` pattern:

```
vm.01  vm.02  vm.03        (default base: "vm")
dev.01  dev.02  dev.03     (custom base: "dev")
lab.01  lab.02             (custom base: "lab")
```

The next available number is determined by scanning existing Hyper-V VMs.

## Requirements

- **OS:** Windows 10/11 or Windows Server 2016+
- **PowerShell:** 5.1+ or PowerShell 7+
- **Hyper-V:** Module installed and enabled
- **Privileges:** Administrator (scripts self-elevate when run via `irm | iex`)

## Project Structure

```
vm-tools/
├── vm-new.ps1       # Create new VMs
├── vm-copy.ps1      # Clone existing VMs
├── vm-config.ps1    # Shared helper (storage paths, VM status)
├── VERSION          # Semantic version
├── CHANGELOG.md     # Release history
├── LICENSE          # MIT License
├── .gitignore       # Excludes runtime logs
└── README.md        # This file
```

## Help

```powershell
Get-Help .\vm-new.ps1 -Full          # Full help for vm-new
Get-Help .\vm-copy.ps1 -Full         # Full help for vm-copy
.\vm-new.ps1 -?                      # Quick help
.\vm-copy.ps1 -?                     # Quick help
```

## Part of

[PowerShellScripts](https://github.com/mytech-today-now/PowerShellScripts) — A collection of PowerShell automation tools by myTech.Today.

Also available as a standalone repo: [vm-tools](https://github.com/mytech-today-now/vm-tools)

