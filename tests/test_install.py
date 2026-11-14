"""Simulate fresh-install verification and rollback in temporary directories."""
import os,pathlib,subprocess,tempfile,shutil
source=pathlib.Path(__file__).resolve().parents[1]
for language in ("it", "en"):
 for failure in ("monitor","cgi","cgi_empty","cgi_unknown","cgi_partial","stop","lock","invalid_history","valid_history","none","custom_port","busy_ipv4","busy_ipv6","port_zero","port_low","port_high","port_text","port_leading","port_long","netstat_error"):
  missing_monitor = failure == "monitor"
  with tempfile.TemporaryDirectory() as temp:
   root=pathlib.Path(temp);binpath=root/'bin';binpath.mkdir();(root/'etc/init.d').mkdir(parents=True);(root/'usr/lib').mkdir(parents=True)
   shutil.copytree(source/'payload',root/'payload');shutil.copy(source/'VERSION',root/'VERSION');(root/'payload/www/cgi-bin/settings').write_text('stale interval API')
   # Simulated service always succeeds; process status is controlled by jsonfilter.
   (root/'payload/aaaia-lan-monitor.init').write_text('#!/bin/sh\ncase "$1" in start) touch "$SIM_RUNNING" "$SIM_STARTED";; stop) [ "$FAIL_STOP" = 1 ] && exit 1; rm -f "$SIM_RUNNING";; esac\nexit 0\n')
   release=root/'release';release.write_text("DISTRIB_RELEASE='25.12.1'\n")
   uhttpd=root/'uhttpd';uhttpd.write_text('#!/bin/sh\nexit 0\n');uhttpd.chmod(0o755)
   def mock(name,body):
    p=binpath/name;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o755)
   mock('id',"printf '0\\n'");mock('apk','exit 0')
   mock('ubus','''if [ -e "$SIM_STARTED" ] && [ ! -e "$SIM_RUNNING" ]; then
 case "$SCENARIO" in
  cgi_empty) printf '{  \\n }\\n'; exit 0;;
  cgi_unknown) echo '{"aaaia-lan-monitor":{}}'; exit 0;;
  cgi_partial) if [ ! -e "$SIM_POLLED" ]; then touch "$SIM_POLLED"; echo '{"aaaia-lan-monitor":{}}'; else echo '{}'; fi; exit 0;;
 esac
fi
echo '{"aaaia-lan-monitor":{}}'
''')
   mock('jsonfilter','cat >/dev/null; case "$*" in *l3_device*) echo br-lan;; *monitor.running*|*web.running*) if [ -e "$SIM_STARTED" ] && [ ! -e "$SIM_RUNNING" ]; then case "$SCENARIO" in cgi_empty|cgi_unknown|cgi_partial) exit 1;; esac; fi; case "$*" in *monitor.running*) if [ "$FAIL_MONITOR" = 1 ] || [ ! -e "$SIM_RUNNING" ]; then echo false; else echo true; fi;; *) if [ -e "$SIM_RUNNING" ]; then echo true; else echo false; fi;; esac;; *) echo true;; esac')
   mock('ip',"printf '2: br-lan inet 192.168.7.1/24 scope global br-lan\\n'")
   mock('netstat', '''case "$SCENARIO" in netstat_error) exit 1;; busy_ipv4) echo 'tcp 0 0 0.0.0.0:65335 0.0.0.0:* LISTEN'; exit 0;; busy_ipv6) echo 'tcp6 0 0 :::65335 :::* LISTEN'; exit 0;; esac
[ -e "$SIM_SERVICE" ] && printf 'tcp 0 0 192.168.7.1:%s 0.0.0.0:* LISTEN\n' "$TEST_PORT"; exit 0''')
   mock('arping',"printf '%s\\n' '-I interface'");mock('sleep','exit 0');mock('wget',"while [ $# -gt 0 ]; do arg=$1; if [ \"$1\" = '-O' ]; then shift; output=$1; fi; shift; done; printf '%s' \"$arg\" > \"$SIM_URL\"; printf '#DEVICES\\n' > \"$output\"; [ \"$FAIL_CGI\" != 1 ]")
   install=(source/('install-'+language+'.sh')).read_text().replace('/var/run/aaaia-lan-watch-install.lock',str(root/'lock')).replace('/etc/openwrt_release',str(release)).replace('/etc/init.d/aaaia-lan-monitor',str(root/'etc/init.d/service')).replace('/etc/aaaia-lan-monitor.conf',str(root/'etc/config')).replace('/usr/lib/aaaia-lan-monitor',str(root/'usr/lib/app')).replace('/usr/sbin/uhttpd',str(uhttpd)).replace('/tmp/lan-watch-verify.XXXXXX',str(root/'verify.XXXXXX')).replace('/root/lan-monitor-data/devices.tsv',str(root/'devices.tsv'))
   (root/'install.sh').write_text(install)
   env=os.environ.copy();env.update(PATH=str(binpath)+':'+env['PATH'],FAIL_MONITOR='1' if missing_monitor else '0',FAIL_CGI='1' if failure in ('cgi','cgi_empty','cgi_unknown','cgi_partial','stop') else '0',FAIL_STOP='1' if failure=='stop' else '0',SIM_SERVICE=str(root/'etc/init.d/service'),SIM_RUNNING=str(root/'running'),SIM_STARTED=str(root/'started'),SIM_POLLED=str(root/'polled'),SCENARIO=failure,SIM_URL=str(root/'last-url'))
   if failure=='lock': (root/'lock').mkdir()
   if failure in ('invalid_history','valid_history'):
    original_history=('bad:mac\t192.168.7.5\tname\t1\t1\tonline\t0\n' if failure=='invalid_history' else '02:11:22:33:44:55\t192.168.7.5\tname\t1\t1\tonline\t0\n')
    (root/'devices.tsv').write_text(original_history)
   port_inputs={'custom_port':'42424','port_zero':'0','port_low':'1023','port_high':'65536','port_text':'abc','port_leading':'065335','port_long':'999999999999999999999'}
   chosen=port_inputs.get(failure,'');env['TEST_PORT']=chosen or '65335'
   if failure in ('none','custom_port'):
    preview_env=env.copy();preview_env['LAN_WATCH_PREVIEW']='1'
    preview=subprocess.run(['sh','install.sh'],cwd=root,input='\n'+chosen+'\n',text=True,capture_output=True,env=preview_env)
    assert preview.returncode==0 and 'http://192.168.7.1:'+env['TEST_PORT']+'/' in preview.stdout and not (root/'usr/lib/app').exists() and not (root/'etc/config').exists(),(preview.returncode,preview.stdout,preview.stderr)
   result=subprocess.run(['sh','install.sh'],cwd=root,input='\n'+chosen+'\n',text=True,capture_output=True,env=env)
   app=root/'usr/lib/app';config=root/'etc/config';service=root/'etc/init.d/service'
   if failure.startswith('port_') or failure in ('busy_ipv4','busy_ipv6','netstat_error'):
    assert result.returncode!=0 and not app.exists() and not config.exists() and not service.exists(),(failure,result.returncode,result.stdout,result.stderr)
   elif failure=='lock':
    assert result.returncode!=0 and (root/'lock').exists() and not app.exists() and not config.exists() and not service.exists(),(result.returncode,result.stderr)
   elif failure=='invalid_history':
    assert result.returncode!=0 and (root/'devices.tsv').read_text()==original_history and not app.exists() and not config.exists() and not service.exists() and 'dati conservati' in result.stderr,(result.returncode,result.stdout,result.stderr)
   elif failure in ('stop','cgi_unknown'):
    assert result.returncode!=0 and app.exists() and config.exists() and service.exists() and 'file conservati' in result.stderr,(result.returncode,result.stderr)
   elif failure not in ('none','valid_history','custom_port'):
    expected='Service verification failed' if missing_monitor else 'Dashboard verification failed'
    assert result.returncode!=0 and expected in result.stderr and not app.exists() and not config.exists() and not service.exists(),(result.returncode,result.stdout,result.stderr)
   else:
    assert result.returncode==0 and app.exists() and config.exists() and service.exists() and not (app/'www/cgi-bin/settings').exists() and ('Installazione completata' if language=='it' else 'Installation complete') in result.stdout,(result.returncode,result.stdout,result.stderr)
   if failure in ('none','valid_history','custom_port'):
    if language=='it':
     assert all(text in result.stdout for text in ('Scanner e pannello: processi verificati', 'Pannello e API: risposta verificata', 'Prima scansione: non ancora verificata', 'http://192.168.7.1:'+env['TEST_PORT']+'/', 'senza password', 'VPN', 'Nessuna regola firewall'))
    else:
     assert all(text in result.stdout for text in ('Scanner and dashboard: processes verified', 'Dashboard and API: response verified', 'First scan: not yet verified', 'http://192.168.7.1:'+env['TEST_PORT']+'/', 'No password', 'VPN', 'No firewall rules'))
   if failure in ('none','valid_history','custom_port'):
    assert 'LAN_PORT="'+env['TEST_PORT']+'"' in config.read_text()
    assert (root/'last-url').read_text()=='http://192.168.7.1:'+env['TEST_PORT']+'/cgi-bin/status'
   if failure=='valid_history': assert (root/'devices.tsv').read_text()==original_history
   assert not list(root.glob('verify.*'))
   assert (root/'lock').exists() == (failure=='lock')
print('OK: fresh install rejects collector and CGI failures and rolls back; success requires CGI and both instances')
