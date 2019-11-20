#!/bin/bash -eu

if [ "$BASH_SOURCE" != "$0" ]
then
  echo "$BASH_SOURCE must be executed, not sourced"
  return 1 # shouldn't use exit when sourced
fi

function log_progress () {
  if typeset -f setup_progress > /dev/null; then
    setup_progress "configure: $1"
  fi
  echo "configure: $1"
}

if [ "${FLOCKED:-}" != "$0" ]
then
  PARENT="$(ps -o comm= $PPID)"
  if [ "$PARENT" != "setup-teslausb" ]
  then
    log_progress "STOP: $0 must be called from setup-teslausb: $PARENT"
    exit 1
  fi

  if FLOCKED="$0" flock -en -E 99 "$0" "$0" "$@" || case "$?" in
  99) echo already running
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

ARCHIVE_SYSTEM=${ARCHIVE_SYSTEM:-none}

function check_variable () {
    local var_name="$1"
    if [ -z "${!var_name+x}" ]
    then
        log_progress "STOP: Define the variable $var_name like this: export $var_name=value"
        exit 1
    fi
}

function install_rc_local () {
    local install_home="$1"

    if grep -q archiveloop /etc/rc.local
    then
        log_progress "Skipping rc.local installation"
        return
    fi

    log_progress "Configuring /etc/rc.local to run the archive scripts at startup..."
    echo "#!/bin/bash -eu" > ~/rc.local
    echo "install_home=\"${install_home}\"" >> ~/rc.local
    cat << 'EOF' >> ~/rc.local
LOGFILE=/tmp/rc.local.log

function log () {
  echo "$( date )" >> "$LOGFILE"
  echo "$1" >> "$LOGFILE"
}

log "Launching archival script..."
"$install_home"/archiveloop &
log "All done"
exit 0
EOF

    cat ~/rc.local > /etc/rc.local
    rm ~/rc.local
    log_progress "Installed rc.local."
}

function check_archive_configs () {
    log_progress "Checking archive configs: "

    case "$ARCHIVE_SYSTEM" in
        rsync)
            check_variable "RSYNC_USER"
            check_variable "RSYNC_SERVER"
            check_variable "RSYNC_PATH"
            export archiveserver="$RSYNC_SERVER"
            ;;
        rclone)
            check_variable "RCLONE_DRIVE"
            check_variable "RCLONE_PATH"
            export archiveserver="8.8.8.8" # since it's a cloud hosted drive we'll just set this to google dns
            ;;
        cifs)
            check_variable "sharename"
            check_variable "shareuser"
            check_variable "sharepassword"
            check_variable "archiveserver"
            ;;
        none)
            export archiveserver=localhost
            ;;
        *)
            log_progress "STOP: Unrecognized archive system: $ARCHIVE_SYSTEM"
            exit 1
            ;;
    esac

    log_progress "done"
}

function get_archive_module () {

    case "$ARCHIVE_SYSTEM" in
        rsync)
            echo "run/rsync_archive"
            ;;
        rclone)
            echo "run/rclone_archive"
            ;;
        cifs)
            echo "run/cifs_archive"
            ;;
        none)
            echo "run/none_archive"
            ;;
        *)
            log_progress "Internal error: Attempting to configure unrecognized archive system: $ARCHIVE_SYSTEM"
            exit 1
            ;;
    esac
}

function install_archive_scripts () {
    local install_path="$1"
    local archive_module="$2"

    log_progress "Installing base archive scripts into $install_path"
    get_script $install_path archiveloop run
    get_script $install_path remountfs_rw run
    # Install the tesla_api.py script only if the user provided credentials for its use.
    if [ ! -z ${tesla_email:+x} ]
    then
      get_script $install_path tesla_api.py run
    else
      log_progress "Skipping tesla_api.py install"
    fi

    log_progress "Installing archive module scripts"
    get_script /tmp verify-and-configure-archive.sh $archive_module
    get_script $install_path archive-clips.sh $archive_module
    get_script $install_path connect-archive.sh $archive_module
    get_script $install_path disconnect-archive.sh $archive_module
    get_script $install_path write-archive-configs-to.sh $archive_module
    get_script $install_path archive-is-reachable.sh $archive_module
    if [ ! -z ${musicsharename:+x} ]
    then
      get_script $install_path copy-music.sh $archive_module
    fi
}


function install_python_packages () {
  setup_progress "Installing python packages..."
  apt-get --assume-yes install python3-pip
  pip3 install boto3
}

function check_pushover_configuration () {
    if [ ! -z "${pushover_enabled+x}" ]
    then
        if [ ! -n "${pushover_user_key+x}" ] || [ ! -n "${pushover_app_key+x}"  ]
        then
            log_progress "STOP: You're trying to setup Pushover but didn't provide your User and/or App key."
            log_progress "Define the variables like this:"
            log_progress "export pushover_user_key=put_your_userkey_here"
            log_progress "export pushover_app_key=put_your_appkey_here"
            exit 1
        elif [ "${pushover_user_key}" = "put_your_userkey_here" ] || [  "${pushover_app_key}" = "put_your_appkey_here" ]
        then
            log_progress "STOP: You're trying to setup Pushover, but didn't replace the default User and App key values."
            exit 1
        fi
    fi
}

function check_gotify_configuration () {
    if [ ! -z "${gotify_enabled+x}" ]
    then
        if [ ! -n "${gotify_domain+x}" ] || [ ! -n "${gotify_app_token+x}"  ]
        then
            log_progress "STOP: You're trying to setup Gotify but didn't provide your Domain and/or App token."
            log_progress "Define the variables like this:"
            log_progress "export gotify_domain=https://gotify.domain.com"
            log_progress "export gotify_app_token=put_your_token_here"
            exit 1
        elif [ "${gotify_domain}" = "https://gotify.domain.com" ] || [  "${gotify_app_token}" = "put_your_token_here" ]
        then
            log_progress "STOP: You're trying to setup Gotify, but didn't replace the default Domain and/or App token values."
            exit 1
        fi
    fi
}

function check_ifttt_configuration () {
    if [ ! -z "${ifttt_enabled+x}" ]
    then
        if [ ! -n "${ifttt_event_name+x}" ] || [ ! -n "${ifttt_key+x}"  ]
        then
            log_progress "STOP: You're trying to setup IFTTT but didn't provide your Event Name and/or key."
            log_progress "Define the variables like this:"
            log_progress "export ifttt_event_name=put_your_event_name_here"
            log_progress "export ifttt_key=put_your_key_here"
            exit 1
        elif [ "${ifttt_event_name}" = "put_your_event_name_here" ] || [  "${ifttt_key}" = "put_your_key_here" ]
        then
            log_progress "STOP: You're trying to setup IFTTT, but didn't replace the default Event Name and/or key values."
            exit 1
        fi
    fi
}

function check_sns_configuration () {
    if [ ! -z "${sns_enabled+x}" ]
    then
        if [ ! -n "${aws_access_key_id+x}" ] || [ ! -n "${aws_secret_key+x}" ] || [ ! -n "${aws_sns_topic_arn+x}"  ]
        then
            echo "STOP: You're trying to setup AWS SNS but didn't provide your User and/or App key and/or topic ARN."
            echo "Define the variables like this:"
            echo "export aws_access_key_id=put_your_accesskeyid_here"
            echo "export aws_secret_key=put_your_secretkey_here"
            echo "export aws_sns_topic_arn=put_your_sns_topicarn_here"
            exit 1
        elif [ "${aws_access_key_id}" = "put_your_accesskeyid_here" ] || [  "${aws_secret_key}" = "put_your_secretkey_here" ] || [  "${aws_sns_topic_arn}" = "put_your_sns_topicarn_here" ]
        then
            echo "STOP: You're trying to setup SNS, but didn't replace the default values."
            exit 1
        fi
    fi
}

function configure_pushover () {
    if [ ! -z "${pushover_enabled+x}" ]
    then
        log_progress "Enabling pushover"
        echo "export pushover_enabled=true" > /root/.teslaCamPushoverCredentials
        echo "export pushover_user_key=$pushover_user_key" >> /root/.teslaCamPushoverCredentials
        echo "export pushover_app_key=$pushover_app_key" >> /root/.teslaCamPushoverCredentials
    else
        log_progress "Pushover not configured."
    fi
}

function configure_gotify () {
    if [ ! -z "${gotify_enabled+x}" ]
    then
        log_progress "Enabling Gotify"
        echo "export gotify_enabled=true" > /root/.teslaCamGotifySettings
        echo "export gotify_domain=$gotify_domain" >> /root/.teslaCamGotifySettings
        echo "export gotify_app_token=$gotify_app_token" >> /root/.teslaCamGotifySettings
        echo "export gotify_priority=$gotify_priority" >> /root/.teslaCamGotifySettings
    else
        log_progress "Gotify not configured."
    fi
}

function configure_ifttt () {
    if [ ! -z "${ifttt_enabled+x}" ]
    then
        log_progress "Enabling IFTTT"
        echo "export ifttt_enabled=true" > /root/.teslaCamIftttSettings
        echo "export ifttt_event_name=$ifttt_event_name" >> /root/.teslaCamIftttSettings
        echo "export ifttt_key=$ifttt_key" >> /root/.teslaCamIftttSettings
    else
        log_progress "IFTTT not configured."
    fi
}

function configure_sns () {
    if [ ! -z "${sns_enabled+x}" ]
    then
        log_progress "Enabling SNS"
        mkdir /root/.aws

        echo "[default]" > /root/.aws/credentials
        echo "aws_access_key_id = $aws_access_key_id" >> /root/.aws/credentials
        echo "aws_secret_access_key = $aws_secret_key" >> /root/.aws/credentials

        echo "[default]" > /root/.aws/config
        echo "region = $aws_region" >> /root/.aws/config

        echo "export sns_enabled=true" > /root/.teslaCamSNSTopicARN
        echo "export sns_topic_arn=$aws_sns_topic_arn" >> /root/.teslaCamSNSTopicARN

        install_python_packages
    else
        log_progress "SNS not configured."
    fi
}

function check_and_configure_pushover () {
    check_pushover_configuration

    configure_pushover
}

function check_and_configure_gotify () {
    check_gotify_configuration

    configure_gotify
}

function check_and_configure_ifttt () {
    check_ifttt_configuration

    configure_ifttt
}


function check_and_configure_sns () {
    check_sns_configuration

    configure_sns
}

function install_push_message_scripts() {
    local install_path="$1"
    get_script $install_path send-push-message run
    get_script $install_path send_sns.py run
}

if ! [ $(id -u) = 0 ]
then
    log_progress "STOP: Run sudo -i."
    exit 1
fi

mkdir -p /root/bin

check_and_configure_pushover
check_and_configure_gotify
check_and_configure_ifttt
check_and_configure_sns
install_push_message_scripts /root/bin

check_archive_configs

configFile=/root/teslausb.conf

{
  echo "ARCHIVE_HOST_NAME=$archiveserver"
  echo "ARCHIVE_DELAY=${archivedelay:-20}"
  echo "SNAPSHOTS_ENABLED=${SNAPSHOTS_ENABLED:-true}"
  echo "ARCHIVE_RECENT_CLIPS=${ARCHIVE_RECENT_CLIPS:-false}"
} > $configFile

archive_module="$( get_archive_module )"
log_progress "Using archive module: $archive_module"

install_archive_scripts /root/bin $archive_module
/tmp/verify-and-configure-archive.sh

install_rc_local /root/bin
