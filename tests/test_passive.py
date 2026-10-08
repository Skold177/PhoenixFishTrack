"""The addon only watches. These checks fail if a change makes it send, alter or automate anything."""

import re
import unittest

from support import ADDON, Harness, packet


# Anything here could be seen by the server or change what the game client does.
FORBIDDEN = {
    'sends or injects a packet': r'AddOutgoingPacket|AddIncomingPacket|QueuePacket|GetPacketManager',
    'reads outgoing packets': r'packet_out',
    'changes a packet': r'data_modified|data_raw|chunk_data',
    'sends a command or text to the game': r'QueueCommand|GetChatManager|SetInputText|ExecuteScript|QueueScript',
    'writes game memory': r'memory\.write|write_u?int|write_float|write_string|write_array|ffi\.copy|ffi\.fill',
    'runs a program or opens a connection': r'os\.execute|io\.popen|require\(\'socket|socket\.',
    'reads the hidden fishing packet': r'0x0?115\b',
}

# The incoming packets each tab reads. A new one should be added here on purpose.
# Fishing reads the on-screen messages (0x027, 0x036, 0x043), the skill-up message (0x029), your own
# animation (0x037) and the end of a cast (0x052). It never reads the hidden fishing packet (0x115).
ALLOWED_PACKETS = {
    'fishing.lua': {0x027, 0x029, 0x036, 0x037, 0x043, 0x052},
    'digging.lua': {0x00A, 0x02A, 0x02F, 0x032, 0x034, 0x036, 0x057},
    'helm_model.lua': {0x00A, 0x00B, 0x01E, 0x01F, 0x020, 0x034, 0x057},
}
DATA_FILES = {'fishdata.lua', 'digdata.lua', 'helmdata.lua', 'offsets.lua'}


class PassiveAddonTests(unittest.TestCase):
    def sources(self):
        return {path.name: path.read_text(encoding='utf-8') for path in sorted(ADDON.glob('*.lua'))}

    def test_no_file_sends_alters_or_automates_anything(self):
        for name, text in self.sources().items():
            for what, pattern in FORBIDDEN.items():
                with self.subTest(file=name, what=what):
                    self.assertIsNone(re.search(pattern, text), f'{name} {what}')

    def test_only_incoming_packets_drawing_commands_and_unload_are_hooked(self):
        events = set()
        for text in self.sources().values():
            events.update(re.findall(r"ashita\.events\.register\('(\w+)'", text))
        self.assertEqual(events, {'command', 'packet_in', 'd3d_present', 'unload'})

    def test_each_tab_reads_only_its_listed_incoming_packets(self):
        for name, text in self.sources().items():
            if name in DATA_FILES:
                continue
            read = {int(found, 16) for found in re.findall(r'(?:e\.id\s*[=~]=\s*|\[)(0x[0-9A-Fa-f]{3})\b', text)}
            with self.subTest(file=name):
                self.assertEqual(read, ALLOWED_PACKETS.get(name, set()))

    def test_game_memory_is_only_read_for_the_weather(self):
        users = {name for name, text in self.sources().items() if 'ashita.memory.' in text}
        self.assertEqual(users, {'ui.lua'})
        self.assertEqual(set(re.findall(r'ashita\.memory\.(\w+)', self.sources()['ui.lua'])),
                         {'find', 'read_uint32', 'read_uint8'})

    def test_only_the_addons_own_typed_commands_are_blocked(self):
        h = Harness()
        h.start_main()
        own = h.dispatch('command', command='/ptrack', blocked=False)
        other = h.dispatch('command', command='/fish', blocked=False)
        incoming = h.dispatch('packet_in', id=0x00D, data=packet(48), blocked=False)
        self.assertEqual((own.blocked, other.blocked, incoming.blocked), (True, False, False))


if __name__ == '__main__':
    unittest.main()
