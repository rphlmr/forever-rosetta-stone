"""Nested descriptions transport displayed durations without static duration rules."""
import unittest
from live_value_harness import LiveValueHarness


class NestedTooltipDurationTests(LiveValueHarness, unittest.TestCase):
    def test_referenced_duration_uses_native_value(self):
        self.lua.execute(b"records(900100,'$@spelldesc900101','$@spelldesc900101');records(900101,'Duree $d.','Duration $d.')")
        for seconds in (12,30):
            self.assertEqual(self.capture(900100,f'Duree {seconds} sec.'),f'Duration {seconds} sec.'.encode())

    def test_unknown_duration_units_and_missing_reference_stay_untranslated(self):
        self.lua.execute(b"records(900100,'$@spelldesc900101','$@spelldesc900101');records(900101,'Duree $d.','Duration $d.')")
        self.assertIsNone(self.capture(900100,'Duree 30 unknown.'))
        self.lua.execute(b'fakeRecords[900101].enUS=nil')
        self.assertIsNone(self.capture(900100,'Duree 30 sec.'))


if __name__=='__main__': unittest.main()
