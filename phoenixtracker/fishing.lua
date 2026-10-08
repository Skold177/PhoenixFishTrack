-- Fishing tab: Skold's PhoenixFishTrack (github.com/Skold177/PhoenixFishTrack) as a PhoenixTracker
-- module. The window, theme, settings panel and commands live in phoenixtracker.lua.
require('common');

local imgui     = require('imgui');
local settings  = require('settings');
local ui        = require('ui');
local offsets   = require('offsets');
local rumble    = require('rumble');
local catchpool = require('catchpool');

local DAILY_LIMIT   = 200;
local SKILL_FISHING = 48;
local PADDING       = ui.PADDING;
local SLOT_RANGED   = 2;
local SLOT_AMMO     = 3;
local SLOT_BODY     = 5;
local BAIT_BAGS     = T{ 0, 8, 10, 11, 12, 13, 14, 15, 16 };

-- Entity statuses while fishing (38-43 and 50-53 from the older fishing animations, 56-62 from the
-- current ones). Anything else means the angler has stopped.
local FISHING_STATUS = T{};
for _, range in ipairs({ { 38, 43 }, { 50, 53 }, { 56, 62 } }) do
    for status = range[1], range[2] do
        FISHING_STATUS[status] = true;
    end
end

local FREE_ITEMS = T{
    [591]   = true,
    [1624]  = true,
    [1638]  = true,
    [2341]  = true,
    [5329]  = true,
    [5330]  = true,
    [65535] = true,
};

local MSG = T{
    NOCATCH           = 0x04,
    MONSTER           = 0x05,
    LINEBREAK         = 0x06,
    RODBREAK          = 0x07,
    HOOKED_SMALL      = 0x08,
    LOST              = 0x09,
    CATCH_INV_FULL    = 0x0A,
    CATCH_MULTI       = 0x0E,
    RODBREAK_TOOBIG   = 0x11,
    RODBREAK_TOOHEAVY = 0x12,
    LOST_TOOSMALL     = 0x13,
    LOST_LOWSKILL     = 0x14,
    GIVEUP_BAITLOSS   = 0x24,
    GIVEUP            = 0x25,
    CATCH             = 0x27,
    HOOKED_LARGE      = 0x32,
    HOOKED_ITEM       = 0x33,
    HOOKED_MONSTER    = 0x34,
    GOOD_FEELING      = 0x29,
    BAD_FEELING       = 0x2A,
    TERRIBLE_FEELING  = 0x2B,
    NOSKILL_UNSURE    = 0x2C,
    NOSKILL_SURE      = 0x2D,
    NOSKILL_POSITIVE  = 0x2E,
    KEEN_SENSE        = 0x35,
    EPIC_CATCH        = 0x36,
    LOST_TOOBIG       = 0x3C,
    CATCH_CHEST       = 0x40,
};

local OUTCOMES = T{
    [MSG.NOCATCH]           = 'nothing',
    [MSG.MONSTER]           = 'monster',
    [MSG.LINEBREAK]         = 'snapped',
    [MSG.RODBREAK]          = 'broke',
    [MSG.RODBREAK_TOOBIG]   = 'broke',
    [MSG.RODBREAK_TOOHEAVY] = 'broke',
    [MSG.LOST]              = 'lost',
    [MSG.LOST_TOOSMALL]     = 'lost',
    [MSG.LOST_LOWSKILL]     = 'lost',
    [MSG.LOST_TOOBIG]       = 'lost',
    [MSG.CATCH_INV_FULL]    = 'full',
    [MSG.GIVEUP_BAITLOSS]   = 'gaveup',
    [MSG.GIVEUP]            = 'gaveup',
    [MSG.CATCH]             = 'caught',
    [MSG.CATCH_MULTI]       = 'caught',
    [MSG.CATCH_CHEST]       = 'chest',
};

local HOOKS = T{
    [MSG.HOOKED_SMALL]   = T{ name = 'Small fish', want = 'want_small',   setting = 'vibrate_small',   strong = 140, weak = 140, seconds = 0.35 },
    [MSG.HOOKED_LARGE]   = T{ name = 'Large fish', want = 'want_large',   setting = 'vibrate_large',   strong = 255, weak = 200, seconds = 0.80 },
    [MSG.HOOKED_ITEM]    = T{ name = 'Item',       want = 'want_item',    setting = 'vibrate_item',    strong = 80,  weak = 160, seconds = 0.30 },
    [MSG.HOOKED_MONSTER] = T{ name = 'Monster',    want = 'want_monster', setting = 'vibrate_monster', strong = 255, weak = 255, seconds = 1.00 },
};

local HOOK_BUTTONS = T{
    T{ label = 'Small',   message = MSG.HOOKED_SMALL   },
    T{ label = 'Big',     message = MSG.HOOKED_LARGE   },
    T{ label = 'Item',    message = MSG.HOOKED_ITEM    },
    T{ label = 'Monster', message = MSG.HOOKED_MONSTER },
};

-- One choice, not two toggles: rod breaks are always warned about, and 'line' adds line snaps.
local BREAK_MODES = T{
    T{ label = 'Rod Breaks',        key = 'rod'  },
    T{ label = 'Rod + Line Breaks', key = 'line' },
};

local NOTHING = T{ setting = 'vibrate_nothing', strong = 60, weak = 60, seconds = 0.25 };

local VIBRATE_BUTTONS = T{ unpack(HOOK_BUTTONS) };

local COLOR               = ui.COLOR;
local say                 = ui.say;
local jst_day             = ui.jst_day;
local seconds_until_reset = ui.seconds_until_reset;
local duration            = ui.duration;
local u16                 = ui.u16;
local u32                 = ui.u32;
local text_width          = ui.text_width;
local right_text          = ui.right_text;
local stat_cell           = ui.stat_cell;
local toggle_button       = ui.toggle_button;

-- Shared with phoenixtracker.lua: ctx.settings, and ctx.activity() to switch to this tab.
local ctx = nil;
VIBRATE_BUTTONS:append(T{ label = 'None', rumble = NOTHING });

-- Phoenix settles the reel when the fish bites and picks the feeling from it: a rod that will break
-- always gets a Terrible Feeling, and a line that will snap always gets a Bad Feeling.
local FEELINGS = T{
    [MSG.GOOD_FEELING]     = T{ rod_safe = true,  line_safe = true  },
    [MSG.KEEN_SENSE]       = T{ rod_safe = true,  line_safe = true  },
    [MSG.NOSKILL_UNSURE]   = T{ rod_safe = true,  line_safe = true  },
    [MSG.NOSKILL_SURE]     = T{ rod_safe = true,  line_safe = true  },
    [MSG.NOSKILL_POSITIVE] = T{ rod_safe = true,  line_safe = true  },
    [MSG.BAD_FEELING]      = T{ rod_safe = true,  line_safe = false },
    [MSG.TERRIBLE_FEELING] = T{ rod_safe = false, line_safe = false },
    -- Replaces any other feeling on a near-record large fish, so it says nothing about the rod or line.
    [MSG.EPIC_CATCH]       = T{},
};

local M = T{ key = 'fish', label = 'Fishing' };

-- Settings this tab adds to PhoenixTracker's.
M.defaults = T{
    account         = '',
    hook_x          = 380,
    hook_y          = 300,
    vibrate_small   = true,
    vibrate_large   = true,
    vibrate_item    = true,
    vibrate_monster = true,
    vibrate_nothing = false,
    want_small      = true,
    want_large      = true,
    want_item       = true,
    want_monster    = true,
    break_mode      = 'rod',
};

local function new_session()
    return T{
        started  = nil,
        casts    = 0,
        bites    = 0,
        points   = 0,
        skill    = 0,
        outcomes = T{},
    };
end

local pf = T{
    session         = new_session(),
    label           = nil,
    daily           = nil,
    names           = T{},
    limit_announced = false,
    no_controller   = false,
    gear            = T{ rod = nil, rod_id = nil, bait = nil, bait_id = nil, stack = 0, total = 0 },
    hook            = nil,
    place_hook      = true,
    last_tick       = 0,
    last_pos_save   = 0,
};

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
    if (ctx.settings.account ~= '') then
        return ctx.settings.account;
    end
    return player_name();
end

local function fishing_skill()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (not player) then
        return nil;
    end
    local craft = player:GetCraftSkill(0);
    if (not craft) then
        return nil;
    end
    return craft:GetSkill();
end

local function item_name(id)
    local name = pf.names[id];
    if (name) then
        return name;
    end
    local item = AshitaCore:GetResourceManager():GetItemById(id);
    name = (item and item.Name[1]) or ('Item %d'):fmt(id);
    pf.names[id] = name;
    return name;
end

local function equipped_item(slot)
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    local equipped  = inventory:GetEquippedItem(slot);
    if (not equipped or equipped.Index == 0) then
        return nil;
    end
    local item = inventory:GetContainerItem(bit.rshift(equipped.Index, 8), bit.band(equipped.Index, 0xFF));
    if (not item or item.Id == 0 or item.Id == 65535) then
        return nil;
    end
    return item;
end

local function bait_total(id)
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    local total     = 0;
    for _, bag in ipairs(BAIT_BAGS) do
        for index = 1, inventory:GetContainerCountMax(bag) do
            local item = inventory:GetContainerItem(bag, index);
            if (item and item.Id == id) then
                total = total + item.Count;
            end
        end
    end
    return total;
end

local function refresh_gear()
    local rod  = equipped_item(SLOT_RANGED);
    local bait = equipped_item(SLOT_AMMO);
    local gear = pf.gear;

    gear.rod     = rod and item_name(rod.Id) or nil;
    gear.rod_id  = rod and rod.Id or nil;
    gear.bait    = nil;
    gear.bait_id = nil;
    gear.stack   = 0;
    gear.total   = 0;
    if (bait) then
        gear.bait    = item_name(bait.Id);
        gear.bait_id = bait.Id;
        gear.stack   = bait.Count;
        gear.total   = bait_total(bait.Id);
    end
end

local function has_key_item(id)
    local ok, has = pcall(function ()
        return AshitaCore:GetMemoryManager():GetPlayer():HasKeyItem(id);
    end);
    return not ok or has;
end

local function catch_pool()
    refresh_gear();
    local index  = party():GetMemberTargetIndex(0);
    local entity = AshitaCore:GetMemoryManager():GetEntity();
    local body   = equipped_item(SLOT_BODY);
    -- The client keeps height in Z; the server keeps it in y.
    return catchpool.build(T{
        zone         = party():GetMemberZone(0),
        x            = entity:GetLocalPositionX(index),
        y            = entity:GetLocalPositionZ(index),
        z            = entity:GetLocalPositionY(index),
        rod_id       = pf.gear.rod_id,
        bait_id      = pf.gear.bait_id,
        body         = body and body.Id or nil,
        skill        = fishing_skill(),
        has_key_item = has_key_item,
    });
end

local function pool_empty_reason(pool, message)
    if (not pool.known) then
        return 'No Phoenix fishing data for this zone.';
    end
    if (not pool.bait_ok and (message == MSG.HOOKED_SMALL or message == MSG.HOOKED_LARGE)) then
        return 'This bait isn\'t in the Phoenix fishing data.';
    end
    return 'Nothing in the Phoenix data matches.';
end

local function pool_value(row)
    if (row.odds) then
        return ('%.0f%%'):fmt(row.odds);
    end
    return row.note or '-';
end

local function fresh_day()
    return T{ day = jst_day(), points = 0, catches = T{} };
end

local function save_daily()
    if (not pf.label or not pf.daily) then
        return;
    end
    local all = ui.read_data('fish_daily.lua');
    all[pf.label] = pf.daily;

    local lines = T{ 'return {' };
    for label, day in pairs(all) do
        local catches = T{};
        for id, quantity in pairs(day.catches) do
            catches:append((' [%d] = %d,'):fmt(id, quantity));
        end
        lines:append(('    [%q] = { day = %q, points = %d, catches = {%s } },'):fmt(label, day.day, day.points, catches:concat('')));
    end
    lines:append('}');
    ui.write_data('fish_daily.lua', lines:concat('\n') .. '\n');
end

local function load_daily()
    pf.label = account_label();
    pf.daily = nil;
    if (not pf.label) then
        return;
    end

    -- Picks up today's count from a standalone PhoenixFishTrack install the first time.
    local stored = ui.read_data('fish_daily.lua')[pf.label] or ui.read_data('daily.lua', 'phoenixfishtrack')[pf.label];
    if (stored and stored.day == jst_day()) then
        pf.daily = T{ day = stored.day, points = tonumber(stored.points) or 0, catches = T(stored.catches or {}) };
    else
        pf.daily = fresh_day();
    end
    pf.limit_announced = pf.daily.points >= DAILY_LIMIT;
end

-- Giving up with a lure or being interrupted ends fishing without any message, so the popup also
-- closes once the player is no longer in a fishing animation.
local function clear_finished_hook()
    if (not pf.hook) then
        return;
    end
    local index = party():GetMemberTargetIndex(0);
    if (not FISHING_STATUS[AshitaCore:GetMemoryManager():GetEntity():GetStatus(index)]) then
        pf.hook = nil;
    end
end

local function tick()
    local now = os.time();
    if (now == pf.last_tick) then
        return;
    end
    pf.last_tick = now;

    if (pf.label) then
        refresh_gear();
    end

    if (account_label() ~= pf.label) then
        load_daily();
        return;
    end

    if (pf.daily and pf.daily.day ~= jst_day()) then
        pf.daily           = fresh_day();
        pf.limit_announced = false;
        save_daily();
    end
end

local function fishing_message(data)
    if (u32(data, 0x04) ~= party():GetMemberServerId(0)) then
        return nil;
    end
    local base = offsets[party():GetMemberZone(0)];
    if (not base) then
        return nil;
    end
    return (u16(data, 0x0A) % 0x8000) - base;
end

local function record_outcome(outcome)
    local session = pf.session;
    session.started           = session.started or os.time();
    session.casts             = session.casts + 1;
    session.outcomes[outcome] = (session.outcomes[outcome] or 0) + 1;
end

local function record_catch(id, quantity)
    local daily = pf.daily;
    if (not daily) then
        return;
    end

    daily.catches[id] = (daily.catches[id] or 0) + quantity;
    if (not FREE_ITEMS[id]) then
        daily.points      = daily.points + 1;
        pf.session.points = pf.session.points + 1;
    end
    save_daily();

    if (daily.points >= DAILY_LIMIT and not pf.limit_announced) then
        pf.limit_announced = true;
        ui.warn(('Daily limit reached (%d). Nothing will bite until the JST midnight reset, in %s.'):fmt(DAILY_LIMIT, duration(seconds_until_reset())));
    end
end

local function record_skill(data)
    if (u32(data, 0x08) ~= party():GetMemberServerId(0) or u32(data, 0x0C) ~= SKILL_FISHING) then
        return;
    end
    if (u16(data, 0x18) == 38) then
        pf.session.skill = pf.session.skill + u32(data, 0x10) / 10;
    end
end

local function gear_line(label, name, count)
    local indent = math.max(text_width('Rod:'), text_width('Bait:')) + 8;
    imgui.TextColored(COLOR.muted, label);
    imgui.SameLine(PADDING + indent);
    if (not name) then
        imgui.TextColored(COLOR.danger, 'None');
        return;
    end
    imgui.TextColored(COLOR.secondary, name);
    if (count) then
        imgui.SameLine();
        imgui.TextColored(COLOR.peach, count);
    end
end

local function draw_gear()
    local gear = pf.gear;
    local count = nil;
    if (gear.bait) then
        count = ('x%d'):fmt(gear.stack);
        if (gear.total > gear.stack) then
            count = ('x%d  (%d total)'):fmt(gear.stack, gear.total);
        end
    end

    imgui.Spacing();
    gear_line('Rod:', gear.rod, nil);
    gear_line('Bait:', gear.bait, count);
end

-- Phoenix only breaks a rod after a Terrible Feeling and only snaps a line after a Bad Feeling, so
-- the feeling message settles it. Returns the banner label and its colour, or nil until one arrives.
local function catch_verdict(hook)
    if (not ctx.settings[HOOKS[hook.message].want]) then
        return 'Bad Catch - Not Wanted', COLOR.danger;
    end

    local feeling = FEELINGS[hook.feeling];
    if (not feeling) then
        return nil;
    end
    if (feeling.rod_safe == nil) then
        return 'Epic Catch - Unknown', COLOR.gold;
    end
    if (not feeling.rod_safe) then
        return 'Bad Catch - Could Break', COLOR.danger;
    end
    if (ctx.settings.break_mode == 'line' and not feeling.line_safe) then
        return 'Bad Catch - Could Snap', COLOR.danger;
    end
    return 'Good Catch - No Break', COLOR.success;
end

local function draw_break_mode(width)
    local button_width = (width - 8) / 2;
    imgui.TextColored(COLOR.muted, 'Warn on');
    for index, mode in ipairs(BREAK_MODES) do
        if (index > 1) then
            imgui.SameLine();
        end
        if (toggle_button(('%s##pf_break_%d'):fmt(mode.label, index), ctx.settings.break_mode == mode.key, button_width)) then
            ctx.settings.break_mode = mode.key;
            settings.save();
        end
    end
end

local function draw_hook(width, scale)
    local hook = pf.hook;
    if (not hook) then
        return;
    end

    imgui.TextColored(COLOR.ember, HOOKS[hook.message].name);
    right_text(width, COLOR.muted, hook.pool.area or 'Area unknown');

    local label, color = catch_verdict(hook);
    if (label) then
        -- A button, because it centres its label; every state shares one colour so it reads as a banner.
        imgui.PushStyleColor(ImGuiCol_Button, color);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, color);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, color);
        imgui.PushStyleColor(ImGuiCol_Text, COLOR.abyss);
        imgui.Button(label .. '##pf_verdict', { width, imgui.GetTextLineHeight() + 6 * scale });
        imgui.PopStyleColor(4);
    end
    imgui.Spacing();

    local rows = hook.pool[hook.message];
    if (#rows == 0) then
        imgui.TextColored(COLOR.faint, pool_empty_reason(hook.pool, hook.message));
        return;
    end

    local flags = bit.bor(ImGuiTableFlags_RowBg, ImGuiTableFlags_BordersInnerH, ImGuiTableFlags_PadOuterX);
    local size  = { width, 0 };
    if (#rows > 8) then
        flags = bit.bor(flags, ImGuiTableFlags_ScrollY);
        size  = { width, 9 * imgui.GetTextLineHeightWithSpacing() };
    end

    if (imgui.BeginTable('##pf_hook', 3, flags, size)) then
        imgui.TableSetupColumn('Could be', ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.TableSetupColumn('Skill', ImGuiTableColumnFlags_WidthFixed, text_width('Skill') + 4 * scale, 0);
        imgui.TableSetupColumn('Odds', ImGuiTableColumnFlags_WidthFixed, math.max(text_width('Odds'), text_width('100%'), text_width('quest')) + 4 * scale, 0);
        imgui.TableHeadersRow();
        for _, row in ipairs(rows) do
            imgui.TableNextRow();
            imgui.TableNextColumn();
            imgui.TextColored(row.legendary and COLOR.gold or COLOR.secondary, row.name);
            imgui.TableNextColumn();
            imgui.TextColored(COLOR.muted, row.skill and tostring(row.skill) or '-');
            imgui.TableNextColumn();
            imgui.TextColored(row.odds and COLOR.text or COLOR.faint, pool_value(row));
        end
        imgui.EndTable();
    end
end

local function draw_daily(width, scale, font, font_size)
    local daily = pf.daily;
    local done  = daily.points >= DAILY_LIMIT;

    imgui.Spacing();
    imgui.TextColored(COLOR.muted, 'DAILY CATCHES');

    imgui.PushFont(font, font_size * 2.0);
    local big = imgui.GetFontSize();
    imgui.TextColored(done and COLOR.success or COLOR.text, tostring(daily.points));
    imgui.PopFont();
    local small = imgui.GetFontSize();
    imgui.SameLine();
    imgui.SetCursorPosY(imgui.GetCursorPosY() + (big - small) * 0.8);
    imgui.TextColored(COLOR.muted, ('/ %d'):fmt(DAILY_LIMIT));
    right_text(width, COLOR.ember, ('%d%%'):fmt(math.floor(math.min(daily.points, DAILY_LIMIT) * 100 / DAILY_LIMIT)));

    imgui.PushStyleColor(ImGuiCol_PlotHistogram, done and COLOR.success or COLOR.royal);
    imgui.ProgressBar(math.min(1, daily.points / DAILY_LIMIT), { width, 10 * scale }, '');
    imgui.PopStyleColor(1);

    local reset_in = seconds_until_reset();
    imgui.TextColored(COLOR.secondary, ('%d left'):fmt(math.max(0, DAILY_LIMIT - daily.points)));
    right_text(width, COLOR.muted, ('resets %s (%s)'):fmt(os.date('%H:%M', os.time() + reset_in), duration(reset_in)));

    if (done) then
        imgui.TextColored(COLOR.gold, 'Limit reached. Nothing bites until the reset.');
    end
    imgui.Spacing();
end

local function draw_session(width)
    if (not imgui.CollapsingHeader('Session', ImGuiTreeNodeFlags_DefaultOpen)) then
        return;
    end

    local session = pf.session;
    local caught  = session.outcomes.caught or 0;
    local elapsed = session.started and (os.time() - session.started) or 0;

    local hit_rate = '-';
    if (session.casts > 0) then
        hit_rate = ('%.0f%%'):fmt(caught * 100 / session.casts);
    end

    local per_hour = '-';
    local to_limit = '-';
    if (elapsed >= 60 and session.points > 0) then
        local rate = session.points * 3600 / elapsed;
        per_hour = ('%.0f'):fmt(rate);
        to_limit = duration(math.max(0, DAILY_LIMIT - pf.daily.points) / rate * 3600);
    end

    local skill = fishing_skill();
    local gain_color = COLOR.text;
    if (session.skill > 0) then
        gain_color = COLOR.success;
    end

    if (imgui.BeginTable('##pf_session', 4, ImGuiTableFlags_SizingStretchSame, { width, 0 })) then
        stat_cell('Casts', tostring(session.casts));
        stat_cell('Bites', tostring(session.bites));
        stat_cell('Caught', tostring(caught));
        stat_cell('Hit rate', hit_rate);
        stat_cell('Per hour', per_hour);
        stat_cell(('To %d'):fmt(DAILY_LIMIT), to_limit);
        stat_cell('Skill', skill and tostring(skill) or '-');
        stat_cell('Gained', ('+%.1f'):fmt(session.skill), gain_color);
        imgui.EndTable();
    end
end

local function vibrate(hook)
    if (not rumble.pulse(hook.strong, hook.weak, hook.seconds)) then
        pf.no_controller = true;
        return;
    end
    pf.no_controller = false;
end

local function draw_toggles(id, width, buttons, key, on_enable)
    local button_width = (width - (#buttons - 1) * 8) / #buttons;
    for index, button in ipairs(buttons) do
        local hook    = button.rumble or HOOKS[button.message];
        local setting = hook[key];
        local on      = ctx.settings[setting];

        if (toggle_button(('%s##pf_%s_%d'):fmt(button.label, id, index), on, button_width)) then
            ctx.settings[setting] = not on;
            settings.save();
            if (ctx.settings[setting] and on_enable) then
                on_enable(hook);
            end
        end

        if (index < #buttons) then
            imgui.SameLine();
        end
    end
end

local function draw_vibrate(width)
    if (not imgui.CollapsingHeader('Vibrate on Hook', ImGuiTreeNodeFlags_DefaultOpen)) then
        return;
    end

    draw_toggles('vibrate', width, VIBRATE_BUTTONS, 'setting', vibrate);
    if (pf.no_controller) then
        imgui.TextColored(COLOR.muted, 'No USB DualSense or XInput pad found.');
    end
end

local function draw_wanted(width)
    if (not imgui.CollapsingHeader('On Hook Display', ImGuiTreeNodeFlags_DefaultOpen)) then
        return;
    end

    draw_toggles('want', width, HOOK_BUTTONS, 'want');
    draw_break_mode(width);
end

local function draw_catches(width, scale)
    if (not imgui.CollapsingHeader('Today\'s Catch', ImGuiTreeNodeFlags_DefaultOpen)) then
        return;
    end

    local rows = T{};
    for id, quantity in pairs(pf.daily.catches) do
        rows:append(T{ id = id, name = item_name(id), quantity = quantity });
    end

    if (#rows == 0) then
        imgui.TextColored(COLOR.faint, 'Nothing landed yet today.');
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

    if (imgui.BeginTable('##pf_catches', 2, flags, size)) then
        imgui.TableSetupColumn('Item', ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.TableSetupColumn('Qty', ImGuiTableColumnFlags_WidthFixed, 44 * scale, 0);
        imgui.TableHeadersRow();
        for _, row in ipairs(rows) do
            imgui.TableNextRow();
            imgui.TableNextColumn();
            if (FREE_ITEMS[row.id]) then
                imgui.TextColored(COLOR.muted, row.name);
                imgui.SameLine();
                imgui.TextColored(COLOR.faint, 'no point');
            else
                imgui.TextColored(COLOR.secondary, row.name);
            end
            imgui.TableNextColumn();
            imgui.TextColored(COLOR.text, tostring(row.quantity));
        end
        imgui.EndTable();
    end
end

local function remember_position(x_key, y_key)
    local x, y = imgui.GetWindowPos();
    if (type(x) == 'table') then
        y = x.y or x[2];
        x = x.x or x[1];
    end
    if (not x or not y) then
        return;
    end

    x = math.floor(x);
    y = math.floor(y);
    if (x == ctx.settings[x_key] and y == ctx.settings[y_key]) then
        return;
    end

    ctx.settings[x_key] = x;
    ctx.settings[y_key] = y;
    if (os.clock() - pf.last_pos_save > 1.0) then
        pf.last_pos_save = os.clock();
        settings.save();
    end
end

-- Wide enough that every toggle in the widest button row shows its whole label at the current font.
local function fit_toggles(width, scale)
    local widest = 0;
    for _, button in ipairs(VIBRATE_BUTTONS) do
        widest = math.max(widest, text_width(button.label));
    end
    local needed = #VIBRATE_BUTTONS * (widest + 16 * scale) + (#VIBRATE_BUTTONS - 1) * 8;
    return math.max(width, needed);
end

local function render_hook(scale, width)
    if (not pf.hook) then
        return;
    end

    if (pf.place_hook) then
        imgui.SetNextWindowPos({ ctx.settings.hook_x, ctx.settings.hook_y }, ImGuiCond_Always);
        pf.place_hook = false;
    end

    local flags = bit.bor(ui.window_flags(ctx.settings.locked), ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoFocusOnAppearing);
    if (imgui.Begin('On the Line##phoenixfishtrack_hook', true, flags)) then
        imgui.PushFont(imgui.GetFont(), imgui.GetFontSize() * scale);
        draw_hook(width, scale);
        remember_position('hook_x', 'hook_y');
        imgui.PopFont();
    end
    imgui.End();
end

local function print_pool()
    local pool = catch_pool();
    if (not pool.known) then
        say('No Phoenix fishing data for this zone.');
        return;
    end

    say(('Area: %s'):fmt(pool.area or 'unknown, showing the whole zone'));
    for _, button in ipairs(HOOK_BUTTONS) do
        local names = T{};
        for _, row in ipairs(pool[button.message]) do
            names:append(('%s (%s)'):fmt(row.name, pool_value(row)));
        end
        local list = #names > 0 and names:concat(', ') or pool_empty_reason(pool, button.message);
        say(('%s: %s'):fmt(HOOKS[button.message].name, list));
    end
end

local function set_account(label)
    local previous = pf.daily;
    ctx.settings.account = label;
    settings.save();
    load_daily();

    if (previous and pf.daily and pf.daily.points == 0 and next(pf.daily.catches) == nil and previous.day == pf.daily.day) then
        pf.daily           = previous;
        pf.limit_announced = previous.points >= DAILY_LIMIT;
        save_daily();
    end
end


-----------------------------------
-- PhoenixTracker module interface
-----------------------------------
function M.init(context)
    ctx = context;
end

-- Daily count for the header and whether this tab has data to draw yet.
function M.ready()
    return pf.daily ~= nil;
end

function M.day()
    return pf.daily and pf.daily.day or jst_day();
end

function M.account()
    return ctx.settings.account;
end

-- Wide enough that every vibrate toggle shows its whole label at the current font.
function M.fit_width(width, scale)
    return fit_toggles(width, scale);
end

function M.draw(width, scale, font, font_size)
    draw_gear();
    draw_daily(width, scale, font, font_size);
    draw_vibrate(width);
    draw_wanted(width);
    draw_session(width);
    draw_catches(width, scale);
end

-- The On the Line popup shows whichever tab is open.
function M.render_popups(scale, width)
    render_hook(scale, width);
end

function M.reset_session()
    pf.session = new_session();
end

function M.reset_positions()
    ctx.settings.hook_x = M.defaults.hook_x;
    ctx.settings.hook_y = M.defaults.hook_y;
    pf.place_hook = true;
end

function M.reload()
    pf.place_hook = true;
    load_daily();
end

function M.help(prefix)
    say(('%s set <count> - correct today\'s catch count'):fmt(prefix));
    say(('%s account <name> - share one count between characters on the same account'):fmt(prefix));
    say(('%s account - count this character on its own again'):fmt(prefix));
    say(('%s reset - clear fishing session stats'):fmt(prefix));
    say(('%s pool - list what can bite where you are standing'):fmt(prefix));
end

-- Returns true if the subcommand was handled.
function M.command(sub, args, prefix)
    if (sub == 'set') then
        local count = tonumber(args[3]);
        if (not count or not pf.daily) then
            say(('Usage: %s set <count>'):fmt(prefix));
            return true;
        end
        pf.daily.points    = math.max(0, math.floor(count));
        pf.limit_announced = pf.daily.points >= DAILY_LIMIT;
        save_daily();
        say(('Today\'s catch count set to %d / %d.'):fmt(pf.daily.points, DAILY_LIMIT));
    elseif (sub == 'account') then
        set_account(table.concat(args, ' ', 3));
        if (ctx.settings.account == '') then
            say('Counting this character\'s catches on its own.');
        else
            say(('Sharing today\'s catch count with every character set to "%s".'):fmt(ctx.settings.account));
        end
    elseif (sub == 'reset') then
        M.reset_session();
        say('Fishing session stats cleared.');
    elseif (sub == 'pool') then
        print_pool();
    else
        return false;
    end
    return true;
end

function M.packet_in(e)
    if (e.id == 0x029) then
        record_skill(e.data);
        return;
    end
    if (e.id ~= 0x027 and e.id ~= 0x036 and e.id ~= 0x043) then
        return;
    end

    local message = fishing_message(e.data);
    if (not message) then
        return;
    end

    local hook = HOOKS[message];
    if (hook) then
        pf.session.bites = pf.session.bites + 1;
        if (ctx.settings[hook.setting]) then
            vibrate(hook);
        end
        pf.hook = T{ message = message, pool = catch_pool() };
        ctx.activity(M);
        return;
    end

    if (FEELINGS[message]) then
        if (pf.hook) then
            pf.hook.feeling = message;
        end
        return;
    end

    local outcome = OUTCOMES[message];
    if (not outcome) then
        return;
    end
    pf.hook = nil;
    record_outcome(outcome);
    ctx.activity(M);
    if (message == MSG.NOCATCH and ctx.settings.vibrate_nothing) then
        vibrate(NOTHING);
    end

    if (e.id == 0x027 and outcome == 'caught') then
        local quantity = 1;
        if (message == MSG.CATCH_MULTI) then
            quantity = u32(e.data, 0x14);
        end
        record_catch(u32(e.data, 0x10), quantity);
    end
end

function M.present()
    rumble.update();
    clear_finished_hook();
    tick();
end

function M.unload()
    rumble.close();
    save_daily();
end

return M;
