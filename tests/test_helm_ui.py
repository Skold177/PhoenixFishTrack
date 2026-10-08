import unittest

from support import Harness, packet


class HelmTabTests(unittest.TestCase):
    def tab(self, module, zone):
        h = Harness(module)
        h.state.zone = zone
        h.module.reload()
        return h

    def test_harvesting_and_excavation_show_their_own_uncapped_activity(self):
        for module, zone, key in (('harvesting', 115, 'harvest'),
                                  ('excavation', 117, 'excavate')):
            with self.subTest(module=module):
                h = self.tab(module, zone)
                cells = h.draw()
                self.assertEqual(h.module.key, key)
                self.assertEqual(cells['Attempts'], '0')
                self.assertEqual(cells['Finds'], '0')
                self.assertIn('No rare-item depletion or item caps for this activity.', h.text)
                self.assertFalse(any('/ 100' in text for text in h.text))
                self.assertFalse(h.command('fatigue', ['0'], '/pharvest'))

    def test_mining_distinguishes_unknown_progress_from_fresh_odds(self):
        h = self.tab('mining', 62)  # Halvung has a shared rare pool.
        h.draw()
        self.assertIn('Unknown', h.text)
        self.assertTrue(any('Earlier progress is unknown' in text for text in h.text))
        self.assertTrue(any('Fresh assumes every allowance is unused' in text for text in h.text))
        self.assertTrue(any('Zoning resets it; waiting here does not' in text for text in h.text))

        self.assertTrue(h.command('fatigue', ['0'], '/pmine'))
        h.draw()
        self.assertNotIn('Unknown', h.text)
        self.assertIn('0 / 5', h.text)

    def test_mining_cap_ui_explains_that_midnight_alone_does_not_reset_it(self):
        h = self.tab('mining', 61)  # Mount Zhayolm has capped ores.
        h.draw()
        self.assertTrue(any('on zone entry after JST midnight' in text for text in h.text))
        self.assertTrue(any('/pmine cap <item-id> <count>' in text for text in h.text))
        self.assertTrue(h.command('cap', ['646', '3'], '/pmine'))
        self.assertTrue(h.command('cap', ['685', '1'], '/pmine'))
        h.draw()
        self.assertIn('3 / 10', h.text)
        self.assertIn('1 / 2', h.text)
        self.assertNotIn('Unknown', h.text)

    def test_full_bags_count_attempt_and_break_without_displaying_a_find(self):
        h = self.tab('harvesting', 115)
        zone = h.load('helmdata').types[1].zones[115]
        npc, event = next(iter(zone.npcs.items()))
        item = zone.rows[1][1]
        h.packet(0x034, packet(64, u32={0x04: npc, 0x08: item, 0x0C: 1, 0x10: 1},
                              u16={0x2A: 115, 0x2C: event}))
        cells = h.draw()
        self.assertEqual(cells['Attempts'], '1')
        self.assertEqual(cells['Finds'], '0')
        self.assertEqual(cells['Broken'], '1')
        self.assertEqual(cells['Full bags'], '1')
        self.assertEqual(h.activities, ['harvest'])
        self.assertTrue(any('Full bags prevent an item award' in text for text in h.text))

    def test_pool_command_and_session_reset_are_scoped_to_the_tab(self):
        h = self.tab('excavation', 117)
        self.assertTrue(h.command('pool', prefix='/pexcavate'))
        self.assertTrue(any('Tahrongi Canyon' in text for text in h.messages))
        self.assertTrue(h.command('reset', prefix='/pexcavate'))
        self.assertIn('Excavation session stats cleared.', h.messages)
        self.assertFalse(h.command('account', ['other'], '/pexcavate'))


if __name__ == '__main__':
    unittest.main()
