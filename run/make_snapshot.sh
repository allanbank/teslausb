#!/bin/bash -eu

if [ "${BASH_SOURCE[0]}" != "$0" ]
then
  echo "${BASH_SOURCE[0]} must be executed, not sourced"
  return 1 # shouldn't use exit when sourced
fi

if [ "${FLOCKED:-}" != "$0" ]
then
  mkdir -p /backingfiles/snapshots
  if FLOCKED="$0" flock -E 99 /backingfiles/snapshots "$0" "$@" || case "$?" in
  99) echo "failed to lock snapshots dir"
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

function copy_file_to {
  local group="${1}"
  local file="${2}"

  local localdir=/backingfiles/TeslaCam/${group}

  local filedir=${file%/*}
  local filename=${file##/*/}
  local filedate=${filename:0:10}
  local filehour=${filename:11:2}
  local fileparentdir=${filedir##/*/}

  if [ "${group}" == "RecentClips" ]
  then
    local destdir="${localdir}/${filedate}/${filehour}"
  else 
    local destdir="${localdir}/${fileparentdir}"
  fi

  if [ ! -d "${destdir}" ]
  then
    mkdir -p "${destdir}" 
  fi

  local destfile="${destdir}/${filename}"
  if [ ! -e "${destfile}" ] || [ "${file}" -nt "${destfile}" ]
  then
    log "Copying ${group}/.../${filename}"
    # Set the copy to not interfere with the Tesla's I/O
    ionice -t -c 3 rm -f "${destdir}/_${filename}"
    ionice -t -c 3 cp --preserve=timestamps "${file}" "${destdir}/_${filename}"
    mv "${destdir}/_${filename}" "${destfile}"
  fi
}


function copy_files_for_snapshot {
  local mntpoint="$1"

  for group in SentryClips SavedClips RecentClips
  do
    if [ -d "${mntpoint}/TeslaCam/${group}" ] ; then
      log "Copying files from ${mntpoint}/TeslaCam/${group}..."
      while IFS= read -r -d '' file
      do
        copy_file_to "${group}" "${file}"
      done < <( find "${mntpoint}/TeslaCam/${group}" -type f -print0 )
    else
      log "${mntpoint}/TeslaCam/${group} does not exist. Skipping copy."
    fi
  done
}

function free_space {
  readonly need_to_free="$1"
  local freed=0

  log "Freeing ${need_to_free} bytes of space for snapshot."
  # Remove all RecentClips before removing any Saved or Sentry Clips.
  for path in /backingfiles/TeslaCam/RecentClips /backingfiles/TeslaCam
  do
    if [ $freed -lt "$need_to_free" ]
    then
      while IFS= read -r file
      do
        local size
        # shellcheck disable=SC2046
        size=$(eval $(stat --format="echo \$((%b*%B))" "${file}"))
        if rm -f "${file}"
        then
          (( freed+=size ))
          if [ "$need_to_free" -lt $freed ]
          then
            return 0
          fi
        else
          log "Warning: Could not delete '${file}' to free space."
        fi
      done < <( find "${path}" -type f -printf "%C@ %p\n" | sort -n | sed 's/[^ ]\+ //' )
    else
      # Freed enough space.
      return 0
    fi
  done
  return 1
}

function snapshot {
  local imgsize
  local freespace
  local fssize
  local tenpercentminfree
  local wanted
  local freespace
  # Only take a snapshot if the remaining free space is greater than
  # the size of the cam disk image. Delete older snapshots if necessary
  # to achieve that.
  # todo: this could be put in a background task and with a lower free
  # space requirement, to delete old snapshots just before running out
  # of space and thus make better use of space
  # shellcheck disable=SC2046
  imgsize=$(eval $(stat --format="echo \$((%b*%B))" /backingfiles/cam_disk.bin))
  # shellcheck disable=SC2046
  freespace=$(eval $(stat --file-system --format="echo \$((%f*%S))" /backingfiles/cam_disk.bin))
  # shellcheck disable=SC2046
  fssize=$(eval $(stat --file-system --format="echo \$((%b*%S))" /backingfiles/cam_disk.bin))
  tenpercentminfree=$(( fssize/ 10 ))
  wanted=$imgsize

  if [ "$imgsize" -lt $tenpercentminfree ]
  then
    # Free the larger (10%) of the disk.
    wanted=tenpercentminfree
  fi
  if [ "$freespace" -lt $wanted ]
  then
    local need_to_free=$((wanted-freespace))
    if ! free_space ${need_to_free}
    then
      # shellcheck disable=SC2046
      freespace=$(eval $(stat --file-system --format="echo \$((%f*%S))" /backingfiles/cam_disk.bin))
      log "Insufficient free space ($freespace) to take a snapshot. Want $wanted free. Aborting!"
      return 1
    fi
  fi
  
  local snaptime
  snaptime=$(date "+%Y%m%dT%H%M%S")

  local snapdir="/backingfiles/snapshots/snap-${snaptime}"
  local snapmnt="$snapdir/mnt"
  local name="$snapdir/snap.bin"
  rm -rf "$snapdir"
  log "Taking snapshot of cam disk: $name"
  /root/bin/mount_snapshot.sh /backingfiles/cam_disk.bin "$name" "$snapmnt"
  log "Took snapshot"

  fix_errors_in_image "$name"
  copy_files_for_snapshot "$snapmnt"

  log "Discarding Snapshot"
  /root/bin/release_snapshot.sh "$snapmnt"
  rm -rf "$snapdir"
  return 0
}

if ! snapshot
then
  log "Failed to take snapshot"
fi

