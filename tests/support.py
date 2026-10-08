"""Run the shipped Lua modules with deterministic Ashita boundary stubs."""

from pathlib import Path
import re
import struct

from lupa.luajit21 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "phoenixtracker"


def packet(size=48, *, u16=None, u32=None, u8=None):
    """Build a packet with the byte offsets used by Ashita's packet events."""
    data = bytearray(size)
    for values, fmt in ((u8, "<B"), (u16, "<H"), (u32, "<I")):
        for offset, value in (values or {}).items():
            struct.pack_into(fmt, data, offset, value)
    return bytes(data)


class Harness:
    """A fresh LuaJIT VM per test; disk reads return independent table copies.

    ``state`` and ``settings`` are Lua tables and accept normal Python indexing.
    ``data`` stores parsed Lua save files keyed by filename, or
    ``addon_name/filename`` for legacy data. Use ``seed`` for Python dictionaries.
    """

    def __init__(self, module=None, *, initialize=True):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.data = {}
        self.writes = []
        self.reads = []
        self.messages = []
        self.cells = []
        self.text = []
        self.headers = []
        self.buttons = []
        self.settings_saves = 0
        self.activities = []
        self.lua.globals()._capture_message = self.messages.append
        self.lua.globals()._capture_text = self.text.append
        self.lua.globals()._capture_header = self.headers.append
        self.lua.globals()._capture_button = lambda label, width: self.buttons.append((label, width))
        self.lua.globals()._capture_cell = lambda label, value, *_: self.cells.append((label, value))
        self.lua.globals()._read_data = self._read_data
        self.lua.globals()._write_data = self._write_data
        self.lua.globals()._save_settings = self._save_settings
        self.lua.globals()._activity = lambda tab: self.activities.append(tab["key"])
        self.lua.execute(_STUBS)
        self.state = self.lua.globals().state
        for path in ADDON.glob("*.lua"):
            for constant in set(re.findall(r"\bImGui\w+", path.read_text(encoding="utf-8"))):
                self.lua.globals()[constant] = 1
        self.lua.globals().package.path = ADDON.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.ui = self.load("ui")
        self.lua.globals().ui = self.ui
        self.lua.execute("""
            ui.read_data = function(name, addon_name) return _read_data(name, addon_name) end
            ui.write_data = function(name, body) return _write_data(name, body) end
            ui.jst_day = function() return state.day end
            ui.seconds_until_reset = function() return 100 end
            ui.say = function(message) _capture_message(message) end
            ui.warn = ui.say
            ui.stat_cell = function(label, value, color) _capture_cell(label, value, color) end
        """)
        self.module = self.load(module) if module else None
        self.settings = self.table({"visible": True, "auto_switch": True, "account": "", "dig_account": ""})
        if self.module:
            for key, value in self.module.defaults.items():
                self.settings[key] = value
            context = self.lua.table(settings=self.settings, activity=self.lua.globals()._activity)
            self.module.init(context)
            if initialize:
                self.module.reload()

    def load(self, name):
        return self.lua.eval("require")(name)

    def table(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({key: self.table(item) for key, item in value.items()})
        if isinstance(value, (list, tuple)):
            return self.lua.table_from([self.table(item) for item in value])
        return value

    def seed(self, filename, value, addon_name=None):
        key = f"{addon_name}/{filename}" if addon_name else filename
        self.data[key] = self.table(value)

    def _read_data(self, filename, addon_name=None):
        self.reads.append((filename, addon_name))
        key = f"{addon_name}/{filename}" if addon_name else filename
        value = self.data.get(key)
        return self.lua.globals().clone(value) if value is not None else self.lua.globals().T()

    def _write_data(self, filename, body):
        self.writes.append((filename, body))
        self.data[filename] = self.lua.execute(body)

    def _save_settings(self):
        self.settings_saves += 1

    def start_main(self, *, name=None, server_id=None, settings=None):
        """Load the entry point with Ashita settings identity independent of party memory."""
        stub = self.load("settings")
        stub.name = self.state.player_name if name is None else name
        stub.server_id = self.state.player_id if server_id is None else server_id
        stub.current = self.table(settings or {})
        self.load("phoenixtracker")
        self.settings = stub.loaded
        self.module = self.load("fishing")

    def settings_update(self, settings, *, name, server_id):
        stub = self.load("settings")
        stub.name, stub.server_id = name, server_id
        self.settings = self.table(settings)
        for callback in stub.callbacks.values():
            callback(self.settings)

    def dispatch(self, event, **fields):
        value = self.lua.table_from(fields)
        callbacks = self.lua.globals().event_callbacks[event]
        if callbacks:
            for callback in callbacks.values():
                callback(value)
        return value

    def packet(self, packet_id, data):
        self.module.packet_in(self.lua.table(id=packet_id, data=data))

    def packet_out(self, packet_id, data):
        self.module.packet_out(self.lua.table(id=packet_id, data=data))

    def present(self):
        self.module.present()

    def advance(self, seconds=1, *, day=None):
        self.state.now += seconds
        self.state.clock += seconds
        if day is not None:
            self.state.day = day

    def command(self, sub, args=None, prefix=None):
        prefix = prefix or "/p" + self.module.key
        words = [prefix, sub, *(args or [])]
        return self.module.command(sub, self.table(words), prefix)

    def draw(self):
        self.cells.clear()
        self.text.clear()
        self.headers.clear()
        self.module.draw(500, 1, self.lua.table(), 16)
        return dict(self.cells)

    def get_upvalue(self, name):
        """Inspect state after driving public events; never mutate it for a test."""
        for _, value in self.module.items():
            if self.lua.globals().type(value) == "function":
                found = self.lua.globals().find_upvalue(value, name)
                if found is not None:
                    return found
        return None


_STUBS = r'''
string.fmt = string.format
string.args = function(value)
    local out = {}
    for word in value:gmatch('%S+') do out[#out + 1] = word end
    return out
end
local methods = { append = function(self, value) self[#self + 1] = value end, concat = table.concat }
function T(value) return setmetatable(value or {}, { __index = methods }) end
function clone(value)
    if type(value) ~= 'table' then return value end
    local out = T{}
    for k, v in pairs(value) do out[k] = clone(v) end
    return out
end
function find_upvalue(fn, wanted, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 200 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
        if type(value) == 'function' then
            local found = find_upvalue(value, wanted, seen)
            if found ~= nil then return found end
        end
    end
end
state = { player_name = 'Tester', player_id = 12345, zone = 100, status = 0,
    day = '2026-10-08', now = 1791468000, clock = 100, x = 0, y = 0, z = 0,
    skill = 50, level = 75, index = 1, inventory = {}, equipment = {},
    weather_signature = 0x400000, memory_weather = 0 }
os.time = function() return state.now end
os.clock = function() return state.clock end
local party = {
    GetMemberName = function() return state.player_name end,
    GetMemberServerId = function() return state.player_id end,
    GetMemberZone = function() return state.zone end,
    GetMemberTargetIndex = function() return state.index end,
}
local entity = {
    GetStatus = function() return state.status end,
    GetLocalPositionX = function() return state.x end,
    GetLocalPositionY = function() return state.y end,
    GetLocalPositionZ = function() return state.z end,
}
local inventory = {
    GetContainerCountMax = function(_, bag) return 80 end,
    GetContainerItem = function(_, bag, index) return (state.inventory[bag] or {})[index] end,
    GetEquippedItem = function(_, slot) return state.equipment[slot] end,
}
local player = {
    GetCraftSkill = function() return { GetSkill = function() return state.skill end } end,
    HasKeyItem = function() return false end,
    GetMainJobLevel = function() return state.level end,
}
local memory = {
    GetParty = function() return party end,
    GetEntity = function() return entity end,
    GetInventory = function() return inventory end,
    GetPlayer = function() return player end,
}
AshitaCore = {
    GetMemoryManager = function() return memory end,
    GetInstallPath = function() return 'TEST_ASHITA' end,
    GetResourceManager = function() return { GetItemById = function(_, id)
        return { Name = { 'Item ' .. id } }
    end } end,
}
addon = { name = 'phoenixtracker' }
event_callbacks = {}
ashita = { events = { register = function(event, name, callback)
    event_callbacks[event] = event_callbacks[event] or {}
    event_callbacks[event][name] = callback
end }, fs = { exists = function() return true end }, memory = {
    find = function() return state.weather_signature end,
    read_uint32 = function(address) return address + 0x1000 end,
    read_uint8 = function() return state.memory_weather end,
} }
ICON_FA_GEAR = 'Gear'
local function noop() end
local draw_list = setmetatable({}, { __index = function() return noop end })
local imgui = setmetatable({
    Begin = function() return true end,
    BeginTable = function() return true end,
    CollapsingHeader = function(label) _capture_header(label); return true end,
    CalcTextSize = function(text) return #text * 7 end,
    GetFontSize = function() return 16 end,
    GetFont = function() return {} end,
    GetFontBaked = function() return { FindGlyph = function()
        return { X0 = 0, X1 = 12, Y0 = 0, Y1 = 16 }
    end } end,
    GetItemRectMin = function() return 0, 0 end,
    GetItemRectMax = function() return 100, 20 end,
    GetWindowPos = function() return 60, 300 end,
    GetTextLineHeight = function() return 16 end,
    GetTextLineHeightWithSpacing = function() return 20 end,
    GetCursorPosY = function() return 0 end,
    GetCursorScreenPos = function() return 0, 0 end,
    GetWindowDrawList = function() return draw_list end,
    GetColorU32 = function() return 0 end,
    TextColored = function(_, text) _capture_text(text) end,
    Text = function(text) _capture_text(text) end,
    Button = function(label, size)
        _capture_button(label, size and size[1])
        return false
    end,
    Checkbox = function() return false end,
}, { __index = function() return noop end })
package.preload.common = function() return {} end
package.preload.imgui = function() return imgui end
package.preload.chat = function() return {} end
package.preload.settings = function()
    -- Like Ashita's library, this knows the logged-in character. start_main and settings_update
    -- set a name of their own, as a login or logout would.
    local settings = setmetatable({ callbacks = {} }, { __index = function(_, key)
        if key == 'name' then return state.player_name end
        if key == 'server_id' then return state.player_id end
    end })
    settings.save = function() _save_settings() end
    settings.load = function(defaults)
        local loaded = clone(defaults)
        for k, v in pairs(settings.current or {}) do loaded[k] = clone(v) end
        settings.loaded = loaded
        return loaded
    end
    settings.register = function(_, key, callback) settings.callbacks[key] = callback end
    return settings
end
package.preload.rumble = function() return { pulse = function() return true end, update = noop, close = noop } end
package.preload.catchpool = function() return { build = function()
    return { known = true, bait_ok = true, area = 'Test area', [0x08] = {}, [0x32] = {}, [0x33] = {}, [0x34] = {} }
end } end
'''
