#!/bin/bash -eu

# Copies or moves files to "$drive:$path" via rclone.

script=$(basename "$0")
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
cmd="copy --create-empty-src-dirs"
while getopts 's:p:mc' OPTION; do
  case "$OPTION" in
    s) src="$OPTARG"
       ;;
    p) extpath="$OPTARG"
       ;;
    m) op="Move"
       op_future='Moving'
       op_past="Moved"
       cmd="move --create-empty-src-dirs --delete-empty-src-dirs"
       ;;
    c) op="Copy"
       op_future='Copying'
       op_past="Copied"
       cmd="copy --create-empty-src-dirs"
       ;;
    *) usage; 
       exit 1
       ;;
  esac
done
shift "$((OPTIND -1))"

# Verify the src and extpath are set.
if [ ! -d "$src/$extpath" ]
then
  log "Could not find the path to $op clips from: '$src/$extpath'"
  exit 2
fi

source /root/.teslaCamRcloneConfig

file_count=$(find "$src/$extpath" -type f | wc -l)
lastdir=$(basename "$extpath")
# shellcheck disable=SC2154
# shellcheck disable=SC2086
rclone --config /root/.config/rclone/rclone.conf \
       ${cmd} \
       "$src/$extpath" \
       "$drive:$path/${lastdir}/" \
       >> "$LOG_FILE" 2>&1 || echo ""

files_remaining=$(find "$src/$extpath" -type f | wc -l)

/root/bin/send-push-message "TeslaUSB:" "${op_past} $file_count $extpath files(s), ${files_remaining} remain."
log "${op_future} $extpath clips to archive via rclone finished."
