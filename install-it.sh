#!/bin/sh
# Interactive Italian installation and preview.
set -eu
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || { echo 'Esegui come root.' >&2; exit 1; }
[ -r /etc/openwrt_release ] || { echo 'Questo non sembra OpenWrt.' >&2; exit 1; }
. /etc/openwrt_release
case "${DISTRIB_RELEASE:-}" in 25.12.*|25.12-SNAPSHOT|v0.64.3-3K) ;; *) echo "Richiesto OpenWrt 25.12.x; rilevato ${DISTRIB_RELEASE:-sconosciuto}." >&2; exit 1;; esac
command -v apk >/dev/null && command -v ubus >/dev/null && command -v jsonfilter >/dev/null && command -v ip >/dev/null && [ -x /usr/sbin/uhttpd ] || { echo 'Mancano apk, ubus, jsonfilter, ip o uhttpd: installazione interrotta.' >&2; exit 1; }
status=$(ubus call network.interface.lan status) || { echo 'Interfaccia logica lan non disponibile.' >&2; exit 1; }
LAN_DEVICE=$(printf '%s' "$status" | jsonfilter -e '@.l3_device')
[ -n "$LAN_DEVICE" ] || LAN_DEVICE=$(printf '%s' "$status" | jsonfilter -e '@.device')
case "$LAN_DEVICE" in ''|*[!a-zA-Z0-9_.:-]*) echo 'Dispositivo LAN non rilevato.' >&2; exit 1;; esac
addresses=$(ip -4 -o addr show dev "$LAN_DEVICE" | awk '$4 ~ /\/24$/ {sub(/\/24$/,"",$4); print $4}')
[ -n "$addresses" ] || { echo 'Nessuna LAN IPv4 /24 rilevata.' >&2; exit 1; }
count=$(printf '%s\n' "$addresses" | awk 'NF{n++} END{print n+0}')
if [ "$count" -eq 1 ]; then addr=$addresses; else
 echo "Indirizzi /24 disponibili su $LAN_DEVICE:"
 printf '%s\n' "$addresses"
 printf 'Inserisci indirizzo LAN da monitorare: '
 read -r addr
 printf '%s\n' "$addresses" | grep -Fxq "$addr" || { echo 'Indirizzo non valido.' >&2; exit 1; }
fi
LAN_PREFIX=${addr%.*}
green=; dim=; reset=;
printf '\n  %sRETE RILEVATA%s\n\n  Rete          %s.0/24\n  Interfaccia   %s\n' "$green" "$reset" "$LAN_PREFIX" "$LAN_DEVICE"
printf '\n  %sGATEWAY DELLA LAN%s\n\n  Inserisci l’indirizzo del router che gestisce la rete.\n  Esempi: 192.168.0.1  oppure  192.168.1.254\n  Per cercare i nomi, LAN WATCH interroga questo indirizzo tramite DNS inverso.\n  Il gateway deve offrire anche un servizio DNS locale.\n  Invio senza indirizzo: scansione senza ricerca dei nomi.\n\n  %s>%s IP gateway: ' "$green" "$reset" "$green" "$reset"
read -r LAN_DNS
if [ -n "$LAN_DNS" ]; then
 case "$LAN_DNS" in "$LAN_PREFIX".*) ;; *) echo 'Il gateway deve appartenere alla rete /24 selezionata.' >&2; exit 1;; esac
 printf '%s\n' "$LAN_DNS" | awk -F. 'NF!=4{exit 1}{for(i=1;i<=4;i++)if($i !~ /^[0-9]+$/ || $i>255)exit 1}' || { echo 'IP gateway non valido.' >&2; exit 1; }

fi
printf '\n  PORTA DEL PANNELLO\n\n  Scegli una porta TCP tra 1024 e 65535. Invio = 65335.\n  La porta non e una password: usa solo LAN o VPN fidata.\n\n  > Porta [65335]: '
read -r LAN_PORT
LAN_PORT=${LAN_PORT:-65335}
case "$LAN_PORT" in 0*|*[!0-9]*|??????*) echo 'Porta non valida: usare un numero tra 1024 e 65535.' >&2; exit 1;; esac
[ "$LAN_PORT" -ge 1024 ] && [ "$LAN_PORT" -le 65535 ] || { echo 'Porta non valida: usare un numero tra 1024 e 65535.' >&2; exit 1; }
if [ "${LAN_WATCH_PREVIEW:-0}" = 1 ]; then
 printf '\n  %sCONFIGURAZIONE%s\n\n' "$green" "$reset"
 printf '  Rete          %s.0/24\n  Interfaccia   %s\n  Gateway       %s\n  Porta         %s\n  Accesso       senza password\n' "$LAN_PREFIX" "$LAN_DEVICE" "${LAN_DNS:-non impostato}" "$LAN_PORT"
 printf '\n  %sAPRI NEL BROWSER%s\n\n  %shttp://%s:%s/%s\n\n' "$green" "$reset" "$green" "$addr" "$LAN_PORT" "$reset"
 printf '  Anteprima: nessuna modifica eseguita.\n  Per installare: sh lwinstall.sh\n\n'
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
[ ! -e /usr/lib/aaaia-lan-monitor ] && [ ! -e /etc/init.d/aaaia-lan-monitor ] && [ ! -e /etc/aaaia-lan-monitor.conf ] || { echo 'Monitor già installato: nessuna modifica.' >&2; exit 1; }
if ! listen_state=$(netstat -lnt 2>/dev/null); then
 echo 'Cannot inspect listening ports / Impossibile verificare le porte.' >&2; exit 1
fi
if printf '%s\n' "$listen_state" | awk -v p=":$LAN_PORT" 'substr($4,length($4)-length(p)+1)==p {found=1} END {exit !found}'; then
 echo "Porta $LAN_PORT gia occupata: installazione interrotta." >&2
 exit 1
fi
if ! command -v wget >/dev/null; then echo 'wget is required to verify the dashboard.' >&2; exit 1; fi
if [ -n "$LAN_DNS" ] && ! command -v dig >/dev/null; then echo 'Installazione bind-dig...'; apk add bind-dig; fi
if ! command -v arping >/dev/null; then echo 'Installazione iputils-arping...'; apk add iputils-arping; fi
command -v arping >/dev/null || { echo 'arping non disponibile.' >&2; exit 1; }
if [ -n "$LAN_DNS" ]; then command -v dig >/dev/null || { echo 'dig non disponibile.' >&2; exit 1; }; fi
arping --help 2>&1 | grep -q -- '-I' || { echo 'arping non compatibile.' >&2; exit 1; }
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
cp payload/www/index-it.html /usr/lib/aaaia-lan-monitor/www/index.html
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
 echo 'Avvio del pannello fallito: controlla logread e lo stato del servizio.' >&2
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
printf '\nInstallazione completata.\n\n  Scanner e pannello: processi verificati\n  Pannello e API: risposta verificata\n  Prima scansione: non ancora verificata; attendi qualche minuto.\n\n  Apri dal browser sulla stessa LAN:\n\n  http://%s:%s/\n\n  Accesso senza password: chi raggiunge il pannello puo leggere i dati.\n  Via VPN funziona solo se gia configurata e autorizzata verso l’IP LAN.\n  Nessuna regola firewall e stata modificata. Non esporre il pannello sulla WAN.\n' "$addr" "$LAN_PORT"
release_install_lock
trap - EXIT HUP INT TERM
printf 'Controlla i log con: logread -e aaaia-lan-monitor\n'
