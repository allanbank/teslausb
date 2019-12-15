#!/bin/bash -eu

VERS_OPT=
SEC_OPT=

function log_progress () {
  # shellcheck disable=SC2034
  if typeset -f setup_progress > /dev/null; then
    setup_progress "verify-and-configure-archive: $*"
  fi
  echo "verify-and-configure-archive: $1"
}

function check_archive_server_reachable () {
  # shellcheck disable=SC2154
  log_progress "Verifying that the archive server $archiveserver is reachable..."
  local serverunreachable=false
  hping3 -c 1 -S -p 445 "$archiveserver" 1>/dev/null 2>&1 || serverunreachable=true

  if [ "$serverunreachable" = true ]
  then
    log_progress "STOP: The archive server $archiveserver is unreachable. Try specifying its IP address instead."
    exit 1
  fi

  log_progress "The archive server is reachable."
}

function check_archive_mountable () {
  local test_mount_location="/tmp/archivetestmount"

  log_progress "Verifying that the archive share is mountable..."

  if [ ! -e "$test_mount_location" ]
  then
    mkdir "$test_mount_location"
  fi

  local tmp_credentials_file_path="/tmp/teslaCamArchiveCredentials"
  /root/bin/write-archive-configs-to.sh "$tmp_credentials_file_path"

  local mounted=false
  local try_versions="${cifs_version:-@@ default 3.0 2.1 2.0 1.0}"
  local try_secs="${cifs_sec:-@@ ntlmssp ntlmv2 ntlm}"

  echo "Trying all combinations of vers=($try_versions) and sec=($try_secs)"
  for vers in $try_versions
  do
    for sec in $try_secs
    do
      versopt=""
      secopt=""
      if [ "$vers" != "@@" ]
      then
        versopt="vers=$vers"
      fi
      if [ "$sec" != "@@" ]
      then
        secopt="sec=$sec"
      fi
      local commandline="mount -t cifs '//$1/$2' '$test_mount_location' -o 'credentials=${tmp_credentials_file_path},iocharset=utf8,file_mode=0777,dir_mode=0777,$versopt,$secopt'"
      log_progress "Trying mount command-line:"
      log_progress "$commandline"
      if eval "$commandline"
      then
        mounted=true
        break 2
      fi
    done
  done
  if [ "$mounted" = false ]
  then
    log_progress "STOP: no working combination of vers and sec mount options worked"
    exit 1
  else
    log_progress "The archive share is mountable using: $commandline"
    # the music archive must be mountable with the same mount options
    # so fix the options now
    export cifs_version=$vers
    export cifs_sec=$sec
    VERS_OPT=$versopt
    SEC_OPT=$secopt
  fi

  umount "$test_mount_location"
}

function install_required_packages () {
  log_progress "Installing/updating required packages if needed"
  apt-get -y --force-yes install hping3
  log_progress "Done"
}

install_required_packages

check_archive_server_reachable
# shellcheck disable=SC2154
check_archive_mountable "$archiveserver" "$sharename"
# shellcheck disable=SC2154
if [ -n "${musicsharename:+x}" ]
then
  check_archive_mountable "$archiveserver" "$musicsharename"
fi

function configure_archive () {
  log_progress "Configuring the archive..."

  local archive_path="/mnt/archive"
  local music_archive_path="/mnt/musicarchive"

  if [ ! -e "$archive_path" ]
  then
    mkdir "$archive_path"
  fi

  local credentials_file_path="/root/.teslaCamArchiveCredentials"
  /root/bin/write-archive-configs-to.sh "$credentials_file_path"

  if ! grep -w -q "$archive_path" /etc/fstab
  then
    local sharenameforstab="${sharename// /\\040}"
    echo "//$archiveserver/$sharenameforstab $archive_path cifs credentials=${credentials_file_path},iocharset=utf8,file_mode=0777,dir_mode=0777,$VERS_OPT,$SEC_OPT 0" >> /etc/fstab
  fi

  if [ -n "${musicsharename:+x}" ]
  then
    if [ ! -e "$music_archive_path" ]
    then
      mkdir "$music_archive_path"
    fi
    if ! grep -w -q "$music_archive_path" /etc/fstab
    then
      local musicsharenameforstab="${musicsharename// /\\040}"
      echo "//$archiveserver/$musicsharenameforstab $music_archive_path cifs credentials=${credentials_file_path},iocharset=utf8,file_mode=0777,dir_mode=0777,$VERS_OPT,$SEC_OPT 0" >> /etc/fstab
    fi
  fi

  log_progress "Configured the archive."
}

configure_archive
