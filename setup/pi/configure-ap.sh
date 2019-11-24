#!/bin/bash -eu

# based on https://blog.thewalr.us/2017/09/26/raspberry-pi-zero-w-simultaneous-ap-and-managed-mode-wifi/

function log_progress () {
  # shellcheck disable=SC2034
  if typeset -f setup_progress > /dev/null; then
    setup_progress "configure-ap: $1"
  fi
  echo "configure-ap: $1"
}

if [ -z "${AP_SSID+x}" ]
then
  log_progress "AP_SSID not set"
  exit 1
fi

if [ -z "${AP_PASS+x}" ] || [ "$AP_PASS" = "password" ] || (( ${#AP_PASS} < 8))
then
  log_progress "AP_PASS not set, not changed from default, or too short"
  exit 1
fi

if ! grep -q id_str /etc/wpa_supplicant/wpa_supplicant.conf
then
  IP=${AP_IP:-"192.168.66.1"}
  NET=$(echo -n "$IP" | sed -e 's/\.[0-9]\{1,3\}$//')

  # install required packages
  log_progress "installing dnsmasq and hostapd"
  apt-get -y --force-yes install dnsmasq hostapd

  log_progress "configuring AP '$AP_SSID' with IP $IP"
  # create udev rule
  MAC="$(cat /sys/class/net/wlan0/address)"
  cat <<- EOF > /etc/udev/rules.d/70-persistent-net.rules
	SUBSYSTEM=="ieee80211", ACTION=="add|change", ATTR{macaddress}=="$MAC", KERNEL=="phy0", \
	RUN+="/sbin/iw phy phy0 interface add ap0 type __ap", \
	RUN+="/bin/ip link set ap0 address $MAC"
	EOF

  # configure dnsmasq
  cat <<- EOF > /etc/dnsmasq.conf
	interface=lo,ap0
	no-dhcp-interface=lo,wlan0
	bind-interfaces
	bogus-priv
	dhcp-range=${NET}.100,${NET}.150,12h
	EOF

  # configure hostapd
  cat <<- EOF > /etc/hostapd/hostapd.conf
	ctrl_interface=/var/run/hostapd
	ctrl_interface_group=0
	interface=ap0
	driver=nl80211
	ssid=${AP_SSID}
	hw_mode=g
	channel=11
	wmm_enabled=0
	macaddr_acl=0
	auth_algs=1
	wpa=2
	wpa_passphrase=${AP_PASS}
	wpa_key_mgmt=WPA-PSK
	wpa_pairwise=TKIP CCMP
	rsn_pairwise=CCMP
	EOF
  cat <<- EOF > /etc/default/hostapd
	DAEMON_CONF="/etc/hostapd/hostapd.conf"
	EOF

  # define network interfaces. Note use of 'AP1' name, defined in wpa_supplication.conf below
  cat <<- EOF > /etc/network/interfaces
	source-directory /etc/network/interfaces.d

	auto lo
	auto ap0
	auto wlan0
	iface lo inet loopback

	allow-hotplug ap0
	iface ap0 inet static
	    address ${IP}
	    netmask 255.255.255.0
	    hostapd /etc/hostapd/hostapd.conf

	allow-hotplug wlan0
	iface wlan0 inet manual
	    wpa-roam /etc/wpa_supplicant/wpa_supplicant.conf
	iface AP1 inet dhcp
	EOF

  if [ ! -L /var/lib/misc ]
  then
    if ! findmnt --mountpoint /mutable
    then
        mount /mutable
    fi
    mkdir -p /mutable/varlib
    mv /var/lib/misc /mutable/varlib
    ln -s /mutable/varlib/misc /var/lib/misc
  fi

  # update the host name to have the AP IP address, otherwise
  # clients connected to the IP will get 127.0.0.1 when looking
  # up the teslausb host name
  sed -i -e "/^127.0.0.1\s*localhost/b; s/^127.0.0.1\(\s*.*\)/$IP\1/" /etc/hosts

  # add ID string to wpa_supplicant
  sed -i -e 's/}/  id_str="AP1"\n}/'  /etc/wpa_supplicant/wpa_supplicant.conf
else
  log_progress "AP mode already configured"
fi
