#!/bin/bash -eu

SRC=$1
SNAP=$2
MNT=$3

if mount | grep "$MNT"
then
  echo "snapshot already mounted"
fi

if [ ! -d "$MNT" ]
then
  mkdir -p "$MNT"
fi

SNAPDIR=$(dirname "$SNAP")
if [ ! -d "$SNAPDIR" ]
then
  mkdir -p "$SNAPDIR"
fi

if [ -e "$SNAP" ]
then
  umount "$MNT" || true
  rm -rf "$SNAP"
fi

# make a copy-on-write snapshot of the current image
cp --reflink=always "$SRC" "$SNAP"
# at this point we have a snapshot of the cam image, which is completely
# independent of the still in-use image exposed to the car

# create loopback and scan the partition table, this will create an additional loop
# device in addition to the main loop device, e.g. /dev/loop0 and /dev/loop0p1
losetup -P -f "$SNAP"
PARTLOOP=$(losetup -j "$SNAP" | awk '{print $1}' | sed 's/:/p1/')
fsck "$PARTLOOP" -- -a || true

mount -o ro "$PARTLOOP" "$MNT"

