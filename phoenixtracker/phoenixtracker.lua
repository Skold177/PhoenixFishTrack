addon.name    = 'phoenixtracker';
addon.author  = 'Skold, Grimwald';
addon.version = '1.0.0';
addon.desc    = 'Tracks Phoenix fishing and chocobo digging against their daily allowances.';
addon.link    = 'https://phoenix-xi.com/';

-- One window with a tab per activity. Fishing is Skold's PhoenixFishTrack
-- (github.com/Skold177/PhoenixFishTrack); digging follows the same layout and theme.

require('common');

local imgui    = require('imgui');
local settings = require('settings');
local ui       = require('ui');
local fishing  = require('fishing');
local digging  = require('digging');

local COLOR         = ui.COLOR;
local PADDING       = ui.PADDING;
local text_width    = ui.text_width;
local toggle_button = ui.toggle_button;
-- Ashita's default font includes FontAwesome; imgui.lua defines the glyph.
local COG           = ICON_FA_GEAR;
local COG_CODEPOINT = 0xF013;

-- Tabs in the order they appear. Each one is a module with the same set of functions.
local TABS = T{ fishing, digging };

local default_settings = T{
    visible     = true,
    locked      = false,
    scale       = 1.0,
    alpha       = 0.94,
    x           = 60,
    y           = 300,
    tab         = 'fish',
    auto_switch = true,
};
for _, tab in ipairs(TABS) do
    for key, value in pairs(tab.defaults) do
        default_settings[key] = value;
    end
end

local pt = T{
    place_window   = true,
    reset_position = false,
    show_settings  = false,
    pending        = T{},
    last_pos_save  = 0,
};

-- Shared with every tab.
local ctx = T{ settings = settings.load(default_settings) };

local function tab_by_key(key)
    for _, tab in ipairs(TABS) do
        if (tab.key == key) then
            return tab;
        end
    end
    return TABS[1];
end

local function active_tab()
    return tab_by_key(ctx.settings.tab);
end

local function select_tab(tab)
    if (ctx.settings.tab ~= tab.key) then
        ctx.settings.tab = tab.key;
        settings.save();
    end
end

-- A tab calls this when you fish or dig, so the window follows what you're doing.
function ctx.activity(tab)
    if (ctx.settings.auto_switch) then
        select_tab(tab);
    end
end

for _, tab in ipairs(TABS) do
    tab.init(ctx);
end

local function player_name()
    local name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0);
    if (not name or name == '') then
        return nil;
    end
    return name;
end

-----------------------------------
-- Window
-----------------------------------
-- The cog opens the settings panel with a left click, for controllers and touch screens that
-- can't right-click.
local function draw_header(width, scale, tab)
    local who = player_name() or '';
    if (tab.account() ~= '') then
        who = ('%s  |  %s'):fmt(who, tab.account());
    end
    local day       = ('%s JST'):fmt(tab.day());
    local cog_width = text_width(COG) + 12 * scale;

    imgui.AlignTextToFramePadding();
    imgui.TextColored(COLOR.peach, who);
    imgui.SameLine(PADDING + width - cog_width - 8 - text_width(day));
    imgui.TextColored(COLOR.muted, day);
    imgui.SameLine(PADDING + width - cog_width);
    if (toggle_button('##pt_settings', pt.show_settings, cog_width)) then
        pt.show_settings = not pt.show_settings;
    end

    -- Centred on the glyph's drawn bounds; its advance width leaves it off-centre as a button label.
    local glyph  = imgui.GetFontBaked():FindGlyph(COG_CODEPOINT);
    local x0, y0 = imgui.GetItemRectMin();
    local x1, y1 = imgui.GetItemRectMax();
    local pos    = { (x0 + x1 - glyph.X0 - glyph.X1) / 2, (y0 + y1 - glyph.Y0 - glyph.Y1) / 2 };
    local color  = pt.show_settings and COLOR.text or COLOR.muted;
    imgui.GetWindowDrawList():AddText(pos, imgui.GetColorU32(color), COG);
end

-- Uses the same toggle buttons as the rest of the window rather than an ImGui tab bar, so it matches
-- the theme exactly and works with a left click on a controller.
local function draw_tabs(width, scale)
    -- Two filled rows (the cog and the tabs) need a wider gap than a text row would to look apart.
    imgui.Dummy({ 0, 6 * scale });
    local button_width = (width - (#TABS - 1) * 8) / #TABS;
    for index, tab in ipairs(TABS) do
        if (index > 1) then
            imgui.SameLine();
        end
        if (toggle_button(('%s##pt_tab_%s'):fmt(tab.label, tab.key), ctx.settings.tab == tab.key, button_width)) then
            select_tab(tab);
        end
    end
    imgui.Dummy({ 0, 2 * scale });
end

-- Saves once the slider is let go. A live slider applies while dragging; otherwise the value is
-- held until release, so scale doesn't resize the window under the slider mid-drag.
local function setting_slider(id, key, low, high, format, step, width, live)
    imgui.SetNextItemWidth(width);
    local buffer = { pt.pending[key] or ctx.settings[key] };
    if (imgui.SliderFloat(('##pt_%s_%s'):fmt(id, key), buffer, low, high, format, ImGuiSliderFlags_AlwaysClamp)) then
        local value = math.floor(buffer[1] / step + 0.5) * step;
        if (live) then
            ctx.settings[key] = value;
        else
            pt.pending[key] = value;
        end
    end
    if (imgui.IsItemDeactivatedAfterEdit()) then
        if (pt.pending[key]) then
            ctx.settings[key] = pt.pending[key];
            pt.pending[key]   = nil;
        end
        settings.save();
    end
end

local function menu_slider(label, key, low, high, format, step, live)
    imgui.TextColored(COLOR.muted, label);
    setting_slider('menu', key, low, high, format, step, 160, live);
end

-- The label column fits the longest label at the current font, so no label is clipped at small scales.
local function settings_row(label, key, low, high, format, step, width, live)
    local indent = math.max(text_width('Scale'), text_width('Opacity')) + 8;
    imgui.AlignTextToFramePadding();
    imgui.TextColored(COLOR.muted, label);
    imgui.SameLine(PADDING + indent);
    setting_slider('panel', key, low, high, format, step, width - indent, live);
end

local function draw_settings(width, tab)
    if (not pt.show_settings) then
        return;
    end

    imgui.Spacing();
    imgui.TextColored(COLOR.muted, 'SETTINGS');
    settings_row('Scale', 'scale', 0.5, 3.0, '%.2f', 0.05, width, false);
    settings_row('Opacity', 'alpha', 0.3, 1.0, '%.2f', 0.01, width, true);

    local button_width = (width - 16) / 3;
    if (toggle_button('Lock##pt_panel_lock', ctx.settings.locked, button_width)) then
        ctx.settings.locked = not ctx.settings.locked;
        settings.save();
    end
    imgui.SameLine();
    if (toggle_button('Reset Position##pt_panel_pos', false, button_width)) then
        pt.reset_position = true;
    end
    imgui.SameLine();
    if (toggle_button('Reset Session##pt_panel_session', false, button_width)) then
        tab.reset_session();
    end
    if (toggle_button('Switch tab when I fish or dig##pt_panel_auto', ctx.settings.auto_switch, width)) then
        ctx.settings.auto_switch = not ctx.settings.auto_switch;
        settings.save();
    end
    imgui.Separator();
end

local function draw_context_menu(tab)
    if (not imgui.BeginPopupContextWindow()) then
        return;
    end
    if (imgui.MenuItem('Lock Window', nil, ctx.settings.locked)) then
        ctx.settings.locked = not ctx.settings.locked;
        settings.save();
    end
    if (imgui.MenuItem('Switch Tab Automatically', nil, ctx.settings.auto_switch)) then
        ctx.settings.auto_switch = not ctx.settings.auto_switch;
        settings.save();
    end
    if (imgui.MenuItem(('Reset %s Session'):fmt(tab.label))) then
        tab.reset_session();
    end
    if (imgui.MenuItem('Reset Position')) then
        pt.reset_position = true;
    end
    if (imgui.MenuItem('Hide')) then
        ctx.settings.visible = false;
        settings.save();
    end
    imgui.Separator();
    menu_slider('Scale', 'scale', 0.5, 3.0, '%.2f', 0.05, false);
    menu_slider('Opacity', 'alpha', 0.3, 1.0, '%.2f', 0.01, true);
    imgui.EndPopup();
end

local function remember_position()
    local x, y = ui.vec2(imgui.GetWindowPos());
    if (not x or not y) then
        return;
    end
    x = math.floor(x);
    y = math.floor(y);
    if (x == ctx.settings.x and y == ctx.settings.y) then
        return;
    end
    ctx.settings.x = x;
    ctx.settings.y = y;
    if (os.clock() - pt.last_pos_save > 1.0) then
        pt.last_pos_save = os.clock();
        settings.save();
    end
end

-- Every tab gets the same width, so the window doesn't jump when you switch.
local function window_width(scale)
    local width = ui.BASE_WIDTH * scale;
    for _, tab in ipairs(TABS) do
        width = math.max(width, tab.fit_width(width, scale));
    end
    return width;
end

local function render_main(scale, width)
    local tab = active_tab();
    if (not ctx.settings.visible or not tab.ready()) then
        return;
    end

    if (pt.place_window) then
        imgui.SetNextWindowPos({ ctx.settings.x, ctx.settings.y }, ImGuiCond_Always);
        pt.place_window = false;
    end

    local is_open = T{ true };
    if (imgui.Begin('PhoenixTracker##phoenixtracker', is_open, ui.window_flags(ctx.settings.locked))) then
        local font      = imgui.GetFont();
        local font_size = imgui.GetFontSize() * scale;
        imgui.PushFont(font, font_size);
        draw_header(width, scale, tab);
        draw_settings(width, tab);
        draw_tabs(width, scale);
        tab.draw(width, scale, font, font_size);
        draw_context_menu(tab);
        remember_position();
        imgui.PopFont();
    end
    imgui.End();

    if (not is_open[1]) then
        ctx.settings.visible = false;
        settings.save();
    end
end

-- Applied before the windows are drawn, so remember_position doesn't save the old spot back.
local function reset_positions()
    ctx.settings.x = default_settings.x;
    ctx.settings.y = default_settings.y;
    for _, tab in ipairs(TABS) do
        tab.reset_positions();
    end
    pt.place_window   = true;
    pt.reset_position = false;
    settings.save();
end

local function render()
    if (pt.reset_position) then
        reset_positions();
    end

    local scale = ctx.settings.scale;
    local width = window_width(scale);

    local color_count, var_count = ui.push_theme(ctx.settings.alpha);
    render_main(scale, width);
    for _, tab in ipairs(TABS) do
        tab.render_popups(scale, width);
    end
    imgui.PopStyleVar(var_count);
    imgui.PopStyleColor(color_count);
end

-----------------------------------
-- Commands
-----------------------------------
-- /pfish and /pdig go straight to their tab; /ptrack works on whichever tab is open.
local COMMANDS = T{
    ['/pfish'] = fishing,
    ['/pdig']  = digging,
};
local TAB_WORDS = T{ fish = fishing, fishing = fishing, dig = digging, digging = digging };

local function print_help(prefix, tab)
    ui.say(('%s - show or hide the window'):fmt(prefix));
    if (prefix == '/ptrack') then
        ui.say('/ptrack fish | dig - open that tab');
    end
    ui.say(('%s scale <0.5-3> - window size'):fmt(prefix));
    ui.say(('%s auto - switch tabs automatically when you fish or dig, on or off'):fmt(prefix));
    tab.help(prefix);
end

ashita.events.register('command', 'phoenixtracker_command', function (e)
    local args = e.command:args();
    if (#args == 0) then
        return;
    end
    local command = args[1]:lower();
    if (command ~= '/ptrack' and command ~= '/phoenixtracker' and command ~= '/pfish' and command ~= '/pdig') then
        return;
    end
    e.blocked = true;

    local prefix = command == '/phoenixtracker' and '/ptrack' or command;
    local tab    = COMMANDS[command] or active_tab();
    local sub    = (args[2] or ''):lower();

    if (sub == '') then
        -- /pfish and /pdig open their own tab, or hide the window if it's already showing it.
        if (COMMANDS[command] and (not ctx.settings.visible or ctx.settings.tab ~= tab.key)) then
            ctx.settings.visible = true;
            select_tab(tab);
        else
            ctx.settings.visible = not ctx.settings.visible;
        end
        settings.save();
    elseif (TAB_WORDS[sub]) then
        ctx.settings.visible = true;
        select_tab(TAB_WORDS[sub]);
        settings.save();
    elseif (sub == 'show' or sub == 'hide') then
        ctx.settings.visible = sub == 'show';
        settings.save();
    elseif (sub == 'scale') then
        local scale = tonumber(args[3]);
        if (not scale) then
            ui.say(('Usage: %s scale <0.5-3>'):fmt(prefix));
            return;
        end
        ctx.settings.scale = math.min(3.0, math.max(0.5, scale));
        settings.save();
    elseif (sub == 'auto') then
        ctx.settings.auto_switch = not ctx.settings.auto_switch;
        settings.save();
        ui.say(ctx.settings.auto_switch and 'Tabs switch when you fish or dig.' or 'Tabs only switch when you pick one.');
    elseif (not tab.command(sub, args, prefix)) then
        print_help(prefix, tab);
    end
end);

-----------------------------------
-- Events
-----------------------------------
ashita.events.register('packet_in', 'phoenixtracker_packet_in', function (e)
    for _, tab in ipairs(TABS) do
        tab.packet_in(e);
    end
end);

ashita.events.register('d3d_present', 'phoenixtracker_present', function ()
    for _, tab in ipairs(TABS) do
        tab.present();
    end
    render();
end);

ashita.events.register('unload', 'phoenixtracker_unload', function ()
    for _, tab in ipairs(TABS) do
        tab.unload();
    end
end);

settings.register('settings', 'phoenixtracker_settings_update', function (s)
    if (s) then
        ctx.settings = s;
    end
    settings.save();
    pt.place_window = true;
    for _, tab in ipairs(TABS) do
        tab.reload();
    end
end);
