#!/bin/sh
# Remove LAN WATCH while preserving recorded history and installed dependencies.
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Esegui come root / Run as root.' >&2; exit 1; }
# Shared with install and upgrade. An existing lock is never assumed stale.
INSTALL_LOCK=/var/run/aaaia-lan-watch-install.lock
if ! mkdir "$INSTALL_LOCK" 2>/dev/null; then
 echo 'Operazione già in corso o blocco da verificare / Operation in progress or lock needs inspection.' >&2
 exit 1
fi
release_install_lock() { rmdir "$INSTALL_LOCK" 2>/dev/null || :; }
trap release_install_lock EXIT
trap 'exit 1' HUP INT TERM
for tool in ubus jsonfilter netstat; do
 command -v "$tool" >/dev/null || { echo "Impossibile verificare il servizio: manca $tool / Cannot verify service." >&2; exit 1; }
done
CONFIG=/etc/aaaia-lan-monitor.conf
lan_port=59876
if [ -f "$CONFIG" ]; then
port_lines=$(grep -c '^LAN_PORT=' "$CONFIG" || :)
case "$port_lines" in
 0) lan_port=59876;;
 1) lan_port=$(sed -n 's/^LAN_PORT="\([0-9]*\)"$/\1/p' "$CONFIG");;
 *) echo 'Invalid LAN_PORT in existing config.' >&2; exit 1;;
esac
case "$lan_port" in ''|0*|*[!0-9]*|??????*) echo 'Invalid LAN_PORT in existing config.' >&2; exit 1;; esac
[ "$lan_port" -ge 1024 ] && [ "$lan_port" -le 65535 ] || { echo 'Invalid LAN_PORT in existing config.' >&2; exit 1; }
fi
if [ -x /etc/init.d/aaaia-lan-monitor ]; then
 if ! /etc/init.d/aaaia-lan-monitor stop; then
  echo 'Arresto fallito: file conservati / Stop failed: files retained.' >&2; exit 1
 fi
fi
# procd may remove the web instance before the scanner exits; wait for it to settle.
stopped=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
 if ! service_state=$(ubus call service list '{"name":"aaaia-lan-monitor"}' 2>/dev/null); then
  echo 'Impossibile verificare i processi: file conservati / Cannot verify processes; files retained.' >&2; exit 1
 fi
 compact=$(printf '%s' "$service_state" | awk '{gsub(/[ \t\r\n]/,""); printf "%s",$0}')
 if [ "$compact" = '{}' ]; then stopped=1; break; fi
 monitor_state=$(printf '%s' "$service_state" | jsonfilter -e '@["aaaia-lan-monitor"].instances.monitor.running' 2>/dev/null) || monitor_state=unknown
 web_state=$(printf '%s' "$service_state" | jsonfilter -e '@["aaaia-lan-monitor"].instances.web.running' 2>/dev/null) || web_state=unknown
 if [ "$monitor_state" = false ] && [ "$web_state" = false ]; then stopped=1; break; fi
 [ "$attempt" -eq 10 ] || sleep 1
done
[ "$stopped" -eq 1 ] || { echo 'Arresto non confermato: file conservati / Stop not confirmed; files retained.' >&2; exit 1; }
# procd may lose track of a surviving shell. Inspect Linux process command lines.
for proc_cmd in /proc/[0-9]*/cmdline; do
 [ -r "$proc_cmd" ] || continue
 if tr '\000' ' ' < "$proc_cmd" 2>/dev/null | grep -Fq '/usr/lib/aaaia-lan-monitor/monitor.sh'; then
  echo 'Scanner ancora attivo: file conservati / Scanner still active; files retained.' >&2; exit 1
 fi
done
if ! listen_state=$(netstat -lnt 2>/dev/null); then
 echo 'Stato porte non verificabile: file conservati / Cannot verify listening ports; files retained.' >&2; exit 1
fi
if printf '%s\n' "$listen_state" | awk -v p=":$lan_port" 'substr($4,length($4)-length(p)+1)==p {found=1} END {exit !found}'; then
 echo "Porta $lan_port ancora in uso: file conservati / Port still in use; files retained." >&2; exit 1
fi
if [ -x /etc/init.d/aaaia-lan-monitor ]; then
 if ! /etc/init.d/aaaia-lan-monitor disable; then
  echo 'Disattivazione fallita: file conservati / Disable failed; files retained.' >&2; exit 1
 fi
fi
rm -f /etc/init.d/aaaia-lan-monitor /etc/aaaia-lan-monitor.conf
rm -rf /usr/lib/aaaia-lan-monitor
printf '%s\n' 'Monitor rimosso. Storico conservato in /root/lan-monitor-data; pacchetti conservati.'
