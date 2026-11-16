"""Cooldown suffixes follow their source formats, including Unicode delimiters."""

import unittest

from live_value_harness import LiveValueHarness


class ItemCooldownDelimiterTests(LiveValueHarness, unittest.TestCase):
    def test_traditional_chinese_fullwidth_parentheses(self):
        for minutes in (1, 2):
            native = f'使用： 恢復21點生命力。 （{minutes}分鐘冷卻時間）'
            actual = self.lua.globals().item(118, 439, 44, native.encode(), b'zhTW', b'frFR')
            self.assertEqual(actual[0], f'Utiliser : Rend 21 points de vie. ({minutes} min de recharge.)'.encode())
            self.assertFalse(actual[2])

    def test_delimiters_come_from_source_format(self):
        self.lua.execute("""
            addon.tooltipFormatsByLocale.zhTW.ITEM_COOLDOWN_TOTAL_MIN = '【%d分鐘冷卻時間】'
        """.encode())
        native = '使用： 恢復21點生命力。 【2分鐘冷卻時間】'
        actual = self.lua.globals().item(118, 439, 44, native.encode(), b'zhTW', b'frFR')
        self.assertEqual(actual[0], b'Utiliser : Rend 21 points de vie. (2 min de recharge.)')
        self.assertFalse(actual[2])

    def test_unrecognized_cooldown_is_not_guessed(self):
        native = '使用： 恢復21點生命力。 （未知冷卻時間）'
        actual = self.lua.globals().item(118, 439, 44, native.encode(), b'zhTW', b'frFR')
        self.assertIsNone(actual[0])
        self.assertTrue(actual[2])


if __name__ == '__main__':
    unittest.main()
