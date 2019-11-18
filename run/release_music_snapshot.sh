#!/bin/sh

# for some reason "umount -d" doesn't remove the loop device, so we have to remove it ourselves
MNT=$(echo "$1" | sed 's/\/$//')
LOOP=$(mount | grep -w "$MNT" | awk '{print $1}' | sed 's/p1$//')
SNAP=$(losetup -l --noheadings $LOOP | awk '{print $6}')
umount $MNT
losetup -d $LOOP
