-- Works out what could be on the line from what the player can see: zone, position, rod, bait,
-- fishing skill, Vana'diel time and the hook message. Mirrors fishingutils::FishingCheck in the
-- Phoenix server; the data comes from fishdata.lua (tools/build_fishdata.ps1).

require('common');

local data = require('fishdata');

local VANA_EPOCH     = 1009810800;
local SHELLFISH_BAIT = 0x40;
local LURE           = 1;
local POLY_EXTREME   = 10000;

local KIND = T{
    small   = 0x08,
    large   = 0x32,
    item    = 0x33,
    monster = 0x34,
};

local function clamp(value, low, high)
    return math.min(high, math.max(low, value));
end

local function wave(frequency, phase, x)
    return clamp(0.5 * math.cos(frequency * x + phase) + 0.5, 0, 1);
end

local function round(value)
    if (value < 0) then
        return -math.floor(-value + 0.5);
    end
    return math.floor(value + 0.5);
end

local HOUR_PATTERN = T{
    [1] = function (h) return wave(0.82, 0.16, h); end,
    [2] = function (h) return (h ~= 5 and h ~= 17) and 1.0 or 0.5; end,
    [3] = function (h) return (h == 5 or h == 17) and 1.0 or 0.5; end,
    [4] = function (h) return (h > 19 or h < 4) and 1.0 or 0.5; end,
    [5] = function (h) return wave(0.60, 3.50, h); end,
    [6] = function (h) return wave(0.53, 0.00, h); end,
    [7] = function (h) return wave(0.23, 3.53, h); end,
};

local MOON_PATTERN = T{
    [1] = function (m) return wave(1.75, 0.10, m); end,
    [2] = function (m) return wave(1.75, 3.30, m); end,
    [3] = function (m) return clamp(1 - math.floor(m / 7), 0, 1); end,
    [4] = function (m) return wave(0.90, 3.14, m); end,
};
-- The server maps pattern 5 onto pattern 4.
MOON_PATTERN[5] = MOON_PATTERN[4];

local MONTH_PATTERN = T{
    [1]  = function (m) return wave(0.40, -1.60, m); end,
    [2]  = function (m) return wave(0.60, -1.00, m); end,
    [3]  = function (m) return wave(0.50, 3.05, m); end,
    [4]  = function (m) return wave(1.04, 0.00, m); end,
    [5]  = function (m) return wave(0.40, 3.50, m); end,
    [6]  = function (m) return wave(0.90, -2.00, m); end,
    [7]  = function (m) return wave(0.49, 1.63, m); end,
    [8]  = function (m) return wave(1.04, -2.60, m); end,
    [9]  = function (m) return wave(0.49, -1.25, m); end,
    [10] = function (m) return wave(0.50, 0.53, m); end,
};

local function moon_phase(days)
    local daysmod = (days + 886 * 360 + 26) % 84;
    local phase;
    if (daysmod >= 42) then
        phase = math.floor(100 * ((daysmod - 42) / 42) + 0.5);
    else
        phase = math.floor(100 * (1 - (daysmod / 42)) + 0.5);
    end

    local direction = 2;
    if (daysmod == 42 or daysmod == 0) then
        direction = 0;
    elseif (daysmod < 42) then
        direction = 1;
    end

    if (phase <= 5 or (phase <= 10 and direction == 1)) then
        return 0;
    elseif (phase >= 7 and phase <= 38 and direction == 2) then
        return 1;
    elseif (phase >= 40 and phase <= 55 and direction == 2) then
        return 2;
    elseif (phase >= 57 and phase <= 88 and direction == 2) then
        return 3;
    elseif (phase >= 95 or (phase >= 90 and direction == 2)) then
        return 4;
    elseif (phase >= 62 and phase <= 93 and direction == 1) then
        return 5;
    elseif (phase >= 45 and phase <= 60 and direction == 1) then
        return 6;
    elseif (phase >= 12 and phase < 43 and direction == 1) then
        return 7;
    end
    return 0;
end

local function vana_clock()
    local seconds = (os.time() - VANA_EPOCH) * 25;
    local days    = math.floor(seconds / 86400);
    -- vanadiel_time::get_month() rounds up and wraps month 12 to 0; the server then subtracts one
    -- into a uint8, so the last month of the year reads as 255.
    local month = (math.floor(days / 30) + 1) % 12 - 1;
    if (month < 0) then
        month = 255;
    end
    return T{
        hour  = math.floor(seconds / 3600) % 24,
        month = month,
        moon  = moon_phase(days),
    };
end

local function pattern_modifier(patterns, pattern, value, default)
    local fn = patterns[pattern];
    return (fn and fn(value) or default) + 0.25;
end

-- fishingutils::CalculateHookChance
local function hook_chance(ctx, fish_id, fish)
    local month  = pattern_modifier(MONTH_PATTERN, fish.month, ctx.clock.month, 0.5);
    local hour   = pattern_modifier(HOUR_PATTERN, fish.hour, ctx.clock.hour, 0.5) * 2;
    local moon   = pattern_modifier(MOON_PATTERN, fish.moon, ctx.clock.moon, 1.0) * 3;
    local chance = math.floor(25 * math.max(0, (moon + hour + month) / 3));

    local power = data.affinity[ctx.bait_id][fish_id];
    local lure  = ctx.bait.type == LURE;
    if (power == 1) then
        chance = chance + (lure and 30 or 35);
    elseif (power == 2) then
        chance = chance + (lure and 60 or 65);
    elseif (power == 3) then
        chance = chance + (lure and 75 or 80);
    end

    local skill = ctx.skill;
    if (skill) then
        if (fish.skill > skill) then
            chance = chance - math.min(math.floor((fish.skill - skill) * 0.25), chance);
        end
        if (skill - 10 > fish.skill) then
            chance = chance - math.min(math.floor((skill - 10 - fish.skill) * 0.15), chance);
        end
    end

    local rod = ctx.rod;
    if (rod and not rod.legendary) then
        if (fish.size < rod.size) then
            chance = chance - math.min(3, chance);
        elseif (rod.size < fish.size) then
            chance = chance - math.min(5, chance);
        end
    end

    if (bit.band(ctx.bait.flags, SHELLFISH_BAIT) ~= 0 and fish.shellfish) then
        chance = chance + 50;
    end

    if (fish.rarity < 1000) then
        chance = math.floor(chance * fish.rarity / 1000);
    end

    return clamp(chance, 20, 120);
end

local function on_segment(p, q, r)
    return q[1] <= math.max(p[1], r[1]) and q[1] >= math.min(p[1], r[1])
       and q[3] <= math.max(p[3], r[3]) and q[3] >= math.min(p[3], r[3]);
end

local function orientation(p, q, r)
    local value = round(q[3] - p[3]) * (r[1] - q[1]) - (q[1] - p[1]) * (r[3] - q[3]);
    if (value == 0) then
        return 0;
    end
    return value > 0 and 1 or 2;
end

local function intersects(p1, q1, p2, q2)
    local o1 = orientation(p1, q1, p2);
    local o2 = orientation(p1, q1, q2);
    local o3 = orientation(p2, q2, p1);
    local o4 = orientation(p2, q2, q1);

    return (o1 ~= o2 and o3 ~= o4)
        or (o1 == 0 and on_segment(p1, p2, q1))
        or (o2 == 0 and on_segment(p1, q2, q1))
        or (o3 == 0 and on_segment(p2, p1, q2))
        or (o4 == 0 and on_segment(p2, q1, q2));
end

local function within_height(area, y)
    local half = math.floor(area.height / 2);
    return y >= area.y - half and y <= area.y + half;
end

-- fishingutils::isInsidePoly, including its ray towards (10000, 0)
local function inside_poly(area, p)
    local points = area.bounds;
    if (not within_height(area, p[2]) or not points or #points < 3) then
        return false;
    end

    local extreme = { POLY_EXTREME, p[3], 0 };
    local count   = 0;
    for i = 1, #points do
        local a = points[i];
        local b = points[(i % #points) + 1];
        if (intersects(a, b, p, extreme)) then
            if (orientation(a, p, b) == 0) then
                return on_segment(a, p, b);
            end
            count = count + 1;
        end
    end
    return count % 2 == 1;
end

local function inside_cylinder(area, p)
    if (not within_height(area, p[2])) then
        return false;
    end

    -- The server loads bound_radius into a uint8.
    local radius = area.radius % 256;
    local dx     = math.abs(p[1] - area.x);
    local dz     = math.abs(p[3] - area.z);
    if (dx > radius or dz > radius) then
        return false;
    end
    return dx + dz <= radius or dx * dx + dz * dz <= radius * radius;
end

-- fishingutils::GetFishingArea; position is in server axes (y is height).
local function find_area(zone, x, y, z)
    local p = { x, y, z };
    for _, area in ipairs(data.areas[zone] or {}) do
        if (area.type == 0
            or (area.type == 1 and inside_cylinder(area, p))
            or (area.type == 2 and inside_poly(area, p))) then
            return area;
        end
    end
    return nil;
end

local function catch_ids(zone, area)
    local catch  = data.catch[zone] or {};
    local groups = T{};
    if (area) then
        if (catch[area.id]) then
            groups:append(catch[area.id]);
        end
    else
        for _, group in pairs(catch) do
            groups:append(group);
        end
    end

    local seen = T{};
    local ids  = T{};
    for _, group in ipairs(groups) do
        for _, id in ipairs(data.groups[group] or {}) do
            if (not seen[id]) then
                seen[id] = true;
                ids:append(id);
            end
        end
    end
    return ids;
end

local function key_item_ok(ctx, key_item)
    return not key_item or ctx.has_key_item(key_item);
end

local function add_odds(rows)
    local total = 0;
    for _, row in ipairs(rows) do
        total = total + (row.weight or 0);
    end
    for _, row in ipairs(rows) do
        if (row.weight and total > 0) then
            row.odds = row.weight * 100 / total;
        end
    end
    table.sort(rows, function (a, b)
        if ((a.odds or -1) == (b.odds or -1)) then
            return a.name < b.name;
        end
        return (a.odds or -1) > (b.odds or -1);
    end);
    return rows;
end

-- The server picks one fish from the whole bait pool; the hook message then only reveals its size.
local function fish_rows(ctx, ids, size)
    local rows = T{};
    if (not ctx.bait or not data.affinity[ctx.bait_id]) then
        return rows;
    end
    for _, id in ipairs(ids) do
        local fish = data.fish[id];
        if (fish and not fish.item and fish.size == size and data.affinity[ctx.bait_id][id]
            and (not ctx.skill or ctx.skill >= fish.skill or fish.skill - ctx.skill <= 100)
            and key_item_ok(ctx, fish.keyitem)) then
            rows:append(T{
                name      = fish.name,
                skill     = fish.skill,
                weight    = hook_chance(ctx, id, fish),
                legendary = fish.legendary,
            });
        end
    end
    return add_odds(rows);
end

local function item_rows(ctx, ids)
    local rows = T{};
    for _, id in ipairs(ids) do
        local item = data.fish[id];
        if (item and item.item and (item.quest_only or key_item_ok(ctx, item.keyitem))) then
            if (item.quest) then
                rows:append(T{ name = item.name, skill = item.skill, note = 'quest' });
            else
                local weight = math.floor(100 * item.rarity / 1000);
                if (weight > 0) then
                    rows:append(T{ name = item.name, skill = item.skill, weight = weight });
                end
            end
        end
    end
    return add_odds(rows);
end

local function monster_rows(ctx, area)
    local rows = T{};
    local seen = T{};
    for _, mob in ipairs(data.mobs[ctx.zone] or {}) do
        local here = not area or mob.area == 0 or mob.area == area.id;
        local bait = not mob.bait or mob.bait == ctx.bait_id or mob.alt_bait == ctx.bait_id;
        if (here and (not mob.nm or bait) and not seen[mob.name]) then
            seen[mob.name] = true;
            rows:append(T{ name = mob.name, note = mob.nm and (mob.quest and 'quest' or 'NM') or nil });
        end
    end
    table.sort(rows, function (a, b)
        if ((a.note == nil) ~= (b.note == nil)) then
            return a.note == nil;
        end
        return a.name < b.name;
    end);
    return rows;
end

local catchpool = T{ KIND = KIND };

-- ctx: zone, x, y, z (server axes), rod_id, bait_id, skill, has_key_item(id)
function catchpool.build(ctx)
    ctx.rod   = data.rods[ctx.rod_id or 0];
    ctx.bait  = data.baits[ctx.bait_id or 0];
    ctx.clock = vana_clock();

    local area = nil;
    if (ctx.x) then
        area = find_area(ctx.zone, ctx.x, ctx.y, ctx.z);
    end

    local ids = catch_ids(ctx.zone, area);
    return T{
        known          = data.areas[ctx.zone] ~= nil,
        area           = area and area.name or nil,
        bait_ok        = ctx.bait ~= nil,
        [KIND.small]   = fish_rows(ctx, ids, 0),
        [KIND.large]   = fish_rows(ctx, ids, 1),
        [KIND.item]    = item_rows(ctx, ids),
        [KIND.monster] = monster_rows(ctx, area),
    };
end

return catchpool;
