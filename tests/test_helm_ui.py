import unittest

from support import Harness, packet


class HelmTabTests(unittest.TestCase):
    def tab(self, module, zone):
        h = Harness(module)
        h.state.zone = zone
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
                self.assertEqual(h.headers, ['Session', 'Possible Finds', 'Today\'s Items'])
                self.assertFalse(h.command('fatigue', ['0']))

    def test_mining_distinguishes_unknown_progress_from_fresh_odds(self):
        h = self.tab('mining', 62)  # Halvung has a shared rare pool.
        h.draw()
        self.assertIn('Rare-item Fatigue', h.headers)
        self.assertIn('Unknown', h.text)
        self.assertTrue(any('there may be more' in text for text in h.text))
        self.assertTrue(any('Fresh: odds before any rare finds' in text for text in h.text))
        self.assertTrue(any('rarer until you zone' in text for text in h.text))

        self.assertTrue(h.command('fatigue', ['0'], '/pmine'))
        h.draw()
        self.assertNotIn('Unknown', h.text)
        self.assertIn('0 / 5', h.text)

    def test_logging_shows_hatchets_pool_and_shared_rare_fatigue(self):
        h = self.tab('logging', 24)  # Lufaise Meadows shares Elm and Oak depletion.
        h.state.inventory[0] = h.table({1: {'Id': 1021, 'Count': 7}})
        h.draw()
        self.assertIn('Item 1021 x7', h.text)
        self.assertIn('Unknown', h.text)
        self.assertTrue(any('/plog fatigue <count>' in text for text in h.text))
        self.assertTrue(h.command('fatigue', ['20'], '/plog'))
        h.draw()
        self.assertIn('20 / 20', h.text)
        self.assertNotIn('Unknown', h.text)
        self.assertTrue(h.command('pool', prefix='/plog'))
        self.assertIn('Item 690: 0.0%', h.messages)
        self.assertIn('Item 699: 0.0%', h.messages)
        self.assertFalse(h.command('cap', ['690', '0'], '/plog'))
        self.assertTrue(h.command('reset', prefix='/plog'))
        h.draw()
        self.assertIn('20 / 20', h.text)

    def test_logging_zones_without_depletion_show_exact_odds(self):
        h = self.tab('logging', 123)  # Yuhtunga has no rare depletion.
        h.draw()
        self.assertIn('Nothing gets rarer as you gather in this zone.', h.text)
        self.assertNotIn('Unknown', h.text)

    def test_mining_cap_ui_explains_that_midnight_alone_does_not_reset_it(self):
        h = self.tab('mining', 61)  # Mount Zhayolm has capped ores.
        h.draw()
        self.assertTrue(any('zone in here after JST midnight' in text for text in h.text))
        self.assertTrue(any('/pmine cap 646 <count> sets your Item 646 count.' in text for text in h.text))
        self.assertTrue(h.command('cap', ['646', '3'], '/pmine'))
        self.assertTrue(h.command('cap', ['685', '1'], '/pmine'))
        h.draw()
        self.assertIn('3 / 10', h.text)
        self.assertIn('1 / 2', h.text)
        self.assertNotIn('Unknown', h.text)

    def test_full_inventory_counts_as_an_attempt_that_found_nothing(self):
        h = self.tab('harvesting', 115)
        zone = h.load('helmdata').types[1].zones[115]
        npc, event = next(iter(zone.npcs.items()))
        item = zone.rows[1][1]
        h.packet(0x034, packet(64, u32={0x04: npc, 0x08: item, 0x0C: 1, 0x10: 1},
                              u16={0x2A: 115, 0x2C: event}))
        cells = h.draw()
        self.assertEqual(cells['Attempts'], '1')
        self.assertEqual(cells['Finds'], '0')
        self.assertEqual(cells['Nothing'], '1')
        self.assertEqual(cells['Broken'], '1')
        self.assertEqual(list(cells), ['Attempts', 'Finds', 'Nothing', 'Broken', 'Hit rate', 'Expected', 'Per hour'])
        self.assertEqual(h.activities, ['harvest'])

    def test_pool_command_and_session_reset_are_scoped_to_the_tab(self):
        h = self.tab('excavation', 117)
        self.assertTrue(h.command('pool', prefix='/pexcavate'))
        self.assertTrue(any('Tahrongi Canyon' in text for text in h.messages))
        self.assertTrue(h.command('reset', prefix='/pexcavate'))
        self.assertIn('Excavation session stats cleared.', h.messages)
        self.assertFalse(h.command('account', ['other'], '/pexcavate'))


if __name__ == '__main__':
    unittest.main()
