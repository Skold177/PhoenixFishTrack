import unittest

from support import Harness, packet


class TrackerIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness()
        self.h.start_main()

    def command(self, text):
        return self.h.dispatch('command', command=text, blocked=False)

    def test_activity_aliases_open_and_toggle_their_own_tabs(self):
        for prefix, key in (('/pfish', 'fish'), ('/pdig', 'dig'),
                            ('/pharvest', 'harvest'), ('/plog', 'log'), ('/pmine', 'mine'),
                            ('/pexcavate', 'excavate')):
            with self.subTest(prefix=prefix):
                self.h.settings.visible = False
                self.assertTrue(self.command(prefix).blocked)
                self.assertTrue(self.h.settings.visible)
                self.assertEqual(self.h.settings.tab, key)
                self.command(prefix)
                self.assertFalse(self.h.settings.visible)
                self.h.settings.tab = 'different'
                self.command(prefix + ' show')
                self.assertTrue(self.h.settings.visible)
                self.assertEqual(self.h.settings.tab, key)

    def test_tracker_accepts_short_and_full_activity_names(self):
        for word, key in (('fish', 'fish'), ('fishing', 'fish'), ('dig', 'dig'),
                          ('digging', 'dig'), ('harvest', 'harvest'),
                          ('harvesting', 'harvest'), ('log', 'log'), ('logging', 'log'), ('mine', 'mine'),
                          ('mining', 'mine'), ('excavate', 'excavate'),
                          ('excavation', 'excavate')):
            self.command('/ptrack ' + word)
            self.assertEqual(self.h.settings.tab, key)
        self.assertFalse(self.command('/unrelated mine').blocked)

    def test_all_tabs_render_and_gathering_buttons_fit_both_small_and_large_scales(self):
        for scale in (0.5, 1, 3):
            self.h.settings.scale = scale
            for key in ('fish', 'dig', 'harvest', 'log', 'mine', 'excavate'):
                self.h.settings.tab = key
                self.h.buttons.clear()
                self.h.dispatch('d3d_present')
                buttons = [(label.split('##')[0], width) for label, width in self.h.buttons
                           if '##pt_tab_' in label]
                self.assertEqual([label for label, _ in buttons],
                                 ['Fishing', 'Digging', 'Harvesting', 'Logging', 'Mining', 'Excavation'])
                for label, width in buttons:
                    self.assertGreaterEqual(width, len(label) * 7 * scale + 16)
                self.assertAlmostEqual(buttons[0][1] * 2 + 8, buttons[2][1] * 4 + 24)

    def test_valid_gathering_events_auto_switch_only_to_the_matching_activity(self):
        data = self.h.load('helmdata')
        for type_id, zid, key in ((1, 115, 'harvest'), (2, 173, 'excavate'), (3, 123, 'log'), (4, 62, 'mine')):
            self.h.state.zone = zid
            npc, event = next(iter(data.types[type_id].zones[zid].npcs.items()))
            body = packet(64, u32={4: npc}, u16={0x2A: zid, 0x2C: event})
            self.h.settings.tab = 'fish'
            self.h.dispatch('packet_in', id=0x034, data=body)
            self.assertEqual(self.h.settings.tab, key)
            self.h.settings.auto_switch = False
            self.h.settings.tab = 'dig'
            self.h.dispatch('packet_in', id=0x034, data=body)
            self.assertEqual(self.h.settings.tab, 'dig')
            self.h.settings.auto_switch = True
            unrelated = packet(64, u32={4: npc + 500}, u16={0x2A: zid, 0x2C: event})
            self.h.dispatch('packet_in', id=0x034, data=unrelated)
            self.assertEqual(self.h.settings.tab, 'dig')

    def test_mining_commands_work_while_another_tab_is_selected(self):
        self.h.state.zone = 62
        self.command('/pmine fatigue 4')
        self.assertEqual(self.h.settings.tab, 'fish')
        self.assertIn('Shared rare-pool count set to 4.', self.h.messages)
        self.command('/ptrack mining')
        self.h.text.clear()
        self.h.dispatch('d3d_present')
        self.assertIn('4 / 5', self.h.text)
        self.command('/pmine reset')
        self.h.text.clear()
        self.h.dispatch('d3d_present')
        self.assertIn('4 / 5', self.h.text)


if __name__ == '__main__':
    unittest.main()
