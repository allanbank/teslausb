#! /bin/bash

shopt -s globstar nullglob

# SC1091 - Don't complain about not being able to find files that don't exist.
shellcheck --exclude=SC1091 \
           ./setup/pi/setup-teslausb \
           ./pi-gen-sources/00-teslausb-tweaks/files/rc.local \
           ./pi-gen-sources/00-teslausb-tweaks/files/stage_flash \
           ./run/archiveloop \
           ./run/remountfs_rw \
           ./run/send-push-message \
           ./run/waitforidle \
           ./**/*.{sh,ksh,bash}