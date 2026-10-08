import unittest

from support import Harness, packet


class FishingLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness('fishing')
        self.pf = self.h.get_upvalue('pf')
        self.base = self.h.load('offsets')[self.h.state.zone]

    def animation(self, status, player_id=None):
        self.h.state.status = status
        self.h.packet(0x037, packet(64, u32={0x24: player_id or self.h.state.player_id},
                                   u8={0x30: status}))

    def message(self, message, packet_id=0x036, item=4401, quantity=1):
        self.h.packet(packet_id, packet(u32={0x04: self.h.state.player_id,
                                             0x10: item, 0x14: quantity},
                                       u16={0x0A: 0x8000 + self.base + message}))

    def release(self):
        self.h.packet(0x052, packet(u32={0x04: 4}))

    def settle(self):
        self.h.advance(3)
        self.h.present()

    def outcome(self, name):
        return self.pf.session.outcomes[name] or 0

    def test_catch_nothing_and_silent_lure_cancel_each_count_one_cast(self):
        self.animation(56)
        self.message(0x08)
        self.animation(57)
        self.message(0x27, 0x027)
        self.animation(0)

        self.animation(56)
        self.message(0x04)
        self.animation(62)
        self.animation(0)

        self.animation(56)
        self.message(0x08)
        self.animation(57)
        self.animation(62)
        self.settle()

        self.assertEqual(self.pf.session.casts, 3)
        self.assertEqual(self.pf.daily.points, 1)
        self.assertEqual(self.outcome('caught'), 1)
        self.assertEqual(self.outcome('nothing'), 1)
        self.assertEqual(self.outcome('gaveup'), 1)
        cells = self.h.draw()
        self.assertEqual(cells['Hit rate'], '33%')
        self.assertEqual(cells['Nothing'], '1')
        self.assertEqual(cells['Cancelled'], '1')

    def test_normal_results_are_counted_once_in_either_packet_order(self):
        for outcome in (0x04, 0x05, 0x06, 0x07, 0x09, 0x0A, 0x24, 0x25, 0x27, 0x40):
            for ending_first in (False, True):
                with self.subTest(outcome=outcome, ending_first=ending_first):
                    self.h.module.reset_session()
                    self.animation(56)
                    if ending_first:
                        self.animation(62)
                    self.message(outcome, 0x027 if outcome == 0x27 else 0x036)
                    self.message(outcome, 0x027 if outcome == 0x27 else 0x036)
                    self.animation(62)
                    self.release()
                    self.animation(0)
                    self.settle()
                    self.assertEqual(self.pf.session.casts, 1)
                    self.assertEqual(self.outcome('gaveup'), int(outcome in (0x24, 0x25)))

    def test_late_nothing_replaces_provisional_cancel(self):
        self.animation(56)
        self.animation(62)
        self.settle()
        self.assertEqual(self.outcome('gaveup'), 1)
        self.message(0x04)
        self.assertEqual(self.pf.session.casts, 1)
        self.assertEqual(self.outcome('gaveup'), 0)
        self.assertEqual(self.outcome('nothing'), 1)

    def test_late_catch_records_items_once_without_an_extra_cast(self):
        self.animation(56)
        self.message(0x08)
        self.animation(62)
        self.settle()
        self.message(0x0E, 0x027, quantity=3)
        self.message(0x0E, 0x027, quantity=3)
        self.assertEqual(self.pf.session.casts, 1)
        self.assertEqual(self.outcome('gaveup'), 0)
        self.assertEqual(self.outcome('caught'), 1)
        self.assertEqual(self.pf.daily.catches[4401], 3)
        self.assertEqual(self.pf.daily.points, 1)

    def test_interruption_without_a_hook_counts_once(self):
        self.animation(56)
        self.release()
        self.animation(0)
        self.settle()
        self.release()
        self.settle()
        self.assertEqual(self.pf.session.casts, 1)
        self.assertEqual(self.outcome('gaveup'), 1)

    def test_rejected_start_and_other_players_do_not_create_casts(self):
        self.message(0x02)  # No rod equipped.
        self.release()
        self.animation(56, player_id=9999)
        self.animation(0)
        self.settle()
        self.assertEqual(self.pf.session.casts, 0)

    def test_repeated_start_and_hook_notifications_do_not_split_a_cast(self):
        self.animation(56)
        self.animation(56)
        self.message(0x08)
        self.message(0x08)
        self.animation(57)
        self.message(0x25)
        self.animation(62)
        self.settle()
        self.assertEqual(self.pf.session.casts, 1)
        self.assertEqual(self.pf.session.bites, 1)
        self.assertEqual(self.outcome('gaveup'), 1)

    def test_repeated_nothing_casts_are_not_deduplicated_across_starts(self):
        for _ in range(3):
            self.animation(56)
            self.message(0x04)
            self.animation(62)
        self.assertEqual(self.pf.session.casts, 3)
        self.assertEqual(self.outcome('nothing'), 3)

    def test_hook_after_loading_mid_cast_still_tracks_silent_end(self):
        self.message(0x08)
        self.animation(57)
        self.animation(0)
        self.settle()
        self.assertEqual(self.pf.session.casts, 1)
        self.assertEqual(self.outcome('gaveup'), 1)

    def test_next_start_settles_previous_silent_cast_before_the_grace_expires(self):
        self.animation(56)
        self.message(0x08)
        self.animation(62)
        self.animation(56)
        self.message(0x04)
        self.assertEqual(self.pf.session.casts, 2)
        self.assertEqual(self.outcome('gaveup'), 1)
        self.assertEqual(self.outcome('nothing'), 1)


if __name__ == '__main__':
    unittest.main()
