addon.name    = 'phoenixfishtrack';
addon.author  = 'Skold';
addon.version = '1.0';
addon.desc    = 'Tracks Phoenix fishing against the 200 catch daily allowance.';
addon.link    = 'https://phoenix-xi.com/';

require('common');

local chat     = require('chat');
local imgui    = require('imgui');
local settings = require('settings');
local offsets  = require('offsets');
local rumble   = require('rumble');

local DAILY_LIMIT   = 200;
local SKILL_FISHING = 48;
local JST_OFFSET    = 9 * 3600;
local BASE_WIDTH    = 300;
local PADDING       = 12;
local SLOT_RANGED   = 2;
local SLOT_AMMO     = 3;
local BAIT_BAGS     = T{ 0, 8, 10, 11, 12, 13, 14, 15, 16 };

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
    [MSG.HOOKED_SMALL]   = T{ setting = 'vibrate_small',   strong = 140, weak = 140, seconds = 0.35 },
    [MSG.HOOKED_LARGE]   = T{ setting = 'vibrate_large',   strong = 255, weak = 200, seconds = 0.80 },
    [MSG.HOOKED_ITEM]    = T{ setting = 'vibrate_item',    strong = 80,  weak = 160, seconds = 0.30 },
    [MSG.HOOKED_MONSTER] = T{ setting = 'vibrate_monster', strong = 255, weak = 255, seconds = 1.00 },
};

local VIBRATE_BUTTONS = T{
    T{ label = 'Small',   message = MSG.HOOKED_SMALL   },
    T{ label = 'Big',     message = MSG.HOOKED_LARGE   },
    T{ label = 'Item',    message = MSG.HOOKED_ITEM    },
    T{ label = 'Monster', message = MSG.HOOKED_MONSTER },
};

local function rgb(hex, alpha)
    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        alpha or 1.0,
    };
end

local COLOR = T{
    abyss     = rgb('180e0e'),
    surface1  = rgb('291c1c'),
    surface2  = rgb('321f1f'),
    border    = rgb('d2abab', 0.20),
    subtle    = rgb('d2abab', 0.12),
    text      = rgb('fff8f8'),
    secondary = rgb('eae1e1'),
    peach     = rgb('d2abab'),
    muted     = rgb('8a6b6b'),
    faint     = rgb('5a4545'),
    royal     = rgb('c55151'),
    tint      = rgb('c55151', 0.30),
    hover     = rgb('d45e5e'),
    ember     = rgb('ff8d79'),
    danger    = rgb('e04040'),
    gold      = rgb('c5a131'),
    success   = rgb('63ba8a'),
    clear     = { 0, 0, 0, 0 },
};

local default_settings = T{
    visible         = true,
    locked          = false,
    account         = '',
    scale           = 1.0,
    alpha           = 0.94,
    x               = 60,
    y               = 300,
    vibrate_small   = true,
    vibrate_large   = true,
    vibrate_item    = true,
    vibrate_monster = true,
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
    settings        = settings.load(default_settings),
    session         = new_session(),
    label           = nil,
    daily           = nil,
    names           = T{},
    limit_announced = false,
    no_controller   = false,
    gear            = T{ rod = nil, bait = nil, stack = 0, total = 0 },
    place_window    = true,
    last_tick       = 0,
    last_pos_save   = 0,
};

local function say(message)
    print(chat.header(addon.name):append(chat.message(message)));
end

local function jst_day()
    return os.date('!%Y-%m-%d', os.time() + JST_OFFSET);
end

local function seconds_until_reset()
    return 86400 - ((os.time() + JST_OFFSET) % 86400);
end

local function duration(seconds)
    seconds = math.max(0, math.floor(seconds));
    local hours   = math.floor(seconds / 3600);
    local minutes = math.floor((seconds % 3600) / 60);
    if (hours > 0) then
        return ('%dh %02dm'):fmt(hours, minutes);
    end
    return ('%dm %02ds'):fmt(minutes, seconds % 60);
end

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
    if (pf.settings.account ~= '') then
        return pf.settings.account;
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

    gear.rod   = rod and item_name(rod.Id) or nil;
    gear.bait  = nil;
    gear.stack = 0;
    gear.total = 0;
    if (bait) then
        gear.bait  = item_name(bait.Id);
        gear.stack = bait.Count;
        gear.total = bait_total(bait.Id);
    end
end

local function daily_folder()
    return ('%s\\config\\addons\\%s\\'):fmt(AshitaCore:GetInstallPath(), addon.name);
end

local function read_all_daily()
    local chunk = loadfile(daily_folder() .. 'daily.lua');
    if (not chunk) then
        return T{};
    end
    local ok, data = pcall(chunk);
    if (not ok or type(data) ~= 'table') then
        return T{};
    end
    return data;
end

local function write_all_daily(all)
    local folder = daily_folder();
    if (not ashita.fs.exists(folder)) then
        ashita.fs.create_directory(folder);
    end
    local file = io.open(folder .. 'daily.lua', 'w');
    if (not file) then
        return;
    end
    file:write('return {\n');
    for label, day in pairs(all) do
        file:write(('    [%q] = { day = %q, points = %d, catches = {'):fmt(label, day.day, day.points));
        for id, quantity in pairs(day.catches) do
            file:write((' [%d] = %d,'):fmt(id, quantity));
        end
        file:write(' } },\n');
    end
    file:write('}\n');
    file:close();
end

local function fresh_day()
    return T{ day = jst_day(), points = 0, catches = T{} };
end

local function save_daily()
    if (not pf.label or not pf.daily) then
        return;
    end
    local all = read_all_daily();
    all[pf.label] = pf.daily;
    write_all_daily(all);
end

local function load_daily()
    pf.label = account_label();
    pf.daily = nil;
    if (not pf.label) then
        return;
    end

    local stored = read_all_daily()[pf.label];
    if (stored and stored.day == jst_day()) then
        pf.daily = T{ day = stored.day, points = tonumber(stored.points) or 0, catches = T(stored.catches or {}) };
    else
        pf.daily = fresh_day();
    end
    pf.limit_announced = pf.daily.points >= DAILY_LIMIT;
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

local function u16(data, offset)
    local low, high = data:byte(offset + 1, offset + 2);
    return (low or 0) + (high or 0) * 256;
end

local function u32(data, offset)
    return u16(data, offset) + u16(data, offset + 2) * 65536;
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
        print(chat.header(addon.name):append(chat.warning(('Daily limit reached (%d). Nothing will bite until the JST midnight reset, in %s.'):fmt(DAILY_LIMIT, duration(seconds_until_reset())))));
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

local function text_width(text)
    local width = imgui.CalcTextSize(text);
    if (type(width) == 'table') then
        return width.x or width[1] or 0;
    end
    return width or 0;
end

local function right_text(width, color, text)
    imgui.SameLine(PADDING + width - text_width(text));
    imgui.TextColored(color, text);
end

local function stat_cell(label, value, color)
    imgui.TableNextColumn();
    imgui.TextColored(COLOR.muted, label);
    imgui.TextColored(color or COLOR.text, value);
end

local function push_theme()
    local colors = {
        { ImGuiCol_WindowBg,          { COLOR.abyss[1], COLOR.abyss[2], COLOR.abyss[3], pf.settings.alpha } },
        { ImGuiCol_TitleBg,           COLOR.surface1 },
        { ImGuiCol_TitleBgActive,     COLOR.surface2 },
        { ImGuiCol_TitleBgCollapsed,  COLOR.surface1 },
        { ImGuiCol_Border,            COLOR.border   },
        { ImGuiCol_Separator,         COLOR.border   },
        { ImGuiCol_Text,              COLOR.text     },
        { ImGuiCol_TextDisabled,      COLOR.muted    },
        { ImGuiCol_FrameBg,           COLOR.surface2 },
        { ImGuiCol_PlotHistogram,     COLOR.royal    },
        { ImGuiCol_Header,            COLOR.surface2 },
        { ImGuiCol_HeaderHovered,     COLOR.tint     },
        { ImGuiCol_HeaderActive,      COLOR.royal    },
        { ImGuiCol_TableHeaderBg,     COLOR.surface2 },
        { ImGuiCol_TableBorderLight,  COLOR.subtle   },
        { ImGuiCol_TableBorderStrong, COLOR.border   },
        { ImGuiCol_TableRowBg,        COLOR.clear    },
        { ImGuiCol_TableRowBgAlt,     COLOR.surface1 },
        { ImGuiCol_PopupBg,           COLOR.surface1 },
        { ImGuiCol_CheckMark,         COLOR.royal    },
        { ImGuiCol_Button,            COLOR.royal    },
        { ImGuiCol_ButtonHovered,     COLOR.hover    },
        { ImGuiCol_ButtonActive,      COLOR.royal    },
        { ImGuiCol_ScrollbarBg,       COLOR.abyss    },
        { ImGuiCol_ScrollbarGrab,     COLOR.surface2 },
        { ImGuiCol_ResizeGrip,        COLOR.clear    },
    };
    for _, color in ipairs(colors) do
        imgui.PushStyleColor(color[1], color[2]);
    end

    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 8.0);
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { PADDING, 10 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 8, 5 });
    imgui.PushStyleVar(ImGuiStyleVar_CellPadding, { 4, 3 });

    return #colors, 5;
end

local function draw_header(width)
    local who = player_name() or '';
    if (pf.settings.account ~= '') then
        who = ('%s  |  %s'):fmt(who, pf.settings.account);
    end
    imgui.TextColored(COLOR.peach, who);
    right_text(width, COLOR.muted, ('%s JST'):fmt(pf.daily.day));
end

local function gear_line(label, name, count, scale)
    imgui.TextColored(COLOR.muted, label);
    imgui.SameLine(PADDING + 40 * scale);
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

local function draw_gear(scale)
    local gear = pf.gear;
    local count = nil;
    if (gear.bait) then
        count = ('x%d'):fmt(gear.stack);
        if (gear.total > gear.stack) then
            count = ('x%d  (%d total)'):fmt(gear.stack, gear.total);
        end
    end

    imgui.Spacing();
    gear_line('Rod:', gear.rod, nil, scale);
    gear_line('Bait:', gear.bait, count, scale);
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

local function draw_vibrate(width)
    if (not imgui.CollapsingHeader('Vibrate on Hook', ImGuiTreeNodeFlags_DefaultOpen)) then
        return;
    end

    local button_width = (width - 3 * 8) / 4;
    for index, button in ipairs(VIBRATE_BUTTONS) do
        local hook = HOOKS[button.message];
        local on   = pf.settings[hook.setting];

        imgui.PushStyleColor(ImGuiCol_Button, on and COLOR.royal or COLOR.surface2);
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, on and COLOR.hover or COLOR.tint);
        imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR.royal);
        imgui.PushStyleColor(ImGuiCol_Text, on and COLOR.text or COLOR.muted);
        if (imgui.Button(('%s##pf_vibrate_%d'):fmt(button.label, index), { button_width, 0 })) then
            pf.settings[hook.setting] = not on;
            settings.save();
            if (pf.settings[hook.setting]) then
                vibrate(hook);
            end
        end
        imgui.PopStyleColor(4);

        if (index < #VIBRATE_BUTTONS) then
            imgui.SameLine();
        end
    end

    if (pf.no_controller) then
        imgui.TextColored(COLOR.muted, 'No USB DualSense or XInput pad found.');
    end
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

local function draw_context_menu()
    if (not imgui.BeginPopupContextWindow()) then
        return;
    end
    if (imgui.MenuItem('Lock Window', nil, pf.settings.locked)) then
        pf.settings.locked = not pf.settings.locked;
        settings.save();
    end
    if (imgui.MenuItem('Reset Session')) then
        pf.session = new_session();
    end
    if (imgui.MenuItem('Hide')) then
        pf.settings.visible = false;
        settings.save();
    end
    imgui.EndPopup();
end

local function remember_position()
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
    if (x == pf.settings.x and y == pf.settings.y) then
        return;
    end

    pf.settings.x = x;
    pf.settings.y = y;
    if (os.clock() - pf.last_pos_save > 1.0) then
        pf.last_pos_save = os.clock();
        settings.save();
    end
end

local function render()
    if (not pf.settings.visible or not pf.daily) then
        return;
    end

    local scale = pf.settings.scale;
    local width = BASE_WIDTH * scale;

    if (pf.place_window) then
        imgui.SetNextWindowPos({ pf.settings.x, pf.settings.y }, ImGuiCond_Always);
        pf.place_window = false;
    end

    local flags = bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoCollapse);
    if (pf.settings.locked) then
        flags = bit.bor(flags, ImGuiWindowFlags_NoMove);
    end

    local color_count, var_count = push_theme();
    local is_open = T{ true };
    if (imgui.Begin('PhoenixFishtrack##phoenixfishtrack', is_open, flags)) then
        local font      = imgui.GetFont();
        local font_size = imgui.GetFontSize() * scale;
        imgui.PushFont(font, font_size);
        draw_header(width);
        draw_gear(scale);
        draw_daily(width, scale, font, font_size);
        draw_vibrate(width);
        draw_session(width);
        draw_catches(width, scale);
        draw_context_menu();
        remember_position();
        imgui.PopFont();
    end
    imgui.End();
    imgui.PopStyleVar(var_count);
    imgui.PopStyleColor(color_count);

    if (not is_open[1]) then
        pf.settings.visible = false;
        settings.save();
    end
end

local function print_help()
    say('/pfish - show or hide the window');
    say('/pfish set <count> - correct today\'s catch count');
    say('/pfish account <name> - share one count between characters on the same account');
    say('/pfish account - count this character on its own again');
    say('/pfish scale <0.5-3> - window size');
    say('/pfish reset - clear session stats');
end

local function set_account(label)
    local previous = pf.daily;
    pf.settings.account = label;
    settings.save();
    load_daily();

    if (previous and pf.daily and pf.daily.points == 0 and next(pf.daily.catches) == nil and previous.day == pf.daily.day) then
        pf.daily           = previous;
        pf.limit_announced = previous.points >= DAILY_LIMIT;
        save_daily();
    end
end

ashita.events.register('command', 'phoenixfishtrack_command', function (e)
    local args = e.command:args();
    if (#args == 0) then
        return;
    end
    local command = args[1]:lower();
    if (command ~= '/pfish' and command ~= '/phoenixfishtrack') then
        return;
    end
    e.blocked = true;

    local sub = (args[2] or ''):lower();
    if (sub == '') then
        pf.settings.visible = not pf.settings.visible;
        settings.save();
    elseif (sub == 'show' or sub == 'hide') then
        pf.settings.visible = sub == 'show';
        settings.save();
    elseif (sub == 'set') then
        local count = tonumber(args[3]);
        if (not count or not pf.daily) then
            say('Usage: /pfish set <count>');
            return;
        end
        pf.daily.points    = math.max(0, math.floor(count));
        pf.limit_announced = pf.daily.points >= DAILY_LIMIT;
        save_daily();
        say(('Today\'s count set to %d / %d.'):fmt(pf.daily.points, DAILY_LIMIT));
    elseif (sub == 'account') then
        set_account(table.concat(args, ' ', 3));
        if (pf.settings.account == '') then
            say('Counting this character on its own.');
        else
            say(('Sharing today\'s count with every character set to "%s".'):fmt(pf.settings.account));
        end
    elseif (sub == 'scale') then
        local scale = tonumber(args[3]);
        if (not scale) then
            say('Usage: /pfish scale <0.5-3>');
            return;
        end
        pf.settings.scale = math.min(3.0, math.max(0.5, scale));
        settings.save();
    elseif (sub == 'reset') then
        pf.session = new_session();
        say('Session stats cleared.');
    else
        print_help();
    end
end);

ashita.events.register('packet_in', 'phoenixfishtrack_packet_in', function (e)
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
        if (pf.settings[hook.setting]) then
            vibrate(hook);
        end
        return;
    end

    local outcome = OUTCOMES[message];
    if (not outcome) then
        return;
    end
    record_outcome(outcome);

    if (e.id == 0x027 and outcome == 'caught') then
        local quantity = 1;
        if (message == MSG.CATCH_MULTI) then
            quantity = u32(e.data, 0x14);
        end
        record_catch(u32(e.data, 0x10), quantity);
    end
end);

ashita.events.register('d3d_present', 'phoenixfishtrack_present', function ()
    rumble.update();
    tick();
    render();
end);

ashita.events.register('unload', 'phoenixfishtrack_unload', function ()
    rumble.close();
    save_daily();
end);

settings.register('settings', 'phoenixfishtrack_settings_update', function (s)
    if (s) then
        pf.settings = s;
    end
    settings.save();
    pf.place_window = true;
    load_daily();
end);
