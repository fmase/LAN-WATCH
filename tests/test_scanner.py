#!/usr/bin/env python3
"""Offline behavior tests for the actual POSIX-awk state reducer and API filter."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / 'payload/monitor.sh').read_text()
API = (ROOT / 'payload/www/cgi-bin/status').read_text()
AWK = SCRIPT.split("awk -v now=\"$now\" -v misses=\"$MISSES\" -v events=\"$DIR/events.tmp\" '", 1)[1].split("\n  ' \"$DIR/leases.tmp\"", 1)[0]
FILTER = API.split("awk -F '\\t' '", 1)[1].split("' \"$DIR/events.tsv\"", 1)[0]

class ScannerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = pathlib.Path(self.tmp.name)
        for f in ('leases', 'names', 'observed', 'devices', 'events'):
            (self.d / f).write_text('')
    def tearDown(self): self.tmp.cleanup()
    def scan(self, observed, now, names='', leases=''):
        for name, contents in [('observed', observed), ('names', names), ('leases', leases)]:
            (self.d/name).write_text(contents)
        eventfile = self.d/'new-events'
        eventfile.unlink(missing_ok=True)
        result=subprocess.run(['awk','-v',f'now={now}','-v','misses=3','-v',f'events={eventfile}', AWK,*[str(self.d/x) for x in ('leases','names','observed','devices')]], capture_output=True,text=True,check=True)
        (self.d/'devices').write_text(result.stdout)
        if eventfile.exists():
            with (self.d/'events').open('a') as f:f.write(eventfile.read_text())
        return [line.split('\t') for line in result.stdout.splitlines()]
    def events(self): return [line.split('\t') for line in (self.d/'events').read_text().splitlines()]
    def test_discovery_missed_threshold_recovery_and_changed_address(self):
        a='aa:bb:cc:dd:ee:01'; b='aa:bb:cc:dd:ee:02'
        data=self.scan(f'{a}\t192.168.1.2\n{b}\t192.168.1.3\n',100,names=f'{a}\tDesktop\n')
        self.assertEqual({x[0]:x[5] for x in data},{a:'online',b:'online'})
        self.assertEqual(len(self.events()),2)
        for now in (160,220):
            data=self.scan(f'{b}\t192.168.1.3\n',now)
            self.assertEqual({x[0]:x[5] for x in data}[a],'online')
        data=self.scan(f'{b}\t192.168.1.3\n',280)
        self.assertEqual({x[0]:x[5] for x in data}[a],'non rilevato')
        self.assertEqual(self.events()[-1][1:3],['non rilevato',a])
        self.assertEqual(self.events()[-1][-1], '100')
        data=self.scan(f'{a}\t192.168.1.9\n{b}\t192.168.1.3\n',340)
        self.assertEqual({x[0]:x[5] for x in data}[a],'online')
        self.assertEqual({x[0]:x[2] for x in data}[a],'')
        self.assertEqual(self.events()[-1][1:3],['rilevato',a])
        self.assertEqual(self.events()[-1][3], '192.168.1.9')
    def test_name_survives_missed_scans_and_offline_event(self):
        mac='aa:bb:cc:dd:ee:01'; other='aa:bb:cc:dd:ee:02'
        self.scan(f'{mac}\t192.168.1.2\n{other}\t192.168.1.3\n',100,names=f'{mac}\tiPhone\n')
        for now in (130,160,190):
            rows=self.scan(f'{other}\t192.168.1.3\n',now)
            self.assertEqual({row[0]:row[2] for row in rows}[mac],'iPhone')
        self.assertEqual(self.events()[-1][1:3],['non rilevato',mac])
        self.assertEqual(self.events()[-1][4],'iPhone')
    def test_lease_priority_and_ptr_fallback(self):
        a='aa:bb:cc:dd:ee:01'; b='aa:bb:cc:dd:ee:02'
        data=self.scan(f'{a}\t192.168.1.2\n{b}\t192.168.1.3\n',100,names=f'{a}\tPTR\n{b}\tRouterName\n',leases=f'999999 {a.upper()} 192.168.1.2 MyHost *\n')
        self.assertEqual({x[0]:x[2] for x in data},{a:'MyHost',b:'RouterName'})
    def test_matching_names_do_not_merge_distinct_macs(self):
        a='aa:bb:cc:dd:ee:01'; b='aa:bb:cc:dd:ee:02'
        rows=self.scan(f'{a}\t192.168.1.2\n{b}\t192.168.1.3\n',100,names=f'{a}\tlwip0\n{b}\tlwip0\n')
        self.assertEqual(len(rows), 2)
        self.assertEqual({row[0] for row in rows},{a,b})
        self.assertEqual({row[2] for row in rows},{'lwip0'})
    def test_old_lease_for_different_address_does_not_override_ptr(self):
        mac='aa:bb:cc:dd:ee:01'
        rows=self.scan(f'{mac}\t192.168.1.9\n',100,names=f'{mac}\tNewPTR\n',leases=f'999999 {mac} 192.168.1.2 OldHost *\n')
        self.assertEqual(rows[0][2],'NewPTR')
    def test_api_filters_before_limiting_to_30(self):
        lines=[]
        for i in range(40):
            lines.append(f'{i}\tnon rilevato\tmac{i}\tip\tname\t0')
            lines.extend(f'{i}\tprima rilevazione\tmac\tip\tname\t0' for _ in range(20))
        result=subprocess.run(['awk','-F','\t',FILTER],input='\n'.join(lines)+'\n',capture_output=True,text=True,check=True)
        filtered=result.stdout.splitlines()
        self.assertEqual(len(filtered),30)
        self.assertEqual(filtered[0].split('\t')[0],'10')
        self.assertEqual(filtered[-1].split('\t')[0],'39')
        self.assertTrue(all(x.split('\t')[1]=='non rilevato' for x in filtered))


class FullScannerSimulation(unittest.TestCase):
    def test_mocked_scan_to_real_state_files(self):
        # The production script is unmodified except its Linux sysfs and lock
        # paths in this sandbox copy. All network-facing commands are fakes.
        import os, time, signal
        with tempfile.TemporaryDirectory() as tmp:
            d=pathlib.Path(tmp); bindir=d/'bin';bindir.mkdir()
            for name, script in {
                'ip': '#!/bin/sh\nprintf "2: test0 inet 192.0.2.1/24 scope global test0\\n"\n',
                'arping': '#!/bin/sh\ncase "$7" in 192.0.2.2) echo "Unicast reply from 192.0.2.2 [aa:bb:cc:dd:ee:02]"; exit 0;; 192.0.2.3) echo "Unicast reply from 192.0.2.3 [aa:bb:cc:dd:ee:03]"; exit 0;; *) exit 1;; esac\n',
                'dig': '#!/bin/sh\ncase "$3" in 192.0.2.2) echo desktop.lan.;; esac\n',
            }.items():
                p=bindir/name;p.write_text(script);p.chmod(0o755)
            code=SCRIPT.replace('[ -d "/sys/class/net/$IFACE" ]', '[ -d "'+str(d)+'/sys/$IFACE" ]').replace('LOCK=/var/run/aaaia-lan-monitor.lock', 'LOCK='+str(d/'lock'))
            # Force empty lease fixture; do not consume host-local information.
            code=code.replace('/tmp/dhcp.leases', str(d/'no-leases'))
            (d/'sys/test0').mkdir(parents=True)
            script=d/'monitor.sh';script.write_text(code)
            env=dict(os.environ, PATH=str(bindir)+':'+os.environ.get('PATH','/usr/bin:/bin'))
            proc=subprocess.Popen(['sh',str(script),'test0','192.0.2',str(d/'data'),'192.0.2.1'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
            try:
                until=time.monotonic()+15
                while time.monotonic()<until and proc.poll() is None and not (d/'data/last-scan').exists():time.sleep(.05)
                if not (d/'data/last-scan').exists():
                    raise AssertionError('scan did not complete; process exit='+str(proc.poll()))
                rows=[x.split('\t') for x in (d/'data/devices.tsv').read_text().splitlines()]
                self.assertEqual({r[1] for r in rows},{'192.0.2.2','192.0.2.3'})
                self.assertEqual({r[1]:r[2] for r in rows}['192.0.2.2'],'desktop')
                self.assertEqual(len((d/'data/events.tsv').read_text().splitlines()),2)
            finally:
                if proc.poll() is None: os.killpg(proc.pid,signal.SIGTERM)
                try:proc.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid,signal.SIGKILL);proc.communicate(timeout=3)


class ConcurrentProbeStress(unittest.TestCase):
    def test_254_simultaneous_results_remain_distinct_and_well_formed(self):
        # Mock all 254 hosts responding at once. Exercise the real parallel
        # collection logic, not a reimplementation of the reducer.
        import os, re, signal, time
        with tempfile.TemporaryDirectory() as tmp:
            d = pathlib.Path(tmp); bindir = d/'bin'; bindir.mkdir(); (d/'sys/test0').mkdir(parents=True)
            fake = {
                'ip': '#!/bin/sh\nprintf "2: test0 inet 192.0.2.1/24 scope global test0\\n"\n',
                'arping': '#!/bin/sh\nn=${7##*.}\nprintf "Unicast reply [%02x:11:22:33:44:55]\\n" "$n"\n',
            }
            for name, content in fake.items():
                f = bindir/name; f.write_text(content); f.chmod(0o755)
            code = SCRIPT.replace('[ -d "/sys/class/net/$IFACE" ]', '[ -d "'+str(d)+'/sys/$IFACE" ]').replace('LOCK=/var/run/aaaia-lan-monitor.lock', 'LOCK='+str(d/'lock')).replace('/tmp/dhcp.leases', str(d/'no-leases'))
            script=d/'monitor.sh'; script.write_text(code)
            env=dict(os.environ, PATH=str(bindir)+':'+os.environ.get('PATH','/usr/bin:/bin'))
            process=subprocess.Popen(['sh', str(script), 'test0', '192.0.2', str(d/'data')], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
            try:
                until=time.monotonic()+30
                while time.monotonic()<until and process.poll() is None and not (d/'data/last-scan').exists(): time.sleep(.05)
                if not (d/'data/last-scan').exists():
                    raise AssertionError('concurrent scan failed: exit='+str(process.poll()))
                raw=(d/'data/observed.tmp').read_text().splitlines()
                self.assertEqual(len(raw),254)
                parsed=[line.split('\t') for line in raw]
                self.assertTrue(all(len(parts)==2 and re.fullmatch(r'(?:[0-9a-f]{2}:){5}[0-9a-f]{2}',parts[0]) and re.fullmatch(r'192\.0\.2\.(?:[1-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-4])',parts[1]) for parts in parsed))
                self.assertEqual(len({parts[0] for parts in parsed}),254)
                for mac, ip in parsed:
                    self.assertEqual(mac, f'{int(ip.rsplit(".",1)[1]):02x}:11:22:33:44:55')
                rows=[line.split('\t') for line in (d/'data/devices.tsv').read_text().splitlines()]
                self.assertEqual(len(rows),254)
                self.assertTrue(all(len(row)==7 for row in rows))
            finally:
                if process.poll() is None: os.killpg(process.pid,signal.SIGTERM)
                try: process.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid,signal.SIGKILL); process.communicate(timeout=3)


class FailureSimulation(unittest.TestCase):
    def check_rejected_scan(self, arping_script, expected_error, awk_script=None, original=None):
        import os, time, signal
        with tempfile.TemporaryDirectory() as tmp:
            d=pathlib.Path(tmp); bindir=d/'bin';bindir.mkdir(); (d/'sys/test0').mkdir(parents=True)
            for name, script in {
                'ip':'#!/bin/sh\nprintf "2: test0 inet 192.0.2.1/24 scope global test0\\n"\n',
                'arping':arping_script,
            }.items():
                p=bindir/name;p.write_text(script);p.chmod(0o755)
            if awk_script:
                p=bindir/'awk';p.write_text(awk_script);p.chmod(0o755)
            code=SCRIPT.replace('[ -d "/sys/class/net/$IFACE" ]','[ -d "'+str(d)+'/sys/$IFACE" ]').replace('LOCK=/var/run/aaaia-lan-monitor.lock','LOCK='+str(d/'lock')).replace('/tmp/dhcp.leases',str(d/'no-leases'))
            script=d/'monitor.sh';script.write_text(code)
            (d/'data').mkdir(); original=original or 'aa:bb:cc:dd:ee:02\t192.0.2.2\tDevice\t100\t100\tonline\t0\n'; (d/'data/devices.tsv').write_text(original)
            env=dict(os.environ,PATH=str(bindir)+':'+os.environ.get('PATH','/usr/bin:/bin'))
            proc=subprocess.Popen(['sh',str(script),'test0','192.0.2',str(d/'data')],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
            try:
                until=time.monotonic()+15
                while time.monotonic()<until and proc.poll() is None and not (d/'data/error').exists():time.sleep(.05)
                self.assertTrue((d/'data/error').exists(), 'scanner failed to report error')
                self.assertIn(expected_error,(d/'data/error').read_text())
                self.assertEqual((d/'data/devices.tsv').read_text(),original)
                self.assertFalse((d/'data/last-scan').exists())
            finally:
                if proc.poll() is None: os.killpg(proc.pid,signal.SIGTERM)
                try:proc.communicate(timeout=3)
                except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.communicate(timeout=3)
    def test_malformed_existing_mac_does_not_rewrite_state(self):
        bad='aa:bb:cc:dd:ee:02aa:bb:cc:dd:ee:03\t192.0.2.2\tDevice\t100\t100\tonline\t0\n'
        probe='#!/bin/sh\ncase "$7" in 192.0.2.2) echo "Unicast reply [aa:bb:cc:dd:ee:02]"; exit 0;; *) exit 1;; esac\n'
        self.check_rejected_scan(probe, 'Archivio dispositivi non valido', original=bad)
    def test_arp_error_does_not_mark_devices_offline(self):
        self.check_rejected_scan('#!/bin/sh\nexit 2\n','Errore arping')
    def test_fully_empty_scan_does_not_mark_devices_offline(self):
        self.check_rejected_scan('#!/bin/sh\nexit 1\n','Scansione vuota')
    def test_state_reducer_failure_reports_error_and_preserves_state(self):
        import shutil
        real_awk=shutil.which('awk')
        wrapper='#!/bin/sh\ncase "$2" in now=*) exit 2;; esac\nexec '+real_awk+' "$@"\n'
        probe='#!/bin/sh\ncase "$7" in 192.0.2.2) echo "Unicast reply [aa:bb:cc:dd:ee:02]"; exit 0;; *) exit 1;; esac\n'
        self.check_rejected_scan(probe,'Errore aggiornamento',wrapper)

if __name__ == '__main__':
    unittest.main()
