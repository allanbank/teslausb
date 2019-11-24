#!/bin/bash -eu

SNAP=$1
MNT=$2

if [ ! -d "$MNT" ]
then
  mkdir -p "$MNT"
fi

if mount | grep "$MNT"
then
  echo "snapshot already mounted"
fi

# create loopback and scan the partition table, this will create an additional loop
# device in addition to the main loop device, e.g. /dev/loop0 and /dev/loop0p1
if [ -z "$(losetup -j "$SNAP")" ]
then
  losetup -P -f "$SNAP"
fi
PARTLOOP=$(losetup -j "$SNAP" | awk '{print $1}' | sed 's/:/p1/')
#fsck $PARTLOOP -- -a || true

echo mount "$PARTLOOP" "$MNT"
mount -o ro "$PARTLOOP" "$MNT"

