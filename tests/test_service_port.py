"""Exercise init's actual port selection without an OpenWrt router."""
import pathlib
import subprocess
import tempfile
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1]

class PortSelection(unittest.TestCase):
    def run_init(self, config):
        with tempfile.TemporaryDirectory() as temp:
            temp = pathlib.Path(temp)
            cfg = temp / 'config'
            cfg.write_text('LAN_DEVICE="br-lan"\nLAN_PREFIX="192.168.1"\nLAN_IP="192.168.1.1"\nLAN_DNS=""\n' + config)
            init = (SOURCE / 'payload/aaaia-lan-monitor.init').read_text().replace('/etc/aaaia-lan-monitor.conf', str(cfg))
            harness = '''procd_open_instance() { :; }
procd_close_instance() { :; }
procd_set_param() { [ "$1" != command ] || printf '%s\\n' "$*"; }
''' + init + '\nstart_service\n'
            return subprocess.run(['sh'], input=harness, text=True, capture_output=True)

    def test_legacy_and_custom(self):
        for config, port in (('', '59876'), ('LAN_PORT="65335"\n', '65335'), ('LAN_PORT="42424"\n', '42424')):
            with self.subTest(port=port):
                r = self.run_init(config)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertIn('-p 192.168.1.1:' + port, r.stdout)

    def test_invalid(self):
        for port in ('', '0', '1023', '65536', '065335', 'x', '99999999999999'):
            with self.subTest(port=port):
                r = self.run_init('LAN_PORT="' + port + '"\n')
                self.assertNotEqual(r.returncode, 0)
                self.assertNotIn('uhttpd', r.stdout)

if __name__ == '__main__':
    unittest.main()
