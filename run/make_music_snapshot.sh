#!/bin/bash -eu

if [ "${BASH_SOURCE[0]}" != "$0" ]
then
  echo "${BASH_SOURCE[0]} must be executed, not sourced"
  return 1 # shouldn't use exit when sourced
fi

if [ "${FLOCKED:-}" != "$0" ]
then
  mkdir -p "$MUSIC_MOUNT"
  if FLOCKED="$0" flock -E 99 "$MUSIC_MOUNT" "$0" "$@" || case "$?" in
  99) echo "failed to lock musicsnapshot dir"
      exit 99
      ;;
  *)  exit $?
      ;;
  esac
  then
    # success
    exit 0
  fi
fi

function snapshot {
  # Only take a snapshot if the remaining free space is greater than
  # the size of the cam disk image. Delete older snapshots if necessary
  # to achieve that.
  # todo: this could be put in a background task and with a lower free
  # space requirement, to delete old snapshots just before running out
  # of space and thus make better use of space
  local imgsize
  local freespace

  # shellcheck disable=SC2046
  imgsize=$(eval $(stat --format="echo \$((%b*%B))" /backingfiles/music_disk.bin))
  # shellcheck disable=SC2046
  freespace=$(eval $(stat --file-system --format="echo \$((%f*%S))" /backingfiles/music_disk.bin))

  if [ "$freespace" -lt "$imgsize" ]
  then
    log "Insufficient free space ($freespace) to take a music snapshot. Want $imgsize free. Aborting!"
    return 1
  fi
  
  local name=/backingfiles/music_disk.bin.snap
  rm -rf "$name"
  log "Taking music snapshot of music disk: $name"
  /root/bin/mount_snapshot.sh /backingfiles/music_disk.bin "$name" "$MUSIC_MOUNT"
  log "Took music snapshot"

  fix_errors_in_image "$name"

  return 0
}

if ! snapshot
then
  log "Failed to take snapshot"
fi

