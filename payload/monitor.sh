#!/bin/sh
# OpenWrt LAN monitor: run as root with an explicitly selected /24 interface.
set -eu
IFACE=${1:-}
PREFIX=${2:-}
DIR=${3:-/root/lan-monitor-data}
DNS_SERVER=${4:-}
INTERVAL=60
MIN_REST=3
MISSES=${MISSES:-3}
case "$IFACE" in ''|*[!a-zA-Z0-9_.:-]*) echo 'Interfaccia non valida' >&2; exit 1;; esac
[ -d "/sys/class/net/$IFACE" ] || { echo 'Interfaccia inesistente' >&2; exit 1; }
printf '%s\n' "$PREFIX" | awk -F. 'NF!=3 {exit 1} {for(i=1;i<=3;i++) if($i !~ /^[0-9]+$/ || $i>255) exit 1}' || { echo 'Prefisso /24 non valido' >&2; exit 1; }
if [ -n "$DNS_SERVER" ]; then
  case "$DNS_SERVER" in "$PREFIX".*) ;; *) echo 'Gateway outside monitored /24' >&2; exit 1;; esac
  printf '%s\n' "$DNS_SERVER" | awk -F. 'NF!=4{exit 1}{for(i=1;i<=4;i++)if($i !~ /^[0-9]+$/ || $i>255)exit 1}' || exit 1
fi
case "$MISSES" in ''|*[!0-9]*) echo 'Soglia non valida' >&2; exit 1;; esac
[ "$MISSES" -ge 2 ] || { echo 'Soglia minima 2' >&2; exit 1; }
if ! command -v arping >/dev/null || ! command -v ip >/dev/null; then echo 'Servono arping e ip' >&2; exit 1; fi
ip -4 -o addr show dev "$IFACE" | awk -v prefix="$PREFIX." '$4 ~ /\/24$/ && index($4,prefix)==1 {ok=1} END {exit !ok}' || { echo 'Interfaccia senza indirizzo /24 nel prefisso indicato' >&2; exit 1; }
umask 077
mkdir -p "$DIR"
LOCK=/var/run/aaaia-lan-monitor.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  oldpid=$(cat "$LOCK/pid" 2>/dev/null || :)
  case "$oldpid" in ''|*[!0-9]*) echo "Lock non verificabile: $LOCK" >&2; exit 1;; esac
  if kill -0 "$oldpid" 2>/dev/null; then echo 'Monitor già avviato' >&2; exit 1; fi
  rm -f "$LOCK/pid"
  rmdir "$LOCK" || exit 1
  mkdir "$LOCK" || exit 1
fi
printf '%s\n' "$$" > "$LOCK/pid"
scan_dir=
cleanup() {
  case "$scan_dir" in /tmp/lan-watch-scan.*) rm -rf "$scan_dir" ;; esac
  rm -f "$LOCK/pid"
  rmdir "$LOCK" 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 0' HUP INT TERM
[ -f "$DIR/devices.tsv" ] || : > "$DIR/devices.tsv"
[ -f "$DIR/events.tsv" ] || : > "$DIR/events.tsv"
export IFACE PREFIX DIR
# At least 60 seconds between starts and three seconds of rest after each cycle.
# An old interval preference is deliberately ignored and preserved on disk.
wait_until_next_scan() {
  finished=$(date +%s)
  # If the wall clock moved backward, begin a fresh conservative wait.
  [ "$finished" -ge "$started" ] || started=$finished
  elapsed=$((finished - started))
  delay=$((INTERVAL - elapsed))
  [ "$delay" -ge "$MIN_REST" ] || delay=$MIN_REST
  sleep "$delay"
}

while :; do
  started=$(date +%s)
  : > "$DIR/observed.tmp"
  : > "$DIR/probe-errors.tmp"
  scan_dir=$(mktemp -d /tmp/lan-watch-scan.XXXXXX) || { echo 'Impossibile preparare la scansione' > "$DIR/error"; wait_until_next_scan; continue; }
  # Bound concurrency to 16 ARP requests. Each successful reply supplies the MAC.
  probe_failed=0
  pids=
  i=1
  while [ "$i" -le 254 ]; do
    (
      ipaddr="$PREFIX.$i"
      rc=0
      response=$(arping -I "$IFACE" -c 1 -w 1 "$ipaddr" 2>/dev/null) || rc=$?
      if [ "$rc" -gt 1 ]; then printf 'error\n' > "$scan_dir/error.$i" || exit 1; exit 0; fi
      [ "$rc" -eq 0 ] || exit 0
      mac=$(printf '%s\n' "$response" | awk 'match($0,/([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}/){print tolower(substr($0,RSTART,RLENGTH));exit}')
      # BusyBox awk may not support interval expressions.
      [ -n "$mac" ] || mac=$(printf '%s\n' "$response" | tr '[]()' '    ' | awk '{for(i=1;i<=NF;i++) if($i ~ /^[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]$/){print tolower($i);exit}}')
      [ -n "$mac" ] || { printf 'error\n' > "$scan_dir/error.$i" || exit 1; exit 0; }
      printf '%s\t%s\n' "$mac" "$ipaddr" > "$scan_dir/host.$i" || exit 1
      exit 0
    ) &
    pids="$pids $!"
    if [ $((i % 16)) -eq 0 ]; then
      for pid in $pids; do wait "$pid" || probe_failed=1; done
      pids=
    fi
    i=$((i+1))
  done
  for pid in $pids; do wait "$pid" || probe_failed=1; done
  if [ "$probe_failed" -ne 0 ]; then
    rm -rf "$scan_dir"
    scan_dir=
    echo 'Errore raccolta risposte: scansione scartata' > "$DIR/error"
    wait_until_next_scan
    continue
  fi
  for file in "$scan_dir"/host.*; do [ ! -f "$file" ] || cat "$file" >> "$DIR/observed.tmp"; done
  for file in "$scan_dir"/error.*; do [ ! -f "$file" ] || printf 'error\n' >> "$DIR/probe-errors.tmp"; done
  rm -rf "$scan_dir"
  scan_dir=
  if [ -s "$DIR/probe-errors.tmp" ]; then echo "Errore arping: scansione scartata" > "$DIR/error"; wait_until_next_scan; continue; fi
  # OMR has DHCP disabled: obtain optional PTR names from the LAN DNS.
  : > "$DIR/names.tmp"
  if [ -n "$DNS_SERVER" ] && command -v dig >/dev/null; then
    while IFS="$(printf '\t')" read -r mac addr; do
      name=$(dig @"$DNS_SERVER" -x "$addr" +short +norecurse +time=1 +tries=1 2>/dev/null | head -n 1 | sed 's/\.$//;s/\.lan$//I')
      case "$name" in ''|*[!a-zA-Z0-9_.-]*) continue;; esac
      printf '%s\t%s\n' "$mac" "$name" >> "$DIR/names.tmp"
    done < "$DIR/observed.tmp"
  fi
  now=$(date +%s)
  : > "$DIR/leases.tmp"
  [ ! -r /tmp/dhcp.leases ] || cp /tmp/dhcp.leases "$DIR/leases.tmp"
  rm -f "$DIR/events.tmp"
  if [ ! -s "$DIR/observed.tmp" ] && [ -s "$DIR/devices.tsv" ]; then
    echo 'Scansione vuota: stato precedente conservato; verificare la rete.' > "$DIR/error"
    wait_until_next_scan
    continue
  fi
  # Never propagate malformed persisted rows. Keep original data for diagnosis.
  if ! awk -F '\t' '
    function validmac(s, a,n,i) {
      n=split(s,a,":"); if(n!=6) return 0;
      for(i=1;i<=6;i++) if(a[i] !~ /^[[:xdigit:]][[:xdigit:]]$/) return 0;
      return 1
    }
    NF!=7 || !validmac($1) {bad=1}
    END {exit bad?1:0}
  ' "$DIR/devices.tsv"; then
    echo 'Archivio dispositivi non valido: dati originali conservati; verificare il file devices.tsv.' > "$DIR/error"
    wait_until_next_scan
    continue
  fi
  # Names are optional DHCP metadata, never evidence of presence.
  awk -v now="$now" -v misses="$MISSES" -v events="$DIR/events.tmp" 'BEGIN{FS=OFS="\t"}
    FILENAME==ARGV[1] { n=split($0,lease,/[[:space:]]+/); if(n>=4) {mac=tolower(lease[2]); names[mac]=(lease[4]=="*"?"":lease[4]); lease_ip[mac]=lease[3]} next }
    FILENAME==ARGV[2] { if(NF>=2) ptr[$1]=$2; next }
    FILENAME==ARGV[3] { if(NF>=2){ip[$1]=$2; seen[$1]=1} next }
    FILENAME==ARGV[4] { mac=$1; known[mac]=1; present=(mac in seen); name=""; if(lease_ip[mac]==(present?ip[mac]:$2)) name=names[mac]; if(name=="") name=ptr[mac]; if(name=="" && (!present || $2==ip[mac]))name=$3;
      if(present) { if($6!="online") print now,"rilevato",mac,ip[mac],name,now >> events; print mac,ip[mac],name,$4,now,"online",0 }
      else { n=$7+1; state=$6; if(state=="online" && n>=misses){state="non rilevato"; print now,state,mac,$2,name,$5 >> events} print mac,$2,name,$4,$5,state,n }
      next }
    END { for(mac in seen) if(!(mac in known)){name=""; if(lease_ip[mac]==ip[mac]) name=names[mac]; if(name=="") name=ptr[mac]; print mac,ip[mac],name,now,now,"online",0; print now,"prima rilevazione",mac,ip[mac],name,now >> events} }
  ' "$DIR/leases.tmp" "$DIR/names.tmp" "$DIR/observed.tmp" "$DIR/devices.tsv" > "$DIR/devices.tmp" 2>"$DIR/error.tmp" || { echo 'Errore aggiornamento, stato precedente conservato' > "$DIR/error"; wait_until_next_scan; continue; }
  [ ! -f "$DIR/events.tmp" ] || { cat "$DIR/events.tmp" >> "$DIR/events.tsv"; rm -f "$DIR/events.tmp"; }
  mv "$DIR/devices.tmp" "$DIR/devices.tsv"
  if [ "$(wc -l < "$DIR/events.tsv")" -gt 10000 ]; then
    tail -n 10000 "$DIR/events.tsv" > "$DIR/events.rotate" && mv "$DIR/events.rotate" "$DIR/events.tsv"
  fi
  rm -f "$DIR/error"
  printf '%s\n' "$now" > "$DIR/last-scan"
  wait_until_next_scan
done
