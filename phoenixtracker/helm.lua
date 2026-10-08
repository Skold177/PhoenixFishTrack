-- Shared presentation for harvesting, logging, mining and excavation. The model owns the server rules,
-- packet correlation and saved counts; each tab gets its own model and session.
require('common');

local imgui      = require('imgui');
local ui         = require('ui');
local helmdata   = require('helmdata');
local helm_model = require('helm_model');

local COLOR = ui.COLOR;
local helm = {};

local function percent(value)
    if (value == nil) then
        return 'Unknown';
    end
    return ('%.1f%%'):fmt(value);
end

local function note(width, color, text)
    imgui.PushTextWrapPos(ui.PADDING + width);
    imgui.TextColored(color, text);
    imgui.PopTextWrapPos();
end

function helm.new(type_id)
    local definition = assert(helmdata.types[type_id], 'Unknown HELM type');
    local model = helm_model.new(type_id);
    local ctx;
    local names = T{};
    local M = T{ key = definition.key, label = definition.label, defaults = T{} };
    local prefix = ({ [1] = '/pharvest', [2] = '/pexcavate', [3] = '/plog', [4] = '/pmine' })[type_id];
    local has_depletion, has_caps = false, false;
    for _, zone in pairs(definition.zones) do
        has_depletion = has_depletion or zone.depletion ~= nil;
        has_caps = has_caps or next(zone.daily_caps or {}) ~= nil;
    end
    local tracks_fatigue = has_depletion or has_caps;

    local function item_name(id)
        if (not names[id]) then
            local item = AshitaCore:GetResourceManager():GetItemById(id);
            names[id] = (item and item.Name[1]) or ('Item %d'):fmt(id);
        end
        return names[id];
    end

    local function pool_now()
        return model.pool();
    end

    local function info_line(label, value, color)
        local indent = math.max(ui.text_width('Zone:'), ui.text_width('Tool:')) + 8;
        imgui.TextColored(COLOR.muted, label);
        imgui.SameLine(ui.PADDING + indent);
        imgui.TextColored(color or COLOR.secondary, value);
    end

    local function draw_status(width, snapshot, pool)
        imgui.Spacing();
        info_line('Zone:', snapshot.zone and snapshot.zone.name or 'No known pool here', snapshot.zone and COLOR.secondary or COLOR.faint);
        local count = snapshot.tool_count or 0;
        info_line('Tool:', ('%s x%d'):fmt(item_name(definition.tool), count), count > 0 and COLOR.secondary or COLOR.danger);
        if (pool.known) then
            if (snapshot.zone.note) then
                note(width, COLOR.peach, snapshot.zone.note);
            end
            if (snapshot.zone.weathers) then
                if (pool.weather_available == false) then
                    note(width, COLOR.gold, 'No harvesting points in this weather. Rain or squalls are required.');
                elseif (pool.weather_available == nil) then
                    note(width, COLOR.muted, 'Weather unknown. Harvesting points require rain or squalls.');
                else
                    note(width, COLOR.secondary, 'Rain or squalls: harvesting points can appear.');
                end
            end
            if (pool.low_level) then
                note(width, COLOR.danger, ('Main level %d required to find items here. Tools can still break.'):fmt(pool.min_level));
            elseif (count == 0) then
                note(width, COLOR.muted, 'Keep a tool in your inventory to gather here.');
            end
        end
    end

    local function draw_daily(width, font, font_size, snapshot)
        local daily = snapshot.daily;
        imgui.Spacing();
        imgui.TextColored(COLOR.muted, 'TODAY\'S FINDS');
        imgui.PushFont(font, font_size * 2.0);
        imgui.TextColored(COLOR.text, tostring(daily.finds));
        imgui.PopFont();
        ui.right_text(width, COLOR.muted, ('%d attempts'):fmt(daily.attempts));
        note(width, COLOR.faint, 'Observed totals reset at JST midnight.');
        imgui.Spacing();
    end

    local function draw_session(width, snapshot, pool)
        if (not imgui.CollapsingHeader('Session', ImGuiTreeNodeFlags_DefaultOpen)) then
            return;
        end
        local session = snapshot.session;
        local elapsed = session.started and (os.time() - session.started) or 0;
        local hit_rate = session.attempts > 0 and percent(session.finds * 100 / session.attempts) or '-';
        local per_hour = elapsed >= 60 and ('%.0f'):fmt(session.finds * 3600 / elapsed) or '-';
        local expected = pool.known and percent(pool.low_level and 0 or pool.obtain_rate) or '-';
        if (imgui.BeginTable('##helm_' .. M.key .. '_session', 4, ImGuiTableFlags_SizingStretchSame, { width, 0 })) then
            ui.stat_cell('Attempts', tostring(session.attempts));
            ui.stat_cell('Finds', tostring(session.finds));
            ui.stat_cell('Nothing', tostring(session.nothing));
            ui.stat_cell('Hit rate', hit_rate);
            ui.stat_cell('Broken', tostring(session.broken));
            ui.stat_cell('Full bags', tostring(session.full));
            ui.stat_cell('Per hour', per_hour);
            ui.stat_cell('Expected', expected);
            imgui.EndTable();
        end
        if ((session.unconfirmed or 0) > 0) then
            note(width, COLOR.gold, ('%d results could not be confirmed in inventory. Item totals exclude them.'):fmt(session.unconfirmed));
        end
        if ((snapshot.pending or 0) > 0) then
            note(width, COLOR.muted, ('%d item awards awaiting confirmation.'):fmt(snapshot.pending));
        end
        if (session.full > 0) then
            note(width, COLOR.muted, 'Full bags prevent an item award; they do not use up rare-item allowances.');
        end
    end

    local function draw_fatigue(width, scale, snapshot)
        if (not imgui.CollapsingHeader('Rare-item Fatigue', ImGuiTreeNodeFlags_DefaultOpen)) then
            return;
        end
        if (not tracks_fatigue) then
            note(width, COLOR.secondary, 'No rare-item depletion or item caps for this activity.');
            return;
        end
        if (not snapshot.zone) then
            note(width, COLOR.faint, ('Enter a %s zone to see its rare-item rules.'):fmt(M.label:lower()));
            return;
        end

        local fatigue = snapshot.fatigue;
        local depletion = fatigue.depletion;
        local caps = fatigue.caps or {};
        local unknown = false;
        if (depletion) then
            imgui.TextColored(COLOR.muted, 'Shared rare pool');
            if (depletion.known) then
                ui.right_text(width, COLOR.ember, ('%d / %d'):fmt(depletion.count, depletion.max));
                imgui.PushStyleColor(ImGuiCol_PlotHistogram, COLOR.royal);
                imgui.ProgressBar(math.min(1, depletion.count / depletion.max), { width, 8 * scale }, '');
                imgui.PopStyleColor(1);
            else
                unknown = true;
                ui.right_text(width, COLOR.gold, 'Unknown');
                note(width, COLOR.muted, ('%d rare finds observed this run. Earlier progress is unknown.'):fmt(depletion.observed or 0));
            end
            local pool_names = T{};
            for id in pairs(snapshot.zone.depletion.pool) do
                pool_names:append(item_name(id));
            end
            table.sort(pool_names);
            note(width, COLOR.faint, 'Shared by ' .. pool_names:concat(', ') .. '.');
            note(width, COLOR.secondary, 'Each find lowers every item\'s weight in this pool. Zoning resets it; waiting here does not.');
        end

        local cap_ids = T{};
        for id in pairs(caps) do
            cap_ids:append(id);
        end
        table.sort(cap_ids);
        if (#cap_ids > 0) then
            local flags = bit.bor(ImGuiTableFlags_RowBg, ImGuiTableFlags_BordersInnerH, ImGuiTableFlags_PadOuterX);
            if (imgui.BeginTable('##helm_' .. M.key .. '_caps', 2, flags, { width, 0 })) then
                imgui.TableSetupColumn('Capped item', ImGuiTableColumnFlags_WidthStretch, 0, 0);
                imgui.TableSetupColumn('Obtained', ImGuiTableColumnFlags_WidthFixed, ui.text_width('Unknown') + 8 * scale, 0);
                imgui.TableHeadersRow();
                for _, id in ipairs(cap_ids) do
                    local cap = caps[id];
                    unknown = unknown or not cap.known;
                    imgui.TableNextRow();
                    imgui.TableNextColumn();
                    imgui.TextColored(COLOR.secondary, item_name(id));
                    imgui.TableNextColumn();
                    imgui.TextColored(cap.known and COLOR.text or COLOR.gold, cap.known and ('%d / %d'):fmt(cap.count, cap.limit) or 'Unknown');
                end
                imgui.EndTable();
            end
            note(width, COLOR.secondary, 'Each capped item becomes less likely after a find. Its cap resets on zone entry after JST midnight, not while you remain here.');
        end
        if (not depletion and #cap_ids == 0) then
            note(width, COLOR.secondary, 'This zone has no rare-item depletion or item caps.');
        elseif (unknown) then
            note(width, COLOR.gold, 'Current odds are unknown until the relevant reset is observed or a known count is entered.');
            if (depletion) then
                note(width, COLOR.faint, prefix .. ' fatigue <count> sets a known shared-pool count.');
            end
            if (#cap_ids > 0) then
                note(width, COLOR.faint, prefix .. ' cap <item-id> <count> sets a known item count.');
            end
        end
    end

    local function draw_pool(width, scale, pool)
        if (not imgui.CollapsingHeader('Possible Finds', ImGuiTreeNodeFlags_DefaultOpen)) then
            return;
        end
        if (not pool.known) then
            note(width, COLOR.faint, 'No Phoenix pool data for this activity in this zone.');
            return;
        end
        local flags = bit.bor(ImGuiTableFlags_RowBg, ImGuiTableFlags_BordersInnerH, ImGuiTableFlags_PadOuterX);
        local size = { width, 0 };
        if (#pool.rows > 12) then
            flags = bit.bor(flags, ImGuiTableFlags_ScrollY);
            size = { width, 13 * imgui.GetTextLineHeightWithSpacing() };
        end
        if (imgui.BeginTable('##helm_' .. M.key .. '_pool', tracks_fatigue and 3 or 2, flags, size)) then
            local odds_width = math.max(ui.text_width('Unknown'), ui.text_width('100.0%')) + 4 * scale;
            imgui.TableSetupColumn('Item', ImGuiTableColumnFlags_WidthStretch, 0, 0);
            if (tracks_fatigue) then
                imgui.TableSetupColumn('Fresh', ImGuiTableColumnFlags_WidthFixed, odds_width, 0);
            end
            imgui.TableSetupColumn(tracks_fatigue and 'Now' or 'Odds', ImGuiTableColumnFlags_WidthFixed, odds_width, 0);
            imgui.TableHeadersRow();
            for _, row in ipairs(pool.rows) do
                imgui.TableNextRow();
                imgui.TableNextColumn();
                imgui.TextColored(row.affected and COLOR.peach or COLOR.secondary, item_name(row.id));
                if (tracks_fatigue) then
                    imgui.TableNextColumn();
                    imgui.TextColored(COLOR.muted, percent(row.base_odds));
                end
                imgui.TableNextColumn();
                imgui.TextColored(row.odds ~= nil and COLOR.text or COLOR.gold, percent(row.odds));
            end
            imgui.EndTable();
        end
        note(width, COLOR.faint, 'Odds are conditional on finding an item; they are not the chance per attempt.');
        if (tracks_fatigue) then
            note(width, COLOR.muted, 'Fresh assumes every allowance is unused. Now adjusts all odds for the tracked rare-item counts.');
        end
        if (pool.low_level) then
            note(width, COLOR.danger, ('The pool unlocks at main level %d.'):fmt(pool.min_level));
        end
    end

    local function draw_items(width, scale, snapshot)
        if (not imgui.CollapsingHeader('Today\'s Items', ImGuiTreeNodeFlags_DefaultOpen)) then
            return;
        end
        local rows = T{};
        for id, quantity in pairs(snapshot.daily.items) do
            rows:append(T{ id = id, name = item_name(id), quantity = quantity });
        end
        table.sort(rows, function(a, b)
            if (a.quantity == b.quantity) then
                return a.name < b.name;
            end
            return a.quantity > b.quantity;
        end);
        if (#rows == 0) then
            note(width, COLOR.faint, 'No confirmed items gathered today.');
        else
            local flags = bit.bor(ImGuiTableFlags_RowBg, ImGuiTableFlags_BordersInnerH, ImGuiTableFlags_PadOuterX);
            local size = { width, 0 };
            if (#rows > 10) then
                flags = bit.bor(flags, ImGuiTableFlags_ScrollY);
                size = { width, 11 * imgui.GetTextLineHeightWithSpacing() };
            end
            if (imgui.BeginTable('##helm_' .. M.key .. '_items', 2, flags, size)) then
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
                imgui.EndTable();
            end
        end
        if ((snapshot.daily.unconfirmed or 0) > 0) then
            note(width, COLOR.gold, ('%d unconfirmed results today.'):fmt(snapshot.daily.unconfirmed));
        end
    end

    local function print_pool()
        local snapshot = model.snapshot();
        local pool = pool_now();
        if (not pool.known) then
            ui.say('No Phoenix pool data for this activity in this zone.');
            return;
        end
        ui.say(('%s: %s chance to find something.'):fmt(snapshot.zone.name, percent(pool.low_level and 0 or pool.obtain_rate)));
        for _, row in ipairs(pool.rows) do
            local odds = percent(row.odds);
            if (row.odds == nil) then
                odds = ('unknown now; %s before fatigue'):fmt(percent(row.base_odds));
            end
            ui.say(('%s: %s'):fmt(item_name(row.id), odds));
        end
    end

    function M.init(context) ctx = context; end
    function M.ready() return model.snapshot().ready; end
    function M.day() return model.snapshot().day; end
    function M.account() return ''; end
    function M.fit_width(width) return width; end
    function M.render_popups() end
    function M.reset_positions() end
    function M.reset_session() model.reset_session(); end
    function M.reload() model.reload(); end
    function M.present() model.present(); end
    function M.unload() model.unload(); end

    function M.packet_in(e)
        if (model.packet_in(e)) then
            ctx.activity(M);
        end
    end

    function M.draw(width, scale, font, font_size)
        local snapshot = model.snapshot();
        local pool = pool_now();
        draw_status(width, snapshot, pool);
        draw_daily(width, font, font_size, snapshot);
        draw_session(width, snapshot, pool);
        draw_fatigue(width, scale, snapshot);
        draw_pool(width, scale, pool);
        draw_items(width, scale, snapshot);
    end

    function M.help(command)
        ui.say(('%s pool - list possible finds and current odds'):fmt(command));
        ui.say(('%s reset - clear this activity\'s session stats'):fmt(command));
        if (has_depletion) then
            ui.say(('%s fatigue <count> - set a known shared rare-pool count here'):fmt(command));
        end
        if (has_caps) then
            ui.say(('%s cap <item-id> <count> - set a known capped-item count here'):fmt(command));
        end
    end

    function M.command(sub, args, command)
        if (sub == 'pool') then
            print_pool();
        elseif (sub == 'reset') then
            model.reset_session();
            ui.say(M.label .. ' session stats cleared.');
        elseif (sub == 'fatigue' and has_depletion) then
            local count = tonumber(args[3]);
            if (not count) then
                ui.say(('Usage: %s fatigue <count>'):fmt(command));
            else
                local ok, reason = model.set_depletion(count);
                ui.say(ok and ('Shared rare-pool count set to %d.'):fmt(count) or reason);
            end
        elseif (sub == 'cap' and has_caps) then
            local id, count = tonumber(args[3]), tonumber(args[4]);
            if (not id or not count) then
                ui.say(('Usage: %s cap <item-id> <count>'):fmt(command));
            else
                local ok, reason = model.set_cap(id, count);
                ui.say(ok and ('%s count set to %d.'):fmt(item_name(id), count) or reason);
            end
        else
            return false;
        end
        return true;
    end

    return M;
end

return helm;
