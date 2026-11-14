#!/bin/sh
# Interactive English installation and preview.
set -eu
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || { echo 'Run as root.' >&2; exit 1; }
[ -r /etc/openwrt_release ] || { echo 'This does not appear to be OpenWrt.' >&2; exit 1; }
. /etc/openwrt_release
case "${DISTRIB_RELEASE:-}" in 25.12.*|25.12-SNAPSHOT|v0.64.3-3K) ;; *) echo "OpenWrt 25.12.x required; detected ${DISTRIB_RELEASE:-unknown}." >&2; exit 1;; esac
command -v apk >/dev/null && command -v ubus >/dev/null && command -v jsonfilter >/dev/null && command -v ip >/dev/null && [ -x /usr/sbin/uhttpd ] || { echo 'Missing apk, ubus, jsonfilter, ip or uhttpd; installation stopped.' >&2; exit 1; }
status=$(ubus call network.interface.lan status) || { echo 'Logical LAN interface unavailable.' >&2; exit 1; }
LAN_DEVICE=$(printf '%s' "$status" | jsonfilter -e '@.l3_device')
[ -n "$LAN_DEVICE" ] || LAN_DEVICE=$(printf '%s' "$status" | jsonfilter -e '@.device')
case "$LAN_DEVICE" in ''|*[!a-zA-Z0-9_.:-]*) echo 'LAN device not detected.' >&2; exit 1;; esac
addresses=$(ip -4 -o addr show dev "$LAN_DEVICE" | awk '$4 ~ /\/24$/ {sub(/\/24$/,"",$4); print $4}')
[ -n "$addresses" ] || { echo 'No IPv4 /24 LAN detected.' >&2; exit 1; }
count=$(printf '%s\n' "$addresses" | awk 'NF{n++} END{print n+0}')
if [ "$count" -eq 1 ]; then addr=$addresses; else
 echo "Available /24 addresses on $LAN_DEVICE:"
 printf '%s\n' "$addresses"
 printf 'Enter the LAN address to monitor: '
 read -r addr
 printf '%s\n' "$addresses" | grep -Fxq "$addr" || { echo 'Invalid address.' >&2; exit 1; }
fi
LAN_PREFIX=${addr%.*}
green=; dim=; reset=;
printf '\n  %sNETWORK DETECTED%s\n\n  Network       %s.0/24\n  Interface     %s\n' "$green" "$reset" "$LAN_PREFIX" "$LAN_DEVICE"
printf '\n  %sLAN GATEWAY%s\n\n  Enter the address of the router managing the network.\n  Examples: 192.168.0.1  or  192.168.1.254\n  LAN WATCH uses this address for reverse DNS name lookups.\n  The gateway must also provide a local DNS service.\n  Press Enter without an address to skip name lookup.\n\n  %s>%s Gateway IP: ' "$green" "$reset" "$green" "$reset"
read -r LAN_DNS
if [ -n "$LAN_DNS" ]; then
 case "$LAN_DNS" in "$LAN_PREFIX".*) ;; *) echo 'Gateway must be in the selected /24 LAN.' >&2; exit 1;; esac
 printf '%s\n' "$LAN_DNS" | awk -F. 'NF!=4{exit 1}{for(i=1;i<=4;i++)if($i !~ /^[0-9]+$/ || $i>255)exit 1}' || { echo 'Invalid gateway IP.' >&2; exit 1; }

fi
printf '\n  DASHBOARD PORT\n\n  Choose a TCP port from 1024 to 65535. Enter = 65335.\n  The port is not a password: use only a trusted LAN or VPN.\n\n  > Port [65335]: '
read -r LAN_PORT
LAN_PORT=${LAN_PORT:-65335}
case "$LAN_PORT" in 0*|*[!0-9]*|??????*) echo 'Invalid port: use a number from 1024 to 65535.' >&2; exit 1;; esac
[ "$LAN_PORT" -ge 1024 ] && [ "$LAN_PORT" -le 65535 ] || { echo 'Invalid port: use a number from 1024 to 65535.' >&2; exit 1; }
if [ "${LAN_WATCH_PREVIEW:-0}" = 1 ]; then
 printf '\n  %sCONFIGURATION%s\n\n' "$green" "$reset"
 printf '  Network       %s.0/24\n  Interface     %s\n  Gateway       %s\n  Port          %s\n  Access        no password\n' "$LAN_PREFIX" "$LAN_DEVICE" "${LAN_DNS:-not set}" "$LAN_PORT"
 printf '\n  %sOPEN IN YOUR BROWSER%s\n\n  %shttp://%s:%s/%s\n\n' "$green" "$reset" "$green" "$addr" "$LAN_PORT" "$reset"
 printf '  Preview: no changes made.\n  To install: sh lwinstall.sh\n\n'
 exit 0
fi
# Refuse an invalid existing device archive without modifying or deleting it.
if [ -f /root/lan-monitor-data/devices.tsv ] && ! awk -F '\t' '
  function validmac(s,a,n,i) {
    n=split(s,a,":"); if(n!=6) return 0;
    for(i=1;i<=6;i++) if(a[i] !~ /^[[:xdigit:]][[:xdigit:]]$/) return 0;
    return 1
  }
  NF!=7 || !validmac($1) {bad=1}
  END {exit bad?1:0}
' /root/lan-monitor-data/devices.tsv; then
  echo 'Archivio dispositivi non valido: dati conservati; installazione interrotta. / Invalid device archive: data preserved; installation stopped.' >&2
  exit 1
fi
# Shared with upgrades; never guess whether an existing lock is stale.
INSTALL_LOCK=/var/run/aaaia-lan-watch-install.lock
if ! mkdir "$INSTALL_LOCK" 2>/dev/null; then echo 'Installation lock exists / Blocco installazione presente.' >&2; exit 1; fi
release_install_lock() { rmdir "$INSTALL_LOCK" 2>/dev/null || :; }
trap release_install_lock EXIT
trap 'exit 1' HUP INT TERM
[ ! -e /usr/lib/aaaia-lan-monitor ] && [ ! -e /etc/init.d/aaaia-lan-monitor ] && [ ! -e /etc/aaaia-lan-monitor.conf ] || { echo 'Monitor already installed: no changes made.' >&2; exit 1; }
if ! listen_state=$(netstat -lnt 2>/dev/null); then
 echo 'Cannot inspect listening ports / Impossibile verificare le porte.' >&2; exit 1
fi
if printf '%s\n' "$listen_state" | awk -v p=":$LAN_PORT" 'substr($4,length($4)-length(p)+1)==p {found=1} END {exit !found}'; then
 echo "Port $LAN_PORT already in use; installation stopped." >&2
 exit 1
fi
if ! command -v wget >/dev/null; then echo 'wget is required to verify the dashboard.' >&2; exit 1; fi
if [ -n "$LAN_DNS" ] && ! command -v dig >/dev/null; then echo 'Installing bind-dig...'; apk add bind-dig; fi
if ! command -v arping >/dev/null; then echo 'Installing iputils-arping...'; apk add iputils-arping; fi
command -v arping >/dev/null || { echo 'arping unavailable.' >&2; exit 1; }
if [ -n "$LAN_DNS" ]; then command -v dig >/dev/null || { echo 'dig unavailable.' >&2; exit 1; }; fi
arping --help 2>&1 | grep -q -- '-I' || { echo 'Incompatible arping.' >&2; exit 1; }
umask 077
verify_file=
rollback_install() {
  result=$?
  trap - EXIT HUP INT TERM
  [ -z "$verify_file" ] || rm -f "$verify_file"
  if [ "$result" -ne 0 ]; then
    echo 'Installation failed / Installazione fallita.' >&2
    safe=1
    if [ -x /etc/init.d/aaaia-lan-monitor ]; then
      /etc/init.d/aaaia-lan-monitor stop || safe=0
      /etc/init.d/aaaia-lan-monitor disable || safe=0
      stopped=0
      # procd can delete instances asynchronously after stop; '{}' is fully stopped.
      for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if ! service_state=$(ubus call service list '{"name":"aaaia-lan-monitor"}' 2>/dev/null); then safe=0; break; fi
        compact=$(printf '%s' "$service_state" | awk '{gsub(/[ \t\r\n]/,""); printf "%s",$0}')
        if [ "$compact" = '{}' ]; then stopped=1; break; fi
        monitor_state=$(printf '%s' "$service_state" | jsonfilter -e '@["aaaia-lan-monitor"].instances.monitor.running' 2>/dev/null) || monitor_state=unknown
        web_state=$(printf '%s' "$service_state" | jsonfilter -e '@["aaaia-lan-monitor"].instances.web.running' 2>/dev/null) || web_state=unknown
        if [ "$monitor_state" = false ] && [ "$web_state" = false ]; then stopped=1; break; fi
        [ "$attempt" -eq 10 ] || sleep 1
      done
      [ "$stopped" -eq 1 ] || safe=0
    fi
    if [ "$safe" -eq 1 ]; then
      rm -f /etc/init.d/aaaia-lan-monitor /etc/aaaia-lan-monitor.conf
      rm -rf /usr/lib/aaaia-lan-monitor
    else
      echo 'Service may still be active; files retained for recovery / Servizio forse attivo: file conservati.' >&2
    fi
  fi
  release_install_lock
}
trap rollback_install EXIT
mkdir -p /usr/lib/aaaia-lan-monitor/www/cgi-bin
cp payload/monitor.sh /usr/lib/aaaia-lan-monitor/monitor.sh
cp VERSION /usr/lib/aaaia-lan-monitor/VERSION
cp payload/www/index-en.html /usr/lib/aaaia-lan-monitor/www/index.html
cp payload/www/cgi-bin/status /usr/lib/aaaia-lan-monitor/www/cgi-bin/status
cp payload/aaaia-lan-monitor.init /etc/init.d/aaaia-lan-monitor
chmod 755 /usr/lib/aaaia-lan-monitor/monitor.sh /usr/lib/aaaia-lan-monitor/www/cgi-bin/status /etc/init.d/aaaia-lan-monitor
chmod 755 /usr/lib/aaaia-lan-monitor /usr/lib/aaaia-lan-monitor/www /usr/lib/aaaia-lan-monitor/www/cgi-bin
chmod 644 /usr/lib/aaaia-lan-monitor/www/index.html
printf 'LAN_DEVICE="%s"\nLAN_PREFIX="%s"\nLAN_IP="%s"\nLAN_DNS="%s"\nLAN_PORT="%s"\n' "$LAN_DEVICE" "$LAN_PREFIX" "$addr" "$LAN_DNS" "$LAN_PORT" > /etc/aaaia-lan-monitor.conf
/etc/init.d/aaaia-lan-monitor enable
/etc/init.d/aaaia-lan-monitor start
sleep 2
if ! netstat -lnt 2>/dev/null | awk -v a="$addr:$LAN_PORT" '$4==a {ok=1} END {exit !ok}'; then
 echo 'Dashboard failed to start; check logread and service status.' >&2
 exit 1
fi
# Verify both services and the CGI independently of the listening socket.
state=$(ubus call service list '{"name":"aaaia-lan-monitor"}')
monitor=$(printf '%s' "$state" | jsonfilter -e '@["aaaia-lan-monitor"].instances.monitor.running')
web=$(printf '%s' "$state" | jsonfilter -e '@["aaaia-lan-monitor"].instances.web.running')
[ "$monitor" = true ] && [ "$web" = true ] || { echo 'Service verification failed.' >&2; exit 1; }
verify_file=$(mktemp /tmp/lan-watch-verify.XXXXXX)
wget -q -T 3 -O "$verify_file" "http://$addr:$LAN_PORT/cgi-bin/status" || { echo 'Dashboard verification failed.' >&2; exit 1; }
grep -q '^#DEVICES$' "$verify_file" || { echo 'Dashboard returned invalid data.' >&2; exit 1; }
rm -f "$verify_file"
verify_file=
printf '\nInstallation complete.\n\n  Scanner and dashboard: processes verified\n  Dashboard and API: response verified\n  First scan: not yet verified; allow a few minutes.\n\n  Open in a browser on the same LAN:\n\n  http://%s:%s/\n\n  No password: anyone who can reach the dashboard can read its data.\n  VPN access requires existing configuration and permission to reach the LAN IP.\n  No firewall rules were changed. Do not expose the dashboard to the WAN.\n' "$addr" "$LAN_PORT"
release_install_lock
trap - EXIT HUP INT TERM
printf 'Check logs with: logread -e aaaia-lan-monitor\n'
