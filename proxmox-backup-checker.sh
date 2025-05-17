#!/bin/bash
# ============================================================
# Proxmox VM Backup Configuration Checker
# This script checks the backup configuration of all VMs on a Proxmox cluster
# ============================================================

# ---- Text colors for better readability ----
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---- Function to display script usage ----
function show_usage() {
    echo -e "${BLUE}Usage:${NC} $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --cluster-nodes    List all nodes in the cluster before checking VMs"
    echo "  -d, --details          Show detailed backup configuration information"
    echo "  -v, --vmid ID          Check backup configuration for a specific VM ID only"
    echo "  -h, --help             Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --details                    # Check all VMs with detailed backup info"
    echo "  $0 --vmid 100                   # Check only VM with ID 100"
    echo "  $0 --vmid 100 --details         # Check VM 100 with detailed backup info"
}

# ---- Function to check if a VM ID is included in any backup job ----
function is_vm_in_backup() {
    local vmid="$1"
    local found=false
    
    # If JSON parsing failed and we're using the file method
    if [ "$all_backup_jobs" = "[]" ] && [ -f "/etc/pve/vzdump.cron" ]; then
        while read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue
            
            # Check if the line contains the VM ID or if it's a backup job for all VMs (doesn't contain -vmid)
            if [[ ! "$line" =~ -vmid ]]; then
                # No vmid parameter means all VMs
                found=true
                break
            elif [[ "$line" =~ -vmid[[:space:]]+([^[:space:]]+) ]]; then
                local vm_list="${BASH_REMATCH[1]}"
                
                # Check for direct match in comma-separated list
                if [[ ",$vm_list," == *",$vmid,"* ]]; then
                    found=true
                    break
                fi
                
                # Check for ranges in VM list
                while read -r item; do
                    # If it's a range (contains a hyphen)
                    if [[ "$item" == *-* ]]; then
                        local start_range=$(echo "$item" | cut -d'-' -f1)
                        local end_range=$(echo "$item" | cut -d'-' -f2)
                        
                        if (( vmid >= start_range && vmid <= end_range )); then
                            found=true
                            break 2
                        fi
                    fi
                done < <(echo "$vm_list" | tr ',' '\n')
            fi
        done < /etc/pve/vzdump.cron
    else
        # Use JSON method if available
        # Check through all backup jobs
        if echo "$all_backup_jobs" | jq -e '.[]' > /dev/null 2>&1; then
            while read -r vm_list; do
                # Empty vmid means all VMs are backed up
                if [ -z "$vm_list" ]; then
                    found=true
                    break
                fi
                
                # Check for direct match in comma-separated list
                if [[ ",$vm_list," == *",$vmid,"* ]]; then
                    found=true
                    break
                fi
                
                # Check for ranges
                while read -r item; do
                    # If it's a range (contains a hyphen)
                    if [[ "$item" == *-* ]]; then
                        local start_range=$(echo "$item" | cut -d'-' -f1)
                        local end_range=$(echo "$item" | cut -d'-' -f2)
                        
                        if (( vmid >= start_range && vmid <= end_range )); then
                            found=true
                            break 2
                        fi
                    fi
                done < <(echo "$vm_list" | tr ',' '\n')
            done < <(echo "$all_backup_jobs" | jq -r '.[] | select(.enabled==1 or .enabled==null) | .vmid // ""')
            
            # Check if all VMs are backed up (indicated by empty vmid field)
            if ! $found && echo "$all_backup_jobs" | jq -r '.[] | select((.enabled==1 or .enabled==null) and (.vmid=="" or .vmid==null))' | grep -q .; then
                found=true
            fi
        fi
    fi
    
    if $found; then
        return 0
    else
        return 1
    fi
}

# ---- Function to get backup jobs for a VM ----
function get_vm_backup_jobs() {
    local vmid="$1"
    local backup_jobs=()
    
    # If JSON parsing failed and we're using the file method
    if [ "$all_backup_jobs" = "[]" ] && [ -f "/etc/pve/vzdump.cron" ]; then
        local job_count=1
        
        while read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue
            
            # Check if the line contains the VM ID or if it's a backup job for all VMs (doesn't contain -vmid)
            local is_included=false
            
            if [[ ! "$line" =~ -vmid ]]; then
                # No vmid parameter means all VMs
                is_included=true
            elif [[ "$line" =~ -vmid[[:space:]]+([^[:space:]]+) ]]; then
                local vm_list="${BASH_REMATCH[1]}"
                
                # Check for direct match in comma-separated list
                if [[ ",$vm_list," == *",$vmid,"* ]]; then
                    is_included=true
                else
                    # Check for ranges in VM list
                    while read -r item; do
                        # If it's a range (contains a hyphen)
                        if [[ "$item" == *-* ]]; then
                            local start_range=$(echo "$item" | cut -d'-' -f1)
                            local end_range=$(echo "$item" | cut -d'-' -f2)
                            
                            if (( vmid >= start_range && vmid <= end_range )); then
                                is_included=true
                                break
                            fi
                        fi
                    done < <(echo "$vm_list" | tr ',' '\n')
                fi
            fi
            
            if $is_included; then
                backup_jobs+=("job_$job_count")
            fi
            
            ((job_count++))
        done < /etc/pve/vzdump.cron
    else
        # Use JSON method if available
        if echo "$all_backup_jobs" | jq -e '.[]' > /dev/null 2>&1; then
            while read -r job; do
                local vm_list=$(echo "$job" | jq -r '.vmid // ""')
                local job_id=$(echo "$job" | jq -r '.id // "unknown"')
                
                # Check for all VMs backup job
                if [[ -z "$vm_list" ]]; then
                    backup_jobs+=("$job_id")
                    continue
                fi
                
                # Check for direct match in comma-separated list
                if [[ ",$vm_list," == *",$vmid,"* ]]; then
                    backup_jobs+=("$job_id")
                    continue
                fi
                
                # Check for ranges
                while read -r item; do
                    # If it's a range (contains a hyphen)
                    if [[ "$item" == *-* ]]; then
                        local start_range=$(echo "$item" | cut -d'-' -f1)
                        local end_range=$(echo "$item" | cut -d'-' -f2)
                        
                        if (( vmid >= start_range && vmid <= end_range )); then
                            backup_jobs+=("$job_id")
                            break
                        fi
                    fi
                done < <(echo "$vm_list" | tr ',' '\n')
            done < <(echo "$all_backup_jobs" | jq -c '.[] | select(.enabled==1 or .enabled==null)')
        fi
    fi
    
    # Return the array as a space-separated string
    echo "${backup_jobs[@]}"
}

# ---- Function to check VM disk configuration for backup ----
function check_vm_disks_backup() {
    local vmid="$1"
    local node="$2"
    local vm_type="$3"
    
    # Array to store disks and their backup status
    local all_disks=()
    local excluded_disks=()
    
    # Default values in case we can't get disk info
    local all_count=0
    local excluded_count=0
    
    if [[ "$vm_type" == "qemu" ]]; then
        # Get VM config
        local vm_config=$(pvesh get /nodes/$node/qemu/$vmid/config --output-format=json 2>/dev/null)
        
        if [[ -n "$vm_config" ]]; then
            # Extract all disk keys
            local disk_keys=$(echo "$vm_config" | jq 'keys[] | select(. | test("^(scsi|sata|ide|virtio)[0-9]+$"))' -r)
            
            for disk_key in $disk_keys; do
                local disk_value=$(echo "$vm_config" | jq -r --arg key "$disk_key" '.[$key]')
                
                # Add to all_disks
                all_disks+=("$disk_key")
                
                # Check if disk is marked for backup exclusion
                if [[ "$disk_value" == *",backup=0"* ]]; then
                    excluded_disks+=("$disk_key")
                fi
            done
        fi
    elif [[ "$vm_type" == "lxc" ]]; then
        # Get container config
        local vm_config=$(pvesh get /nodes/$node/lxc/$vmid/config --output-format=json 2>/dev/null)
        
        if [[ -n "$vm_config" ]]; then
            # Extract all disk keys (rootfs, mp0, mp1, etc.)
            local disk_keys=$(echo "$vm_config" | jq 'keys[] | select(. | test("^(rootfs|mp[0-9]+)$"))' -r)
            
            for disk_key in $disk_keys; do
                local disk_value=$(echo "$vm_config" | jq -r --arg key "$disk_key" '.[$key]')
                
                # Add to all_disks
                all_disks+=("$disk_key")
                
                # Check if disk is marked for backup exclusion
                if [[ "$disk_value" == *",backup=0"* ]]; then
                    excluded_disks+=("$disk_key")
                fi
            done
        fi
    fi
    
    # Count the disks
    all_count=${#all_disks[@]}
    excluded_count=${#excluded_disks[@]}
    
    # Print detailed disk information if requested
    if [ "$SHOW_DETAILS" = true ] && [ $all_count -gt 0 ]; then
        echo -e "   │"
        echo -e "   ├── Disk Configuration:"
        
        for disk_key in "${all_disks[@]}"; do
            local is_excluded=false
            for excluded in "${excluded_disks[@]}"; do
                if [[ "$disk_key" == "$excluded" ]]; then
                    is_excluded=true
                    break
                fi
            done
            
            if [ "$is_excluded" = true ]; then
                echo -e "   │   ├── ${RED}✗${NC} $disk_key - ${RED}Excluded from backup${NC}"
            else
                echo -e "   │   ├── ${GREEN}✓${NC} $disk_key - ${GREEN}Included in backup${NC}"
            fi
        done
        echo -e "   │"
    fi
    
    # Return results as a string that can be parsed
    echo "all:$all_count,excluded:$excluded_count"
}

# ---- Function to print additional VM information when checking a specific VM ----
function print_vm_details() {
    local vmid="$1"
    
    # Get detailed VM info
    local vm_details=$(pvesh get /cluster/resources --type vm --output-format=json | jq --arg vmid "$vmid" '.[] | select(.vmid == ($vmid | tonumber))')
    
    if [[ -n "$vm_details" ]]; then
        local node=$(echo "$vm_details" | jq -r '.node')
        local vm_type=$(echo "$vm_details" | jq -r '.type')
        local status=$(echo "$vm_details" | jq -r '.status')
        local maxmem=$(echo "$vm_details" | jq -r '.maxmem // "N/A"')
        local maxdisk=$(echo "$vm_details" | jq -r '.maxdisk // "N/A"')
        local cpus=$(echo "$vm_details" | jq -r '.maxcpu // "N/A"')
        
        # Convert bytes to human-readable format
        if [[ "$maxmem" != "N/A" ]]; then
            maxmem=$(echo "$maxmem" | awk '{ split( "B KB MB GB TB PB" , v ); s=1; while( $1>1024 ){ $1/=1024; s++ } printf "%.2f %s", $1, v[s] }')
        fi
        
        if [[ "$maxdisk" != "N/A" ]]; then
            maxdisk=$(echo "$maxdisk" | awk '{ split( "B KB MB GB TB PB" , v ); s=1; while( $1>1024 ){ $1/=1024; s++ } printf "%.2f %s", $1, v[s] }')
        fi
        
        # Translate VM type to a more readable format
        if [[ "$vm_type" == "qemu" ]]; then
            vm_type="Virtual Machine (QEMU)"
        elif [[ "$vm_type" == "lxc" ]]; then
            vm_type="Container (LXC)"
        fi
        
        echo -e "${BLUE}=== VM Details ===${NC}"
        echo -e "VM ID: $vmid"
        echo -e "Node: $node"
        echo -e "Type: $vm_type"
        echo -e "Status: $status"
        echo -e "Memory: $maxmem"
        echo -e "Disk: $maxdisk"
        echo -e "CPUs: $cpus"
        
        # Get more detailed info based on VM type
        if [[ "$vm_type" == "Virtual Machine (QEMU)" ]]; then
            local qemu_details=$(pvesh get /nodes/$node/qemu/$vmid/config --output-format=json 2>/dev/null)
            
            if [[ -n "$qemu_details" ]]; then
                local os_type=$(echo "$qemu_details" | jq -r '.ostype // "N/A"')
                echo -e "OS Type: $os_type"
                
                # Check for disk configuration
                local disk_keys=$(echo "$qemu_details" | jq 'keys[] | select(. | test("^(scsi|sata|ide|virtio)[0-9]+$"))' -r)
                if [[ -n "$disk_keys" ]]; then
                    echo -e "Disk Configuration:"
                    
                    while read -r disk_key; do
                        local disk_value=$(echo "$qemu_details" | jq -r --arg key "$disk_key" '.[$key]')
                        
                        # Check if disk is marked for backup exclusion
                        if [[ "$disk_value" == *",backup=0"* ]]; then
                            echo -e "  ${RED}✗${NC} $disk_key - ${RED}Excluded from backup${NC}"
                            echo -e "    $disk_value"
                        else
                            echo -e "  ${GREEN}✓${NC} $disk_key - ${GREEN}Included in backup${NC}"
                            echo -e "    $disk_value"
                        fi
                    done < <(echo "$disk_keys")
                fi
            fi
        elif [[ "$vm_type" == "Container (LXC)" ]]; then
            local lxc_details=$(pvesh get /nodes/$node/lxc/$vmid/config --output-format=json 2>/dev/null)
            
            if [[ -n "$lxc_details" ]]; then
                local os_template=$(echo "$lxc_details" | jq -r '.ostemplate // "N/A"')
                echo -e "OS Template: $os_template"
                
                # Check for disk configuration (rootfs and mount points)
                local disk_keys=$(echo "$lxc_details" | jq 'keys[] | select(. | test("^(rootfs|mp[0-9]+)$"))' -r)
                if [[ -n "$disk_keys" ]]; then
                    echo -e "Disk Configuration:"
                    
                    while read -r disk_key; do
                        local disk_value=$(echo "$lxc_details" | jq -r --arg key "$disk_key" '.[$key]')
                        
                        # Check if disk is marked for backup exclusion
                        if [[ "$disk_value" == *",backup=0"* ]]; then
                            echo -e "  ${RED}✗${NC} $disk_key - ${RED}Excluded from backup${NC}"
                            echo -e "    $disk_value"
                        else
                            echo -e "  ${GREEN}✓${NC} $disk_key - ${GREEN}Included in backup${NC}"
                            echo -e "    $disk_value"
                        fi
                    done < <(echo "$disk_keys")
                fi
            fi
        fi
        
        echo ""
    fi
}

# ---- Main Script ----

# Parse command line options
SHOW_CLUSTER_NODES=false
SHOW_DETAILS=false
SPECIFIC_VMID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--cluster-nodes)
            SHOW_CLUSTER_NODES=true
            shift
            ;;
        -d|--details)
            SHOW_DETAILS=true
            shift
            ;;
        -v|--vmid)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                SPECIFIC_VMID="$2"
                shift 2
            else
                echo -e "${RED}Error:${NC} --vmid requires a valid numeric VM ID."
                show_usage
                exit 1
            fi
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Error:${NC} Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if we're running on a Proxmox node
if ! command -v pvesh &> /dev/null; then
    echo -e "${RED}Error:${NC} This script must be run on a Proxmox VE node."
    exit 1
fi

echo -e "${BLUE}=== Proxmox VM Backup Configuration Checker ===${NC}"
echo -e "${BLUE}Date:${NC} $(date)"
echo ""

# Show cluster nodes if requested
if [ "$SHOW_CLUSTER_NODES" = true ]; then
    echo -e "${BLUE}Cluster Nodes:${NC}"
    pvesh get /nodes --output-format=json | jq -r '.[] | "\(.node) (\(.status))"' | while read -r node_info; do
        node_status=$(echo "$node_info" | grep -o '(.*)')
        node_name=$(echo "$node_info" | sed "s/ $node_status//")
        
        if [[ "$node_info" == *"(online)"* ]]; then
            echo -e "  ${GREEN}✓${NC} $node_name ${GREEN}online${NC}"
        else
            echo -e "  ${RED}✗${NC} $node_name ${RED}offline${NC}"
        fi
    done
    echo ""
fi

# Get list of all backup jobs
all_backup_jobs=$(pvesh get /cluster/backup --output-format=json)

# Check if backup jobs JSON is valid
if ! echo "$all_backup_jobs" | jq empty 2>/dev/null; then
    echo -e "${RED}Error:${NC} Could not parse backup jobs. Using alternate method."
    # Alternative approach if JSON parsing fails
    all_backup_jobs="[]"
    
    # Get backup configuration using direct file access instead
    if [ -f "/etc/pve/vzdump.cron" ]; then
        echo -e "${BLUE}Reading backup configuration from /etc/pve/vzdump.cron${NC}"
    else
        echo -e "${RED}Warning:${NC} Could not find backup configuration file."
    fi
fi

# Count variables
total_vms=0
vms_with_backup=0
vms_without_backup=0
vms_with_partial_backup=0
total_excluded_disks=0

# Get all VMs and containers
if [[ -n "$SPECIFIC_VMID" ]]; then
    echo -e "${BLUE}Checking backup configuration for VM ID ${SPECIFIC_VMID}...${NC}"
    # Get specific VM
    all_vms=$(pvesh get /cluster/resources --type vm --output-format=json | jq --arg vmid "$SPECIFIC_VMID" '[.[] | select(.vmid == ($vmid | tonumber))]')
    
    # Check if VM exists
    if [[ $(echo "$all_vms" | jq length) -eq 0 ]]; then
        echo -e "${RED}Error:${NC} VM with ID $SPECIFIC_VMID not found in the cluster."
        exit 1
    fi
else
    echo -e "${BLUE}Scanning all VMs and Containers...${NC}"
    # Get all VMs (QEMU)
    all_vms=$(pvesh get /cluster/resources --type vm --output-format=json)
fi
echo ""

# Process each VM
if [[ -n "$SPECIFIC_VMID" ]]; then
    # Print detailed VM information when checking a specific VM
    print_vm_details "$SPECIFIC_VMID"
fi

# Store node and vm_type for later use in summary (especially for specific VM)
VM_NODE=""
VM_TYPE=""
VM_DISK_INFO=""

echo "$all_vms" | jq -c '.[]' | while read -r vm; do
    vmid=$(echo "$vm" | jq -r '.vmid')
    name=$(echo "$vm" | jq -r '.name')
    node=$(echo "$vm" | jq -r '.node')
    vm_type=$(echo "$vm" | jq -r '.type')
    status=$(echo "$vm" | jq -r '.status')
    
    # Store for later use in summary if we're checking a specific VM
    if [[ "$vmid" == "$SPECIFIC_VMID" ]]; then
        VM_NODE="$node"
        VM_TYPE="$vm_type"
    fi
    
    # Translate VM type to a more readable format
    if [[ "$vm_type" == "qemu" ]]; then
        vm_type_display="VM"
    elif [[ "$vm_type" == "lxc" ]]; then
        vm_type_display="CT"
    else
        vm_type_display="$vm_type"
    fi
    
    # Count total VMs
    ((total_vms++))
    
    # Check if VM is included in any backup job
    if is_vm_in_backup "$vmid"; then
        # Check if all disks are included in backup
        disk_info=$(check_vm_disks_backup "$vmid" "$node" "$vm_type")
        
        # Store disk info for summary if this is the specific VM we're looking at
        if [[ "$vmid" == "$SPECIFIC_VMID" ]]; then
            VM_DISK_INFO="$disk_info"
        fi
        
        # Parse disk info safely
        if [[ "$disk_info" == *"all:"* && "$disk_info" == *"excluded:"* ]]; then
            all_disk_count=$(echo "$disk_info" | cut -d',' -f1 | cut -d':' -f2)
            excluded_disk_count=$(echo "$disk_info" | cut -d',' -f2 | cut -d':' -f2)
            
            # Ensure we have valid integers
            if [[ "$all_disk_count" =~ ^[0-9]+$ && "$excluded_disk_count" =~ ^[0-9]+$ ]]; then
                if [ "$excluded_disk_count" -gt 0 ]; then
                    echo -e "${YELLOW}!${NC} [$vmid] $name ($vm_type_display on $node) - ${YELLOW}Partially included in backup${NC} ($excluded_disk_count/$all_disk_count disks excluded)"
                    ((vms_with_backup++))
                    ((vms_with_partial_backup++))
                    ((total_excluded_disks+=excluded_disk_count))
                else
                    echo -e "${GREEN}✓${NC} [$vmid] $name ($vm_type_display on $node) - ${GREEN}Fully included in backup${NC}"
                    ((vms_with_backup++))
                fi
            else
                # Fallback if parsing failed
                echo -e "${GREEN}✓${NC} [$vmid] $name ($vm_type_display on $node) - ${GREEN}Included in backup${NC}"
                ((vms_with_backup++))
            fi
        else
            # Fallback if check_vm_disks_backup failed
            echo -e "${GREEN}✓${NC} [$vmid] $name ($vm_type_display on $node) - ${GREEN}Included in backup${NC}"
            ((vms_with_backup++))
        fi
        
        # If detailed view is requested, show the backup jobs
        if [ "$SHOW_DETAILS" = true ]; then
            backup_jobs=$(get_vm_backup_jobs "$vmid")
            for job_id_with_info in $backup_jobs; do
                # Split job_id and inclusion info
                job_id="${job_id_with_info%%:*}"
                inclusion_info="${job_id_with_info#*:}"
                
                # If using the file-based method
                if [[ "$job_id" == job_* ]] && [ "$all_backup_jobs" = "[]" ] && [ -f "/etc/pve/vzdump.cron" ]; then
                    job_num=${job_id#job_}
                    job_line=$(sed -n "${job_num}p" /etc/pve/vzdump.cron)
                    
                    # Skip comments and empty lines
                    [[ "$job_line" =~ ^#.*$ ]] && continue
                    [[ -z "$job_line" ]] && continue
                    
                    # Extract schedule (first 5 fields are cron schedule)
                    schedule=$(echo "$job_line" | awk '{print $1" "$2" "$3" "$4" "$5}')
                    
                    # Extract storage and other parameters
                    if [[ "$job_line" =~ -storage[[:space:]]+([^[:space:]]+) ]]; then
                        storage="${BASH_REMATCH[1]}"
                    else
                        storage="default"
                    fi
                    
                    # Extract mode
                    if [[ "$job_line" =~ -mode[[:space:]]+([^[:space:]]+) ]]; then
                        mode="${BASH_REMATCH[1]}"
                    else
                        mode="snapshot"
                    fi
                    
                    # Extract retention
                    if [[ "$job_line" =~ -maxfiles[[:space:]]+([^[:space:]]+) ]]; then
                        retention="${BASH_REMATCH[1]}"
                    else
                        retention="default"
                    fi
                    
                    echo -e "   ├── Backup Job: ${job_id}"
                    echo -e "   │   ├── Inclusion Type: ${inclusion_info}"
                    echo -e "   │   ├── Schedule: $schedule"
                    echo -e "   │   ├── Storage: $storage"
                    echo -e "   │   ├── Mode: $mode"
                    echo -e "   │   └── Retention: $retention backups"
                else
                    # Using the JSON method
                    job_info=$(echo "$all_backup_jobs" | jq -r ".[] | select(.id==\"$job_id\")")
                    
                    if [[ -n "$job_info" ]]; then
                        schedule=$(echo "$job_info" | jq -r '.schedule // "unknown"')
                        storage=$(echo "$job_info" | jq -r '.storage // "default"')
                        mode=$(echo "$job_info" | jq -r '.mode // "snapshot"')
                        retention=$(echo "$job_info" | jq -r '.maxfiles // "default"')
                        
                        echo -e "   ├── Backup Job: $job_id"
                        echo -e "   │   ├── Inclusion Type: ${inclusion_info}"
                        echo -e "   │   ├── Schedule: $schedule"
                        echo -e "   │   ├── Storage: $storage"
                        echo -e "   │   ├── Mode: $mode"
                        echo -e "   │   └── Retention: $retention backups"
                    else
                        echo -e "   ├── Backup Job: $job_id"
                        echo -e "   │   ├── Inclusion Type: ${inclusion_info}"
                        echo -e "   │   └── (Job details unavailable)"
                    fi
                fi
            done
            echo -e "   │"
        fi
    else
        echo -e "${RED}✗${NC} [$vmid] $name ($vm_type_display on $node) - ${RED}Not included in any backup${NC}"
        ((vms_without_backup++))
    fi
done

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
if [[ -n "$SPECIFIC_VMID" ]]; then
    echo -e "VM ID: $SPECIFIC_VMID"
    # Recheck if VM is included in backups (for consistency)
    if is_vm_in_backup "$SPECIFIC_VMID"; then
        # Use stored disk info to ensure consistency with main output
        if [[ -n "$VM_DISK_INFO" ]]; then
            disk_info="$VM_DISK_INFO"
        else
            # Fallback to rechecking if somehow the stored info is missing
            disk_info=$(check_vm_disks_backup "$SPECIFIC_VMID" "$VM_NODE" "$VM_TYPE")
        fi
        
        # Parse disk info safely
        if [[ "$disk_info" == *"all:"* && "$disk_info" == *"excluded:"* ]]; then
            all_disk_count=$(echo "$disk_info" | cut -d',' -f1 | cut -d':' -f2)
            excluded_disk_count=$(echo "$disk_info" | cut -d',' -f2 | cut -d':' -f2)
            
            # Ensure we have valid integers
            if [[ "$all_disk_count" =~ ^[0-9]+$ && "$excluded_disk_count" =~ ^[0-9]+$ ]]; then
                if [ "$excluded_disk_count" -gt 0 ]; then
                    echo -e "Backup Status: ${YELLOW}Partially included in backup${NC}"
                    echo -e "Disks: $excluded_disk_count out of $all_disk_count disks excluded from backup"
                    echo -e "${YELLOW}Warning: Some disks of this VM are excluded from backup!${NC}"
                    echo -e "Review disk backup settings in VM configuration."
                else
                    echo -e "Backup Status: ${GREEN}Fully included in backup${NC}"
                    if [ "$all_disk_count" -gt 0 ]; then
                        echo -e "Disks: All $all_disk_count disks included in backup"
                    else
                        echo -e "Disks: No disks detected (this may be a detection error)"
                    fi
                fi
            else
                # Fallback if parsing failed
                echo -e "Backup Status: ${GREEN}Included in backup${NC}"
            fi
        else
            # Fallback if check_vm_disks_backup failed
            echo -e "Backup Status: ${GREEN}Included in backup${NC}"
        fi
        
        # Show inclusion method
        backup_jobs=$(get_vm_backup_jobs "$SPECIFIC_VMID")
        if [ -n "$backup_jobs" ]; then
            echo -e "Backup Jobs and Inclusion Methods:"
            for job_id_with_info in $backup_jobs; do
                job_id="${job_id_with_info%%:*}"
                inclusion_type="${job_id_with_info#*:}"
                
                # Get the job description
                job_comment=""
                if [[ "$job_id" != job_* ]]; then
                    job_comment=$(echo "$all_backup_jobs" | jq -r ".[] | select(.id==\"$job_id\") | .comment // \"\"")
                fi
                
                # Get job information
                job_info=""
                if [[ "$job_id" != job_* ]]; then
                    pool=$(echo "$all_backup_jobs" | jq -r ".[] | select(.id==\"$job_id\") | .pool // \"\"")
                    
                    # Get pool from this job
                    if [[ -n "$pool" ]]; then
                        inclusion_type="Pool: $pool"
                    fi
                fi
                
                echo -e "  - ${GREEN}$job_id${NC} - ${inclusion_type}"
            done
        fi
    else
        echo -e "Backup Status: ${RED}Not included in any backup${NC}"
        echo -e "${YELLOW}Warning: This VM is not configured for backup!${NC}"
        echo -e "Consider adding it to a backup job using the Proxmox web interface"
        echo -e "or by editing /etc/pve/vzdump.cron"
    fi
else
    echo -e "Total VMs and Containers: $total_vms"
    echo -e "VMs with full backup: ${GREEN}$((vms_with_backup - vms_with_partial_backup))${NC}"
    
    if [ $vms_with_partial_backup -gt 0 ]; then
        echo -e "VMs with partial backup: ${YELLOW}$vms_with_partial_backup${NC} ($total_excluded_disks disks excluded)"
    fi
    
    echo -e "VMs without backup: ${RED}$vms_without_backup${NC}"

    if [ $vms_without_backup -gt 0 ]; then
        echo -e "${YELLOW}Warning: $vms_without_backup VMs are not configured for backup!${NC}"
    fi
    
    if [ $vms_with_partial_backup -gt 0 ]; then
        echo -e "${YELLOW}Warning: $vms_with_partial_backup VMs have some disks excluded from backup!${NC}"
    fi
    
    if [ $vms_without_backup -gt 0 ] || [ $vms_with_partial_backup -gt 0 ]; then
        echo -e "Consider reviewing backup settings using the Proxmox web interface"
        echo -e "or by editing /etc/pve/vzdump.cron"
    fi
fi

# Display backup jobs
echo ""
echo -e "${BLUE}=== Backup Jobs ===${NC}"

# Check if backup jobs file exists and use it if JSON parsing failed
if [ "$all_backup_jobs" = "[]" ] && [ -f "/etc/pve/vzdump.cron" ]; then
    echo -e "${YELLOW}Using direct file access method for backup jobs${NC}"
    echo ""
    
    while read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        
        echo -e "${BLUE}Backup Job:${NC}"
        
        # Extract schedule (first 5 fields are cron schedule)
        schedule=$(echo "$line" | awk '{print $1" "$2" "$3" "$4" "$5}')
        echo -e "  Schedule: $schedule"
        
        # Extract storage and other parameters
        if [[ "$line" =~ -storage[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  Storage: ${BASH_REMATCH[1]}"
        else
            echo -e "  Storage: default"
        fi
        
        # Extract mode
        if [[ "$line" =~ -mode[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  Mode: ${BASH_REMATCH[1]}"
        else
            echo -e "  Mode: snapshot"
        fi
        
        # Extract retention
        if [[ "$line" =~ -maxfiles[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  Retention: ${BASH_REMATCH[1]} backups"
        else
            echo -e "  Retention: default"
        fi
        
        # Extract VM IDs
        if [[ "$line" =~ -vmid[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  VMs: ${BASH_REMATCH[1]}"
        else
            echo -e "  VMs: all"
        fi
        
        # Extract compression options
        if [[ "$line" =~ -compress[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  Compression: ${BASH_REMATCH[1]}"
        fi
        
        # Extract notification email
        if [[ "$line" =~ -mailto[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  Notification Email: ${BASH_REMATCH[1]}"
        fi
        
        # Extract exclude path pattern
        if [[ "$line" =~ -exclude-path[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  Exclude Path: ${BASH_REMATCH[1]}"
        fi
        
        # Extract bandwidth limit
        if [[ "$line" =~ -bwlimit[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  Bandwidth Limit: ${BASH_REMATCH[1]} KB/s"
        fi
        
        # Extract ionice class
        if [[ "$line" =~ -ionice[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  IO Priority: ${BASH_REMATCH[1]}"
        fi
        
        # Extract stdexcludes
        if [[ "$line" =~ -stdexcludes[[:space:]]+([^[:space:]]+) ]]; then
            stdexcludes="${BASH_REMATCH[1]}"
            if [[ "$stdexcludes" == "0" ]]; then
                echo -e "  Standard Excludes: Disabled"
            else
                echo -e "  Standard Excludes: Enabled"
            fi
        fi
        
        # Extract notes
        if [[ "$line" =~ -notes[[:space:]]+\"([^\"]*)\" ]]; then
            echo -e "  Notes: ${BASH_REMATCH[1]}"
        elif [[ "$line" =~ -notes[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  Notes: ${BASH_REMATCH[1]}"
        fi
        
        # Extract quiet
        if [[ "$line" =~ -quiet[[:space:]]+1 ]]; then
            echo -e "  Quiet Mode: Enabled"
        fi
        
        # Extract pool
        if [[ "$line" =~ -pool[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  Pool: ${BASH_REMATCH[1]}"
        fi
        
        # Extract script
        if [[ "$line" =~ -script[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  Custom Script: ${BASH_REMATCH[1]}"
        fi
        
        # Extract stop parameter
        if [[ "$line" =~ -stop[[:space:]]+1 ]]; then
            echo -e "  Stop VM During Backup: Yes"
        fi
        
        # Extract pigz parameter (parallelize gzip)
        if [[ "$line" =~ -pigz[[:space:]]+([^[:space:]]+) ]]; then
            pigz="${BASH_REMATCH[1]}"
            if [[ "$pigz" == "0" ]]; then
                echo -e "  Parallel Compression: Disabled"
            else
                echo -e "  Parallel Compression: Enabled (pigz)"
            fi
        fi
        
        # Extract zstd parameter
        if [[ "$line" =~ -zstd[[:space:]]+([^[:space:]]+) ]]; then
            echo -e "  Zstd Compression Level: ${BASH_REMATCH[1]}"
        fi
        
        # List all other options we couldn't parse automatically
        echo -e "  Full Command: "
        echo -e "    $line" | fold -s -w 80 | sed 's/^/    /'
        
        echo ""
    done < /etc/pve/vzdump.cron
else
    # Try to use JSON parsing method
    if echo "$all_backup_jobs" | jq -e '.[]' > /dev/null 2>&1; then
        while read -r job; do
            job_id=$(echo "$job" | jq -r '.id // "unknown"')
            enabled=$(echo "$job" | jq -r '.enabled // "1"')
            status=""
            if [[ "$enabled" == "0" ]]; then
                status="${RED}Disabled${NC}"
            else
                status="${GREEN}Enabled${NC}"
            fi
            
            echo -e "${BLUE}Backup Job:${NC} $job_id - Status: $status"
            
            # Basic properties
            schedule=$(echo "$job" | jq -r '.schedule // "unknown"')
            storage=$(echo "$job" | jq -r '.storage // "default"')
            mode=$(echo "$job" | jq -r '.mode // "snapshot"')
            retention=$(echo "$job" | jq -r '.maxfiles // "default"')
            vmid=$(echo "$job" | jq -r '.vmid // "all"')
            
            echo -e "  Schedule: $schedule"
            echo -e "  Storage: $storage"
            echo -e "  Mode: $mode"
            echo -e "  Retention: $retention backups"
            echo -e "  VMs: $vmid"
            
            # Additional properties (if available)
            # Compression options
            compress=$(echo "$job" | jq -r '.compress // "none"')
            echo -e "  Compression: $compress"
            
            # Notification settings
            mailnotification=$(echo "$job" | jq -r '.mailnotification // "none"')
            if [[ "$mailnotification" != "none" ]]; then
                echo -e "  Mail Notification: $mailnotification"
                
                mailto=$(echo "$job" | jq -r '.mailto // "none"')
                if [[ "$mailto" != "none" ]]; then
                    echo -e "  Mail Recipients: $mailto"
                fi
            fi
            
            # Exclude path
            exclude=$(echo "$job" | jq -r '.exclude // "none"')
            if [[ "$exclude" != "none" ]]; then
                echo -e "  Exclude Path: $exclude"
            fi
            
            # Bandwidth limit
            bwlimit=$(echo "$job" | jq -r '.bwlimit // "none"')
            if [[ "$bwlimit" != "none" && "$bwlimit" != "null" ]]; then
                echo -e "  Bandwidth Limit: $bwlimit KB/s"
            fi
            
            # IO Priority
            ionice=$(echo "$job" | jq -r '.ionice // "none"')
            if [[ "$ionice" != "none" && "$ionice" != "null" ]]; then
                echo -e "  IO Priority: $ionice"
            fi
            
            # Standard excludes
            stdexclude=$(echo "$job" | jq -r '.stdexclude // "none"')
            if [[ "$stdexclude" != "none" && "$stdexclude" != "null" ]]; then
                if [[ "$stdexclude" == "0" ]]; then
                    echo -e "  Standard Excludes: Disabled"
                else
                    echo -e "  Standard Excludes: Enabled"
                fi
            fi
            
            # Notes
            notes=$(echo "$job" | jq -r '.notes // "none"')
            if [[ "$notes" != "none" && "$notes" != "null" ]]; then
                echo -e "  Notes: $notes"
            fi
            
            # Pool
            pool=$(echo "$job" | jq -r '.pool // "none"')
            if [[ "$pool" != "none" && "$pool" != "null" ]]; then
                echo -e "  Pool: $pool"
            fi
            
            # Script
            script=$(echo "$job" | jq -r '.script // "none"')
            if [[ "$script" != "none" && "$script" != "null" ]]; then
                echo -e "  Custom Script: $script"
            fi
            
            # Stop parameter
            stopwait=$(echo "$job" | jq -r '.stopwait // "none"')
            if [[ "$stopwait" != "none" && "$stopwait" == "1" ]]; then
                echo -e "  Stop VM During Backup: Yes"
            fi
            
            # Pigz parameter
            pigz=$(echo "$job" | jq -r '.pigz // "none"')
            if [[ "$pigz" != "none" && "$pigz" != "null" ]]; then
                if [[ "$pigz" == "0" ]]; then
                    echo -e "  Parallel Compression: Disabled"
                else
                    echo -e "  Parallel Compression: Enabled (pigz)"
                fi
            fi
            
            # Zstd parameter
            zstd=$(echo "$job" | jq -r '.zstd // "none"')
            if [[ "$zstd" != "none" && "$zstd" != "null" ]]; then
                echo -e "  Zstd Compression Level: $zstd"
            fi
            
            # List all keys and values for debugging and catching anything missed
            echo -e "  All Configuration Parameters:"
            echo "$job" | jq -r 'to_entries | .[] | "    \(.key): \(.value)"' | sort
            
            echo ""
        done < <(echo "$all_backup_jobs" | jq -c '.[]')
    else
        echo -e "${YELLOW}No backup jobs found or couldn't parse backup configuration.${NC}"
        echo -e "Consider checking your backup configuration manually."
    fi
fi
