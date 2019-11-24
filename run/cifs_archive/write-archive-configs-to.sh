#!/bin/bash -eu

FILE_PATH="$1"

# shellcheck disable=SC2154
echo "username=$shareuser" > "$FILE_PATH"
# shellcheck disable=SC2154
echo "password=$sharepassword" >> "$FILE_PATH"
