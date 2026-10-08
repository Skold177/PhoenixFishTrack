-- HELM results and hidden rare-item counters, shared by the four gathering tabs.
require('common');
local ui       = require('ui');
local settings = require('settings');
local data     = require('helmdata');

local M = {};
local CONFIRM_WAIT = 10;
local VANA_EPOCH = 1009810800;

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
        full = 0, broken = 0, unconfirmed = 0, items = {} };
end

local function party()
    return AshitaCore:GetMemoryManager():GetParty();
end

local function identity()
    -- Settings switches identity before party memory during the login packet.
    local name = settings.name;
    if (name == nil) then
        name = party():GetMemberName(0);
    end
    return name and name ~= '' and name or nil;
end

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
    local state = { zones = {} };
    local session = counters();
    local pending = {};
    local seen = {};
    local packet_zone;
    local weather;
    local initialized = false;

    local function zone_id()
        return packet_zone or party():GetMemberZone(0);
    end

    local function save_file(filename, value)
        if (not name) then return; end
        local all = ui.read_data(filename);
        all[name] = all[name] or {};
        all[name][type_id] = value;
        ui.write_data(filename, 'return ' .. serialize(all) .. '\n');
    end

    local function save()
        if (daily) then save_file('helm_daily.lua', daily); end
        save_file('helm_state.lua', state);
    end

    local function fatigue(zid)
        local zone = info.zones[zid];
        if (not zone) then return { caps = {} }; end
        local result = state.zones[zid];
        if (not result) then
            result = { caps = {} };
            state.zones[zid] = result;
        end
        result.caps = result.caps or {};
        if (zone.depletion and not result.depletion) then
            result.depletion = { count = 0, observed = 0, known = false };
        end
        if (result.depletion) then result.depletion.max = zone.depletion.max; end
        for id, limit in pairs(zone.daily_caps or {}) do
            result.caps[id] = result.caps[id] or { count = 0, observed = 0, known = false };
            result.caps[id].limit = limit;
        end
        return result;
    end

    local function rollover()
        if (daily and daily.day ~= ui.jst_day()) then
            daily = counters(ui.jst_day());
            save_file('helm_daily.lua', daily);
        end
    end

    local function add(key, attempt)
        session[key] = (session[key] or 0) + 1;
        if (daily and (not attempt or daily.day == attempt.day)) then
            daily[key] = (daily[key] or 0) + 1;
        end
    end

    local function mark_unknown(attempt)
        local zone = info.zones[attempt.zone];
        local f = fatigue(attempt.zone);
        if (zone.depletion and zone.depletion.pool[attempt.item]) then
            f.depletion.known = false;
        end
        if (f.caps[attempt.item]) then
            f.caps[attempt.item].known = false;
            if (not f.reset_seen) then f.safe_reset_at = attempt.reset_at; end
        end
    end

    local function confirm(attempt)
        add('finds', attempt);
        session.items[attempt.item] = (session.items[attempt.item] or 0) + 1;
        if (daily and daily.day == attempt.day) then
            daily.items[attempt.item] = (daily.items[attempt.item] or 0) + 1;
        end
        local zone = info.zones[attempt.zone];
        local f = fatigue(attempt.zone);
        if (zone.depletion and zone.depletion.pool[attempt.item]) then
            f.depletion.count = math.min(f.depletion.max, f.depletion.count + 1);
            f.depletion.observed = math.min(f.depletion.max, (f.depletion.observed or 0) + 1);
        end
        local cap = f.caps[attempt.item];
        if (cap) then
            cap.count = math.min(cap.limit, cap.count + 1);
            cap.observed = math.min(cap.limit, (cap.observed or 0) + 1);
            -- Mount Zhayolm has one reset deadline shared by both independently capped ores.
            f.reset_at = f.reset_at or attempt.reset_at;
            if (not f.reset_seen) then
                f.safe_reset_at = math.max(f.safe_reset_at or 0, attempt.reset_at);
                f.reset_seen = true;
            end
            for _, capped in pairs(f.caps) do capped.reset_at = f.reset_at; end
        end
    end

    local function resolve_pending(item_id, total, force)
        local changed = false;
        for index = #pending, 1, -1 do
            local attempt = pending[index];
            local held = item_id == attempt.item and total or inventory_total(attempt.item);
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
        if (changed) then save(); end
    end

    function model.reload()
        local next_name = identity();
        -- On a character switch, party/inventory memory may already belong to the new player.
        resolve_pending(nil, nil, next_name ~= name and 'unconfirmed' or true);
        local previous = name;
        name = next_name;
        if (previous ~= name) then
            session = counters();
            packet_zone = nil;
            weather = nil;
        end
        local saved_daily = name and (ui.read_data('helm_daily.lua')[name] or {})[type_id];
        daily = saved_daily and saved_daily.day == ui.jst_day() and saved_daily or counters(ui.jst_day());
        local saved_state = name and (ui.read_data('helm_state.lua')[name] or {})[type_id];
        state = saved_state or { zones = {} };
        state.zones = state.zones or {};
        pending = {};
        seen = {};
        initialized = true;
        -- Persist last observations, but never infer what happened while tracking was unloaded.
        for zid in pairs(info.zones) do
            local f = fatigue(zid);
            if (f.depletion) then
                f.depletion.known = false;
                f.depletion.observed = 0;
            end
            for _, cap in pairs(f.caps) do
                cap.known = false;
                cap.observed = 0;
            end
            if (next(f.caps)) then
                -- A saved deadline may predate unobserved play. Any existing server deadline
                -- expires by the next midnight; a newly observed first ore updates this bound.
                f.safe_reset_at = os.time() + ui.seconds_until_reset();
                f.reset_seen = false;
            end
        end
    end

    local function ensure_player()
        if (not initialized or identity() ~= name) then model.reload(); end
        rollover();
        return name ~= nil;
    end

    local function inventory_packet(e)
        local item, bag, slot;
        if (e.id == 0x020 and #e.data >= 16) then
            item, bag, slot = ui.u16(e.data, 0x0C), e.data:byte(0x0F), e.data:byte(0x10);
        elseif (e.id == 0x01F and #e.data >= 12) then
            item, bag, slot = ui.u16(e.data, 0x08), e.data:byte(0x0B), e.data:byte(0x0C);
        elseif (e.id == 0x01E and #e.data >= 10) then
            bag, slot = e.data:byte(0x09), e.data:byte(0x0A);
        else
            return;
        end
        if (bag ~= 0) then return; end
        local old = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, slot);
        item = item or (old and old.Id);
        if (not item or item == 0) then return; end
        local total = inventory_total(item) - ((old and old.Id == item) and old.Count or 0) + ui.u32(e.data, 0x04);
        resolve_pending(item, total, false);
    end

    function model.packet_in(e)
        if (not ensure_player()) then return false; end
        if (e.id == 0x00B) then
            resolve_pending(nil, nil, true);
            local reason = e.data:byte(5);
            if (reason == 2 or reason == 3) then
                for zid, zone in pairs(info.zones) do
                    if (zone.depletion) then
                        local d = fatigue(zid).depletion;
                        d.count, d.observed, d.known = 0, 0, true;
                    end
                end
                save();
            end
            return false;
        end
        if (e.id == 0x00A and #e.data >= 0x32) then
            packet_zone = ui.u16(e.data, 0x30);
            weather = #e.data >= 0x6A and ui.u16(e.data, 0x68) or nil;
            seen = {};
            local f = fatigue(packet_zone);
            local reset = math.max(f.reset_at or 0, f.safe_reset_at or 0);
            if (reset > 0 and os.time() >= reset) then
                for _, cap in pairs(f.caps) do
                    cap.count, cap.observed, cap.known, cap.reset_at = 0, 0, true, nil;
                end
                f.reset_at = nil;
                f.safe_reset_at = nil;
                f.reset_seen = false;
            end
            save();
            return false;
        end
        if (e.id == 0x057 and #e.data >= 0x0A) then
            weather = ui.u16(e.data, 0x08);
            return false;
        end
        if (e.id == 0x020 or e.id == 0x01F or e.id == 0x01E) then
            inventory_packet(e);
            return false;
        end
        if (e.id ~= 0x034 or #e.data < 0x2E) then return false; end
        local zid, event = ui.u16(e.data, 0x2A), ui.u16(e.data, 0x2C);
        local zone = info.zones[zid];
        if (zid ~= zone_id() or not zone or zone.npcs[ui.u32(e.data, 0x04)] ~= event) then
            return false;
        end
        -- The sequence is the server's packet identity; identical results on later attempts count.
        local sequence = ui.u16(e.data, 0x02);
        local fingerprint = tostring(sequence) .. ':' .. e.data;
        local previous = seen[fingerprint];
        if (sequence ~= 0 and previous and os.clock() - previous < 30) then return false; end
        seen[fingerprint] = os.clock();
        for key, at in pairs(seen) do
            if (os.clock() - at >= 30) then seen[key] = nil; end
        end
        session.started = session.started or os.time();
        local attempt = { item = ui.u32(e.data, 0x08), zone = zid, day = ui.jst_day(), at = os.clock(),
            reset_at = os.time() + ui.seconds_until_reset() };
        add('attempts');
        if (ui.u32(e.data, 0x0C) ~= 0) then add('broken'); end
        if (ui.u32(e.data, 0x10) ~= 0) then
            add('full');
        elseif (attempt.item == 0) then
            add('nothing');
        else
            local waiting = 0;
            for _, existing in ipairs(pending) do
                if (existing.item == attempt.item) then waiting = waiting + 1; end
            end
            attempt.required = inventory_total(attempt.item) + waiting + 1;
            pending[#pending + 1] = attempt;
        end
        save();
        return true;
    end

    function model.present()
        if (ensure_player()) then resolve_pending(nil, nil, false); end
    end

    function model.snapshot()
        ensure_player();
        local zid = zone_id();
        return { ready = name ~= nil, day = daily and daily.day or ui.jst_day(), zone_id = zid,
            zone = info.zones[zid], session = session, daily = daily, fatigue = fatigue(zid),
            tool_count = inventory_total(info.tool), pending = #pending, weather = weather };
    end

    function model.pool()
        local snap = model.snapshot();
        local zone = snap.zone;
        if (not zone) then return { known = false, exact = false, rows = {} }; end
        local rows, base_total, total, exact = {}, 0, 0, true;
        local f = snap.fatigue;
        for _, row in ipairs(zone.rows) do
            local id, base = row[1], row[2];
            do
                if (id == 769) then
                    local day = math.floor((os.time() - VANA_EPOCH) * 25 / 86400) % 8;
                    id = data.rock_by_day[day];
                end
                local weight, affected = base, false;
                local cap = f.caps[id];
                if (cap) then
                    affected = true;
                    exact = exact and cap.known;
                    weight = cap.count >= cap.limit and 0 or math.floor(weight / (cap.count + 1));
                end
                if (zone.depletion and zone.depletion.pool[id]) then
                    affected = true;
                    exact = exact and f.depletion.known;
                    weight = math.floor(weight * math.max(0, f.depletion.max - f.depletion.count) / f.depletion.max);
                end
                rows[#rows + 1] = { id = id, weight = weight, base_weight = base, affected = affected };
                base_total, total = base_total + base, total + weight;
            end
        end
        local level = AshitaCore:GetMemoryManager():GetPlayer():GetMainJobLevel();
        local low_level = level < (zone.min_level or 0);
        local weather_available;
        if (not zone.weathers) then
            weather_available = true;
        elseif (weather ~= nil) then
            weather_available = zone.weathers[weather] == true;
        end
        for _, row in ipairs(rows) do
            row.base_odds = base_total > 0 and row.base_weight * 100 / base_total or 0;
            if (exact) then row.odds = total > 0 and row.weight * 100 / total or 0; end
        end
        table.sort(rows, function(a, b) return a.base_weight > b.base_weight; end);
        return { known = true, exact = exact, rows = rows, obtain_rate = low_level and 0 or zone.obtain_rate,
            break_rate = zone.break_rate, min_level = zone.min_level or 0, low_level = low_level,
            weather_available = weather_available };
    end

    function model.set_depletion(count)
        local f = model.snapshot().fatigue;
        if (not f.depletion) then return false, 'This zone has no shared rare-item depletion.'; end
        if (not count or count < 0 or count > f.depletion.max or count ~= math.floor(count)) then
            return false, ('Use a whole count from 0 to %d.'):fmt(f.depletion.max);
        end
        f.depletion.count, f.depletion.observed, f.depletion.known = count, 0, true;
        save();
        return true;
    end

    function model.set_cap(item, count)
        local cap = model.snapshot().fatigue.caps[item];
        if (not cap) then return false, 'This item has no daily cap in this zone.'; end
        if (not count or count < 0 or count > cap.limit or count ~= math.floor(count)) then
            return false, ('Use a whole count from 0 to %d.'):fmt(cap.limit);
        end
        cap.count, cap.observed, cap.known = count, 0, true;
        local f = fatigue(zone_id());
        f.reset_at = f.reset_at or (os.time() + ui.seconds_until_reset());
        if (not f.reset_seen) then
            f.safe_reset_at = math.max(f.safe_reset_at or 0, os.time() + ui.seconds_until_reset());
        end
        if (count > 0) then f.reset_seen = true; end
        for _, capped in pairs(f.caps) do capped.reset_at = f.reset_at; end
        save();
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
