<#
Builds fishdata.lua from the fishing tables in the Phoenix server repo.

    git clone https://github.com/phoenixffxi/Phoenix
    powershell -ExecutionPolicy Bypass -File tools\build_fishdata.ps1 -Phoenix C:\path\to\Phoenix

Only the columns the addon needs to mirror fishingutils::FishingCheck are kept.
#>
param(
    [Parameter(Mandatory = $true)][string]$Phoenix,
    [string]$Out
)

$ErrorActionPreference = 'Stop';
if (-not $Out) { $Out = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\fishdata.lua'; }
$sql = Join-Path $Phoenix 'sql';

function Split-Values([string]$text) {
    $values = New-Object System.Collections.Generic.List[object];
    $i = 0;
    while ($i -lt $text.Length) {
        $c = $text[$i];
        if ($c -eq ' ' -or $c -eq ',') { $i++; continue; }
        if ($c -eq "'") {
            $sb = New-Object System.Text.StringBuilder;
            $i++;
            while ($i -lt $text.Length) {
                $c = $text[$i];
                if ($c -eq '\') { [void]$sb.Append($text[$i + 1]); $i += 2; continue; }
                if ($c -eq "'") {
                    if ($i + 1 -lt $text.Length -and $text[$i + 1] -eq "'") { [void]$sb.Append("'"); $i += 2; continue; }
                    $i++;
                    break;
                }
                [void]$sb.Append($c);
                $i++;
            }
            $values.Add($sb.ToString());
            continue;
        }
        $start = $i;
        while ($i -lt $text.Length -and $text[$i] -ne ',') { $i++; }
        $values.Add($text.Substring($start, $i - $start).Trim());
    }
    return ,$values;
}

function Read-Rows([string]$table) {
    $rows = New-Object System.Collections.Generic.List[object];
    $pattern = '^INSERT INTO `' + $table + '` VALUES \((.*)\);';
    foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $sql "$table.sql"))) {
        if ($line -match $pattern) {
            $rows.Add((Split-Values $Matches[1]));
        }
    }
    return ,$rows;
}

function Read-Floats([string]$hex) {
    if ($hex -notmatch '^0x([0-9A-Fa-f]+)$') { return @(); }
    $digits = $Matches[1];
    $bytes  = New-Object byte[] ($digits.Length / 2);
    for ($b = 0; $b -lt $bytes.Length; $b++) {
        $bytes[$b] = [Convert]::ToByte($digits.Substring($b * 2, 2), 16);
    }
    $floats = @();
    for ($o = 0; $o + 4 -le $bytes.Length; $o += 4) {
        $floats += [BitConverter]::ToSingle($bytes, $o);
    }
    return $floats;
}

function Lua-String([string]$s) {
    return "'" + ($s -replace '\\', '\\' -replace "'", "\'") + "'";
}

function Lua-Number($n) {
    return ([double]$n).ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture);
}

function Test-Number([string]$text) {
    return $text -match '^-?\d+(\.\d+)?$';
}

function Sort-Keys($keys) {
    return ,@($keys | Sort-Object { [int]$_ });
}

function Format-Keys($keys) {
    $width = 0;
    foreach ($key in $keys) { $width = [Math]::Max($width, "[$key]".Length); }
    $heads = New-Object System.Collections.Generic.List[string];
    foreach ($key in $keys) { $heads.Add("[$key]".PadRight($width)); }
    return ,$heads;
}

function Format-Records($rows, [string[]]$columns) {
    $used    = New-Object System.Collections.Generic.List[string];
    $widths  = @{};
    $numeric = @{};
    foreach ($column in $columns) {
        $width  = -1;
        $number = $true;
        foreach ($row in $rows) {
            if (-not $row.Contains($column)) { continue; }
            $width = [Math]::Max($width, $row[$column].Length);
            if (-not (Test-Number $row[$column])) { $number = $false; }
        }
        if ($width -lt 0) { continue; }
        $used.Add($column);
        $widths[$column]  = $width;
        $numeric[$column] = $number;
    }

    $bodies = New-Object System.Collections.Generic.List[string];
    foreach ($row in $rows) {
        $last = $null;
        foreach ($column in $used) {
            if ($row.Contains($column)) { $last = $column; }
        }
        $cells = New-Object System.Collections.Generic.List[string];
        foreach ($column in $used) {
            $cell = '';
            if ($row.Contains($column)) {
                $value = $row[$column];
                if ($numeric[$column]) { $value = $value.PadLeft($widths[$column]); }
                $cell = "$column = $value";
                if ($column -ne $last) { $cell += ','; }
            }
            $cells.Add($cell.PadRight($column.Length + $widths[$column] + 4));
        }
        $bodies.Add(($cells -join ' ').TrimEnd());
    }

    $width = 0;
    foreach ($body in $bodies) { $width = [Math]::Max($width, $body.Length); }
    for ($i = 0; $i -lt $bodies.Count; $i++) { $bodies[$i] = $bodies[$i].PadRight($width); }
    return ,$bodies;
}

function Emit-Records([string]$indent, $keys, $rows, [string[]]$columns) {
    $heads  = Format-Keys $keys;
    $bodies = Format-Records $rows $columns;
    for ($i = 0; $i -lt $bodies.Count; $i++) {
        Emit ("{0}{1} = {{ {2} }}," -f $indent, $heads[$i], $bodies[$i]);
    }
}

function Emit-Grid([string]$indent, $keys, $lists, [int]$perLine) {
    $heads = Format-Keys $keys;
    $width = 0;
    foreach ($list in $lists) {
        foreach ($cell in $list) { $width = [Math]::Max($width, $cell.Length); }
    }
    $full = $perLine * ($width + 2) - 2;
    for ($k = 0; $k -lt $lists.Count; $k++) {
        $list = $lists[$k];
        $lead = "$indent$($heads[$k]) = { ";
        for ($i = 0; $i -lt $list.Count; $i += $perLine) {
            $cells = New-Object System.Collections.Generic.List[string];
            for ($j = $i; $j -lt [Math]::Min($i + $perLine, $list.Count); $j++) {
                $cell = $list[$j].PadLeft($width);
                if ($j -lt $list.Count - 1) { $cell += ','; }
                $cells.Add($cell);
            }
            $text = $cells -join ' ';
            if ($i + $perLine -ge $list.Count) {
                Emit ($lead + $text.PadRight($full) + ' },');
            } else {
                Emit ($lead + $text);
            }
            $lead = ' ' * $lead.Length;
        }
    }
}

$lua = New-Object System.Text.StringBuilder;
function Emit([string]$line) { [void]$lua.AppendLine($line); }

Emit '-- Generated by tools/build_fishdata.ps1 from https://github.com/phoenixffxi/Phoenix. Do not edit by hand.';
Emit 'return {';

# fishing_fish: fishid, name, skill_level, difficulty, base_delay, base_move, min_length, max_length, ranking,
# size_type, water_type, log, quest, quest_status, flags, hour_pattern, moon_pattern, month_pattern, legendary,
# legendary_flags, item, max_hook, rarity, required_keyitem, required_catches, family, quest_only, contest, disabled
# The hour, moon and month patterns are left out: fishingutils::LoadFishItems never selects them, so
# every fish runs with pattern 0 on the server.
$fish = New-Object "System.Collections.Generic.SortedDictionary[int, object]";
foreach ($r in (Read-Rows 'fishing_fish')) {
    if ([int]$r[28] -ne 0 -or [int]$r[8] -ge 99) { continue; }
    $fields = [ordered]@{
        name   = (Lua-String $r[1]);
        skill  = $r[2];
        size   = $r[9];
        rarity = $r[22];
    };
    if ([int]$r[20] -ne 0) { $fields['item'] = 'true'; }
    if (([int]$r[14] -band 1) -ne 0) { $fields['shellfish'] = 'true'; }
    if ([int]$r[18] -ne 0) { $fields['legendary'] = 'true'; }
    if ([int]$r[23] -ne 0) { $fields['keyitem'] = $r[23]; }
    if ([int]$r[11] -lt 255 -and [int]$r[12] -lt 255) { $fields['quest'] = 'true'; }
    if ([int]$r[26] -ne 0) { $fields['quest_only'] = 'true'; }
    $fish[[int]$r[0]] = $fields;
}
Emit '    fish = {';
Emit-Records '        ' $fish.Keys $fish.Values @('name', 'skill', 'size', 'rarity', 'item', 'shellfish', 'legendary', 'keyitem', 'quest', 'quest_only');
Emit '    },';
Emit '';

# fishing_group: groupid, fishid, rarity, pool_size, restock_rate
$groups = @{};
foreach ($r in (Read-Rows 'fishing_group')) {
    $group = [string]$r[0];
    if (-not $fish.ContainsKey([int]$r[1])) { continue; }
    if (-not $groups.ContainsKey($group)) { $groups[$group] = New-Object System.Collections.Generic.List[string]; }
    $groups[$group].Add($r[1]);
}
$groupKeys = Sort-Keys $groups.Keys;
Emit '    groups = {';
Emit-Grid '        ' $groupKeys @($groupKeys | ForEach-Object { ,$groups[$_] }) 10;
Emit '    },';
Emit '';

# fishing_catch: zoneid, areaid, groupid
$catch   = @{};
$catchAt = @{};
foreach ($r in (Read-Rows 'fishing_catch')) {
    $zone = [string]$r[0];
    if (-not $catch.ContainsKey($zone)) { $catch[$zone] = [ordered]@{}; }
    $catch[$zone]["[$($r[1])]"] = $r[2];
    $catchAt[[int]$r[1]] = $true;
}
$catchKeys = Sort-Keys $catch.Keys;
Emit '    catch = {';
Emit-Records '        ' $catchKeys @($catchKeys | ForEach-Object { $catch[$_] }) @((Sort-Keys $catchAt.Keys) | ForEach-Object { "[$_]" });
Emit '    },';
Emit '';

# fishing_area: zoneid, areaid, name, bound_type, bound_height, bound_radius, bounds, center_x, center_y, center_z
$areas = @{};
foreach ($r in (Read-Rows 'fishing_area')) {
    $zone = [string]$r[0];
    if (-not $areas.ContainsKey($zone)) { $areas[$zone] = New-Object "System.Collections.Generic.SortedDictionary[int, object]"; }
    $areas[$zone][[int]$r[1]] = $r;
}
Emit '    areas = {';
foreach ($zone in (Sort-Keys $areas.Keys)) {
    Emit "        [$zone] = {";
    $rows   = New-Object System.Collections.Generic.List[object];
    $bounds = New-Object System.Collections.Generic.List[object];
    foreach ($r in $areas[$zone].Values) {
        $rows.Add([ordered]@{
            id     = $r[1];
            name   = (Lua-String $r[2]);
            type   = $r[3];
            height = $r[4];
            radius = $r[5];
            x      = (Lua-Number $r[7]);
            y      = (Lua-Number $r[8]);
            z      = (Lua-Number $r[9]);
        });
        # Trailing all-zero points are padding, the same way LoadFishingAreas trims them.
        $floats = Read-Floats $r[6];
        $count  = 0;
        for ($p = 0; $p + 3 -le $floats.Count; $p += 3) {
            if ($floats[$p] -ne 0 -or $floats[$p + 1] -ne 0 -or $floats[$p + 2] -ne 0) { $count = $p / 3 + 1; }
        }
        $points = New-Object System.Collections.Generic.List[object];
        for ($p = 0; $p -lt $count; $p++) {
            $points.Add(@((Lua-Number $floats[$p * 3]), (Lua-Number $floats[$p * 3 + 1]), (Lua-Number $floats[$p * 3 + 2])));
        }
        $bounds.Add($points);
    }
    $bodies = Format-Records $rows @('id', 'name', 'type', 'height', 'radius', 'x', 'y', 'z');
    for ($i = 0; $i -lt $bodies.Count; $i++) {
        $points = $bounds[$i];
        if ($points.Count -eq 0) {
            Emit ("            {{ {0} }}," -f $bodies[$i]);
            continue;
        }
        $widths = @(0, 0, 0);
        foreach ($point in $points) {
            for ($a = 0; $a -lt 3; $a++) { $widths[$a] = [Math]::Max($widths[$a], $point[$a].Length); }
        }
        Emit ("            {{ {0}, bounds = {{" -f $bodies[$i].TrimEnd());
        foreach ($point in $points) {
            Emit ("                {{ {0}, {1}, {2} }}," -f $point[0].PadLeft($widths[0]), $point[1].PadLeft($widths[1]), $point[2].PadLeft($widths[2]));
        }
        Emit '            } },';
    }
    Emit '        },';
}
Emit '    },';
Emit '';

# fishing_zone: zoneid, name, difficulty. City zones come from data/zones/<name>/zone.yaml, found through
# data/enums/zone.yaml. Both change the pool weights in fishingutils::FishingCheck.
$zoneNames = @{};
foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $Phoenix 'data\enums\zone.yaml'))) {
    if ($line -match '^\s+([a-z0-9_]+):\s+(\d+)') {
        $zoneNames[$Matches[2]] = $Matches[1];
    }
}
$zones = New-Object "System.Collections.Generic.SortedDictionary[int, object]";
foreach ($r in (Read-Rows 'fishing_zone')) {
    $fields = [ordered]@{};
    $yaml   = if ($zoneNames.ContainsKey($r[0])) { Join-Path $Phoenix "data\zones\$($zoneNames[$r[0]])\zone.yaml" } else { $null };
    if ($yaml -and (Test-Path $yaml) -and ((Get-Content $yaml -TotalCount 5) -match '^type:.*\bcity\b')) { $fields['city'] = 'true'; }
    if ([int]$r[2] -ne 0) { $fields['difficulty'] = $r[2]; }
    if ($fields.Count -gt 0) { $zones[[int]$r[0]] = $fields; }
}
Emit '    zones = {';
Emit-Records '        ' $zones.Keys $zones.Values @('city', 'difficulty');
Emit '    },';
Emit '';

# fishing_bait_affinity: baitid, fishid, power
$affinity = @{};
foreach ($r in (Read-Rows 'fishing_bait_affinity')) {
    $bait = [string]$r[0];
    if (-not $affinity.ContainsKey($bait)) { $affinity[$bait] = New-Object "System.Collections.Generic.SortedDictionary[int, string]"; }
    $affinity[$bait][[int]$r[1]] = $r[2];
}
$baitKeys = Sort-Keys $affinity.Keys;
$powers   = @($baitKeys | ForEach-Object {
    $entries = $affinity[$_];
    ,@($entries.Keys | ForEach-Object { '[{0}] = {1}' -f $_, $entries[$_] })
});
Emit '    affinity = {';
Emit-Grid '        ' $baitKeys $powers 8;
Emit '    },';
Emit '';

# fishing_bait: baitid, name, type, maxhook, losable, flags, mmm, rankmod
$baits = New-Object "System.Collections.Generic.SortedDictionary[int, object]";
foreach ($r in (Read-Rows 'fishing_bait')) {
    $baits[[int]$r[0]] = [ordered]@{ name = (Lua-String $r[1]); type = $r[2]; flags = $r[5] };
}
Emit '    baits = {';
Emit-Records '        ' $baits.Keys $baits.Values @('name', 'type', 'flags');
Emit '    },';
Emit '';

# fishing_rod: rodid, name, material, size_type, flags, min_rank, max_rank, ... legendary (20), rating
$rods = New-Object "System.Collections.Generic.SortedDictionary[int, object]";
foreach ($r in (Read-Rows 'fishing_rod')) {
    $fields = [ordered]@{ name = (Lua-String $r[1]); size = $r[3] };
    if ([int]$r[20] -ne 0) { $fields['legendary'] = 'true'; }
    $rods[[int]$r[0]] = $fields;
}
Emit '    rods = {';
Emit-Records '        ' $rods.Keys $rods.Values @('name', 'size', 'legendary');
Emit '    },';
Emit '';

# fishing_mob: mobid, name, zoneid, level, min_length, max_length, ranking, difficulty, base_delay, base_move,
# log, quest, nm, nm_flags, areaid, rarity, min_respawn, max_respawn, required_baitid, alternative_baitid,
# required_keyitem, quest_only, disabled
$mobs = @{};
$seen = @{};
foreach ($r in (Read-Rows 'fishing_mob')) {
    if ([int]$r[22] -ne 0) { continue; }
    $zone   = [string]$r[2];
    $fields = [ordered]@{ name = (Lua-String ($r[1] -replace '_', ' ')); area = $r[14] };
    if ([int]$r[12] -ne 0) { $fields['nm'] = 'true'; }
    if ([int]$r[18] -ne 0) { $fields['bait'] = $r[18]; }
    if ([int]$r[19] -ne 0) { $fields['alt_bait'] = $r[19]; }
    if ([int]$r[10] -lt 255 -and [int]$r[11] -lt 255) { $fields['quest'] = 'true'; }
    $entry = @($fields.Keys | ForEach-Object { "$_=$($fields[$_])" }) -join ';';
    if ($seen.ContainsKey("$zone $entry")) { continue; }
    $seen["$zone $entry"] = $true;
    if (-not $mobs.ContainsKey($zone)) { $mobs[$zone] = New-Object System.Collections.Generic.List[object]; }
    $mobs[$zone].Add($fields);
}
Emit '    mobs = {';
foreach ($zone in (Sort-Keys $mobs.Keys)) {
    Emit "        [$zone] = {";
    foreach ($body in (Format-Records $mobs[$zone] @('name', 'area', 'nm', 'bait', 'alt_bait', 'quest'))) {
        Emit "            { $body },";
    }
    Emit '        },';
}
Emit '    },';

Emit '};';

$utf8 = New-Object System.Text.UTF8Encoding($false);
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($Out), $lua.ToString(), $utf8);
Write-Host "Wrote $Out";
