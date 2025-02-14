# nvme-utils

This repository contains utility scripts for managing NVMe devices.

## bind_nvme.sh

### Usage
- **Driver Binding**:
  ```bash
  sudo ./bind_nvme.sh -m {vfio|kernel} [-f /path/to/nvme_devices.yml]
  ```
- **Status Check**:
  ```bash
  sudo ./bind_nvme.sh status [-f /path/to/nvme_devices.yml]
  ```

### Features
`bind_nvme.sh` manages the driver binding for NVMe devices.  
In driver binding mode, it unbinds the device from its current driver and then  
rebinds it to the desired driver as specified (either vfio or kernel).  
In status mode, the script prints the current driver binding state for each  
NVMe device as defined in the provided YAML file.

## find_nvme.sh

### Usage
```bash
./find_nvme.sh
```

### Features
`find_nvme.sh` uses the `lspci` command to retrieve a list of NVMe devices.  
For each device, it locates the corresponding block device(s) in `/sys/block`  
and outputs their information to assist with diagnostics.