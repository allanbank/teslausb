#!/bin/bash -eu

# Copies or moves files to the $ARCHIVE_MOUNT via cp/mv.

script=$(basename $0)
function usage() {
  echo "usage: $script [-m|-c] -s <source> -p <path>" >&2
  echo "        -m, -c: Do a [m]ove or [c]opy of the files." >&2
  echo "                Defaults to copy." >&2
  echo "   -s <source>: The source path to copy files from." >&2
  echo "     -p <path>: The subpath for the files to move. " >&2
  echo "                e.g., 'SentryClips'" >&2
}

src=""
extpath=""
op="Copy"
op_future="Copying"
op_past="Copied"
while getopts 's:p:m' OPTION; do
  case "$OPTION" in
    s) src="$OPTARG" ;;
    p) extpath="$OPTARG" ;;
    m) op="Move"
       op_future='Moving'
       op_past="Moved" ;;
    c) op="Copy"
       op_future='Copying'
       op_past="Copied" ;;
    *) usage; 
       exit 1;;
  esac
done
shift "$(($OPTIND -1))"

# Verify the src and extpath are set.
if [ ! -d "${src}/${extpath}" ]
then
  log "Could not find the path to $op clips from: '${src}/${extpath}'"
  exit 2
fi

function connectionmonitor {
  while true
  do
    for i in {1..5}
    do
      if timeout 6 /root/bin/archive-is-reachable.sh $ARCHIVE_HOST_NAME
      then
        # sleep and then continue outer loop
        sleep 5
        continue 2
      fi
    done
    log "Connection dead, killing ${script}"
    # The archive loop might be stuck on an unresponsive server, so kill it hard.
    # (should be no worse than losing power in the middle of an operation)
    kill -9 $1
    return
  done
}

function processclips() {
  local src="$1"
  local extpath="$2"
  local base="${src}/${extpath}"

  NUM_FILES_OPS=0
  NUM_FILES_FAILED=0

  if [ ! -d "${base}" ]
  then
    log "${base} does not exist, skipping"
    return
  fi

  while IFS= read -r -d '' file
  do
    if [ -f "${base}/${file}" ] 
    then
      relpath=$(dirname "${file}")
      filename=$(basename "${file}")
      destdir="$ARCHIVE_MOUNT/${extpath}/${relpath}"
      destfile="${destdir}/${filename}"
      if [ ! -e "${destfile}" -o "${base}/${file}" -nt "${destfile}" ]
      then 
        log "${op_future} '${extpath}/${file}'"
        mkdir --parents "${destdir}"
        if ionice -t -c 3 cp --preserve=timestamps --force "${base}/${file}" "${destdir}/_${filename}"
        then
          if mv --force "${destdir}/_${filename}" "${destdir}/${filename}"
          then 
            if [ "${op}" == "Move" ] 
            then
              rm -f "${base}/${file}"
            fi
            NUM_FILES_OPS=$((NUM_FILES_OPS + 1))
          else
            log "${op_future} '${extpath}/${file}' final move failed."
            NUM_FILES_FAILED=$((NUM_FILES_FAILED + 1))
          fi
        else
          log "${op_future} '${extpath}/${file}' failed."
          NUM_FILES_FAILED=$((NUM_FILES_FAILED + 1))
        fi
      else
        # Already exists on the destination. If doing a move then delete local.
        if [ "${op}" == "Move" ] 
        then
          rm -f "${base}/${file}"
        fi
      fi
    fi
  done < <( find ${base} -type f -printf "%P\0" )

  log "${op_past} $NUM_FILES_OPS file(s), ${op_future} $NUM_FILES_FAILED failed."
  if [ $NUM_FILES_OPS -gt 0 ]
  then
    /root/bin/send-push-message "TeslaUSB:" "${op_past} $NUM_FILES_OPS dashcam file(s), $NUM_FILES_FAILED failed."
  fi

  log "${op_future} ${extpath} clips to archive finished."
}

connectionmonitor $$ &

log "${op_future} clips from ${extpath}..."
processclips "${src}" "${extpath}"

kill %1


