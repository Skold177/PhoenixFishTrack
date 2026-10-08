-- Digging tab for PhoenixTracker. Tracks chocobo digging against Phoenix's 100 find daily allowance.
-- The window, theme, settings panel and commands live in phoenixtracker.lua.
require('common');

local imgui    = require('imgui');
local settings = require('settings');
local ui       = require('ui');
local digdata  = require('digdata');

local DAILY_LIMIT    = 100;   -- Phoenix DIG_FATIGUE: items found per day, shared by the whole account.
-- Wing skill is hidden: Phoenix blanks it in the skills packet. Its exact level is only sent when you
-- talk to a chocobo stable clerk, as the second event parameter. Zone ID -> clerk event ID.
local STABLE_CLERKS  = T{
    [230] = 846,  -- Arvilauge, Southern San d'Oria
    [234] = 534,  -- Gonija, Bastok Mines
    [241] = 761,  -- Kiria-Romaria, Windurst Woods
};
local GYSAHL_GREENS  = 4545;
local MAX_LEVEL      = 100;
local SAME_SPOT      = 4;     -- Digging within this many yalms of the last dig always finds nothing.
local OUTCOME_WAIT   = 10;    -- Phoenix sends the result about 3 seconds after the dig animation.
local VANA_EPOCH     = 1009810800;
local PADDING        = ui.PADDING;

local RANK_NAMES = T{
    [0] = 'Amateur', 'Recruit', 'Initiate', 'Novice', 'Apprentice', 'Journeyman',
    'Craftsman', 'Artisan', 'Adept', 'Veteran', 'Expert',
};

local WEATHER_NAMES = T{
    [0] = 'Clear', 'Sunshine', 'Clouds', 'Fog', 'Hot Spell', 'Heat Wave', 'Rain', 'Squall',
    'Dust Storm', 'Sand Storm', 'Wind', 'Gales', 'Snow', 'Blizzards', 'Thunder',
    'Thunderstorms', 'Auroras', 'Stellar Glare', 'Gloom', 'Darkness',
};

local M = T{ key = 'dig', label = 'Digging' };

-- Settings this tab adds to PhoenixTracker's.
M.defaults = T{
    dig_account = '',
};

local COLOR               = ui.COLOR;
local say                 = ui.say;
local warn                = ui.warn;
local jst_day             = ui.jst_day;
local seconds_until_reset = ui.seconds_until_reset;
local duration            = ui.duration;
local u16                 = ui.u16;
local u32                 = ui.u32;
local text_width          = ui.text_width;
local right_text          = ui.right_text;
local stat_cell           = ui.stat_cell;

-- Shared with phoenixtracker.lua: ctx.settings, and ctx.activity() to switch to this tab.
local ctx = nil;

local function new_session()
    return T{
        started   = nil,
        digs      = 0,   -- Dig animations, one bunch of Gysahl Greens each.
        found     = 0,   -- Items found, including ones thrown away for a full inventory.
        nothing   = 0,
        too_close = 0,
        after_cap = 0,
        xp        = 0,
        levels    = 0,
    };
end

local pd = T{
    session         = new_session(),
    label           = nil,
    daily           = nil,
    wing            = nil,
    names           = T{},
    pending         = T{},
    weather         = nil,
    zone_in         = 0,
    last_dig        = 0,
    last_spot       = nil,
    last_gain       = nil,
    limit_announced = false,
    last_tick       = 0,
};

-----------------------------------
-- Time
-----------------------------------
local function vana_hour()
    return math.floor((os.time() - VANA_EPOCH) * 25 / 3600) % 24;
end

local function is_night()
    local hour = vana_hour();
    return hour >= 20 or hour < 4;
end

-----------------------------------
-- Player
-----------------------------------
local function party()
    return AshitaCore:GetMemoryManager():GetParty();
end

local function player_name()
    local name = party():GetMemberName(0);
    if (not name or name == '') then
        return nil;
    end
    return name;
end

local function account_label()
    if (ctx.settings.dig_account ~= '') then
        return ctx.settings.dig_account;
    end
    return player_name();
end

local function zone_id()
    return party():GetMemberZone(0);
end

local function dig_zone()
    return digdata.zones[zone_id()];
end

-- Wing skill level, or nil until a stable clerk, a level-up message or /pdig skill has told us.
local function wing_skill()
    return pd.wing and pd.wing.level or nil;
end

-- Phoenix raises the rank at every tenth level, so it's always the level's tens digit.
local function dig_rank()
    local level = wing_skill();
    if (not level) then
        return 0;
    end
    return math.min(10, math.floor(level / 10));
end

local function item_name(id)
    local name = pd.names[id];
    if (name) then
        return name;
    end
    local item = AshitaCore:GetResourceManager():GetItemById(id);
    name = (item and item.Name[1]) or ('Item %d'):fmt(id);
    pd.names[id] = name;
    return name;
end

-- The server only takes greens from the main inventory.
local function greens_count()
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    local total     = 0;
    for index = 1, inventory:GetContainerCountMax(0) do
        local item = inventory:GetContainerItem(0, index);
        if (item and item.Id == GYSAHL_GREENS) then
            total = total + item.Count;
        end
    end
    return total;
end

local function my_position()
    local index  = party():GetMemberTargetIndex(0);
    local entity = AshitaCore:GetMemoryManager():GetEntity();
    return T{
        x = entity:GetLocalPositionX(index),
        y = entity:GetLocalPositionY(index),
        z = entity:GetLocalPositionZ(index),
    };
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
end

-----------------------------------
-- Dig table
-----------------------------------
-- Everything Phoenix can pick from on a successful dig here, with its odds. Mirrors handleItemRoll in
-- modules/phoenix/lua/globals/hobbies/chocobo_digging/pxi_digging_logic.lua.
local function find_pool(rank)
    local zone = dig_zone();
    if (not zone) then
        return nil;
    end

    local night = is_night();
    local rows  = T{};
    local total = 0;
    for _, row in ipairs(zone.rows) do
        local weight = row[3 + rank];
        if (weight > 0 and (night or not digdata.night_only[row[1]])) then
            rows:append(T{ id = row[1], rank = row[2], weight = weight, night = digdata.night_only[row[1]] });
            total = total + weight;
        end
    end

    if (pd.weather) then
        local crystal = digdata.crystal_by_weather[pd.weather];
        if (crystal and digdata.crystal_weight[rank] > 0) then
            rows:append(T{ id = crystal, rank = 0, weight = digdata.crystal_weight[rank] });
            total = total + digdata.crystal_weight[rank];
        end
        local cluster = digdata.cluster_by_weather[pd.weather];
        if (cluster and digdata.cluster_weight[rank] > 0) then
            rows:append(T{ id = cluster, rank = 0, weight = digdata.cluster_weight[rank] });
            total = total + digdata.cluster_weight[rank];
        end
    end

    local avg_xp = 0;
    for _, row in ipairs(rows) do
        row.odds = row.weight * 100 / total;
        row.xp   = digdata.xp_per_rank[row.rank];
        avg_xp   = avg_xp + row.xp * row.weight / total;
    end
    table.sort(rows, function (a, b)
        if (a.weight == b.weight) then
            return a.id < b.id;
        end
        return a.weight > b.weight;
    end);

    return T{
        rows       = rows,
        avg_xp     = avg_xp,
        night      = night,
        ore_note   = digdata.ore_zones[zone_id()] and digdata.ore_weight[rank] > 0,
    };
end

-- The item's rank in this zone's table sets the experience. Crystals and clusters count as Amateur,
-- elemental ores as Expert.
local function xp_for(id)
    local zone = dig_zone();
    if (zone) then
        for _, row in ipairs(zone.rows) do
            if (row[1] == id) then
                return digdata.xp_per_rank[row[2]];
            end
        end
    end
    for _, ore in pairs(digdata.ore_by_day) do
        if (ore == id) then
            return digdata.xp_per_rank[10];
        end
    end
    return digdata.xp_per_rank[0];
end

-----------------------------------
-- Saved data
-----------------------------------
local function save_daily()
    if (not pd.label or not pd.daily) then
        return;
    end
    local all = ui.read_data('dig_daily.lua');
    all[pd.label] = pd.daily;

    local lines = T{ 'return {' };
    for label, day in pairs(all) do
        local items = T{};
        for id, quantity in pairs(day.items or {}) do
            items:append((' [%d] = %d,'):fmt(id, quantity));
        end
        lines:append(('    [%q] = { day = %q, finds = %d, thrown = %d, items = {%s } },'):fmt(
            label, day.day, tonumber(day.finds) or 0, tonumber(day.thrown) or 0, items:concat('')));
    end
    lines:append('}');
    ui.write_data('dig_daily.lua', lines:concat('\n') .. '\n');
end

local function fresh_day()
    return T{ day = jst_day(), finds = 0, thrown = 0, items = T{} };
end

local function load_daily()
    pd.label = account_label();
    pd.daily = nil;
    if (not pd.label) then
        return;
    end
    local stored = ui.read_data('dig_daily.lua')[pd.label];
    if (stored and stored.day == jst_day()) then
        pd.daily = T{
            day    = stored.day,
            finds  = tonumber(stored.finds) or 0,
            thrown = tonumber(stored.thrown) or 0,
            items  = T(stored.items or {}),
        };
    else
        pd.daily = fresh_day();
    end
    pd.limit_announced = pd.daily.finds >= DAILY_LIMIT;
end

local function rollover_day()
    if (pd.daily and pd.daily.day ~= jst_day()) then
        pd.daily           = fresh_day();
        pd.limit_announced = false;
        save_daily();
    end
end

-- Wing skill experience is a hidden character variable, so the addon keeps a range [lo, hi] of where
-- it can be. Each find adds a known amount, and each level-up pins it to below the last find's value.
local function save_wing()
    local name = player_name();
    if (not name or not pd.wing) then
        return;
    end
    local all = ui.read_data('wing.lua');
    all[name] = pd.wing;

    local lines = T{ 'return {' };
    for who, w in pairs(all) do
        lines:append(('    [%q] = { level = %d, lo = %d, hi = %d, calibrated = %s },'):fmt(
            who, w.level, w.lo, w.hi, tostring(w.calibrated == true)));
    end
    lines:append('}');
    ui.write_data('wing.lua', lines:concat('\n') .. '\n');
end

local function fresh_wing(level)
    local need = digdata.xp_to_level[level + 1] or 0;
    return T{ level = level, lo = 0, hi = math.max(0, need - 1), calibrated = false };
end

local function load_wing()
    pd.wing = nil;
    local name = player_name();
    if (not name) then
        return;
    end
    local stored = ui.read_data('wing.lua')[name];
    if (stored and tonumber(stored.level)) then
        pd.wing = T{ level = stored.level, lo = stored.lo, hi = stored.hi, calibrated = stored.calibrated };
    end
end

-- A level from a stable clerk or /pdig skill. The same level keeps the experience estimate.
local function set_level(level, source)
    level = math.min(MAX_LEVEL, math.max(0, math.floor(level)));
    if (pd.wing and pd.wing.level == level) then
        return;
    end
    pd.wing = fresh_wing(level);
    save_wing();
    say(('Wing skill level %d (%s rank) recorded from %s.'):fmt(level, RANK_NAMES[math.min(10, math.floor(level / 10))], source));
end

local function wing_need()
    return digdata.xp_to_level[pd.wing.level + 1];
end

local function gain_xp(amount)
    local wing = pd.wing;
    pd.last_gain  = amount;
    pd.session.xp = pd.session.xp + amount;
    if (not wing or wing.level >= MAX_LEVEL) then
        return;
    end
    -- The previous find didn't level, so experience was still below what the level needs.
    local cap = wing_need() - 1;
    wing.hi = math.min(wing.hi, cap);
    wing.lo = math.min(wing.lo, wing.hi);

    wing.lo = wing.lo + amount;
    wing.hi = wing.hi + amount;
    save_wing();
end

local function level_up(level)
    pd.session.levels = pd.session.levels + 1;
    local wing = pd.wing;

    if (not wing) then
        -- gain_xp could not update an unknown level. Start at the new level so we don't
        -- subtract the old threshold from a range that never included the triggering find.
        wing    = fresh_wing(level);
        pd.wing = wing;
    elseif (level == wing.level + 1) then
        local need = wing_need();
        wing.lo = math.max(0, wing.lo - need);
        wing.hi = wing.hi - need;
    else
        wing.lo = 0;
        wing.hi = math.max(0, (digdata.xp_to_level[level + 1] or 0) - 1);
    end
    -- The excess carried over is always less than the find that caused the level-up.
    if (pd.last_gain) then
        wing.hi = math.min(wing.hi, pd.last_gain - 1);
        wing.calibrated = true;
    end
    wing.level = level;
    wing.hi    = math.max(wing.hi, wing.lo);
    save_wing();
end

-----------------------------------
-- Digging events
-----------------------------------
local function expire_pending()
    local now = os.clock();
    while (#pd.pending > 0 and now - pd.pending[1].at > OUTCOME_WAIT) do
        table.remove(pd.pending, 1);
    end
end

local function take_pending()
    expire_pending();
    if (#pd.pending == 0) then
        return nil;
    end
    return table.remove(pd.pending, 1);
end

-- Phoenix checks, in order: the daily limit, the same spot (under 4 yalms from the last dig that got
-- past both checks), then the accuracy roll. Only a dig that passes the first two moves the spot.
local function on_dig()
    rollover_day();
    local session   = pd.session;
    session.started = session.started or os.time();
    session.digs    = session.digs + 1;
    pd.last_dig     = os.clock();

    local dig = T{ at = os.clock(), day = jst_day() };
    if (pd.daily and pd.daily.finds >= DAILY_LIMIT) then
        dig.capped = true;
    else
        local here = my_position();
        if (pd.last_spot and distance(here, pd.last_spot) < SAME_SPOT) then
            dig.close = true;
        else
            pd.last_spot = here;
        end
    end
    pd.pending:append(dig);
    ctx.activity(M);
end

local function record_find(id, thrown)
    rollover_day();
    local session = pd.session;
    local daily   = pd.daily;
    local dig     = take_pending();
    session.found = session.found + 1;

    -- Phoenix charges the allowance at the animation, three seconds before its result.
    -- A result from before midnight still earns session XP, but belongs to the old day.
    if (daily and (not dig or dig.day == daily.day)) then
        daily.finds = daily.finds + 1;
        if (thrown) then
            daily.thrown = daily.thrown + 1;
        else
            daily.items[id] = (daily.items[id] or 0) + 1;
        end
        save_daily();

        if (daily.finds >= DAILY_LIMIT and not pd.limit_announced) then
            pd.limit_announced = true;
            warn(('Daily limit reached (%d). Digging finds nothing until the JST midnight reset, in %s.'):fmt(
                DAILY_LIMIT, duration(seconds_until_reset())));
        end
    end

    gain_xp(xp_for(id));
end

local function record_nothing()
    local session = pd.session;
    local dig     = take_pending();
    session.nothing = session.nothing + 1;
    if (dig and dig.capped) then
        session.after_cap = session.after_cap + 1;
    elseif (dig and dig.close) then
        session.too_close = session.too_close + 1;
    end
end

local function on_message(message, param)
    local zone = dig_zone();
    if (not zone) then
        return;
    end
    local msg = zone.msg;

    if (message == msg.obtained) then
        -- "Obtained: <item>." is used everywhere, so it only counts right after a dig.
        expire_pending();
        if (#pd.pending > 0) then
            record_find(param, false);
        end
    elseif (message == msg.throw_away) then
        record_find(param, true);
    elseif (message == msg.cache + 5) then
        level_up(param);
    end
end

-----------------------------------
-- Drawing
-----------------------------------
local function percent(value)
    if (value > 0 and value < 0.1) then
        return '<0.1%';
    end
    if (value > 0 and value < 10) then
        return ('%.1f%%'):fmt(value);
    end
    return ('%.0f%%'):fmt(value);
end

-- Wraps at the window edge, so a long note doesn't stretch the auto-sized window.
local function note(width, color, text)
    imgui.PushTextWrapPos(PADDING + width);
    imgui.TextColored(color, text);
    imgui.PopTextWrapPos();
end

local function info_line(label, value, color)
    local indent = math.max(text_width('Zone:'), text_width('Greens:')) + 8;
    imgui.TextColored(COLOR.muted, label);
    imgui.SameLine(PADDING + indent);
    imgui.TextColored(color, value);
end

local function next_dig_in()
    local rank   = dig_rank();
    local now    = os.clock();
    local zone   = pd.zone_in + math.min(60, math.max(10, 60 - rank * 5));
    local dig    = pd.last_dig + math.min(16, math.max(3, 15 - rank * 5));
    if (pd.last_dig == 0) then
        dig = 0;
    end
    if (pd.zone_in == 0) then
        zone = 0;
    end
    return math.max(0, math.max(zone, dig) - now);
end

local function draw_status(width)
    local zone   = dig_zone();
    local greens = greens_count();

    imgui.Spacing();
    if (zone) then
        info_line('Zone:', zone.name, COLOR.secondary);
        local weather = pd.weather and WEATHER_NAMES[pd.weather] or 'unknown';
        right_text(width, COLOR.muted, weather);
    else
        info_line('Zone:', 'No digging here', COLOR.danger);
    end

    info_line('Greens:', tostring(greens), greens > 0 and COLOR.secondary or COLOR.danger);
    if (zone) then
        local wait = next_dig_in();
        if (wait > 0) then
            right_text(width, COLOR.ember, ('next dig in %ds'):fmt(math.ceil(wait)));
        else
            right_text(width, COLOR.success, 'ready to dig');
        end
    end
end

local function draw_daily(width, scale, font, font_size)
    local daily = pd.daily;
    local done  = daily.finds >= DAILY_LIMIT;

    imgui.Spacing();
    imgui.TextColored(COLOR.muted, 'DAILY FINDS');

    imgui.PushFont(font, font_size * 2.0);
    local big = imgui.GetFontSize();
    imgui.TextColored(done and COLOR.success or COLOR.text, tostring(daily.finds));
    imgui.PopFont();
    local small = imgui.GetFontSize();
    imgui.SameLine();
    imgui.SetCursorPosY(imgui.GetCursorPosY() + (big - small) * 0.8);
    imgui.TextColored(COLOR.muted, ('/ %d'):fmt(DAILY_LIMIT));
    right_text(width, COLOR.ember, ('%d%%'):fmt(math.floor(math.min(daily.finds, DAILY_LIMIT) * 100 / DAILY_LIMIT)));

    imgui.PushStyleColor(ImGuiCol_PlotHistogram, done and COLOR.success or COLOR.royal);
    imgui.ProgressBar(math.min(1, daily.finds / DAILY_LIMIT), { width, 10 * scale }, '');
    imgui.PopStyleColor(1);

    local reset_in = seconds_until_reset();
    imgui.TextColored(COLOR.secondary, ('%d left'):fmt(math.max(0, DAILY_LIMIT - daily.finds)));
    right_text(width, COLOR.muted, ('resets %s (%s)'):fmt(os.date('%H:%M', os.time() + reset_in), duration(reset_in)));

    if (done) then
        note(width, COLOR.gold, 'Limit reached. Digs find nothing until the reset.');
    end
    imgui.Spacing();
end

local function draw_session(width)
    if (not imgui.CollapsingHeader('Session', ImGuiTreeNodeFlags_DefaultOpen)) then
        return;
    end

    local session = pd.session;
    local elapsed = session.started and (os.time() - session.started) or 0;

    -- Digs after the daily limit can't find anything, so they're left out of the hit rate.
    local hit_rate = '-';
    local counted  = session.digs - session.after_cap;
    if (counted > 0) then
        hit_rate = ('%.0f%%'):fmt(session.found * 100 / counted);
    end

    local per_hour = '-';
    local to_limit = '-';
    if (elapsed >= 60 and session.found > 0) then
        local rate = session.found * 3600 / elapsed;
        per_hour = ('%.0f'):fmt(rate);
        to_limit = duration(math.max(0, DAILY_LIMIT - pd.daily.finds) / rate * 3600);
    end

    -- Greens still needed to reach the cap, at the hit chance for your rank. Red when your inventory
    -- doesn't hold that many.
    local greens_needed = '-';
    local short_color   = nil;
    if (wing_skill()) then
        local left   = math.max(0, DAILY_LIMIT - pd.daily.finds);
        local needed = math.ceil(left * 100 / digdata.accuracy[dig_rank()]);
        greens_needed = tostring(needed);
        if (needed > greens_count()) then
            short_color = COLOR.danger;
        end
    end

    -- Two-row grid: each column's width follows its longest label, so the long greens labels
    -- don't run into their neighbours.
    local labels = {
        { 'Greens used', 'Per hour' },
        { ('Greens to %d'):fmt(DAILY_LIMIT), ('Time to %d'):fmt(DAILY_LIMIT) },
        { 'Nothing', 'Too close' },
        { 'Hit rate', 'Expected' },
    };
    if (imgui.BeginTable('##pd_session', 4, ImGuiTableFlags_SizingStretchProp, { width, 0 })) then
        for index, pair in ipairs(labels) do
            local widest = math.max(text_width(pair[1]), text_width(pair[2]));
            imgui.TableSetupColumn(('##pd_session_%d'):fmt(index), ImGuiTableColumnFlags_WidthStretch, widest + 8, 0);
        end
        stat_cell(labels[1][1], tostring(session.digs));
        stat_cell(labels[2][1], greens_needed, short_color);
        stat_cell(labels[3][1], tostring(session.nothing));
        stat_cell(labels[4][1], hit_rate);
        stat_cell(labels[1][2], per_hour);
        stat_cell(labels[2][2], to_limit);
        -- Too close sits under Nothing (it's a kind of nothing) and Expected under Hit rate to compare.
        stat_cell(labels[3][2], tostring(session.too_close), session.too_close > 0 and COLOR.ember or nil);
        stat_cell(labels[4][2], wing_skill() and ('%d%%'):fmt(digdata.accuracy[dig_rank()]) or '-');
        imgui.EndTable();
    end
    if (session.after_cap > 0) then
        note(width, COLOR.gold, ('%d greens spent after the daily limit.'):fmt(session.after_cap));
    end
end

local function draw_wing(width, scale, pool)
    if (not imgui.CollapsingHeader('Wing Skill', ImGuiTreeNodeFlags_DefaultOpen)) then
        return;
    end

    local wing = pd.wing;
    if (not wing) then
        imgui.TextColored(COLOR.danger, 'Wing skill unknown.');
        right_text(width, pd.session.xp > 0 and COLOR.success or COLOR.muted, ('+%d XP'):fmt(pd.session.xp));
        note(width, COLOR.faint, 'Talk to a chocobo stable clerk (South San d\'Oria, Bastok Mines or Windurst Woods), or use /pdig skill <level>. A wing skill level-up also sets it.');
        return;
    end

    local rank = math.min(10, math.floor(wing.level / 10));
    imgui.TextColored(COLOR.text, ('Level %d'):fmt(wing.level));
    imgui.SameLine();
    imgui.TextColored(COLOR.peach, RANK_NAMES[rank] or '');

    local gained = ('+%d XP'):fmt(pd.session.xp);
    if (pd.session.levels > 0) then
        gained = ('%s, +%d lv'):fmt(gained, pd.session.levels);
    end
    right_text(width, pd.session.xp > 0 and COLOR.success or COLOR.muted, gained);

    if (wing.level >= MAX_LEVEL) then
        imgui.TextColored(COLOR.gold, 'Wing skill capped.');
        return;
    end

    local need = wing_need();
    local lo   = math.min(wing.lo, need - 1);
    local hi   = math.min(wing.hi, need - 1);
    ui.range_bar(width, 10 * scale, lo / need, (hi + 1) / need, COLOR.gold);

    local xp_text;
    if (lo == hi) then
        xp_text = ('%d / %d XP'):fmt(lo, need);
    else
        xp_text = ('%d-%d / %d XP'):fmt(lo, hi, need);
    end
    imgui.TextColored(COLOR.secondary, xp_text);

    if (pool and pool.avg_xp > 0) then
        local left   = need - (lo + hi) / 2;
        local finds  = math.max(1, math.ceil(left / pool.avg_xp));
        local digs   = math.ceil(finds * 100 / digdata.accuracy[dig_rank()]);
        right_text(width, COLOR.muted, ('~%d finds (~%d digs)'):fmt(finds, digs));
    end

    if (not wing.calibrated) then
        note(width, COLOR.faint, 'Exact progress is known after your next level-up.');
    end
end

local function draw_pool(width, scale, pool)
    if (not imgui.CollapsingHeader('Possible Finds')) then
        return;
    end
    if (not pool) then
        imgui.TextColored(COLOR.faint, 'You can\'t dig in this zone.');
        return;
    end

    local flags = bit.bor(ImGuiTableFlags_RowBg, ImGuiTableFlags_BordersInnerH, ImGuiTableFlags_PadOuterX);
    if (imgui.BeginTable('##pd_pool', 3, flags, { width, 0 })) then
        imgui.TableSetupColumn('Item', ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.TableSetupColumn('XP', ImGuiTableColumnFlags_WidthFixed, text_width('100') + 4 * scale, 0);
        imgui.TableSetupColumn('Odds', ImGuiTableColumnFlags_WidthFixed, math.max(text_width('Odds'), text_width('0.5%')) + 4 * scale, 0);
        imgui.TableHeadersRow();
        for _, row in ipairs(pool.rows) do
            imgui.TableNextRow();
            imgui.TableNextColumn();
            imgui.TextColored(row.night and COLOR.peach or COLOR.secondary, item_name(row.id));
            imgui.TableNextColumn();
            imgui.TextColored(COLOR.muted, tostring(row.xp));
            imgui.TableNextColumn();
            imgui.TextColored(COLOR.text, percent(row.odds));
        end
        imgui.EndTable();
    end

    -- The odds follow the rank column of Phoenix's dig table, so they change every 10 wing skill levels.
    if (wing_skill()) then
        note(width, COLOR.peach, ('Odds are correlated to your current wing skill (%s rank) and change with each new rank.'):fmt(RANK_NAMES[dig_rank()]));
    else
        note(width, COLOR.danger, 'Wing skill unknown, so these are Amateur odds. See Wing Skill above to set it.');
    end
    note(width, COLOR.faint, ('Odds are for what you get when a dig finds something. %s.'):fmt(pool.night and 'Night: seeds can turn up' or 'Day: no seeds until 20:00'));
    if (not pd.weather) then
        note(width, COLOR.faint, 'Weather unknown until it changes or you zone.');
    end
    if (pool.ore_note) then
        note(width, COLOR.faint, 'Elemental ore can also turn up in weather on a waxing crescent.');
    end
end

local function draw_finds(width, scale)
    if (not imgui.CollapsingHeader('Today\'s Dig', ImGuiTreeNodeFlags_DefaultOpen)) then
        return;
    end

    local rows = T{};
    for id, quantity in pairs(pd.daily.items) do
        rows:append(T{ id = id, name = item_name(id), quantity = quantity });
    end

    if (#rows == 0 and pd.daily.thrown == 0) then
        imgui.TextColored(COLOR.faint, 'Nothing dug up yet today.');
        return;
    end

    table.sort(rows, function (a, b)
        if (a.quantity == b.quantity) then
            return a.name < b.name;
        end
        return a.quantity > b.quantity;
    end);

    local flags = bit.bor(ImGuiTableFlags_RowBg, ImGuiTableFlags_BordersInnerH, ImGuiTableFlags_PadOuterX);
    local size  = { width, 0 };
    if (#rows > 10) then
        flags = bit.bor(flags, ImGuiTableFlags_ScrollY);
        size  = { width, 11 * imgui.GetTextLineHeightWithSpacing() };
    end

    if (imgui.BeginTable('##pd_finds', 2, flags, size)) then
        imgui.TableSetupColumn('Item', ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.TableSetupColumn('Qty', ImGuiTableColumnFlags_WidthFixed, 44 * scale, 0);
        imgui.TableHeadersRow();
        for _, row in ipairs(rows) do
            imgui.TableNextRow();
            imgui.TableNextColumn();
            imgui.TextColored(COLOR.secondary, row.name);
            imgui.TableNextColumn();
            imgui.TextColored(COLOR.text, tostring(row.quantity));
        end
        if (pd.daily.thrown > 0) then
            imgui.TableNextRow();
            imgui.TableNextColumn();
            imgui.TextColored(COLOR.danger, 'Thrown away (inventory full)');
            imgui.TableNextColumn();
            imgui.TextColored(COLOR.text, tostring(pd.daily.thrown));
        end
        imgui.EndTable();
    end
end

local function tick()
    local now = os.time();
    if (now == pd.last_tick) then
        return;
    end
    pd.last_tick = now;

    if (account_label() ~= pd.label) then
        load_daily();
        load_wing();
        return;
    end
    rollover_day();
end

-----------------------------------
-- Commands
-----------------------------------
local function print_pool()
    local rank = dig_rank();
    local pool = find_pool(rank);
    if (not pool) then
        say('You can\'t dig in this zone.');
        return;
    end
    local skill = wing_skill() and ('%s rank'):fmt(RANK_NAMES[rank]) or 'wing skill unknown, Amateur odds';
    say(('%s, %s, %d%% chance to find something:'):fmt(dig_zone().name, skill, digdata.accuracy[rank]));
    local names = T{};
    for _, row in ipairs(pool.rows) do
        names:append(('%s %s'):fmt(item_name(row.id), percent(row.odds)));
    end
    say(names:concat(', '));
end

local function set_account(label)
    local previous = pd.daily;
    ctx.settings.dig_account = label;
    settings.save();
    load_daily();

    if (previous and pd.daily and pd.daily.finds == 0 and next(pd.daily.items) == nil and previous.day == pd.daily.day) then
        pd.daily           = previous;
        pd.limit_announced = previous.finds >= DAILY_LIMIT;
        save_daily();
    end
end

-----------------------------------
-- PhoenixTracker module interface
-----------------------------------
function M.init(context)
    ctx = context;
end

function M.ready()
    return pd.daily ~= nil;
end

function M.day()
    return pd.daily and pd.daily.day or jst_day();
end

function M.account()
    return ctx.settings.dig_account;
end

function M.fit_width(width)
    return width;
end

function M.draw(width, scale, font, font_size)
    local pool = find_pool(dig_rank());
    draw_status(width);
    draw_daily(width, scale, font, font_size);
    draw_session(width);
    draw_wing(width, scale, pool);
    draw_pool(width, scale, pool);
    draw_finds(width, scale);
end

function M.render_popups()
end

function M.reset_session()
    pd.session = new_session();
end

function M.reset_positions()
end

function M.reload()
    load_daily();
    load_wing();
end

function M.help(prefix)
    say(('%s set <count> - correct today\'s find count'):fmt(prefix));
    say(('%s account <name> - share one count between characters on the same account'):fmt(prefix));
    say(('%s account - count this character on its own again'):fmt(prefix));
    say(('%s reset - clear digging session stats'):fmt(prefix));
    say(('%s pool - list what can be dug up here'):fmt(prefix));
    say(('%s skill <level> - set your wing skill level (a stable clerk also sets it)'):fmt(prefix));
    say(('%s xp reset - forget the wing skill experience estimate'):fmt(prefix));
end

-- Returns true if the subcommand was handled.
function M.command(sub, args, prefix)
    if (sub == 'set') then
        local count = tonumber(args[3]);
        if (not count or not pd.daily) then
            say(('Usage: %s set <count>'):fmt(prefix));
            return true;
        end
        pd.daily.finds     = math.max(0, math.floor(count));
        pd.limit_announced = pd.daily.finds >= DAILY_LIMIT;
        save_daily();
        say(('Today\'s find count set to %d / %d.'):fmt(pd.daily.finds, DAILY_LIMIT));
    elseif (sub == 'account') then
        set_account(table.concat(args, ' ', 3));
        if (ctx.settings.dig_account == '') then
            say('Counting this character\'s finds on its own.');
        else
            say(('Sharing today\'s find count with every character set to "%s".'):fmt(ctx.settings.dig_account));
        end
    elseif (sub == 'reset') then
        M.reset_session();
        say('Digging session stats cleared.');
    elseif (sub == 'pool') then
        print_pool();
    elseif (sub == 'skill') then
        local level = tonumber(args[3]);
        if (not level) then
            say(('Usage: %s skill <0-100>'):fmt(prefix));
            return true;
        end
        set_level(level, 'your command');
    elseif (sub == 'xp' and (args[3] or ''):lower() == 'reset') then
        local level = wing_skill();
        if (level) then
            pd.wing = fresh_wing(level);
            save_wing();
            say('Wing skill experience estimate cleared.');
        end
    else
        return false;
    end
    return true;
end

function M.packet_in(e)
    local me = party():GetMemberServerId(0);

    if (e.id == 0x00A) then
        -- Zone in: Phoenix blocks digging for a while and forgets the last dig spot.
        pd.zone_in   = os.clock();
        pd.last_dig  = 0;
        pd.last_spot = nil;
        pd.pending   = T{};
        pd.weather   = u16(e.data, 0x68);
        return;
    end

    if (e.id == 0x057) then
        pd.weather = u16(e.data, 0x08);
        return;
    end

    -- Stable clerk conversation. With parameters it's 0x034 and the level is the second one; at
    -- level 0 with nothing else to send, the server uses 0x032 instead.
    if (e.id == 0x034) then
        if (STABLE_CLERKS[u16(e.data, 0x2A)] == u16(e.data, 0x2C)) then
            set_level(u32(e.data, 0x0C), 'the stable clerk');
        end
        return;
    end
    if (e.id == 0x032) then
        if (STABLE_CLERKS[u16(e.data, 0x0A)] == u16(e.data, 0x0C)) then
            set_level(0, 'the stable clerk');
        end
        return;
    end

    if (e.id == 0x02F) then
        if (u32(e.data, 0x04) == me) then
            on_dig();
        end
        return;
    end

    if (e.id == 0x02A) then
        if (u32(e.data, 0x04) == me) then
            on_message(u16(e.data, 0x1A) % 0x8000, u32(e.data, 0x08));
        end
        return;
    end

    if (e.id == 0x036) then
        if (u32(e.data, 0x04) ~= me) then
            return;
        end
        local zone = dig_zone();
        if (zone and u16(e.data, 0x0A) % 0x8000 == zone.msg.nothing) then
            record_nothing();
        end
    end
end

function M.present()
    tick();
end

function M.unload()
    save_daily();
    save_wing();
end

return M;
