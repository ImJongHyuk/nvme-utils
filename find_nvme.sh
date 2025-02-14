#!/bin/bash
# find_nvme.sh

set -e
set -u

# Fetch the list of NVMe devices using lspci.
nvme_devices=$(lspci -nnk | grep -A 3 NVMe | grep -E '^[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | sort | uniq)

while IFS= read -r line; do
  # Extract PCI ID and description.
  pci_id=$(echo "$line" | awk '{print $1}')
  description=$(echo "$line" | cut -d' ' -f2-)
  
  # Find matching NVMe block devices in /sys/block.
  block_devices=$(ls -l /sys/block | grep "$pci_id" | awk '{print $9}' | sort | uniq)
  
  if [[ -n $block_devices ]]; then
    printf "%-40s %-15s\n" "$pci_id $description =>" "[ $(echo "$block_devices" | tr '\n' ' ')]"
  else
    printf "%-40s %-15s\n" "$pci_id $description =>" "[ None ]"
  fi
done <<< "$nvme_devices"
