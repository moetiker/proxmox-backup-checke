# Proxmox VM Backup Checker

A comprehensive tool to check and analyze the backup configuration of all VMs on a Proxmox cluster.

**Current Version: 0.0.1 (Initial Development Release)**

## Features

- Check if all VMs are included in backup jobs
- Identify VMs with disks excluded from backup
- Detailed analysis of backup jobs and their configurations
- Support for both API and file-based configuration retrieval
- Single VM checking with detailed configuration display
- Comprehensive backup job details including compression, notification settings, and more

## Requirements

- Proxmox VE 5.x or higher
- `jq` command-line JSON processor
- Bash 4.x or higher

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/proxmox-backup-checker.git
   cd proxmox-backup-checker
   ```

2. Make the script executable:
   ```bash
   chmod +x proxmox-backup-checker.sh
   ```

## Usage

Run the script on any node in your Proxmox cluster:

```bash
./proxmox-backup-checker.sh [options]
```

### Options

- `-c, --cluster-nodes` - List all nodes in the cluster before checking VMs
- `-d, --details` - Show detailed backup configuration information
- `-v, --vmid ID` - Check backup configuration for a specific VM ID only
- `-h, --help` - Display help message

### Examples

Check all VMs with detailed backup information:
```bash
./proxmox-backup-checker.sh --details
```

Check only a specific VM:
```bash
./proxmox-backup-checker.sh --vmid 100
```

Check a specific VM with detailed information:
```bash
./proxmox-backup-checker.sh --vmid 100 --details
```

## Output Explanation

The script provides a color-coded output with the following indicators:

- ✓ (Green) - VM is fully included in backups (all disks)
- ! (Yellow) - VM is partially included in backups (some disks excluded)
- ✗ (Red) - VM is not included in any backup

The detailed output includes:
- VM metadata (ID, name, node, type)
- Disk configuration and backup status
- Backup job details including schedule, storage, and retention settings
- Comprehensive summary of backup coverage across the cluster

## How It Works

The script first tries to use the Proxmox API (`pvesh`) to gather information about VMs and backup jobs. If the API method fails, it falls back to reading the configuration directly from `/etc/pve/vzdump.cron`.

For each VM, it:
1. Checks if the VM is included in any backup job
2. Examines the VM's disk configuration to see if any disks are excluded from backup
3. Collects detailed information about the backup jobs that include the VM

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
