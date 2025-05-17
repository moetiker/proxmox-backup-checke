# Changelog

All notable changes to the Proxmox VM Backup Checker will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Support for detecting VMs included in backups via resource pools
- Added "Inclusion Type" information to backup job details
- Enhanced pool membership detection
- Improved summary with backup job ID and inclusion method information
- Better error messages for disk detection issues

### Fixed
- Fixed issue where VMs in resource pools were incorrectly reported as not backed up
- Fixed inconsistency between main output and summary for specific VM checks
- Improved display of resource pool information in backup job summaries
- Fixed "No disks detected" issue in summary when disks are shown in VM details
- Fixed "local: can only be used in a function" error in summary section

## [0.0.1] - 2025-05-16

### Added

- Initial development release of the Proxmox VM Backup Checker script
- Ability to check backup configuration for all VMs on a Proxmox cluster
- Ability to check backup configuration for a specific VM by ID
- Identification of VMs with disks excluded from backup
- Detection of VMs not included in any backup job
- Color-coded output for better readability
- Detailed backup job information display:
  - Schedule, storage, mode, and retention settings
  - Compression options (including pigz, zstd settings)
  - Notification settings
  - Bandwidth limits and I/O priority settings
  - Excluded paths
  - Custom scripts
  - VM stop/suspend behavior during backup
- Support for API-based configuration retrieval
- Fallback to file-based configuration when API fails
- Command-line options:
  - `--cluster-nodes` to list all nodes in the cluster
  - `--details` to show detailed backup configuration
  - `--vmid ID` to check a specific VM
  - `--help` to display usage information
- Summary statistics showing protected vs. unprotected VMs
- Human-readable formatting of disk sizes and memory

### Documentation

- Added comprehensive README.md with usage instructions
- Added installation script
- Added contribution guidelines
- Added MIT license

[Unreleased]: https://github.com/moetiker/proxmox-backup-checker/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/moetiker/proxmox-backup-checker/releases/tag/v0.0.1
