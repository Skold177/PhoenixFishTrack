import unittest

from support import Harness, packet


class HelmModelTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness()
        self.h.state.zone = 62  # Halvung, a shared five-ore depletion pool.
        self.data = self.h.load('helmdata')
        self.model = self.h.load('helm_model').new(4)
        self.sequence = 1

    def send(self, packet_id, body):
        return self.model.packet_in(self.h.lua.table(id=packet_id, data=body))

    def event(self, item=0, broken=0, full=0, zone=None, npc=None, event=None, sequence=None):
        zid = zone if zone is not None else self.model.snapshot().zone_id
        entry = self.data.types[4].zones[zid]
        default_npc, default_event = next(iter(entry.npcs.items()))
        seq = self.sequence if sequence is None else sequence
        self.sequence += 1
        return self.send(0x034, packet(52, u16={2: seq, 0x2A: zid, 0x2C: event if event is not None else default_event},
                                       u32={4: npc if npc is not None else default_npc, 8: item, 12: broken, 16: full}))

    def held(self, item, count, slot=1):
        self.h.state.inventory[0] = self.h.table({slot: {'Id': item, 'Count': count}})

    def award(self, item, count=1, slot=1, packet_id=0x020):
        if packet_id == 0x020:
            body = packet(u32={4: count}, u16={12: item}, u8={14: 0, 15: slot})
        elif packet_id == 0x01F:
            body = packet(u32={4: count}, u16={8: item}, u8={10: 0, 11: slot})
        else:
            body = packet(u32={4: count}, u8={8: 0, 9: slot})
        self.send(packet_id, body)  # Packet handlers run before the client's inventory changes.
        self.held(item, count, slot)

    def zone_in(self, zid):
        self.send(0x00A, packet(160, u16={0x30: zid}))

    def zone_out(self, reason=2):
        self.send(0x00B, packet(u8={4: reason}))

    def snap(self):
        return self.model.snapshot()

    def test_unknown_history_hides_all_current_odds(self):
        pool = self.model.pool()
        self.assertTrue(pool.known)
        self.assertFalse(pool.exact)
        for _, row in pool.rows.items():
            self.assertIsNone(row.odds)
            self.assertGreater(row.base_odds, 0)

    def test_inventory_confirmed_find_can_also_break_tool(self):
        self.assertTrue(self.model.set_depletion(0))
        self.assertTrue(self.event(739, broken=1))
        self.assertEqual((self.snap().session.attempts, self.snap().session.broken), (1, 1))
        self.assertEqual(self.snap().session.finds, 0)
        self.assertEqual(self.snap().pending, 1)

        self.award(739)

        snap = self.snap()
        self.assertEqual((snap.session.finds, snap.daily.finds, snap.pending), (1, 1, 0))
        self.assertEqual(snap.daily['items'][739], 1)
        self.assertEqual((snap.fatigue.depletion.count, snap.fatigue.depletion.known), (1, True))
        self.assertEqual(self.h.data['helm_daily.lua']['Tester'][4]['items'][739], 1)

    def test_existing_stack_growth_confirms_once_for_each_inventory_format(self):
        for packet_id in (0x01E, 0x01F, 0x020):
            with self.subTest(packet_id=packet_id):
                self.setUp()
                self.held(739, 5)
                self.event(739)
                self.award(739, 6, packet_id=packet_id)
                self.award(739, 6, packet_id=packet_id)
                self.model.present()
                self.assertEqual(self.snap().session.finds, 1)

    def test_memory_update_before_next_frame_also_confirms(self):
        self.held(739, 5)
        self.event(739)
        self.held(739, 6)
        self.model.present()
        self.assertEqual(self.snap().session.finds, 1)

    def test_nothing_and_break_are_independent(self):
        self.event(0, broken=1)
        snap = self.snap()
        self.assertEqual((snap.session.attempts, snap.session.nothing, snap.session.broken, snap.session.finds), (1, 1, 1, 0))

    def test_full_inventory_never_uses_rare_pool(self):
        self.model.set_depletion(0)
        self.event(739, broken=1, full=1)
        self.award(739)  # An unrelated subsequent inventory update cannot become this full result.
        snap = self.snap()
        self.assertEqual((snap.session.full, snap.session.broken, snap.session.finds), (1, 1, 0))
        self.assertEqual(snap.fatigue.depletion.count, 0)
        self.assertTrue(snap.fatigue.depletion.known)

    def test_unconfirmed_award_does_not_claim_find_or_exact_fatigue(self):
        self.model.set_depletion(0)
        self.event(739)
        self.h.advance(11)
        self.model.present()
        snap = self.snap()
        self.assertEqual((snap.session.finds, snap.session.unconfirmed, snap.fatigue.depletion.count), (0, 1, 0))
        self.assertFalse(snap.fatigue.depletion.known)
        self.award(739)
        self.assertEqual(self.snap().session.finds, 0)

    def test_duplicate_event_is_ignored_but_identical_next_attempt_counts(self):
        self.event(739, sequence=99)
        self.event(739, sequence=99)
        self.event(739, sequence=100)
        self.award(739, 2)
        self.assertEqual((self.snap().session.attempts, self.snap().session.finds), (2, 2))

    def test_wrong_npc_event_or_zone_does_not_count(self):
        self.assertFalse(self.event(npc=123))
        self.assertFalse(self.event(event=5555))
        self.assertFalse(self.event(zone=61))
        self.assertFalse(self.send(0x02A, packet(u32={4: self.h.state.player_id, 8: 739})))
        self.assertEqual(self.snap().session.attempts, 0)

    def test_zone_packet_handles_party_memory_lag(self):
        self.zone_in(61)
        self.assertEqual(self.h.state.zone, 62)
        self.assertEqual(self.snap().zone_id, 61)
        self.assertTrue(self.event(zone=61))
        self.assertFalse(self.event(zone=62))

    def test_real_zone_exit_resets_depletion_but_logout_does_not(self):
        self.model.set_depletion(4)
        self.zone_out(1)
        self.zone_in(62)
        self.assertEqual(self.snap().fatigue.depletion.count, 4)
        for reason in (2, 3):
            with self.subTest(reason=reason):
                self.model.set_depletion(4)
                self.zone_out(reason)
                self.zone_in(62)
                self.assertEqual(self.snap().fatigue.depletion.count, 0)
                self.assertTrue(self.snap().fatigue.depletion.known)

    def test_reload_retains_last_counts_without_claiming_unobserved_history(self):
        self.model.set_depletion(3)
        self.event(739)
        self.award(739)
        self.model.unload()
        other = self.h.load('helm_model').new(4)
        snap = other.snapshot()
        self.assertEqual(snap.daily.finds, 1)
        self.assertEqual((snap.fatigue.depletion.count, snap.fatigue.depletion.observed), (4, 0))
        self.assertFalse(snap.fatigue.depletion.known)

    def test_reload_with_pending_result_marks_it_unconfirmed(self):
        self.model.set_depletion(1)
        self.event(739)
        self.model.reload()
        self.assertEqual(self.snap().daily.unconfirmed, 1)
        self.assertFalse(self.snap().fatigue.depletion.known)

    def test_daily_rollover_does_not_reset_depletion(self):
        self.model.set_depletion(3)
        self.event()
        self.h.advance(101, day='2026-10-09')
        self.model.present()
        snap = self.snap()
        self.assertEqual(snap.daily.attempts, 0)
        self.assertEqual(snap.session.attempts, 1)
        self.assertEqual(snap.fatigue.depletion.count, 3)

    def test_confirming_yesterdays_find_does_not_count_it_today(self):
        self.event(739)
        self.h.advance(3, day='2026-10-09')
        self.award(739)
        self.assertEqual(self.snap().daily.finds, 0)
        self.assertEqual(self.snap().session.finds, 1)
        self.assertEqual(self.snap().fatigue.depletion.count, 1)

    def test_mount_caps_reset_on_entry_after_deadline_only(self):
        self.zone_in(61)
        self.model.set_cap(646, 10)
        self.model.set_cap(685, 2)
        self.zone_out()
        self.zone_in(61)
        self.assertEqual(self.snap().fatigue.caps[646].count, 10)
        self.h.advance(101, day='2026-10-09')
        self.model.present()
        self.assertEqual(self.snap().fatigue.caps[646].count, 10)
        self.zone_in(61)
        for item in (646, 685):
            cap = self.snap().fatigue.caps[item]
            self.assertEqual(cap.count, 0)
            self.assertTrue(cap.known)
            self.assertIsNone(cap.reset_at)

    def test_mount_ores_share_the_first_obtains_reset_deadline(self):
        self.zone_in(61)
        self.event(646)
        self.award(646)
        deadline = self.snap().fatigue.caps[646].reset_at
        self.h.advance(101, day='2026-10-09')
        self.event(685)
        self.award(685)
        self.assertEqual(self.snap().fatigue.caps[685].reset_at, deadline)
        self.zone_in(61)
        self.assertEqual(self.snap().fatigue.caps[646].count, 0)
        self.assertEqual(self.snap().fatigue.caps[685].count, 0)

    def test_unknown_mount_history_becomes_known_after_midnight_and_entry(self):
        self.zone_in(61)
        self.assertFalse(self.snap().fatigue.caps[646].known)
        self.h.advance(101, day='2026-10-09')
        self.model.present()
        self.assertFalse(self.snap().fatigue.caps[646].known)
        self.zone_in(61)
        self.assertTrue(self.snap().fatigue.caps[646].known)
        self.assertEqual(self.snap().fatigue.caps[646].count, 0)

    def test_stale_saved_deadline_cannot_reset_unobserved_new_daily_cycle(self):
        self.zone_in(61)
        self.model.set_cap(685, 1)
        self.model.unload()
        self.h.advance(101, day='2026-10-09')
        self.model = self.h.load('helm_model').new(4)
        self.zone_in(61)
        self.assertFalse(self.snap().fatigue.caps[685].known)
        self.assertEqual(self.snap().fatigue.caps[685].count, 1)
        self.h.advance(101, day='2026-10-10')
        self.zone_in(61)
        self.assertTrue(self.snap().fatigue.caps[685].known)
        self.assertEqual(self.snap().fatigue.caps[685].count, 0)

    def test_first_observed_ore_can_start_a_deadline_after_initial_horizon(self):
        self.zone_in(61)
        self.h.advance(101, day='2026-10-09')
        self.event(685)
        self.award(685)
        self.zone_in(61)
        self.assertEqual(self.snap().fatigue.caps[685].count, 1)
        self.assertFalse(self.snap().fatigue.caps[685].known)

    def test_manual_count_correction_does_not_extend_observed_deadline(self):
        self.zone_in(61)
        self.model.set_cap(685, 1)
        self.h.advance(101, day='2026-10-09')
        self.model.set_cap(685, 2)
        self.zone_in(61)
        self.assertEqual(self.snap().fatigue.caps[685].count, 0)

    def test_shared_depletion_weights_and_normalization_match_server(self):
        self.model.set_depletion(2)
        pool = self.model.pool()
        rows = {row.id: row for _, row in pool.rows.items()}
        self.assertEqual(rows[739].weight, 12)  # floor(20 * (5-2) / 5)
        self.assertEqual(rows[2228].weight, 6)
        self.assertAlmostEqual(sum(row.odds for row in rows.values()), 100)
        self.model.set_depletion(5)
        rows = {row.id: row for _, row in self.model.pool().rows.items()}
        self.assertEqual((rows[739].odds, rows[2228].odds), (0, 0))

    def test_individual_caps_divide_weight_and_gate_only_capped_ore(self):
        self.zone_in(61)
        self.model.set_cap(646, 1)
        self.model.set_cap(685, 2)
        rows = {row.id: row for _, row in self.model.pool().rows.items()}
        self.assertEqual(rows[646].weight, rows[646].base_weight // 2)
        self.assertEqual(rows[685].odds, 0)
        self.assertGreater(rows[646].odds, 0)

    def test_tools_and_low_level_status_use_player_inventory_and_level(self):
        self.held(605, 12)
        self.zone_in(61)
        self.h.state.level = 19
        self.assertEqual(self.snap().tool_count, 12)
        self.assertTrue(self.model.pool().low_level)
        self.assertEqual(self.model.pool().obtain_rate, 0)

    def test_reset_session_preserves_daily_and_rare_counts(self):
        self.model.set_depletion(2)
        self.event()
        self.model.reset_session()
        self.assertEqual(self.snap().session.attempts, 0)
        self.assertEqual(self.snap().daily.attempts, 1)
        self.assertEqual(self.snap().fatigue.depletion.count, 2)

    def test_characters_do_not_share_fatigue_or_daily_counts(self):
        self.model.set_depletion(2)
        self.event()
        self.h.state.player_name = 'Second'
        self.model.present()
        self.assertEqual(self.snap().daily.attempts, 0)
        self.assertEqual(self.snap().fatigue.depletion.count, 0)
        self.event()
        self.assertEqual(self.h.data['helm_daily.lua']['Tester'][4].attempts, 1)
        self.assertEqual(self.h.data['helm_daily.lua']['Second'][4].attempts, 1)

    def test_character_switch_never_confirms_old_award_using_new_inventory(self):
        self.model.set_depletion(0)
        self.event(739)
        self.h.state.player_name = 'Second'
        self.held(739, 12)
        self.model.present()
        saved = self.h.data['helm_daily.lua']['Tester'][4]
        self.assertEqual((saved.finds, saved.unconfirmed), (0, 1))
        self.assertEqual(self.snap().daily.finds, 0)

    def test_all_activities_keep_separate_daily_records_in_one_file(self):
        for type_id in (1, 2, 3, 4):
            info = self.data.types[type_id]
            zid, zone = next(iter(info.zones.items()))
            self.h.state.zone = zid
            model = self.h.load('helm_model').new(type_id)
            npc, event = next(iter(zone.npcs.items()))
            model.packet_in(self.h.lua.table(id=0x034, data=packet(52,
                u16={2: type_id, 0x2A: zid, 0x2C: event}, u32={4: npc, 12: 1})))
        for type_id in (1, 2, 3, 4):
            saved = self.h.data['helm_daily.lua']['Tester'][type_id]
            self.assertEqual((saved.attempts, saved.nothing, saved.broken), (1, 1, 1))

    def test_rain_only_harvesting_uses_zone_and_weather_updates(self):
        self.h.state.zone = 123  # Yuhtunga Jungle
        model = self.h.load('helm_model').new(1)
        self.assertIsNone(model.pool().weather_available)
        model.packet_in(self.h.lua.table(id=0x00A, data=packet(160, u16={0x30: 123, 0x68: 0})))
        self.assertFalse(model.pool().weather_available)
        model.packet_in(self.h.lua.table(id=0x057, data=packet(u16={8: 6})))
        self.assertTrue(model.pool().weather_available)

    def test_korroloka_event_zero_is_a_valid_excavation_attempt(self):
        self.h.state.zone = 173
        model = self.h.load('helm_model').new(2)
        npc, event = next(iter(self.data.types[2].zones[173].npcs.items()))
        self.assertEqual(event, 0)
        accepted = model.packet_in(self.h.lua.table(id=0x034, data=packet(52,
            u16={2: 1, 0x2A: 173, 0x2C: 0}, u32={4: npc})))
        self.assertTrue(accepted)
        self.assertEqual(model.snapshot().session.nothing, 1)


class LoggingModelTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness()
        self.h.state.zone = 24  # Lufaise Meadows
        self.data = self.h.load('helmdata')
        self.model = self.h.load('helm_model').new(3)
        self.sequence = 1

    def event(self, item=0, broken=0, full=0, type_id=3):
        zone = self.data.types[type_id].zones[self.h.state.zone]
        npc, event = next(iter(zone.npcs.items()))
        body = packet(52, u16={2: self.sequence, 0x2A: self.h.state.zone, 0x2C: event},
                      u32={4: npc, 8: item, 12: broken, 16: full})
        self.sequence += 1
        return self.h.lua.table(id=0x034, data=body)

    def award(self, item, count=1, slot=1):
        body = packet(u32={4: count}, u16={12: item}, u8={14: 0, 15: slot})
        self.model.packet_in(self.h.lua.table(id=0x020, data=body))
        if self.h.state.inventory[0] is None:
            self.h.state.inventory[0] = self.h.table({})
        self.h.state.inventory[0][slot] = self.h.table({'Id': item, 'Count': count})

    def test_logging_success_failure_full_bags_and_broken_hatchets(self):
        self.model.set_depletion(0)
        self.model.packet_in(self.event(690, broken=1))
        self.assertEqual(self.model.snapshot().session.finds, 0)
        self.award(690)
        self.model.packet_in(self.event(0, broken=1))
        self.model.packet_in(self.event(690, broken=1, full=1))
        self.model.packet_in(self.event(688))
        self.award(688, slot=2)

        snapshot = self.model.snapshot()
        self.assertEqual((snapshot.session.attempts, snapshot.session.finds, snapshot.session.nothing,
                          snapshot.session.full, snapshot.session.broken), (4, 2, 1, 1, 3))
        self.assertEqual(snapshot.daily['items'][690], 1)
        self.assertEqual(snapshot.daily['items'][688], 1)
        self.assertEqual(snapshot.fatigue.depletion.count, 1)
        self.assertTrue(snapshot.fatigue.depletion.known)
        self.assertEqual(self.h.data['helm_daily.lua']['Tester'][3].finds, 2)

    def test_logging_counts_hatchets_only_in_main_inventory(self):
        self.h.state.inventory[0] = self.h.table({
            1: {'Id': 1021, 'Count': 12}, 2: {'Id': 1021, 'Count': 2},
            3: {'Id': 605, 'Count': 9}, 4: {'Id': 1020, 'Count': 7},
        })
        self.h.state.inventory[8] = self.h.table({1: {'Id': 1021, 'Count': 12}})
        self.assertEqual(self.model.snapshot().tool_count, 14)

    def test_elm_and_oak_share_depletion_and_real_zoning_resets_it(self):
        self.model.set_depletion(0)
        self.model.packet_in(self.event(690))
        self.award(690)
        self.model.packet_in(self.event(699))
        self.award(699, slot=2)
        snapshot = self.model.snapshot()
        self.assertEqual(snapshot.fatigue.depletion.count, 2)
        rows = {row.id: row for _, row in self.model.pool().rows.items()}
        self.assertEqual((rows[690].weight, rows[699].weight), (153, 99))

        self.model.set_depletion(20)
        rows = {row.id: row for _, row in self.model.pool().rows.items()}
        self.assertEqual((rows[690].odds, rows[699].odds), (0, 0))
        self.model.packet_in(self.h.lua.table(id=0x00B, data=packet(u8={4: 1})))
        self.assertEqual(self.model.snapshot().fatigue.depletion.count, 20)
        self.model.packet_in(self.h.lua.table(id=0x00B, data=packet(u8={4: 2})))
        self.model.packet_in(self.h.lua.table(id=0x00A, data=packet(160, u16={0x30: 24})))
        self.assertEqual(self.model.snapshot().fatigue.depletion.count, 0)
        self.assertTrue(self.model.pool().exact)

    def test_logging_and_harvesting_in_same_zone_are_isolated(self):
        self.h.state.zone = 123  # Yuhtunga: both tools have separate NPCs and events.
        harvest = self.h.load('helm_model').new(1)
        logging_event = self.event(688)
        self.assertTrue(self.model.packet_in(logging_event))
        self.assertFalse(harvest.packet_in(logging_event))
        self.award(688)

        harvesting_event = self.event(type_id=1, broken=1)
        self.assertFalse(self.model.packet_in(harvesting_event))
        self.assertTrue(harvest.packet_in(harvesting_event))
        self.assertEqual((self.model.snapshot().session.attempts, self.model.snapshot().session.finds), (1, 1))
        self.assertEqual((harvest.snapshot().session.attempts, harvest.snapshot().session.nothing,
                          harvest.snapshot().session.broken), (1, 1, 1))
        self.assertEqual(self.h.data['helm_daily.lua']['Tester'][3].finds, 1)
        self.assertEqual(self.h.data['helm_daily.lua']['Tester'][1].finds, 0)

    def test_logging_reload_keeps_collected_items_but_not_false_exact_fatigue(self):
        self.model.set_depletion(0)
        self.model.packet_in(self.event(690))
        self.award(690)
        self.model.unload()
        reloaded = self.h.load('helm_model').new(3).snapshot()
        self.assertEqual(reloaded.daily['items'][690], 1)
        self.assertEqual(reloaded.fatigue.depletion.count, 1)
        self.assertFalse(reloaded.fatigue.depletion.known)


if __name__ == '__main__':
    unittest.main()
