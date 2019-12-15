#!/bin/sh

# for some reason "umount -d" doesn't remove the loop device, so we have to remove it ourselves
MNT=$(echo "$1" | sed 's/\/$//')
LOOP=$(mount | grep -w "$MNT" | awk '{print $1}' | sed 's/p1$//')
umount "$MNT"
losetup -d "$LOOP"

# delete all dead links
find /backingfiles/TeslaCam/ -depth -xtype l -delete || true

# delete all Sentry, saved and recent folders that are now empty
find /backingfiles/TeslaCam/ -mindepth 2 -depth -type d -empty -exec rmdir "{}" \;