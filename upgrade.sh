#!/bin/sh
# Upgrade an existing installation while retaining its configuration and history.
# Upgrade without replacing configuration or historical data.
set -eu
cd "$(dirname "$0")"
APP=/usr/lib/aaaia-lan-monitor
INIT=/etc/init.d/aaaia-lan-monitor
CONFIG=/etc/aaaia-lan-monitor.conf
[ "$(id -u)" -eq 0 ] || { echo 'Root required / Esegui come root.' >&2; exit 1; }
[ -r /etc/openwrt_release ] || { echo 'OpenWrt release unavailable.' >&2; exit 1; }
. /etc/openwrt_release
case "${DISTRIB_RELEASE:-}" in 25.12.*|25.12-SNAPSHOT|v0.64.3-3K) ;; *) echo 'Unsupported release / Versione non supportata.' >&2; exit 1;; esac
for f in "$APP/monitor.sh" "$APP/www/index.html" "$APP/www/cgi-bin/status" "$INIT" "$CONFIG" VERSION payload/monitor.sh payload/aaaia-lan-monitor.init payload/www/cgi-bin/status; do
 [ -f "$f" ] || { echo "Missing required file / File mancante: $f" >&2; exit 1; }
done
if grep -q '<html lang="it"' "$APP/www/index.html"; then
 language=it
elif grep -q '<html lang="en"' "$APP/www/index.html"; then
 language=en
else
 echo 'Cannot determine installed language; no changes made. / Lingua installata non riconosciuta; nessuna modifica.' >&2
 exit 1
fi
[ -f "payload/www/index-$language.html" ] || { echo 'Missing language file.' >&2; exit 1; }
version=$(cat VERSION)
oldversion=$(cat "$APP/VERSION" 2>/dev/null || printf '%s' 'legacy')
case "$version" in ''|*[!0-9.]*) echo 'Invalid package version.' >&2; exit 1;; esac
case "$oldversion" in legacy) ;; ''|*[!0-9.]*) echo 'Unknown installed version; no changes made.' >&2; exit 1;; esac
# The 1.0, 1.0.1 and 1.0.2 experimental builds were published before
# adopting the 0.1 version scheme. Only this explicit migration to 0.1 is
# exempt from the numeric downgrade check; all other downgrades are refused.
renumbered=0
case "$oldversion:$version" in
  1.0:0.1|1.0.1:0.1|1.0.2:0.1) renumbered=1;;
esac
if [ "$oldversion" != legacy ] && [ "$renumbered" -eq 0 ] && ! awk -v a="$oldversion" -v b="$version" 'BEGIN {na=split(a,x,".");nb=split(b,y,"."); n=na>nb?na:nb;for(i=1;i<=n;i++){if(x[i]+0>y[i]+0)exit 1;if(x[i]+0<y[i]+0)exit 0}exit 0}'; then
 echo 'Installed version is newer; downgrade refused. / Versione installata più recente: downgrade rifiutato.' >&2
 exit 1
fi
# Corrupted device identities cannot be migrated safely or silently merged.
DEVICE_STATE=/root/lan-monitor-data/devices.tsv
if [ -e "$DEVICE_STATE" ]; then
 [ -r "$DEVICE_STATE" ] || { echo 'Cannot read device history; no changes made / Storico dispositivi non leggibile; nessuna modifica.' >&2; exit 1; }
 if ! awk -F '\t' '
  function validmac(s,a,n,i) { n=split(s,a,":"); if(n!=6)return 0; for(i=1;i<=6;i++)if(a[i] !~ /^[[:xdigit:]][[:xdigit:]]$/)return 0; return 1 }
  NF!=7 || !validmac($1) {bad=1} END {exit bad?1:0}
 ' "$DEVICE_STATE"; then
  echo 'Malformed device records: preserve and inspect history before updating; no changes made / Record MAC malformati: conservare e verificare lo storico prima di aggiornare; nessuna modifica.' >&2
  exit 1
 fi
fi
# Read, validate and do not execute installed config.
lan_ip=$(sed -n 's/^LAN_IP="\([0-9.]*\)"$/\1/p' "$CONFIG")
if [ -z "$lan_ip" ] || ! printf '%s\n' "$lan_ip" | awk -F. 'NF!=4{exit 1}{for(i=1;i<=4;i++)if($i !~ /^[0-9]+$/ || $i>255)exit 1}'; then echo 'Invalid LAN_IP in existing config.' >&2; exit 1; fi
port_lines=$(grep -c '^LAN_PORT=' "$CONFIG" || :)
case "$port_lines" in
 0) lan_port=59876;;
 1) lan_port=$(sed -n 's/^LAN_PORT="\([0-9]*\)"$/\1/p' "$CONFIG");;
 *) echo 'Invalid LAN_PORT in existing config.' >&2; exit 1;;
esac
case "$lan_port" in ''|0*|*[!0-9]*|??????*) echo 'Invalid LAN_PORT in existing config.' >&2; exit 1;; esac
[ "$lan_port" -ge 1024 ] && [ "$lan_port" -le 65535 ] || { echo 'Invalid LAN_PORT in existing config.' >&2; exit 1; }
if [ "$oldversion" = legacy ]; then
 if [ "$language" = it ]; then
  oldversion_display='sconosciuta (VERSION assente)'
  echo '  Impossibile verificare un eventuale downgrade: versione precedente sconosciuta.' >&2
 else
  oldversion_display='unknown (VERSION missing)'
  echo '  Cannot verify whether this is a downgrade: installed version is unknown.' >&2
 fi
else
 oldversion_display=$oldversion
fi
if [ "$language" = it ]; then
 printf '\n  LAN WATCH — AGGIORNAMENTO\n\n  Versione installata: %s\n  Versione disponibile: %s\n  Lingua: Italiano\n  Pannello: http://%s:%s/\n\n  Configurazione e storico saranno conservati.\n' "$oldversion_display" "$version" "$lan_ip" "$lan_port"
else
 printf '\n  LAN WATCH — UPDATE\n\n  Installed version: %s\n  Available version: %s\n  Language: English\n  Dashboard: http://%s:%s/\n\n  Configuration and history will be preserved.\n' "$oldversion_display" "$version" "$lan_ip" "$lan_port"
fi
needs_dns=0
if ! grep -q '^LAN_DNS=' "$CONFIG"; then
 needs_dns=1
 echo 'Gateway for DNS missing in existing configuration; update will ask explicitly / Gateway DNS assente: verra richiesto esplicitamente.'
fi
if [ "$renumbered" -eq 1 ]; then
 if [ "$language" = it ]; then
  echo '  Rinumerazione: questa versione sperimentale passa alla serie 0.1.'
 else
  echo '  Version renumbering: this experimental build moves to the 0.1 series.'
 fi
fi
if [ "${LAN_WATCH_PREVIEW:-0}" = 1 ]; then
 if [ "$language" = it ]; then echo '  Anteprima: nessuna modifica eseguita.'; else echo '  Preview: no changes made.'; fi
 exit 0
fi
if [ "$language" = it ]; then printf '\n  Aggiornare? [s/N]: '; else printf '\n  Update? [y/N]: '; fi
read -r answer
case "$language:$answer" in it:s|it:S|en:y|en:Y) ;; *) echo 'Annullato / Cancelled.'; exit 0;; esac
if [ "$needs_dns" -eq 1 ]; then
 if [ "$language" = it ]; then printf 'IP del gateway per i nomi (Invio per disabilitare ricerca nomi): '; else printf 'Gateway IP for names (Enter to disable name lookups): '; fi
 read -r chosen_dns
 if [ -n "$chosen_dns" ]; then
  lan_prefix=${lan_ip%.*}
  case "$chosen_dns" in "$lan_prefix".*) ;; *) echo 'Gateway must be in the monitored /24 / Gateway fuori dalla rete /24.' >&2; exit 1;; esac
  printf '%s\n' "$chosen_dns" | awk -F. 'NF!=4{exit 1}{for(i=1;i<=4;i++)if($i !~ /^[0-9]+$/ || $i>255)exit 1}' || { echo 'Invalid gateway.' >&2; exit 1; }
  command -v dig >/dev/null || { echo 'dig required for name lookups / Serve dig per i nomi.' >&2; exit 1; }
 fi
fi
INSTALL_LOCK=/var/run/aaaia-lan-watch-install.lock
if ! mkdir "$INSTALL_LOCK" 2>/dev/null; then echo 'Installation lock exists / Blocco installazione presente.' >&2; exit 1; fi
release_install_lock() { rmdir "$INSTALL_LOCK" 2>/dev/null || :; }
trap release_install_lock EXIT
trap 'exit 1' HUP INT TERM
if ! command -v ubus >/dev/null || ! command -v jsonfilter >/dev/null || ! command -v wget >/dev/null; then echo 'Missing verification tools: ubus/jsonfilter/wget.' >&2; exit 1; fi
for f in payload/monitor.sh payload/aaaia-lan-monitor.init payload/www/cgi-bin/status; do sh -n "$f" || exit 1; done
# Stage and keep the old tree under the same parent filesystem as APP.
# mv of the tree is then an atomic rename, not a cross-filesystem copy.
[ -d "$APP" ] && [ ! -L "$APP" ] || { echo 'Application directory is not a real directory.' >&2; exit 1; }
umask 077
work=$(mktemp -d /usr/lib/.lan-watch-upgrade.XXXXXX) || exit 1
stop_attempted=0
was_running=0
was_enabled=0
config_migrated=0
restart_safe=1
config_tmp=
rollback() {
 code=$?
 trap - EXIT HUP INT TERM
 if [ "$code" -ne 0 ]; then
  echo 'Update failed: attempting rollback / Aggiornamento fallito: ripristino in corso.' >&2
  if [ -d "$work/previous" ]; then
   # Never replace files while the new service may still be running.
   if ! "$INIT" stop >/dev/null 2>&1; then
    echo "Cannot stop updated service; recovery files retained at $work" >&2; release_install_lock; exit 1
   fi
   # procd may return {} or temporarily omit an instance after stop.
   stopped=0
   for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if ! service_state=$(ubus call service list '{"name":"aaaia-lan-monitor"}' 2>/dev/null); then
     echo "Cannot inspect service; recovery files retained at $work" >&2; release_install_lock; exit 1
    fi
    compact=$(printf '%s' "$service_state" | awk '{gsub(/[ \t\r\n]/,"");printf "%s",$0}')
    if [ "$compact" = '{}' ]; then stopped=1; break; fi
    running_monitor=$(printf '%s' "$service_state" | jsonfilter -e '@["aaaia-lan-monitor"].instances.monitor.running' 2>/dev/null) || running_monitor=unknown
    running_web=$(printf '%s' "$service_state" | jsonfilter -e '@["aaaia-lan-monitor"].instances.web.running' 2>/dev/null) || running_web=unknown
    if [ "$running_monitor" = false ] && [ "$running_web" = false ]; then stopped=1; break; fi
    [ "$attempt" -eq 10 ] || sleep 1
   done
   if [ "$stopped" -ne 1 ]; then echo "Updated service state uncertain; recovery files retained at $work" >&2; release_install_lock; exit 1; fi
   for proc_cmd in /proc/[0-9]*/cmdline; do
    [ -r "$proc_cmd" ] || continue
    if tr '\000' ' ' < "$proc_cmd" 2>/dev/null | grep -Fq "$APP/monitor.sh"; then
     echo "Scanner still active; recovery files retained at $work" >&2; release_install_lock; exit 1
    fi
   done
   if ! listen_state=$(netstat -lnt 2>/dev/null); then echo "Cannot inspect ports; recovery files retained at $work" >&2; release_install_lock; exit 1; fi
   if printf '%s\n' "$listen_state" | awk -v p=":$lan_port" 'substr($4,length($4)-length(p)+1)==p {found=1} END {exit !found}'; then
    echo "Dashboard port still active; recovery files retained at $work" >&2; release_install_lock; exit 1
   fi
   if ! rm -rf "$APP" || [ -e "$APP" ]; then
    echo "Cannot clear failed update; backup retained at $work" >&2; release_install_lock; exit 1
   fi
   mv "$work/previous" "$APP" || { echo "Restore failed; backup retained at $work" >&2; release_install_lock; exit 1; }
   cp "$work/previous.init" "$INIT" || { echo "Restore init failed; backup retained at $work" >&2; release_install_lock; exit 1; }
   chmod 755 "$INIT" || { echo "Restore permissions failed; backup retained at $work" >&2; release_install_lock; exit 1; }
   if [ "$was_enabled" -eq 1 ]; then "$INIT" enable || :; else "$INIT" disable || :; fi
  fi
  if [ "$config_migrated" -eq 1 ]; then
   if cmp -s "$CONFIG" "$work/new.conf" || cmp -s "$CONFIG" "$work/previous.conf"; then
    [ -n "$config_tmp" ] || config_tmp=$(mktemp /etc/.lan-watch-config.XXXXXX) || { echo "Cannot stage config; recovery files retained at $work" >&2; release_install_lock; exit 1; }
    if ! cp "$work/previous.conf" "$config_tmp" || ! chmod 600 "$config_tmp" || ! mv "$config_tmp" "$CONFIG"; then
     echo "Configuration restore failed; recovery files retained at $work" >&2; release_install_lock; exit 1
    fi
    config_tmp=
   else
    echo "Configuration changed externally; recovery files retained at $work" >&2; release_install_lock; exit 1
   fi
  fi
  # Even if stop or the first rename failed, restore the previous running state.
  if [ "$stop_attempted" -eq 1 ] && [ "$was_running" -eq 1 ] && [ "$restart_safe" -eq 1 ]; then
   if ! "$INIT" start; then
    echo "Previous service could not be restarted; recovery files retained at $work" >&2
    release_install_lock; exit 1
   fi
  fi
 fi
 [ -z "$config_tmp" ] || rm -f "$config_tmp"
 rm -rf "$work"
 release_install_lock
 exit "$code"
}
trap rollback EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$work/new/www/cgi-bin"
cp payload/monitor.sh "$work/new/monitor.sh"
cp "payload/www/index-$language.html" "$work/new/www/index.html"
cp payload/www/cgi-bin/status "$work/new/www/cgi-bin/status"
cp VERSION "$work/new/VERSION"
chmod 755 "$work/new" "$work/new/www" "$work/new/www/cgi-bin" "$work/new/monitor.sh" "$work/new/www/cgi-bin/status"
chmod 644 "$work/new/www/index.html" "$work/new/VERSION"
cp "$INIT" "$work/previous.init"
cp "$CONFIG" "$work/previous.conf"
cp "$CONFIG" "$work/new.conf"
if [ "$needs_dns" -eq 1 ]; then printf '\nLAN_DNS="%s"\n' "$chosen_dns" >> "$work/new.conf"; fi
"$INIT" enabled && was_enabled=1
if "$INIT" status 2>/dev/null | grep -q '^running'; then was_running=1; fi
stop_attempted=1
"$INIT" stop
# procd may return before the old listener releases its socket.
# Wait briefly, but never replace files or start a second service while it remains occupied.
port_released=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
 if ! listen_state=$(netstat -lnt 2>/dev/null); then
  restart_safe=0; echo "Cannot inspect listening ports; update stopped." >&2; exit 1
 fi
 if ! printf '%s\n' "$listen_state" | awk -v p=":$lan_port" 'substr($4,length($4)-length(p)+1)==p {found=1} END {exit !found}'; then
  port_released=1; break
 fi
 [ "$attempt" -eq 10 ] || sleep 1
done
if [ "$port_released" -ne 1 ]; then
 restart_safe=0
 echo 'Port remains occupied after stop; update cancelled; inspect service before restarting.' >&2
 exit 1
fi
# A stopped procd service can leave the previous scanner shell alive.
# Never replace its code or start a second collector until it has exited.
scanner_stopped=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
 scanner_alive=0
 for proc_cmd in /proc/[0-9]*/cmdline; do
  [ -r "$proc_cmd" ] || continue
  if tr '\000' ' ' < "$proc_cmd" 2>/dev/null | grep -Fq "$APP/monitor.sh"; then scanner_alive=1; break; fi
 done
 if [ "$scanner_alive" -eq 0 ]; then scanner_stopped=1; break; fi
 [ "$attempt" -eq 10 ] || sleep 1
done
if [ "$scanner_stopped" -ne 1 ]; then
 restart_safe=0
 echo 'Previous scanner still active: update stopped without replacing files; inspect service before restarting / Scanner precedente ancora attivo: aggiornamento interrotto senza sostituire file; verificare il servizio.' >&2
 exit 1
fi
mv "$APP" "$work/previous"
mv "$work/new" "$APP"
cp payload/aaaia-lan-monitor.init "$INIT"
chmod 755 "$INIT"
if [ "$needs_dns" -eq 1 ]; then
 cmp -s "$CONFIG" "$work/previous.conf" || { echo 'Configuration changed externally; update cancelled.' >&2; exit 1; }
 config_tmp=$(mktemp /etc/.lan-watch-config.XXXXXX) || exit 1
 cp "$work/new.conf" "$config_tmp"
 chmod 600 "$config_tmp"
 config_migrated=1
 mv "$config_tmp" "$CONFIG"
 config_tmp=
fi
"$INIT" start
sleep 3
# Verify both procd instances and the HTTP CGI; do not rely only on a listening port.
state=$(ubus call service list '{"name":"aaaia-lan-monitor"}')
monitor=$(printf '%s' "$state" | jsonfilter -e '@["aaaia-lan-monitor"].instances.monitor.running')
web=$(printf '%s' "$state" | jsonfilter -e '@["aaaia-lan-monitor"].instances.web.running')
[ "$monitor" = true ] && [ "$web" = true ] || { echo 'Service verification failed.' >&2; exit 1; }
wget -q -T 3 -O "$work/status" "http://$lan_ip:$lan_port/cgi-bin/status" || { echo 'Dashboard verification failed.' >&2; exit 1; }
grep -q '^#DEVICES$' "$work/status" || { echo 'Dashboard returned invalid data.' >&2; exit 1; }
cmp -s "$CONFIG" "$work/new.conf" || { echo 'Configuration changed during update; inspect before proceeding.' >&2; exit 1; }
trap - EXIT HUP INT TERM
rm -rf "$work"
release_install_lock
if [ "$language" = it ]; then printf '\n  Aggiornamento completato: v%s\n  http://%s:%s/\n' "$version" "$lan_ip" "$lan_port"; else printf '\n  Update completed: v%s\n  http://%s:%s/\n' "$version" "$lan_ip" "$lan_port"; fi
