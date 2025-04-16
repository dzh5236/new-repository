#!/usr/bin/env bash
set -euo pipefail

trap '' INT TERM HUP

VERBOSE_FLAG=""
for arg in "$@"; do
  if [[ "$arg" == "-verbose" ]]; then
    VERBOSE_FLAG="-verbose"
    break
  fi
done

handle_error() {
  echo "ERROR: $1" >&2
  exit 1
}

check_host() {
  local host="$1"
  if ! ping -c 1 -W 2 "$host" &>/dev/null; then
    handle_error "Cannot reach $host via ping"
  fi
  if ! timeout 3 bash -c "cat < /dev/null > /dev/tcp/${host}/22" 2>/dev/null; then
    handle_error "Port 22 is not open on $host"
  fi
}

[[ -f ./configure-host.sh ]] || handle_error "configure-host.sh not found in current directory"
[[ -x ./configure-host.sh ]] || chmod +x ./configure-host.sh || handle_error "Failed to make configure-host.sh executable"

check_host server1-mgmt
check_host server2-mgmt

scp ./configure-host.sh remoteadmin@server1-mgmt:/root/ || handle_error "Failed to copy to server1-mgmt"
ssh remoteadmin@server1-mgmt -- "/root/configure-host.sh $VERBOSE_FLAG -name loghost -ip 192.168.16.3 -hostentry webhost 192.168.16.4" || handle_error "Configuration failed on server1-mgmt"

scp ./configure-host.sh remoteadmin@server2-mgmt:/root/ || handle_error "Failed to copy to server2-mgmt"
ssh remoteadmin@server2-mgmt -- "/root/configure-host.sh $VERBOSE_FLAG -name webhost -ip 192.168.16.4 -hostentry loghost 192.168.16.3" || handle_error "Configuration failed on server2-mgmt"

sudo ./configure-host.sh $VERBOSE_FLAG -hostentry loghost 192.168.16.3 || handle_error "Failed to update local hostentry for loghost"
sudo ./configure-host.sh $VERBOSE_FLAG -hostentry webhost 192.168.16.4 || handle_error "Failed to update local hostentry for webhost"

if ! ping -c 1 -W 2 loghost &>/dev/null; then
  echo "WARNING: 'loghost' is not reachable by name" >&2
fi
if ! ping -c 1 -W 2 webhost &>/dev/null; then
  echo "WARNING: 'webhost' is not reachable by name" >&2
fi

exit 0
