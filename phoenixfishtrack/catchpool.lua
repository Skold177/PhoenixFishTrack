-- Works out what could be on the line from what the player can see: zone, position, rod, bait,
-- fishing skill, the moon and the hook message. Mirrors fishingutils::FishingCheck in the
-- Phoenix server; the data comes from fishdata.lua.

require('common');

local data = require('fishdata');

local VANA_EPOCH     = 1009810800;
local SHELLFISH_BAIT = 0x40;
local POOR_FISH_BAIT = 0x08;
local LURE           = 1;
local POLY_EXTREME   = 10000;
local LU_SHANG       = 17386;
local EBISU          = 17011;

-- Fisherman's Apron and Fisherman's Smock move some of the item weight to catching nothing.
local APRONS = T{ [14400] = true, [11337] = true };

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

-- MOONPATTERN_2 to MOONPATTERN_5, which FishingCheck uses to weight the item, monster, fish and
-- nothing pools.
local function moon_item(m) return wave(1.75, 3.30, m); end
local function moon_mob(m) return clamp(1 - math.floor(m / 7), 0, 1); end
local function moon_fish(m) return wave(0.90, 3.14, m); end
local function moon_none(m) return wave(0.90, 0.00, m); end

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

local function current_moon()
    local days = math.floor((os.time() - VANA_EPOCH) * 25 / 86400);
    return moon_phase(days);
end

-- fishingutils::CalculateHookChance. Phoenix never loads the fish's hour, moon and month patterns,
-- so every fish gets the pattern-0 modifiers: (1.25 * 3 + 0.75 * 2 + 0.75) / 3 = 2, times 25.
local BASE_HOOK_CHANCE = 50;

local function hook_chance(ctx, fish_id, fish)
    local chance = BASE_HOOK_CHANCE;

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

-- Every fish that can take the bait here, with its hook chance, before the hook message narrows it.
local function hookable_fish(ctx, ids)
    local hooked = T{};
    if (not ctx.bait or not data.affinity[ctx.bait_id]) then
        return hooked;
    end
    for _, id in ipairs(ids) do
        local fish = data.fish[id];
        if (fish and not fish.item and data.affinity[ctx.bait_id][id]
            and (not ctx.skill or ctx.skill >= fish.skill or fish.skill - ctx.skill <= 100)
            and key_item_ok(ctx, fish.keyitem)) then
            hooked:append(T{ fish = fish, chance = hook_chance(ctx, id, fish) });
        end
    end
    return hooked;
end

-- fishingutils::FishingCheck's pool weights: how likely a cast is to land a fish rather than an
-- item, a monster or nothing. Returns the fish weight and the weight of everything else. The server
-- also raises the fish weight by 10% in rain and 20% in a squall, which the addon can't see.
local function pool_weights(ctx, hooked, has_items, has_mobs)
    local moon = current_moon();
    local zone = data.zones[ctx.zone] or {};

    local fish, item, mob, none;
    if (zone.city) then
        fish = math.floor(15 * moon_fish(moon));
        item = 25 + math.floor(20 * moon_item(moon));
        mob  = 0;
        none = 30 + math.floor(15 * moon_none(moon));
    else
        fish = math.floor(25 * moon_fish(moon));
        item = 10 + math.floor(15 * moon_item(moon));
        mob  = 15 + math.floor(15 * moon_mob(moon));
        none = 15 + math.floor(20 * moon_none(moon));
    end

    local best = 0;
    for _, entry in ipairs(hooked) do
        best = math.max(best, entry.chance);
    end
    fish = clamp(best + fish, 10, 120);

    -- The server adds difficulty times a random 20 to 30; this takes the middle.
    none = none + (zone.difficulty or 0) * 25;

    if (APRONS[ctx.body] and item > 0) then
        local moved = math.floor(item * 0.25);
        item = item - moved;
        none = none + moved;
    end

    if (bit.band(ctx.bait.flags, POOR_FISH_BAIT) ~= 0 and fish > 0) then
        fish = fish - math.floor(fish * 0.25);
        item = fish + math.floor(fish * 0.10);
        none = none + math.floor(none * 0.25);
    end

    if (not has_items) then
        none = none + math.floor(item / 2);
        item = 0;
    end
    if (not has_mobs) then
        none = none + math.floor(mob / 2);
        mob  = 0;
    end

    return fish, item + mob + none;
end

-- Lu Shang's and Ebisu (not their +1 versions) raise the fish weight once a fish is picked, more for
-- fish further below the angler's skill.
local function rod_bonus(ctx, fish)
    if ((ctx.rod_id ~= LU_SHANG and ctx.rod_id ~= EBISU) or not ctx.skill or ctx.skill <= fish.skill + 7) then
        return 0;
    end
    local gap        = ctx.skill - fish.skill;
    local lu_shang   = ctx.rod_id == LU_SHANG;
    local multiplier = 1 + math.floor(gap / (lu_shang and 15 or 13));
    -- The server truncates this part to a uint8.
    return (lu_shang and 10 or 15) + math.floor(gap * multiplier / (fish.size + 1)) % 256;
end

-- The server picks one fish from the whole bait pool by hook chance, then rolls whether the cast
-- lands a fish at all; the hook message only reveals the fish's size.
local function fish_rows(ctx, hooked, size, fish_weight, other_weight)
    local rows = T{};
    for _, entry in ipairs(hooked) do
        local fish = entry.fish;
        if (fish.size == size) then
            local weight = fish_weight + rod_bonus(ctx, fish);
            rows:append(T{
                name      = fish.name,
                skill     = fish.skill,
                weight    = entry.chance * weight / (weight + other_weight),
                legendary = fish.legendary,
            });
        end
    end
    return add_odds(rows);
end

-- Also reports whether the server's item pool is non-empty, which it is even for items too rare to
-- ever be picked.
local function item_rows(ctx, ids)
    local rows   = T{};
    local pooled = false;
    for _, id in ipairs(ids) do
        local item = data.fish[id];
        if (item and item.item and (item.quest_only or key_item_ok(ctx, item.keyitem))) then
            if (item.quest) then
                rows:append(T{ name = item.name, skill = item.skill, note = 'quest' });
            else
                pooled = true;
                local weight = math.floor(100 * item.rarity / 1000);
                if (weight > 0) then
                    rows:append(T{ name = item.name, skill = item.skill, weight = weight });
                end
            end
        end
    end
    return add_odds(rows), pooled;
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

-- ctx: zone, x, y, z (server axes), rod_id, bait_id, body (equipped body item id), skill,
-- has_key_item(id)
function catchpool.build(ctx)
    ctx.rod  = data.rods[ctx.rod_id or 0];
    ctx.bait = data.baits[ctx.bait_id or 0];

    local area = nil;
    if (ctx.x) then
        area = find_area(ctx.zone, ctx.x, ctx.y, ctx.z);
    end

    local ids               = catch_ids(ctx.zone, area);
    local hooked            = hookable_fish(ctx, ids);
    local items, has_items  = item_rows(ctx, ids);
    local monsters          = monster_rows(ctx, area);
    local fish_weight, rest = 0, 0;
    if (#hooked > 0) then
        fish_weight, rest = pool_weights(ctx, hooked, has_items, #monsters > 0);
    end

    return T{
        known          = data.areas[ctx.zone] ~= nil,
        area           = area and area.name or nil,
        bait_ok        = ctx.bait ~= nil,
        [KIND.small]   = fish_rows(ctx, hooked, 0, fish_weight, rest),
        [KIND.large]   = fish_rows(ctx, hooked, 1, fish_weight, rest),
        [KIND.item]    = items,
        [KIND.monster] = monsters,
    };
end

return catchpool;
