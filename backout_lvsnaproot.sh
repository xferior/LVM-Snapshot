#!/bin/bash
# backout_lvsnaproot.sh
# Merges snapshot of root logical volume (LV), copies backup /boot, and rebuilds grub.

LV_SNAP="lvsnaproot"

# Directly using the known VG name from your setup
ROOT_FS=$( grep " / " /proc/mounts | awk '{print $1}')
LV_DISPLAY=$(lvdisplay $ROOT_FS)
ROOT_VG=$(echo "$LV_DISPLAY" |grep " VG Name " |awk '{print $NF}')

# Merge the snapshot logical volume and reattempts if failed.
RETRIES=1
DELAY=5
ATTEMPT=0
while [ $ATTEMPT -le $RETRIES ]; do
  lvconvert --merge "/dev/$ROOT_VG/$LV_SNAP"
  if [ $? -eq 0 ]; then
    echo "Snapshot merge initiated. Merging will complete on the next system reboot."
    break
  else
    if [ $ATTEMPT -lt $RETRIES ]; then
      echo "Retrying merge in $DELAY seconds..."
      sleep $DELAY
    else
      echo "Merge failed after $RETRIES retry."
      exit 1
    fi
  fi
  ATTEMPT=$((ATTEMPT + 1))
done

# Specify the backup directory path
BACKUP_DIR="/opt/boot_backout/boot"

# Check if the backup directory exists and has content before attempting to restore
if [ -d "$BACKUP_DIR" ] && [ "$(ls -A $BACKUP_DIR)" ]; then
  # Clear the /boot directory, copy contents from backup
  rm -rf /boot/* || { echo "Error clearing /boot"; exit 1; }
  cp -a $BACKUP_DIR/* /boot/ || { echo "Error restoring /boot"; exit 1; }
else
  echo "No backup found in /opt/boot_backout/boot, skipping restore."
fi

# Update GRUB configuration
if [ -d "/boot/grub" ] || [ -d "/boot/grub2" ]; then
  if command -v grub2-mkconfig >/dev/null; then
    GRUB_CONFIG="/boot/grub2/grub.cfg"
    echo "Running: grub2-mkconfig -o $GRUB_CONFIG ..."
    grub2-mkconfig -o "$GRUB_CONFIG" || { echo "Error updating GRUB config"; exit 1; }
  elif command -v update-grub >/dev/null; then
    echo "Running: update-grub ..."
    update-grub || { echo "Error updating GRUB config"; exit 1; }
  else
    echo "Error: GRUB update command not found."
    exit 1
  fi | grep -v "disk_common"
else
  echo "Error: GRUB directory does not exist, cannot update GRUB config."
  exit 1
fi
