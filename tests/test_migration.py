import unittest

from support import Harness


class FishingMigrationTests(unittest.TestCase):
    def make_legacy(self, h, account="SharedAccount", count=125):
        h.seed(
            f"{h.state.player_name}_{h.state.player_id}\\settings.lua",
            {"account": account},
            "phoenixfishtrack",
        )
        h.seed(
            "daily.lua",
            {account: {"day": h.state.day, "points": count, "catches": {4401: count}}},
            "phoenixfishtrack",
        )

    def migrate(self, h):
        return h.ui.migrate_fishing_account(h.settings, h.state.player_name, h.state.player_id)

    def test_imported_account_loads_existing_shared_daily_count(self):
        h = Harness("fishing")
        self.make_legacy(h)

        self.assertTrue(self.migrate(h))
        h.module.reload()

        self.assertEqual(h.module.account(), "SharedAccount")
        daily = h.get_upvalue("pf").daily
        self.assertEqual(daily.points, 125)
        self.assertEqual(daily.catches[4401], 125)
        h.module.unload()
        self.assertEqual(h.data["fish_daily.lua"]["SharedAccount"].points, 125)

    def test_existing_tracker_account_takes_precedence(self):
        h = Harness("fishing")
        self.make_legacy(h)
        h.settings.account = "NewAccount"
        h.seed("fish_daily.lua", {"NewAccount": {"day": h.state.day, "points": 12, "catches": {}}})

        self.assertTrue(self.migrate(h))
        h.module.reload()

        self.assertEqual(h.module.account(), "NewAccount")
        self.assertEqual(h.get_upvalue("pf").daily.points, 12)

    def test_clearing_account_does_not_repeat_migration(self):
        h = Harness("fishing")
        self.make_legacy(h)
        self.assertTrue(self.migrate(h))
        h.module.reload()

        h.command("account")
        self.assertEqual(h.module.account(), "")
        self.assertFalse(self.migrate(h))
        h.module.reload()

        self.assertEqual(h.module.account(), "")
        self.assertEqual(h.get_upvalue("pf").label, h.state.player_name)

    def test_no_character_does_not_consume_one_time_migration(self):
        h = Harness("fishing")
        self.make_legacy(h)
        for name, server_id in ((None, None), ("", 0), ("Tester", 0)):
            with self.subTest(name=name, server_id=server_id):
                self.assertFalse(h.ui.migrate_fishing_account(h.settings, name, server_id))
                self.assertIsNone(h.settings.fish_account_migrated)
        self.assertTrue(self.migrate(h))
        self.assertEqual(h.settings.account, "SharedAccount")

    def test_missing_legacy_settings_completes_check(self):
        h = Harness("fishing")
        self.assertTrue(self.migrate(h))
        self.assertTrue(h.settings.fish_account_migrated)
        self.assertEqual(h.settings.account, "")
        self.assertFalse(self.migrate(h))

    def test_each_character_uses_its_own_migration_marker(self):
        h = Harness("fishing")
        self.make_legacy(h)
        self.assertTrue(self.migrate(h))
        other = h.table({"account": ""})
        h.seed("Second_67890\\settings.lua", {"account": "SecondAccount"}, "phoenixfishtrack")

        self.assertTrue(h.ui.migrate_fishing_account(other, "Second", 67890))

        self.assertEqual(other.account, "SecondAccount")
        self.assertTrue(other.fish_account_migrated)
        self.assertEqual(h.settings.account, "SharedAccount")

    def test_main_migrates_before_daily_load_using_settings_identity(self):
        h = Harness()
        self.make_legacy(h)
        h.state.player_name = "StalePartyMember"
        h.state.player_id = 11111

        h.start_main(name="Tester", server_id=12345)
        h.module.present()

        self.assertEqual(h.settings.account, "SharedAccount")
        self.assertEqual(h.get_upvalue("pf").daily.points, 125)
        self.assertEqual(h.reads[0], ("Tester_12345\\settings.lua", "phoenixfishtrack"))
        self.assertGreater(h.settings_saves, 0)

        h.seed("Second_67890\\settings.lua", {"account": "SecondAccount"}, "phoenixfishtrack")
        h.seed("daily.lua", {
            "SecondAccount": {"day": h.state.day, "points": 75, "catches": {4401: 75}}
        }, "phoenixfishtrack")
        h.reads.clear()
        # The real settings callback can run before party memory reflects the login.
        h.settings_update({"account": "", "dig_account": ""}, name="Second", server_id=67890)

        self.assertEqual(h.settings.account, "SecondAccount")
        self.assertEqual(h.get_upvalue("pf").daily.points, 75)
        self.assertEqual(h.reads[0], ("Second_67890\\settings.lua", "phoenixfishtrack"))


if __name__ == "__main__":
    unittest.main()
