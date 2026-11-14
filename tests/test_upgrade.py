import pathlib,tempfile,subprocess,os,shutil
src=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as d:
 t=pathlib.Path(d); fake=t/'bin';fake.mkdir();app=t/'app';app.mkdir(); (app/'www/cgi-bin').mkdir(parents=True); (t/'payload/www/cgi-bin').mkdir(parents=True)
 for old,new in [('payload/monitor.sh','payload/monitor.sh'),('payload/aaaia-lan-monitor.init','payload/aaaia-lan-monitor.init'),('payload/www/cgi-bin/status','payload/www/cgi-bin/status'),('payload/www/index-it.html','payload/www/index-it.html'),('payload/www/index-en.html','payload/www/index-en.html'),('VERSION','VERSION')]:
  (t/new).write_bytes((src/old).read_bytes())
 (app/'monitor.sh').write_text('old monitor');(app/'www/index.html').write_text('<html lang="it">');(app/'www/cgi-bin/status').write_text('old api');(app/'VERSION').write_text('0.0.9\n');(app/'www/cgi-bin/settings').write_text('old interval API')
 service=t/'service'; service.write_text('#!/bin/sh\n[ "$1" = status ] && { echo running; exit 0; }\n[ "$1" = start ] && echo start >> "$SIM_LOG"\n[ "$1" = start ] && [ "${FAIL_OLD_RESTART:-0}" = 1 ] && grep -q "old monitor" "$SIM_APP/monitor.sh" && exit 1\n[ "$1" = start ] && touch "$SIM_RUNNING"\n[ "$1" = stop ] && [ "${FAIL_STOP:-0}" = 1 ] && exit 1\n[ "$1" = stop ] && [ "${FAIL_ROLLBACK_STOP:-0}" = 1 ] && [ -e "$SIM_RUNNING" ] && ! grep -q "old monitor" "$SIM_APP/monitor.sh" && exit 1\n[ "$1" = stop ] && rm -f "$SIM_RUNNING"\nexit 0\n');service.chmod(0o755)
 # installed init script is saved/replaced; payload init only needs to be syntactically valid, replace it by a safe mock
 (t/'payload/aaaia-lan-monitor.init').write_text(service.read_text())
 conf=t/'config';conf.write_text('LAN_IP="192.168.7.1"\nLAN_DEVICE="br-lan"\nLAN_DNS=""\n')
 (t/'proc').mkdir()
 release=t/'release';release.write_text("DISTRIB_RELEASE='25.12.1'\n")
 data=t/'history';data.write_text('historical events'); interval=t/'interval';interval.write_text('3\n')
 script=(src/'upgrade.sh').read_text().replace('/proc/[0-9]*/cmdline',str(t/'proc/[0-9]*/cmdline')).replace('/var/run/aaaia-lan-watch-install.lock',str(t/'lock')).replace('/etc/.lan-watch-config.XXXXXX',str(t/'config-stage.XXXXXX')).replace('DEVICE_STATE=/root/lan-monitor-data/devices.tsv','DEVICE_STATE='+str(t/'devices.tsv')).replace('APP=/usr/lib/aaaia-lan-monitor','APP='+str(app)).replace('INIT=/etc/init.d/aaaia-lan-monitor','INIT='+str(service)).replace('CONFIG=/etc/aaaia-lan-monitor.conf','CONFIG='+str(conf)).replace('/etc/openwrt_release',str(release)).replace('/usr/lib/.lan-watch-upgrade.XXXXXX',str(t/'stage.XXXXXX'))
 (t/'upgrade.sh').write_text(script)
 def cmd(name,body):
  p=fake/name;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o755)
 cmd('dig','exit 0');cmd('id',"printf '0\\n'");cmd('ubus',"printf '{}\\n'");cmd('jsonfilter',"cat >/dev/null; if [ -e \"$SIM_RUNNING\" ]; then echo true; else [ \"${EMPTY_JSONFILTER_FAIL:-0}\" != 1 ] || exit 1; echo false; fi");cmd('wget',"while [ $# -gt 0 ]; do if [ \"$1\" = '-O' ]; then shift; outfile=$1; fi; shift; done; printf '#DEVICES\\n' > \"$outfile\"; [ \"${FAIL_WGET:-0}\" != 1 ]");cmd('netstat',"""if [ -f "$SIM_PORT_REMAIN" ]; then
 n=$(cat "$SIM_PORT_REMAIN")
 if [ "$n" -gt 0 ]; then echo $((n-1)) > "$SIM_PORT_REMAIN"; echo 'tcp 0 0 192.168.7.1:59876 0.0.0.0:* LISTEN'; fi
fi
exit 0""");cmd('sleep',"exit 0");cmd('mv', '[ "${FAIL_MOVE:-0}" = 1 ] && [ "$1" = "$SIM_APP" ] && exit 1; exec /bin/mv "$@"');cmd('cp', 'case "${2:-}" in */new/monitor.sh) [ "${FAIL_STAGE:-0}" = 1 ] && exit 1;; esac; exec /bin/cp "$@"')
 env=os.environ.copy();env['PATH']=str(fake)+':'+env['PATH'];env['SIM_LOG']=str(t/'service.log');env['SIM_APP']=str(app);env['SIM_RUNNING']=str(t/'running');env['SIM_PORT_REMAIN']=str(t/'port-remain');(t/'running').touch()
 def run(preview=False,fail=False,stop=False,move=False,stage=False,restart=False,dns='',rollback_stop=False,empty_jsonfilter_fail=False):
  e=env.copy(); e.update({'LAN_WATCH_PREVIEW':'1' if preview else '0','FAIL_WGET':'1' if fail else '0','FAIL_STOP':'1' if stop else '0','FAIL_MOVE':'1' if move else '0','FAIL_STAGE':'1' if stage else '0','FAIL_OLD_RESTART':'1' if restart else '0','FAIL_ROLLBACK_STOP':'1' if rollback_stop else '0','EMPTY_JSONFILTER_FAIL':'1' if empty_jsonfilter_fail else '0'});return subprocess.run(['sh','upgrade.sh'],cwd=t,input='s\n'+dns+'\n',text=True,capture_output=True,env=e)
 # Malformed historical MACs block both preview and install without touching files.
 state=t/'devices.tsv'; malformed='aa:bb:cc:dd:ee:ffaa:bb:cc:dd:ee:ff\t192.168.7.2\tbad\t1\t1\tonline\t0\n';state.write_text(malformed)
 for only_preview in (True,False):
  r=run(preview=only_preview);assert r.returncode!=0 and 'malformed' in r.stderr.lower() and state.read_text()==malformed and (app/'monitor.sh').read_text()=='old monitor' and not list(t.glob('stage.*')),(r.returncode,r.stderr)
 state.unlink()
 r=run(preview=True);assert r.returncode==0 and 'http://192.168.7.1:59876/' in r.stdout and (app/'monitor.sh').read_text()=='old monitor',(r.returncode,r.stderr)
 # Configured ports are preserved; malformed and duplicate values stop before changes.
 base_config=conf.read_text()
 conf.write_text(base_config+'LAN_PORT="42424"\n')
 r=run(preview=True);assert r.returncode==0 and 'http://192.168.7.1:42424/' in r.stdout,(r.returncode,r.stdout,r.stderr)
 r=run(fail=True);assert r.returncode!=0 and conf.read_text()==base_config+'LAN_PORT="42424"\n' and (app/'monitor.sh').read_text()=='old monitor',(r.returncode,r.stdout,r.stderr)
 for invalid in ('LAN_PORT="0"','LAN_PORT="65536"','LAN_PORT="01"','LAN_PORT="no"','LAN_PORT="42424"\nLAN_PORT="65335"'):
  conf.write_text(base_config+invalid+'\n');r=run(preview=True);assert r.returncode!=0 and 'LAN_PORT' in r.stderr,(invalid,r.returncode,r.stderr)
 conf.write_text(base_config)
 if (t/'service.log').exists(): (t/'service.log').unlink()
 # An orphaned old scanner must prevent replacing any files.
 orphan=t/'proc/123';orphan.mkdir();(orphan/'cmdline').write_bytes(b'sh\x00'+str(app/'monitor.sh').encode()+b'\x00')
 r=run();assert r.returncode!=0 and 'Previous scanner still active' in r.stderr and (app/'monitor.sh').read_text()=='old monitor' and not (t/'service.log').exists(),(r.returncode,r.stderr)
 shutil.rmtree(orphan);(t/'running').touch()
 # A listener may disappear asynchronously after stop. Wait before replacing files.
 (t/'port-remain').write_text('2');r=run(fail=True)
 assert r.returncode!=0 and (t/'port-remain').read_text().strip()=='0' and 'Dashboard verification failed' in r.stderr and (app/'monitor.sh').read_text()=='old monitor',(r.returncode,r.stderr)
 (t/'service.log').unlink();(t/'running').touch()
 # A listener that never releases aborts without replacing the old application.
 (t/'port-remain').write_text('20');r=run()
 assert r.returncode!=0 and 'Port remains occupied' in r.stderr and (app/'monitor.sh').read_text()=='old monitor' and not (t/'service.log').exists(),(r.returncode,r.stderr)
 (t/'port-remain').unlink();(t/'running').touch()
 r=run(stage=True);assert r.returncode!=0 and (app/'monitor.sh').read_text()=='old monitor' and not (t/'service.log').exists(),(r.returncode,r.stderr)
 r=run(move=True);assert r.returncode!=0 and (app/'monitor.sh').read_text()=='old monitor' and (t/'service.log').read_text().strip()=='start',(r.returncode,r.stderr)
 (t/'service.log').unlink()
 r=run(stop=True);assert r.returncode!=0 and (app/'monitor.sh').read_text()=='old monitor' and (t/'service.log').read_text().strip()=='start',(r.returncode,r.stderr)
 r=run(fail=True);assert r.returncode!=0 and (app/'monitor.sh').read_text()=='old monitor' and (app/'www/cgi-bin/settings').read_text()=='old interval API' and interval.read_text()=='3\n' and data.read_text()=='historical events',(r.returncode,r.stdout,r.stderr)
 # Real procd returns an empty object after stop; jsonfilter may reject missing fields.
 r=run(fail=True,empty_jsonfilter_fail=True);assert r.returncode!=0 and (app/'monitor.sh').read_text()=='old monitor' and data.read_text()=='historical events' and not list(t.glob('stage.*')),(r.returncode,r.stderr)
 r=run(fail=True,restart=True);retained=list(t.glob('stage.*'));assert r.returncode!=0 and len(retained)==1 and (retained[0]/'previous.init').exists() and 'retained at' in r.stderr and (app/'monitor.sh').read_text()=='old monitor',(r.returncode,r.stderr,retained)
 shutil.rmtree(retained[0])
 r=run(fail=True,rollback_stop=True);retained=list(t.glob('stage.*'));assert r.returncode!=0 and len(retained)==1 and (retained[0]/'previous/monitor.sh').read_text()=='old monitor' and 'Cannot stop updated service' in r.stderr and (app/'monitor.sh').read_text()!='old monitor',(r.returncode,r.stderr,retained)
 # Simulate the operator stopping the still-running service and restoring the old tree.
 shutil.rmtree(app);shutil.move(str(retained[0]/'previous'),str(app));shutil.rmtree(retained[0]);(t/'running').touch()
 r=run();assert r.returncode==0 and (app/'monitor.sh').read_text()!='old monitor' and not (app/'www/cgi-bin/settings').exists() and interval.read_text()=='3\n' and conf.read_text()=='LAN_IP="192.168.7.1"\nLAN_DEVICE="br-lan"\nLAN_DNS=""\n' and data.read_text()=='historical events',(r.returncode,r.stdout,r.stderr)
 # Legacy configs lack LAN_DNS: do not invent one; migration requires explicit input.
 legacy='LAN_IP="192.168.7.1"\nLAN_DEVICE="br-lan"\n'
 conf.write_text(legacy);(app/'VERSION').write_text('0.0.9\n')
 r=run(preview=True);assert r.returncode==0 and 'Gateway' in r.stdout and conf.read_text()==legacy,(r.returncode,r.stdout,r.stderr)
 r=run(fail=True,dns='192.168.7.2');assert r.returncode!=0 and conf.read_text()==legacy,(r.returncode,r.stderr,conf.read_text())
 r=run(dns='192.168.7.2');assert r.returncode==0 and 'LAN_DNS="192.168.7.2"' in conf.read_text(),(r.returncode,r.stdout,r.stderr)
 # An existing install/update lock must stop a second writer without touching state.
 (t/'lock').mkdir(); before=(app/'monitor.sh').read_text();r=run();assert r.returncode!=0 and (app/'monitor.sh').read_text()==before and 'lock' in r.stderr.lower();(t/'lock').rmdir()
 # Earlier published experimental versions are intentionally renumbered to 0.1.
 for prior in ('1.0', '1.0.1', '1.0.2'):
  (app/'VERSION').write_text(prior+'\n');r=run(preview=True);assert r.returncode==0 and 'Rinumerazione' in r.stdout,(prior,r.returncode,r.stdout,r.stderr)
 # The migration itself succeeds and does not rewrite history or configuration.
 (app/'VERSION').write_text('1.0.2\n');before_config=conf.read_text();r=run();assert r.returncode==0 and (app/'VERSION').read_text().strip()=='0.1' and conf.read_text()==before_config and data.read_text()=='historical events',(r.returncode,r.stdout,r.stderr)
 # A failed migration restores both the previously installed version and data.
 (app/'VERSION').write_text('1.0.2\n');r=run(fail=True);assert r.returncode!=0 and (app/'VERSION').read_text().strip()=='1.0.2' and conf.read_text()==before_config and data.read_text()=='historical events',(r.returncode,r.stdout,r.stderr)
 # Updating an installation with a chosen port keeps that port and URL.
 custom=conf.read_text()+'LAN_PORT="42424"\n';conf.write_text(custom)
 (app/'VERSION').write_text('0.0.9\n');r=run()
 assert r.returncode==0 and conf.read_text()==custom and 'http://192.168.7.1:42424/' in r.stdout,(r.returncode,r.stdout,r.stderr)
 # A real downgrade is still refused, including a later 0.x release.
 for newer in ('0.2','9.0'):
  (app/'VERSION').write_text(newer+'\n');r=run();assert r.returncode!=0 and 'downgrade' in r.stderr.lower(),(newer,r.returncode,r.stderr)
 print('OK: preview no writes; failed CGI rollback and retained recovery files on failed old restart; staging failure leaves service untouched; first rename failure and failed stop restore running state; successful upgrade keeps config/history; downgrade rejected')
