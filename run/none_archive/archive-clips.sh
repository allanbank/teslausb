#!/bin/bash -eu

# Copies or moves files by magic!

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
#op_future="Copying"
#op_past="Copied"
#cmd=""
while getopts 's:p:mc' OPTION; do
  case "$OPTION" in
    s) src="$OPTARG"
       ;;
    p) extpath="$OPTARG"
       ;;
    m) op="Move"
       #op_future='Moving'
       #op_past="Moved"
       #cmd="--remove-source-files "
       ;;
    c) op="Copy"
       #op_future='Copying'
       #op_past="Copied"
       #cmd=""
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

log "No archive method configured for ${op}"
