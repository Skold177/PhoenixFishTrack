import importlib.util
import unittest

from support import Harness, ROOT


spec = importlib.util.spec_from_file_location("gen_helmdata", ROOT / "tools" / "gen_helmdata.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class HelmDataTests(unittest.TestCase):
    def setUp(self):
        self.data = Harness().load("helmdata")

    @staticmethod
    def weights(zone):
        return {row[1]: row[2] for _, row in zone.rows.items()}

    def test_phoenix_profile_contains_all_supported_zones_and_no_later_expansions(self):
        expected = {
            1: {51, 52, 109, 115, 123, 124, 145},
            2: {7, 117, 173, 198},
            4: {11, 12, 61, 62, 142, 143, 172, 196, 205},
        }
        self.assertEqual(set(self.data.types.keys()), set(expected))
        for kind, zones in expected.items():
            self.assertEqual(set(self.data.types[kind].zones.keys()), zones)
        self.assertEqual(self.data.source.profile, "Phoenix (pre-WotG)")
        self.assertRegex(self.data.source.commit, r"^[0-9a-f]{40}$")

    def test_every_pool_has_complete_rows_and_unambiguous_npc_events(self):
        seen_targets = set()
        for _, kind in self.data.types.items():
            self.assertIn(kind.tool, (605, 1020))
            for zone_id, zone in kind.zones.items():
                with self.subTest(kind=kind.key, zone=zone_id):
                    rows = self.weights(zone)
                    self.assertTrue(rows)
                    self.assertEqual(len(rows), len(zone.rows))
                    self.assertTrue(all(item > 0 and weight > 0 for item, weight in rows.items()))
                    self.assertGreater(zone.obtain_rate, 0)
                    self.assertLessEqual(zone.obtain_rate, 100)
                    self.assertTrue(list(zone.npcs.items()))
                    for npc, event in zone.npcs.items():
                        self.assertNotIn(npc, seen_targets)
                        seen_targets.add(npc)
                        self.assertGreaterEqual(event, 0)
                    self.assertTrue(set(zone.daily_caps.keys()).issubset(rows))
                    if zone.depletion:
                        self.assertGreater(zone.depletion.max, 0)
                        self.assertTrue(set(zone.depletion.pool.keys()).issubset(rows))

    def test_fixed_era_removals_keep_remaining_server_weights(self):
        harvesting, mining = self.data.types[1].zones, self.data.types[4].zones
        for zone_id, removed in ((51, 2645), (52, 2645), (115, 2713), (145, 2713)):
            self.assertNotIn(removed, self.weights(harvesting[zone_id]))
        for zone_id in (61, 62):
            self.assertNotIn(2860, self.weights(mining[zone_id]))
        self.assertEqual(self.weights(harvesting[51])[1522], 1740)
        self.assertEqual(self.weights(mining[61])[685], 15)
        self.assertEqual(self.weights(mining[196])[645], 570)
        self.assertEqual(self.weights(self.data.types[2].zones[173])[1985], 1910)

    def test_daily_caps_and_visit_pools_match_phoenix_rules(self):
        mining = self.data.types[4].zones
        self.assertEqual(dict(mining[61].daily_caps.items()), {646: 10, 685: 2})
        expected = {62: (5, {2228, 739}), 196: (32, {645, 737}), 205: (20, {645, 646, 739})}
        for zone_id, (maximum, items) in expected.items():
            self.assertEqual(mining[zone_id].depletion.max, maximum)
            self.assertEqual(set(mining[zone_id].depletion.pool.keys()), items)
            self.assertEqual(mining[zone_id].min_level, 20)
        for kind in (1, 2):
            for _, zone in self.data.types[kind].zones.items():
                self.assertFalse(list(zone.daily_caps.items()))
                self.assertIsNone(zone.depletion)

    def test_special_point_weather_and_event_identities_are_preserved(self):
        harvesting = self.data.types[1].zones
        pepper = harvesting[109]
        self.assertTrue(pepper.special)
        self.assertEqual(self.weights(pepper), {1102: 1})
        self.assertEqual(dict(pepper.npcs.items()), {17224342: 12})
        self.assertEqual(self.data.types[4].zones[196].npcs[17580398], 11)
        for zone_id in (123, 124):
            self.assertEqual(set(harvesting[zone_id].weathers.keys()), {6, 7})

    def test_colored_rocks_follow_the_eight_vanadiel_days(self):
        self.assertEqual(dict(self.data.rock_by_day.items()), {
            0: 769, 1: 771, 2: 770, 3: 772, 4: 773, 5: 774, 6: 776, 7: 775,
        })


class HelmGeneratorParserTests(unittest.TestCase):
    def test_nested_tables_resolve_enum_values_without_losing_following_rows(self):
        text = "pool = { [xi.zone.TEST] = { drops = { { 100, xi.item.A }, { 2, xi.item.B } }, rate = 91.81 } }"
        parsed = generator.parse_table(text, "pool", {"xi.zone.TEST": 5, "xi.item.A": 10, "xi.item.B": 20})
        self.assertEqual(parsed, {5: {"drops": {1: {1: 100, 2: 10}, 2: {1: 2, 2: 20}}, "rate": 91.81}})

    def test_unsupported_or_incomplete_source_is_rejected(self):
        for text in (
            "pool = { { 10 + 5, 20 } }",
            "pool = { { 10, xi.item.UNKNOWN } }",
            "pool = { { 10, 20 }",
            "pool = { rate = 1, rate = 2 }",
        ):
            with self.subTest(text=text):
                with self.assertRaises(generator.SourceError):
                    generator.parse_table(text, "pool")


if __name__ == "__main__":
    unittest.main()
