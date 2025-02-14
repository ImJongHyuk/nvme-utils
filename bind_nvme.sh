#!/bin/bash
# bind_nvme.sh

set -e
set -u

# Logging functions
error() { echo "Err: $1" >&2; exit 1; }
info()  { echo "$1"; }
debug() { [ "${DEBUG:-0}" -ne 0 ] && echo "Dbg: $1"; }

usage() {
  echo "Usage:"
  echo "  Binding mode: sudo $0 -m {vfio|kernel} [-f /path/to/nvme_devices.yml]"
  echo "  Status mode:  sudo $0 status [-f /path/to/nvme_devices.yml]"
  exit 1
}

# Default options
method="vfio"
YAML_FILE="nvme_devices.yml"

if [ "${1-}" = "status" ]; then
  shift
  while getopts "f:" opt; do
    case $opt in
      f) YAML_FILE="$OPTARG" ;;
      *) usage ;;
    esac
  done

  status() {
    command -v yq >/dev/null || error "yq not found (https://github.com/mikefarah/yq)"
    [ -f "$YAML_FILE" ] || error "YAML not found: $YAML_FILE"

    count=$(yq e '.nvme_devices | length' "$YAML_FILE")
    info "Total NVMe devices: $count"
    for (( i=0; i<count; i++ )); do
      pci=$(yq e ".nvme_devices[$i].pci" "$YAML_FILE")
      driver_path="/sys/bus/pci/devices/$pci/driver"
      if [ -L "$driver_path" ]; then
        drv=$(basename "$(readlink "$driver_path")")
      else
        drv="none"
      fi
      info "Device $pci is bound to driver: $drv"
    done
  }

  status
  exit 0
fi

# Option parsing for binding mode
while getopts "m:f:" opt; do
  case $opt in
    m) method="$OPTARG" ;;
    f) YAML_FILE="$OPTARG" ;;
    *) usage ;;
  esac
done

if [[ "$method" != "vfio" && "$method" != "kernel" ]]; then
  usage
fi

command -v yq >/dev/null || error "yq not found (https://github.com/mikefarah/yq)"
[ -f "$YAML_FILE" ] || error "YAML not found: $YAML_FILE"

count=$(yq e '.nvme_devices | length' "$YAML_FILE")
if [ "$count" -eq 0 ]; then
  error "No devices."
fi

bind_vfio() {
  local pci="$1"

  # Check current driver.
  local cur_driver="none"
  if [ -L "/sys/bus/pci/devices/$pci/driver" ]; then
    cur_driver=$(basename "$(readlink /sys/bus/pci/devices/$pci/driver)")
  fi
  info "Device $pci bound to $cur_driver"

  if [ "$cur_driver" != "none" ]; then
    local unbind_path="/sys/bus/pci/drivers/$cur_driver/unbind"
    if [ -f "$unbind_path" ]; then
      echo "$pci" | sudo tee "$unbind_path" >/dev/null
      info "Unbound $pci from $cur_driver"
    else
      info "Unbind path for $pci not found"
    fi
  fi

  sudo modprobe vfio-pci

  local override_path="/sys/bus/pci/devices/$pci/driver_override"
  if [ -f "$override_path" ]; then
    echo "vfio-pci" | sudo tee "$override_path" >/dev/null
    echo "$pci" | sudo tee /sys/bus/pci/drivers_probe >/dev/null
    info "Bound $pci to vfio-pci"
  else
    info "driver_override missing; using manual binding"
    local bind_path="/sys/bus/pci/drivers/vfio-pci/bind"
    if [ -f "$bind_path" ]; then
      echo "$pci" | sudo tee "$bind_path" >/dev/null
      info "Manually bound $pci to vfio-pci"
    else
      error "No binding mechanism for $pci"
    fi
  fi

  sleep 1
  if [ -L "/sys/bus/pci/devices/$pci/driver" ]; then
    local new_driver
    new_driver=$(basename "$(readlink /sys/bus/pci/devices/$pci/driver)")
    info "Device $pci now bound to $new_driver"
  else
    info "Device $pci remains unbound"
  fi
}

bind_kernel() {
  local pci="$1"

  # Check current driver.
  local cur_driver="none"
  if [ -L "/sys/bus/pci/devices/$pci/driver" ]; then
    cur_driver=$(basename "$(readlink /sys/bus/pci/devices/$pci/driver)")
  fi
  info "Device $pci bound to $cur_driver"

  local unbind_path=""
  if [ "$cur_driver" = "vfio-pci" ]; then
    unbind_path="/sys/bus/pci/drivers/vfio-pci/unbind"
  elif [ "$cur_driver" != "none" ]; then
    unbind_path="/sys/bus/pci/devices/$pci/driver/unbind"
  fi

  if [ -n "$unbind_path" ] && [ -f "$unbind_path" ]; then
    echo "$pci" | sudo tee "$unbind_path" >/dev/null
    info "Unbound $pci from $cur_driver"
  else
    info "No unbind required for $pci"
  fi

  local override_path="/sys/bus/pci/devices/$pci/driver_override"
  if [ -f "$override_path" ]; then
    echo "nvme" | sudo tee "$override_path" >/dev/null
    info "Set driver_override to nvme for $pci"
  else
    info "driver_override missing for $pci"
  fi

  sudo modprobe nvme

  echo "$pci" | sudo tee /sys/bus/pci/drivers_probe >/dev/null
  info "Bound $pci to nvme"

  sleep 1
  if [ -L "/sys/bus/pci/devices/$pci/driver" ]; then
    local new_driver
    new_driver=$(basename "$(readlink /sys/bus/pci/devices/$pci/driver)")
    info "Device $pci now bound to $new_driver"
  else
    info "Device $pci remains unbound"
  fi
}

for (( i=0; i<count; i++ )); do
  local pci
  pci=$(yq e ".nvme_devices[$i].pci" "$YAML_FILE")
  local mount_point
  mount_point=$(yq e ".nvme_devices[$i].mount" "$YAML_FILE")

  if mountpoint -q "$mount_point"; then
    sudo umount "$mount_point"
  fi

  if [ "$method" = "vfio" ]; then
    bind_vfio "$pci"
  else
    bind_kernel "$pci"
  fi

  info "Processed: $pci"
done

info "Done."
