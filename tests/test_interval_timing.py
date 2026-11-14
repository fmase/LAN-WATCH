"""Check the fixed scan scheduler with a simulated clock, without packets."""
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'payload/monitor.sh'

class IntervalTimingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.data = self.root / 'data'
        self.data.mkdir()
        (self.root / 'clock').write_text('100\n')
        date = self.bin / 'date'
        date.write_text('#!/bin/sh\ncat "$TEST_CLOCK"\n')
        date.chmod(0o755)
        sleep = self.bin / 'sleep'
        sleep.write_text('''#!/bin/sh
[ "${FAIL_SLEEP:-0}" != 1 ] || exit 1
n=$(cat "$TEST_CLOCK")
n=$((n+$1))
printf '%s\\n' "$n" > "$TEST_CLOCK"
''')
        sleep.chmod(0o755)
        text = SOURCE.read_text()
        start = text.index('wait_until_next_scan() {')
        end = text.index('\nwhile :; do\n  started=', start)
        self.wait = text[start:end]
        self.interval = int(re.search(r'^INTERVAL=(\d+)$', text, re.M).group(1))
        self.env = os.environ.copy()
        self.env.update(PATH=str(self.bin)+':'+self.env['PATH'], TEST_CLOCK=str(self.root/'clock'))

    def tearDown(self):
        self.tmp.cleanup()

    def run_wait(self, current, old_interval='3', fail=False):
        (self.root/'clock').write_text(f'{current}\n')
        (self.data/'interval').write_text(f'{old_interval}\n')
        env = self.env.copy()
        if fail:
            env['FAIL_SLEEP'] = '1'
        script=f'set -e\nDIR="{self.data}"\nINTERVAL={self.interval}\nMIN_REST=3\nstarted=100\n{self.wait}\nwait_until_next_scan\n'
        result=subprocess.run(['sh','-c',script],env=env,timeout=10)
        return result.returncode, int((self.root/'clock').read_text())

    def test_short_scan_waits_until_60_seconds_since_start(self):
        self.assertEqual(self.interval, 60)
        self.assertEqual(self.run_wait(115), (0,160))

    def test_cycle_finishing_near_deadline_gets_three_seconds_rest(self):
        self.assertEqual(self.run_wait(159), (0,162))

    def test_cycle_exceeding_interval_still_gets_three_seconds_rest(self):
        self.assertEqual(self.run_wait(170), (0,173))

    def test_previous_setting_is_preserved_but_ignored(self):
        self.assertEqual(self.run_wait(100,old_interval='3'), (0,160))
        self.assertEqual((self.data/'interval').read_text(),'3\n')

    def test_backward_clock_uses_fresh_60_second_wait(self):
        self.assertEqual(self.run_wait(90), (0,150))

    def test_sleep_failure_is_not_silently_accepted(self):
        rc, now = self.run_wait(115,fail=True)
        self.assertNotEqual(rc,0)
        self.assertEqual(now,115)

if __name__ == '__main__':
    unittest.main()
