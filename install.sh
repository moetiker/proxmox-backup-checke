#!/bin/bash

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    echo "Please install jq with your package manager (e.g., apt install jq, yum install jq)"
    exit 1
fi

# Check if we're on a Proxmox node
if ! command -v pvesh &> /dev/null; then
    echo "Error: pvesh command not found. This script must be run on a Proxmox VE node."
    exit 1
fi

# Run the backup checker
./proxmox-backup-checker.sh "$@"
