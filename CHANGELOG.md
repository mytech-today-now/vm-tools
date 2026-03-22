# Changelog

All notable changes to **vm-tools** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-03-15

### Changed

- **vm-copy.ps1** — JSONL logging is now opt-in via `-Log` switch (previously always-on)
- **vm-copy.ps1** — Export path now defaults to `<StorageRoot>\VMExports` derived from
  `vm-config.json` instead of hardcoded `C:\VMExports`
- **vm-copy.ps1** / **vm-new.ps1** — Comprehensive help headers with grouped parameters,
  18/14 examples respectively, `irm | iex` patterns, and `-?` / `Get-Help` hints

### Added

- **vm-new.ps1** — Added `-Log` switch for opt-in JSONL logging (`vm-new.jsonl`)
  with `Write-Log`, `Set-Phase` helpers and phase tracking
- **vm-copy.ps1** / **vm-new.ps1** — Bootstrap now auto-downloads `vm-config.ps1`
  dependency for `irm | iex` remote execution

### Fixed

- **vm-copy.ps1** / **vm-new.ps1** — Updated all URLs from old `PowerShellScripts`
  repo to `vm-tools` repo
- **vm-copy.ps1** — Removed `[ValidateSet]` from `$Level` parameter for PS 5.1
  compatibility (PS 5.1 validates even when the parameter is not provided)
- **vm-copy.ps1** / **vm-new.ps1** — Bootstrap defines global `vm-copy` / `vm-new`
  functions so `irm ... | iex; vm-copy -Args` pattern works correctly

## [1.2.0] - 2026-03-14

### Added

- **vm-config.ps1** — Shared helper providing `Resolve-VMStoragePaths` and
  `Show-VMStatus` functions
- **vm-copy.ps1** / **vm-new.ps1** — Added `-StoragePath` and `-ResetConfig`
  parameters for persistent VM storage path configuration
- **vm-copy.ps1** / **vm-new.ps1** — Shows existing Hyper-V VM status table
  before operations

## [1.1.0] - 2026-03-13

### Added

- **vm-copy.ps1** — Disk-space pre-flight check before export/import; estimates
  total space needed and fails early with a clear message if insufficient

## [1.0.0] - 2026-03-13

### Added

- **vm-new.ps1** — Create Hyper-V Generation 2 VMs with automatic sequential naming
  - Auto-generates names using `<VMName>.##` pattern (e.g. `vm.01`, `vm.02`)
  - Configures Gen 2 VM with TPM 2.0, Default Switch networking
  - Attaches Windows ISO as first boot device
  - Supports `-WhatIf` / `-Confirm` for safe dry-runs
- **vm-copy.ps1** — Clone Hyper-V VMs by export/import with full isolation
  - Exports source VM, imports as copy with new unique ID
  - Removes checkpoints from clone and merges to a single clean VHDX
  - Renames VHDX files to match destination VM name
  - `-Count` parameter to create multiple copies in a single run (1–100)
  - `-VMName` parameter to set a custom base name for clones
  - JSONL structured logging with `-ShowLog`, `-Last`, `-Level`, `-RunId` filters
  - Thread-safe log writes via `FileStream` with `FileShare.ReadWrite`
  - Supports `-WhatIf` / `-Confirm`, `-Append`, `-KeepExport`
- **Remote execution** — Both scripts support `irm <url> | iex` from GitHub
  - Auto-downloads to temp folder and re-launches as proper `.ps1`
  - Self-elevates to Administrator when needed
  - Forwards all bound parameters to the re-launched script
- **Naming convention** — Unified `<BaseName>.##` pattern across both scripts
  - Default base name: `vm`
  - Sequential numbering with zero-padded two-digit suffix
  - Regex-based collision avoidance scans existing VMs

