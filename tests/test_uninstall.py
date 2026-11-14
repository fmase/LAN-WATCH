"""Test uninstall and shared operation lock without touching a router."""
import os
import pathlib
import subprocess
import tempfile
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1]


class UninstallSimulation(unittest.TestCase):
    def run_case(self, scenario):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            bindir = root / 'bin'
            bindir.mkdir()
            (root / 'etc/init.d').mkdir(parents=True)
            app = root / 'app'
            app.mkdir()
            (app / 'monitor.sh').write_text('keep until confirmed stopped')
            config = root / 'config'
            config.write_text('LAN_PORT="42424"\n' if scenario.startswith('custom') else ('LAN_PORT="bad"\n' if scenario=='badconfig' else 'configuration'))
            history = root / 'history'
            history.write_text('original history')
            init = root / 'etc/init.d/service'
            init.write_text('#!/bin/sh\ncase "$1" in stop) [ "$SCENARIO" != stopfail ];; disable) [ "$SCENARIO" != disablefail ];; esac\n')
            init.chmod(0o755)

            def mock(name, content):
                path = bindir / name
                path.write_text('#!/bin/sh\n' + content + '\n')
                path.chmod(0o755)

            mock('id', 'echo 0')
            mock('sleep', 'exit 0')
            mock('ubus', '''[ "$SCENARIO" != ubusfail ] || exit 1
if [ "$SCENARIO" = emptyjson ]; then printf '{  \\n }\\n'; else echo '{"aaaia-lan-monitor":{}}'; fi''')
            mock('jsonfilter', '''cat >/dev/null
[ "$SCENARIO" != jsonfail ] || exit 1
case "$*" in
 *monitor.running*) [ "$SCENARIO" != monitorrunning ] || { echo true; exit 0; };;
 *web.running*) [ "$SCENARIO" != webrunning ] || { echo true; exit 0; };;
esac
echo false''')
            mock('netstat', '''[ "$SCENARIO" != netstatfail ] || exit 1
[ "$SCENARIO" != portbusy ] || echo 'tcp 0 0 192.168.7.1:59876 0.0.0.0:* LISTEN'
[ "$SCENARIO" != custombusy ] || echo 'tcp6 0 0 :::42424 :::* LISTEN'
exit 0''')
            (root / 'proc').mkdir()
            if scenario == 'orphan':
                (root / 'proc/123').mkdir()
                (root / 'proc/123/cmdline').write_bytes(b'sh\x00' + str(app / 'monitor.sh').encode() + b'\x00')
            lock = root / 'lock'
            script = (SOURCE / 'disinstalla.sh').read_text()
            script = script.replace('/var/run/aaaia-lan-watch-install.lock', str(lock))
            script = script.replace('/proc/[0-9]*/cmdline', str(root / 'proc/[0-9]*/cmdline'))
            script = script.replace('/etc/init.d/aaaia-lan-monitor', str(init))
            script = script.replace('/etc/aaaia-lan-monitor.conf', str(config))
            script = script.replace('/usr/lib/aaaia-lan-monitor', str(app))
            script_path = root / 'uninstall.sh'
            script_path.write_text(script)
            env = os.environ.copy()
            env.update(PATH=str(bindir) + ':' + env['PATH'], SCENARIO=scenario)
            if scenario == 'locked':
                lock.mkdir()
            result = subprocess.run(['sh', str(script_path)], env=env,
                                    capture_output=True, text=True)
            self.assertEqual(history.read_text(), 'original history')
            if scenario in ('ok', 'emptyjson', 'customok'):
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(app.exists())
                self.assertFalse(config.exists())
                self.assertFalse(init.exists())
            else:
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertTrue(app.exists(), (scenario, result.stderr))
                self.assertTrue(config.exists())
                self.assertTrue(init.exists())
            self.assertEqual(lock.exists(), scenario == 'locked')

    def test_success_preserves_history(self):
        self.run_case('ok')

    def test_empty_procd_object_after_stop(self):
        self.run_case('emptyjson')

    def test_custom_port(self):
        for scenario in ('customok', 'custombusy', 'badconfig'):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)

    def test_lock_blocks_concurrent_operation(self):
        self.run_case('locked')

    def test_failures_preserve_files(self):
        for scenario in ('stopfail', 'disablefail', 'ubusfail', 'jsonfail',
                         'monitorrunning', 'webrunning', 'netstatfail', 'portbusy', 'orphan'):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)


if __name__ == '__main__':
    unittest.main()
