#!/bin/bash
# create_lvsnaproot.sh
# Creates a snapshot of the root logical volume (LV) and backs up /boot.

# Set size and name of the snapshot
LV_SNAP="lvsnaproot"

# Check if size is specified, if not use default
if [ -z "$1" ]; then
    LV_SIZE=5
else
    LV_SIZE=$1
fi

# Check that size is whole number
if ! [[ $LV_SIZE =~ ^-?[0-9]+$ ]]; then
    echo "LV size is not a whole number"
    exit 1
fi 

# Find root VG and LV names
ROOT_FS=$( grep " / " /proc/mounts | awk '{print $1}')
LV_DISPLAY=$(lvdisplay $ROOT_FS)
ROOT_VG=$(echo "$LV_DISPLAY" |grep " VG Name " |awk '{print $NF}')
ROOT_LV=$(echo "$LV_DISPLAY" |grep " LV Name " |awk '{print $NF}')
[[ -z "$ROOT_VG" ]] && echo "Root VG not found" && exit 1
[[ -z "$ROOT_LV" ]] && echo "Root LV not found" && exit 1

# Reactivate LV using the latest metadata
lvchange --refresh $ROOT_VG/$ROOT_LV

# Define the path for the snapshot LV
SNAPSHOT_LV_PATH="/dev/$ROOT_VG/$LV_SNAP"

# Check if the snapshot logical volume already exists
lvdisplay "$SNAPSHOT_LV_PATH" &> /dev/null
if [ $? -eq 0 ]; then
  echo "$LV_SNAP already exists"
  exit 1
fi

# Calculate the available free space in the VG
VG_FREE_SPACE_RAW=$(vgs --noheadings --units g "$ROOT_VG" | awk '{print $NF}')

# Remove decimal
VG_FREE_G=${VG_FREE_SPACE_RAW%.*} 

# Ensure there is sufficient free space for the snapshot
if [[ ! "$VG_FREE_G" =~ ^[0-9]+$ ]] || (( VG_FREE_G < LV_SIZE )); then
  echo "Insufficient free space in VG: $VG_FREE_SPACE_RAW"
  echo "Attempted to create $LV_SNAP with: ${LV_SIZE}g"
  exit 1
fi

# Specify the backup directory path
BACKUP_DIR="/opt/boot_backout/boot"

# Check that BACKUP_DIR is not empty or unset
if [[ -z "$BACKUP_DIR" ]]; then
  echo "BACKUP_DIR is unset or empty"
  exit 1
fi

# Check if the backup directory exists
if [[ -d "$BACKUP_DIR" ]]; then
  find "$BACKUP_DIR" -mindepth 1 -delete
else
  mkdir -p "$BACKUP_DIR"
fi

# Backup the /boot directory
cp -a /boot/* "$BACKUP_DIR/"

# Attempt to create the logical volume snapshot
lvcreate --size "${LV_SIZE}G" --snapshot --name "$LV_SNAP" "/dev/$ROOT_VG/$ROOT_LV"
if [ $? -eq 0 ]; then
  echo "Snapshot $LV_SNAP created successfully"
else
  echo "Failed to create LV snapshot"
  exit 1
fi
