#!/bin/bash -eu

log "Copying music from archive..."

NUM_FILES_COPIED=0
NUM_FILES_SKIPPED=0
NUM_FILES_ERROR=0
NUM_FILES_DELETED=0
NUM_FILES_DELETE_ERROR=0

SRC="/mnt/musicarchive"
DST="/mnt/music"

function connectionmonitor {
  while true
  do
    # shellcheck disable=SC2034
    for i in {1..10}
    do
      if timeout 3 /root/bin/archive-is-reachable.sh "$ARCHIVE_HOST_NAME"
      then
        # sleep and then continue outer loop
        sleep 5
        continue 2
      fi
    done
    log "connection dead, killing archive-clips"
    # The archive loop might be stuck on an unresponsive server, so kill it hard.
    # (should be no worse than losing power in the middle of an operation)
    kill -9 "$1"
    return
  done
}

if ! findmnt --mountpoint $DST
then
  log "$DST not mounted, skipping"
  exit
fi

connectionmonitor $$ &

# Delete files from the local partition(DST) files that do not exist in the 
# music archive(SRC). This frees space for the new files that may be added.
while read -r file_name
do
  if [ ! -e "$SRC/$file_name" ]
  then
    if rm "$DST/$file_name"
    then
      NUM_FILES_DELETED=$((NUM_FILES_DELETED + 1))
    else
      log "Couldn't delete $DST/$file_name"
      NUM_FILES_DELETE_ERROR=$((NUM_FILES_DELETE_ERROR + 1))
    fi
  fi
done <<< "$(cd "$DST"; find ./* -type f)"

# Copy from the music archive(SRC) to the local parition(DST)
while read -r file_name
do
  if [ ! -e "$DST/$file_name" ]
  then
    dir=$(dirname "$file_name")
    if ! mkdir -p "$DST/$dir"
    then
      log "couldn't make directory $DST/$dir"
      NUM_FILES_ERROR=$((NUM_FILES_ERROR + 1))
      continue
    fi
    if ! cp --preserve=timestamps "$SRC/$file_name" "$DST/$dir/__tmp__"
    then
      log "Couldn't copy $SRC/$file_name"
      NUM_FILES_ERROR=$((NUM_FILES_ERROR + 1))
      continue
    fi
    if ! mv "$DST/$dir/__tmp__" "$DST/$file_name"
    then
      log "Couldn't move to $DST/$file_name"
      NUM_FILES_ERROR=$((NUM_FILES_ERROR + 1))
      continue
    fi
    NUM_FILES_COPIED=$((NUM_FILES_COPIED + 1))
  else
    NUM_FILES_SKIPPED=$((NUM_FILES_SKIPPED + 1))
  fi
done <<< "$(cd "$SRC"; find ./* -type f)"

# Stop the connection monitor.
kill %1

log "Copied $NUM_FILES_COPIED music file(s), deleted $NUM_FILES_DELETED, skipped $NUM_FILES_SKIPPED previously-copied files, encountered $NUM_FILES_ERROR copy errors and $NUM_FILES_DELETE_ERROR delete errors."

if [ $NUM_FILES_COPIED -gt 0 ]
then
  /root/bin/send-push-message "TeslaUSB:" "Copied $NUM_FILES_COPIED music file(s), deleted $NUM_FILES_DELETED, skipped $NUM_FILES_SKIPPED previously-copied files, encountered $NUM_FILES_ERROR copy errors and $NUM_FILES_DELETE_ERROR delete errors."
fi
