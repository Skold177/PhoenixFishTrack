"""Digging packet regressions for hidden XP and the JST allowance boundary."""

import unittest

from support import Harness, packet


class DiggingTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness('digging')
        self.h.state.zone = 100  # West Ronfaure
        self.h.state.day = '2026-10-08'
        self.h.module.reload()

    def dig(self):
        self.h.packet(0x02F, packet(u32={0x04: self.h.state.player_id}))

    def message(self, message, param=0):
        self.h.packet(0x02A, packet(
            u32={0x04: self.h.state.player_id, 0x08: param},
            u16={0x1A: message | 0x8000},
        ))

    def found(self, thrown=False):
        self.message(7267 if thrown else 6417, 17396)  # Little worm: 30 XP

    def nothing(self):
        self.h.packet(0x036, packet(
            u32={0x04: self.h.state.player_id},
            u16={0x0A: 7269 | 0x8000},
        ))

    def advance_day(self):
        self.h.state.day = '2026-10-09'
        self.h.state.now += 3
        self.h.state.clock += 3

    def set_count(self, count):
        self.h.command('set', [str(count)])

    def wing(self):
        return self.h.data['wing.lua'][self.h.state.player_name]

    def daily(self):
        return self.h.data['dig_daily.lua'][self.h.state.player_name]

    def state(self):
        return self.h.get_upvalue('pd')

    def test_first_observed_level_up_preserves_possible_carried_xp(self):
        self.dig()
        self.found()
        self.message(7354, 1)  # Wing level-up: cache offset + 5

        wing = self.wing()
        self.assertEqual((wing.level, wing.lo, wing.hi), (1, 0, 29))
        self.assertTrue(wing.calibrated)
        # A player starting at 150 XP carries 25 after 150 + 30 - 155.
        self.assertLessEqual(wing.lo, 25)
        self.assertGreaterEqual(wing.hi, 25)

        self.h.module.reload()
        self.h.state.x += 5
        self.dig()
        self.found()
        self.assertEqual((self.wing().lo, self.wing().hi), (30, 59))

    def test_known_level_up_retains_accumulated_xp(self):
        self.h.command('skill', ['0'])
        for _ in range(6):
            self.h.state.x += 5
            self.dig()
            self.found()
        self.message(7354, 1)

        self.assertEqual((self.wing().level, self.wing().lo, self.wing().hi), (1, 25, 29))

    def test_level_up_without_observed_find_does_not_claim_exact_xp(self):
        self.message(7354, 1)

        self.assertEqual((self.wing().lo, self.wing().hi), (0, 219))
        self.assertFalse(self.wing().calibrated)

    def test_previous_day_find_never_uses_new_allowance(self):
        for thrown in (False, True):
            for frame_before_result in (False, True):
                with self.subTest(thrown=thrown, frame_before_result=frame_before_result):
                    self.setUp()
                    self.set_count(99)
                    self.dig()
                    self.advance_day()
                    if frame_before_result:
                        self.h.present()
                    self.found(thrown)

                    daily = self.daily()
                    self.assertEqual((daily.day, daily.finds, daily.thrown), ('2026-10-09', 0, 0))
                    self.assertIsNone(daily['items'][17396])
                    state = self.state()
                    self.assertEqual((state.session.found, state.session.xp), (1, 30))
                    self.assertFalse(state.limit_announced)
                    self.assertFalse(any('Daily limit reached' in message for message in self.h.messages))

    def test_new_day_dig_does_not_inherit_previous_days_cap(self):
        self.set_count(100)
        self.advance_day()
        self.dig()  # The packet arrives before the next frame resets the day.
        self.nothing()

        self.assertEqual(self.daily().finds, 0)
        self.assertEqual(self.state().session.after_cap, 0)
        self.assertFalse(self.state().limit_announced)

    def test_queued_digs_keep_their_own_day(self):
        self.set_count(99)
        self.dig()
        self.advance_day()
        self.h.state.x += 5
        self.dig()
        self.found()  # The result for yesterday's dig.
        self.found()  # The result for today's dig.

        self.assertEqual(self.daily().finds, 1)
        self.assertEqual(self.daily()['items'][17396], 1)
        self.assertEqual((self.state().session.found, self.state().session.xp), (2, 60))

    def test_today_still_announces_its_own_cap(self):
        self.set_count(99)
        self.dig()
        self.found()

        self.assertEqual(self.daily().finds, 100)
        self.assertTrue(self.state().limit_announced)
        self.assertEqual(sum('Daily limit reached' in message for message in self.h.messages), 1)

    def test_throw_away_without_animation_is_still_recorded(self):
        self.found(thrown=True)

        self.assertEqual((self.daily().finds, self.daily().thrown), (1, 1))
        self.assertEqual(self.state().session.xp, 30)

    def test_expired_animation_does_not_match_unrelated_obtained_message(self):
        self.dig()
        self.h.state.clock += 11
        self.found()

        self.assertEqual((self.state().daily.finds, self.state().session.found), (0, 0))
        self.assertEqual(self.state().session.xp, 0)


if __name__ == '__main__':
    unittest.main()
