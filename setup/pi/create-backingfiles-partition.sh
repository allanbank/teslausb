#!/bin/bash -eu

function setup_progress () {
  local setup_logfile=/boot/teslausb-headless-setup.log
  local headless_setup=${HEADLESS_SETUP:-false}
  if [ "$headless_setup" = "true" ]
  then
    echo "$( date ) : $1" >> "$setup_logfile"
  fi
  echo "$1"
}

# install XFS tools if needed
if ! hash mkfs.xfs
then
  apt-get -y --force-yes install xfsprogs
fi

# Will check for USB Drive before running sd card
# shellcheck disable=SC2154
if [ -n "$usb_drive" ]
then
  setup_progress "usb_drive is set to $usb_drive"
  # Check if backingfiles and mutable partitions exist
  if [ /dev/disk/by-label/backingfiles -ef /dev/sda2 ] && [ /dev/disk/by-label/mutable -ef /dev/sda1 ]
  then
    setup_progress "Looks like backingfiles and mutable partitions already exist. Skipping partition creation."
  else
    setup_progress "WARNING !!! This will delete EVERYTHING in $usb_drive."
    wipefs -afq "$usb_drive"
    parted "$usb_drive" --script mktable gpt
    setup_progress "$usb_drive fully erased. Creating partitions..."
    parted -a optimal -m /dev/sda mkpart primary ext4 '0%' 2GB
    parted -a optimal -m /dev/sda mkpart primary ext4 2GB '100%'
    setup_progress "Backing files and mutable partitions created."

    setup_progress "Formatting new partitions..."
    # Force creation of filesystems even if previous filesystem appears to exist
    mkfs.ext4 -F -L mutable /dev/sda1
    mkfs.xfs -f -m reflink=1 -L backingfiles /dev/sda2
  fi
    
  BACKINGFILES_MOUNTPOINT="$1"
  MUTABLE_MOUNTPOINT="$2"
  if grep -q backingfiles /etc/fstab
  then
    setup_progress "backingfiles already defined in /etc/fstab. Not modifying /etc/fstab."
  else
    echo "LABEL=backingfiles $BACKINGFILES_MOUNTPOINT xfs auto,rw,noatime 0 2" >> /etc/fstab
  fi
  if grep -q 'mutable' /etc/fstab
  then
    setup_progress "mutable already defined in /etc/fstab. Not modifying /etc/fstab."
  else
    echo "LABEL=mutable $MUTABLE_MOUNTPOINT ext4 auto,rw 0 2" >> /etc/fstab
  fi
  setup_progress "Done."
  exit 0
else
  echo "usb_drive not set. Proceeding to SD card setup"
fi

# If partition 3 is the backingfiles partition, type xfs, and
# partition 4 the mutable partition, type ext4, then return early.
if [ /dev/disk/by-label/backingfiles -ef /dev/mmcblk0p3 ] && \
    [ /dev/disk/by-label/mutable -ef /dev/mmcblk0p4 ] && \
    blkid /dev/mmcblk0p4 | grep -q 'TYPE="ext4"'
then
  if blkid /dev/mmcblk0p3 | grep -q 'TYPE="xfs"'
  then
    # assume these were either created previously by the setup scripts,
    # or manually by the user, and that they're big enough
    setup_progress "using existing backingfiles and mutable partitions"
    return &> /dev/null || exit 0
  elif blkid /dev/mmcblk0p3 | grep -q 'TYPE="ext4"'
  then
    # special case: convert existing backingfiles from ext4 to xfs
    setup_progress "reformatting existing backingfiles as xfs"
    killall archiveloop || true
    modprobe -r g_mass_storage
    if mount | grep -qw "/mnt/cam"
    then
      if ! umount /mnt/cam
      then
        setup_progress "STOP: couldn't unmount /mnt/cam"
        exit 1
      fi
    fi
    if mount | grep -qw "/backingfiles"
    then
      if ! umount /backingfiles
      then
        setup_progress "STOP: couldn't unmount /backingfiles"
        exit 1
      fi
    fi
    mkfs.xfs -f -m reflink=1 -L backingfiles /dev/mmcblk0p3

    # update /etc/fstab
    sed -i 's/LABEL=backingfiles .*/LABEL=backingfiles \/backingfiles xfs auto,rw,noatime 0 2/' /etc/fstab
    mount /backingfiles
    setup_progress "backingfiles converted to xfs and mounted"
    return &> /dev/null || exit 0
  fi
fi

# partition 3 and 4 either don't exist, or are the wrong type
if [ -e /dev/mmcblk0p3 ] || [ -e /dev/mmcblk0p4 ]
then
  setup_progress "STOP: partitions already exist, but are not as expected"
  setup_progress "please delete them and re-run setup"
  exit 1
fi

BACKINGFILES_MOUNTPOINT="$1"
MUTABLE_MOUNTPOINT="$2"

setup_progress "Checking existing partitions..."

DISK_SECTORS=$(blockdev --getsz /dev/mmcblk0)
LAST_DISK_SECTOR=$((DISK_SECTORS - 1))
# mutable partition is 100MB at the end of the disk, calculate its start sector
FIRST_MUTABLE_SECTOR=$((LAST_DISK_SECTOR-204800+1))
# backingfiles partition sits between the root and mutable partition, calculate its start sector and size
LAST_ROOT_SECTOR=$(sfdisk -l /dev/mmcblk0 | grep mmcblk0p2 | awk '{print $3}')
FIRST_BACKINGFILES_SECTOR=$((LAST_ROOT_SECTOR + 1))
BACKINGFILES_NUM_SECTORS=$((FIRST_MUTABLE_SECTOR - FIRST_BACKINGFILES_SECTOR))

ORIGINAL_DISK_IDENTIFIER=$( fdisk -l /dev/mmcblk0 | grep -e "^Disk identifier" | sed "s/Disk identifier: 0x//" )

setup_progress "Modifying partition table for backing files partition..."
echo "$FIRST_BACKINGFILES_SECTOR,$BACKINGFILES_NUM_SECTORS" | sfdisk --force /dev/mmcblk0 -N 3

setup_progress "Modifying partition table for mutable (writable) partition for script usage..."
echo "$FIRST_MUTABLE_SECTOR," | sfdisk --force /dev/mmcblk0 -N 4

# manually adding the partitions to the kernel's view of things is sometimes needed
if [ ! -e /dev/mmcblk0p3 ] || [ ! -e /dev/mmcblk0p4 ]
then
  partx --add --nr 3:4 /dev/mmcblk0
fi
if [ ! -e /dev/mmcblk0p3 ] || [ ! -e /dev/mmcblk0p4 ]
then
  setup_progress "failed to add partitions"
  exit 1
fi

NEW_DISK_IDENTIFIER=$( fdisk -l /dev/mmcblk0 | grep -e "^Disk identifier" | sed "s/Disk identifier: 0x//" )

setup_progress "Writing updated partitions to fstab and /boot/cmdline.txt"
sed -i "s/${ORIGINAL_DISK_IDENTIFIER}/${NEW_DISK_IDENTIFIER}/g" /etc/fstab
sed -i "s/${ORIGINAL_DISK_IDENTIFIER}/${NEW_DISK_IDENTIFIER}/" /boot/cmdline.txt

setup_progress "Formatting new partitions..."
# Force creation of filesystems even if previous filesystem appears to exist
mkfs.xfs -f -m reflink=1 -L backingfiles /dev/mmcblk0p3
mkfs.ext4 -F -L mutable /dev/mmcblk0p4

echo "LABEL=backingfiles $BACKINGFILES_MOUNTPOINT xfs auto,rw,noatime 0 2" >> /etc/fstab
echo "LABEL=mutable $MUTABLE_MOUNTPOINT ext4 auto,rw 0 2" >> /etc/fstab
