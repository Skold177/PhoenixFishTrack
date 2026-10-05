-- Shared look for every PhoenixTracker tab. The palette and style values are Skold's, from
-- PhoenixFishTrack, so every tab draws with exactly the same colours.
require('common');

local chat  = require('chat');
local imgui = require('imgui');

local ui = {};

ui.PADDING    = 12;
ui.BASE_WIDTH = 360;
ui.JST_OFFSET = 9 * 3600;

function ui.rgb(hex, alpha)
    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        alpha or 1.0,
    };
end

local rgb = ui.rgb;

ui.COLOR = T{
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

local COLOR = ui.COLOR;

-----------------------------------
-- Messages and time
-----------------------------------
function ui.say(message)
    print(chat.header(addon.name):append(chat.message(message)));
end

function ui.warn(message)
    print(chat.header(addon.name):append(chat.warning(message)));
end

function ui.jst_day()
    return os.date('!%Y-%m-%d', os.time() + ui.JST_OFFSET);
end

function ui.seconds_until_reset()
    return 86400 - ((os.time() + ui.JST_OFFSET) % 86400);
end

function ui.duration(seconds)
    seconds = math.max(0, math.floor(seconds));
    local hours   = math.floor(seconds / 3600);
    local minutes = math.floor((seconds % 3600) / 60);
    if (hours > 0) then
        return ('%dh %02dm'):fmt(hours, minutes);
    end
    return ('%dm %02ds'):fmt(minutes, seconds % 60);
end

-----------------------------------
-- Drawing helpers
-----------------------------------
-- Ashita returns an ImVec2 either as a table or as two numbers, depending on the call.
function ui.vec2(a, b)
    if (type(a) == 'table') then
        return a.x or a[1], a.y or a[2];
    end
    return a, b;
end

function ui.text_width(text)
    local width = imgui.CalcTextSize(text);
    if (type(width) == 'table') then
        return width.x or width[1] or 0;
    end
    return width or 0;
end

function ui.right_text(width, color, text)
    imgui.SameLine(ui.PADDING + width - ui.text_width(text));
    imgui.TextColored(color, text);
end

function ui.stat_cell(label, value, color)
    imgui.TableNextColumn();
    imgui.TextColored(COLOR.muted, label);
    imgui.TextColored(color or COLOR.text, value);
end

function ui.toggle_button(label, on, width)
    imgui.PushStyleColor(ImGuiCol_Button, on and COLOR.royal or COLOR.surface2);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, on and COLOR.hover or COLOR.tint);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, COLOR.royal);
    imgui.PushStyleColor(ImGuiCol_Text, on and COLOR.text or COLOR.muted);
    local clicked = imgui.Button(label, { width, 0 });
    imgui.PopStyleColor(4);
    return clicked;
end

-- A progress bar for a value only known as a range: solid up to lo, faint from lo to hi.
function ui.range_bar(width, height, lo, hi, color)
    local x, y = ui.vec2(imgui.GetCursorScreenPos());
    local list = imgui.GetWindowDrawList();
    local faint = { color[1], color[2], color[3], 0.35 };
    lo = math.max(0, math.min(1, lo));
    hi = math.max(lo, math.min(1, hi));
    list:AddRectFilled({ x, y }, { x + width, y + height }, imgui.GetColorU32(COLOR.surface2), 4.0);
    if (hi > lo) then
        list:AddRectFilled({ x + width * lo, y }, { x + width * hi, y + height }, imgui.GetColorU32(faint), 0.0);
    end
    if (lo > 0) then
        list:AddRectFilled({ x, y }, { x + width * lo, y + height }, imgui.GetColorU32(color), 4.0);
    end
    imgui.Dummy({ width, height });
end

function ui.window_flags(locked)
    local flags = bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoCollapse);
    if (locked) then
        flags = bit.bor(flags, ImGuiWindowFlags_NoMove);
    end
    return flags;
end

-- Returns how many colours and style vars were pushed, for the matching pops.
function ui.push_theme(alpha)
    local colors = {
        { ImGuiCol_WindowBg,          { COLOR.abyss[1], COLOR.abyss[2], COLOR.abyss[3], alpha } },
        { ImGuiCol_TitleBg,           COLOR.surface1 },
        { ImGuiCol_TitleBgActive,     COLOR.surface2 },
        { ImGuiCol_TitleBgCollapsed,  COLOR.surface1 },
        { ImGuiCol_Border,            COLOR.border   },
        { ImGuiCol_Separator,         COLOR.border   },
        { ImGuiCol_Text,              COLOR.text     },
        { ImGuiCol_TextDisabled,      COLOR.muted    },
        { ImGuiCol_FrameBg,           COLOR.surface2 },
        { ImGuiCol_FrameBgHovered,    COLOR.tint     },
        { ImGuiCol_FrameBgActive,     COLOR.surface2 },
        { ImGuiCol_SliderGrab,        COLOR.royal    },
        { ImGuiCol_SliderGrabActive,  COLOR.hover    },
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
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { ui.PADDING, 10 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 8, 5 });
    imgui.PushStyleVar(ImGuiStyleVar_CellPadding, { 4, 3 });

    return #colors, 5;
end

-----------------------------------
-- Packet helpers
-----------------------------------
function ui.u16(data, offset)
    local low, high = data:byte(offset + 1, offset + 2);
    return (low or 0) + (high or 0) * 256;
end

function ui.u32(data, offset)
    return ui.u16(data, offset) + ui.u16(data, offset + 2) * 65536;
end

-- Saved daily data lives beside Ashita's own settings for the addon.
function ui.data_folder(addon_name)
    return ('%s\\config\\addons\\%s\\'):fmt(AshitaCore:GetInstallPath(), addon_name or addon.name);
end

-- addon_name reads another addon's saved data, for picking up counts from the standalone versions.
function ui.read_data(name, addon_name)
    local chunk = loadfile(ui.data_folder(addon_name) .. name);
    if (not chunk) then
        return T{};
    end
    local ok, data = pcall(chunk);
    if (not ok or type(data) ~= 'table') then
        return T{};
    end
    return data;
end

function ui.write_data(name, body)
    local folder = ui.data_folder();
    if (not ashita.fs.exists(folder)) then
        ashita.fs.create_directory(folder);
    end
    local file = io.open(folder .. name, 'w');
    if (not file) then
        return;
    end
    file:write(body);
    file:close();
end

return ui;
