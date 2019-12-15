#!/bin/bash -eu

FILE_PATH="$1"

(
  echo "user=$RSYNC_USER"
  echo "server=$RSYNC_SERVER"
  echo "path=$RSYNC_PATH"
) > "$FILE_PATH"
