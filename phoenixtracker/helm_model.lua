-- Counts attempts and finds for the four gathering tabs, and keeps its own count of the rare-item
-- fatigue the server hides. HELM is the server's name for harvesting, excavation, logging and mining.
require('common');

local ui       = require('ui');
local settings = require('settings');
local data     = require('helmdata');

local CONFIRM_WAIT   = 10;   -- Seconds a find can take to reach your inventory before it's left uncounted.
local DUPLICATE_WAIT = 30;   -- The same result packet again within this many seconds is a resend.
local VANA_EPOCH     = 1009810800;

-- The only incoming packets a model reads. Any other packet is skipped before any work is done.
local PACKETS = {
    [0x00A] = true,   -- Zone in
    [0x00B] = true,   -- Zone out or logout
    [0x01E] = true,   -- Item quantity
    [0x01F] = true,   -- Item placed in a slot
    [0x020] = true,   -- Item details
    [0x034] = true,   -- Event with parameters, which is how a gathering result arrives
    [0x057] = true,   -- Weather change
};

local M = {};

local function serialize(value)
    if (type(value) == 'table') then
        local parts = {};
        for key, child in pairs(value) do
            parts[#parts + 1] = ('[%s]=%s,'):fmt(serialize(key), serialize(child));
        end
        return '{' .. table.concat(parts) .. '}';
    end
    if (type(value) == 'string') then
        return ('%q'):fmt(value);
    end
    return tostring(value);
end

local function counters(day)
    return { day = day, started = nil, attempts = 0, finds = 0, nothing = 0,
        broken = 0, unconfirmed = 0, items = {} };
end

-- Ashita's settings library has the character's name from the login packet on, and '' while logged out.
local function identity()
    local name = settings.name;
    return name ~= '' and name or nil;
end

-- The server only takes tools from, and puts finds into, the main inventory.
local function inventory_total(id)
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    local total = 0;
    for index = 1, inventory:GetContainerCountMax(0) do
        local item = inventory:GetContainerItem(0, index);
        if (item and item.Id == id) then
            total = total + item.Count;
        end
    end
    return total;
end

function M.new(type_id)
    local info = assert(data.types[type_id], 'Unknown HELM type');
    local model = {};
    local name, daily;
    local session = counters();
    local zone_fatigue = {};
    local pending = {};
    local seen = {};
    local packet_zone;
    local weather;
    local initialized = false;
    local rollover_checked;

    -- The zone-in packet arrives before party memory changes zone.
    local function zone_id()
        return packet_zone or AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
    end

    -----------------------------------
    -- Saved data
    -----------------------------------
    -- Today's counts are the only thing saved: one entry for each character and activity.
    local function save()
        if (not name) then
            return;
        end
        local all = ui.read_data('helm_daily.lua');
        if (type(all[name]) ~= 'table') then
            all[name] = {};
        end
        all[name][type_id] = daily;
        ui.write_data('helm_daily.lua', 'return ' .. serialize(all) .. '\n');
    end

    -- Today's saved counts, or a fresh day. Anything missing or damaged in the file starts at zero.
    local function load_daily()
        local saved = name and ui.read_data('helm_daily.lua')[name];
        saved = type(saved) == 'table' and saved[type_id];
        if (type(saved) ~= 'table' or saved.day ~= ui.jst_day()) then
            return counters(ui.jst_day());
        end
        for key, zero in pairs(counters()) do
            if (type(saved[key]) ~= type(zero)) then
                saved[key] = zero;
            end
        end
        return saved;
    end

    local function rollover()
        -- The JST day can only change when the clock does, so this looks once a second.
        local now = os.time();
        if (now == rollover_checked) then
            return;
        end
        rollover_checked = now;
        if (daily.day ~= ui.jst_day()) then
            daily = counters(ui.jst_day());
            save();
        end
    end

    -----------------------------------
    -- Rare-item fatigue
    -----------------------------------
    -- A zone's rare-item counts. They start unknown and aren't saved: after a reload a saved count
    -- couldn't be trusted, because you may have gathered or zoned while the addon was unloaded.
    --
    -- depletion is a count shared by the zone's rare items, which the server clears when you zone out.
    -- caps are counted one item at a time (Mount Zhayolm's ores). The server gives both ores one reset
    -- time, the JST midnight after the first one is found, and clears them the next time you zone in
    -- past it. reset_at is the latest that time can be; reset_seen means a capped ore has pinned it.
    local function fatigue(zid)
        local zone = info.zones[zid];
        if (not zone) then
            return { caps = {} };
        end
        local f = zone_fatigue[zid];
        if (not f) then
            f = { caps = {} };
            if (zone.depletion) then
                f.depletion = { count = 0, observed = 0, known = false, max = zone.depletion.max };
            end
            for id, limit in pairs(zone.daily_caps) do
                f.caps[id] = { count = 0, known = false, limit = limit };
            end
            zone_fatigue[zid] = f;
        end
        return f;
    end

    -----------------------------------
    -- Gathering results
    -----------------------------------
    -- Counts toward the session, and toward today unless the attempt was made before midnight.
    local function add(key, attempt)
        session[key] = session[key] + 1;
        if (not attempt or daily.day == attempt.day) then
            daily[key] = daily[key] + 1;
        end
    end

    -- The server may or may not have counted this find, so its rare-item count is no longer certain.
    local function mark_unknown(attempt)
        local zone = info.zones[attempt.zone];
        local f    = fatigue(attempt.zone);
        if (zone.depletion and zone.depletion.pool[attempt.item]) then
            f.depletion.known = false;
        end
        local cap = f.caps[attempt.item];
        if (cap) then
            cap.known = false;
            if (not f.reset_seen) then
                f.reset_at = attempt.reset_at;
            end
        end
    end

    local function confirm(attempt)
        add('finds', attempt);
        if (daily.day == attempt.day) then
            daily.items[attempt.item] = (daily.items[attempt.item] or 0) + 1;
        end

        local zone = info.zones[attempt.zone];
        local f    = fatigue(attempt.zone);
        if (zone.depletion and zone.depletion.pool[attempt.item]) then
            f.depletion.count    = math.min(f.depletion.max, f.depletion.count + 1);
            f.depletion.observed = math.min(f.depletion.max, f.depletion.observed + 1);
        end
        local cap = f.caps[attempt.item];
        if (cap) then
            cap.count = math.min(cap.limit, cap.count + 1);
            if (not f.reset_seen) then
                f.reset_at   = math.max(f.reset_at or 0, attempt.reset_at);
                f.reset_seen = true;
            end
        end
    end

    -- Settles the finds still waiting for their item. A find counts once your inventory holds it, and
    -- is left uncounted if that takes longer than CONFIRM_WAIT.
    -- item_id and total: an item's count from an inventory packet the client hasn't applied yet.
    -- force: true settles every find now, for zoning and unloading. 'unconfirmed' also skips the
    -- inventory check, for when the inventory may no longer be this character's.
    local function resolve_pending(item_id, total, force)
        local changed = false;
        for index = #pending, 1, -1 do
            local attempt = pending[index];
            local held    = item_id == attempt.item and total or inventory_total(attempt.item);
            if (force ~= 'unconfirmed' and held >= attempt.required) then
                confirm(attempt);
                table.remove(pending, index);
                changed = true;
            elseif (force or os.clock() - attempt.at >= CONFIRM_WAIT) then
                add('unconfirmed', attempt);
                mark_unknown(attempt);
                table.remove(pending, index);
                changed = true;
            end
        end
        if (changed) then
            save();
        end
    end

    -----------------------------------
    -- Character
    -----------------------------------
    function model.reload()
        local next_name = identity();
        local switched  = next_name ~= name;
        -- After a character switch the inventory may already be the new character's, so finds still
        -- waiting are left uncounted instead of checked against it.
        resolve_pending(nil, nil, switched and 'unconfirmed' or true);
        name = next_name;
        if (switched) then
            session     = counters();
            packet_zone = nil;
            weather     = nil;
        end
        daily        = load_daily();
        zone_fatigue = {};
        pending      = {};
        seen         = {};
        initialized  = true;
        for zid, zone in pairs(info.zones) do
            if (next(zone.daily_caps)) then
                -- Whatever reset time the server already has, it has passed by the next JST midnight.
                -- The first capped ore found after loading can move this later.
                fatigue(zid).reset_at = os.time() + ui.seconds_until_reset();
            end
        end
    end

    -- Reloads when the character changes and starts a new day at JST midnight. False while logged out.
    local function ensure_player()
        if (not initialized or identity() ~= name) then
            model.reload();
        end
        rollover();
        return name ~= nil;
    end

    -----------------------------------
    -- Packets
    -----------------------------------
    -- An item's new total from an inventory packet. The packet arrives before the client applies it,
    -- so the slot's old stack is swapped for the new one.
    local function inventory_packet(e)
        local item, bag, slot;
        if (e.id == 0x020 and #e.data >= 16) then
            item, bag, slot = ui.u16(e.data, 0x0C), e.data:byte(0x0F), e.data:byte(0x10);
        elseif (e.id == 0x01F and #e.data >= 12) then
            item, bag, slot = ui.u16(e.data, 0x08), e.data:byte(0x0B), e.data:byte(0x0C);
        elseif (e.id == 0x01E and #e.data >= 10) then
            -- Quantity only: the item is whatever the slot already holds.
            bag, slot = e.data:byte(0x09), e.data:byte(0x0A);
        else
            return;
        end
        if (bag ~= 0) then
            return;
        end
        local old = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, slot);
        item = item or (old and old.Id);
        if (not item or item == 0) then
            return;
        end
        local total = inventory_total(item) - ((old and old.Id == item) and old.Count or 0) + ui.u32(e.data, 0x04);
        resolve_pending(item, total, false);
    end

    -- Returns true for a gathering result of this activity, so the window can switch to its tab.
    function model.packet_in(e)
        if (not PACKETS[e.id] or not ensure_player()) then
            return false;
        end

        if (e.id == 0x00B) then
            -- Leaving the zone. Reason 2 is a zone change and 3 the Mog House, which clear the shared
            -- rare-item counts on the server. Reason 1 is a logout, which keeps them.
            resolve_pending(nil, nil, true);
            local reason = e.data:byte(5);
            if (reason == 2 or reason == 3) then
                for zid, zone in pairs(info.zones) do
                    if (zone.depletion) then
                        local d = fatigue(zid).depletion;
                        d.count, d.observed, d.known = 0, 0, true;
                    end
                end
            end
            return false;
        end

        if (e.id == 0x00A and #e.data >= 0x32) then
            -- Zone in. Capped ores start over if their reset time has passed.
            packet_zone = ui.u16(e.data, 0x30);
            weather     = #e.data >= 0x6A and ui.u16(e.data, 0x68) or nil;
            seen        = {};
            local f = fatigue(packet_zone);
            if (f.reset_at and os.time() >= f.reset_at) then
                for _, cap in pairs(f.caps) do
                    cap.count, cap.known = 0, true;
                end
                f.reset_at   = nil;
                f.reset_seen = false;
            end
            return false;
        end

        if (e.id == 0x057 and #e.data >= 0x0A) then
            weather = ui.u16(e.data, 0x08);
            return false;
        end

        if (e.id == 0x020 or e.id == 0x01F or e.id == 0x01E) then
            -- Only matters while a find is waiting for its item.
            if (#pending > 0) then
                inventory_packet(e);
            end
            return false;
        end

        -- A gathering result is the event one of this zone's gathering points starts. Its parameters
        -- are the item (0 for nothing), whether the tool broke, and whether your inventory was full.
        if (e.id ~= 0x034 or #e.data < 0x2E) then
            return false;
        end
        local zid, event = ui.u16(e.data, 0x2A), ui.u16(e.data, 0x2C);
        local zone = info.zones[zid];
        if (zid ~= zone_id() or not zone or zone.npcs[ui.u32(e.data, 0x04)] ~= event) then
            return false;
        end

        -- Skip the same packet arriving twice. A later attempt with the same result has a new
        -- sequence number, so it still counts.
        local now      = os.clock();
        local previous = seen[e.data];
        if (ui.u16(e.data, 0x02) ~= 0 and previous and now - previous < DUPLICATE_WAIT) then
            return false;
        end
        seen[e.data] = now;
        for key, at in pairs(seen) do
            if (now - at >= DUPLICATE_WAIT) then
                seen[key] = nil;
            end
        end

        session.started = session.started or os.time();
        local attempt = { item = ui.u32(e.data, 0x08), zone = zid, day = daily.day, at = now,
            reset_at = os.time() + ui.seconds_until_reset() };
        add('attempts');
        if (ui.u32(e.data, 0x0C) ~= 0) then
            add('broken');
        end
        -- With a full inventory the item is lost: the server gives nothing and counts no fatigue.
        if (attempt.item == 0 or ui.u32(e.data, 0x10) ~= 0) then
            add('nothing');
        else
            -- The find counts once your inventory holds one more than it does now, plus one for each
            -- earlier find of the same item that is still waiting.
            local waiting = 0;
            for _, existing in ipairs(pending) do
                if (existing.item == attempt.item) then
                    waiting = waiting + 1;
                end
            end
            attempt.required = inventory_total(attempt.item) + waiting + 1;
            pending[#pending + 1] = attempt;
        end
        save();
        return true;
    end

    function model.present()
        if (ensure_player()) then
            resolve_pending(nil, nil, false);
        end
    end

    -----------------------------------
    -- What the tab draws
    -----------------------------------
    function model.ready()
        return ensure_player();
    end

    function model.day()
        ensure_player();
        return daily.day;
    end

    function model.snapshot()
        ensure_player();
        local zid = zone_id();
        return {
            zone_id    = zid,
            zone       = info.zones[zid],
            session    = session,
            daily      = daily,
            fatigue    = fatigue(zid),
            tool_count = inventory_total(info.tool),
            pending    = #pending,
            -- Zone and weather packets arrive before the client updates its own copy. If the addon
            -- loaded after them, the client's copy is all there is.
            weather    = weather or ui.weather(),
        };
    end

    -- Everything that can be found in this zone, with its odds. Mirrors pickItem and getDropWeight in
    -- the server's scripts/globals/hobbies/helm/logic.lua. Pass the snapshot if you already have one.
    function model.pool(snap)
        snap = snap or model.snapshot();
        local zone = snap.zone;
        if (not zone) then
            return { known = false };
        end

        local f = snap.fatigue;
        local rows, base_total, total, exact = {}, 0, 0, true;
        for _, row in ipairs(zone.rows) do
            local id, base = row[1], row[2];
            -- The Red Rock row stands for the colored rock of the current Vana'diel day.
            if (id == data.rock_by_day[0]) then
                id = data.rock_by_day[math.floor((os.time() - VANA_EPOCH) * 25 / 86400) % 8];
            end

            local weight, affected = base, false;
            local cap = f.caps[id];
            if (cap) then
                affected = true;
                exact    = exact and cap.known;
                weight   = cap.count >= cap.limit and 0 or math.floor(weight / (cap.count + 1));
            end
            if (zone.depletion and zone.depletion.pool[id]) then
                affected = true;
                exact    = exact and f.depletion.known;
                weight   = math.floor(weight * math.max(0, f.depletion.max - f.depletion.count) / f.depletion.max);
            end
            rows[#rows + 1] = { id = id, weight = weight, base_weight = base, affected = affected };
            base_total, total = base_total + base, total + weight;
        end
        -- Odds are only shown when every count they depend on is known.
        for _, row in ipairs(rows) do
            row.base_odds = row.base_weight * 100 / base_total;
            if (exact) then
                row.odds = total > 0 and row.weight * 100 / total or 0;
            end
        end
        table.sort(rows, function (a, b)
            return a.base_weight > b.base_weight;
        end);

        local low_level = AshitaCore:GetMemoryManager():GetPlayer():GetMainJobLevel() < zone.min_level;
        -- nil while the weather is unknown.
        local weather_available;
        if (not zone.weathers) then
            weather_available = true;
        elseif (snap.weather ~= nil) then
            weather_available = zone.weathers[snap.weather] == true;
        end

        return {
            known             = true,
            exact             = exact,
            rows              = rows,
            obtain_rate       = low_level and 0 or zone.obtain_rate,
            min_level         = zone.min_level,
            low_level         = low_level,
            weather_available = weather_available,
        };
    end

    -----------------------------------
    -- Commands
    -----------------------------------
    -- Both return false and a message for the player when the count can't be set.
    function model.set_depletion(count)
        ensure_player();
        local depletion = fatigue(zone_id()).depletion;
        if (not depletion) then
            return false, 'This zone has no rare find count to set.';
        end
        if (not count or count < 0 or count > depletion.max or count ~= math.floor(count)) then
            return false, ('Use a whole number from 0 to %d.'):fmt(depletion.max);
        end
        depletion.count, depletion.observed, depletion.known = count, 0, true;
        return true;
    end

    function model.set_cap(item, count)
        ensure_player();
        local f   = fatigue(zone_id());
        local cap = f.caps[item];
        if (not cap) then
            return false, 'This item has no daily cap in this zone.';
        end
        if (not count or count < 0 or count > cap.limit or count ~= math.floor(count)) then
            return false, ('Use a whole number from 0 to %d.'):fmt(cap.limit);
        end
        cap.count, cap.known = count, true;
        if (not f.reset_seen) then
            f.reset_at = math.max(f.reset_at or 0, os.time() + ui.seconds_until_reset());
        end
        -- A count above zero means the server's reset time is already set.
        if (count > 0) then
            f.reset_seen = true;
        end
        return true;
    end

    function model.reset_session()
        resolve_pending(nil, nil, true);
        session = counters();
    end

    function model.unload()
        resolve_pending(nil, nil, true);
        save();
    end

    return model;
end

return M;
