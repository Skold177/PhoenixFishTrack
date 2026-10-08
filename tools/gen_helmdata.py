"""Generate HELM pools and event identities from a Phoenix checkout or Git ref.

Usage: python tools/gen_helmdata.py phoenixtracker/helmdata.lua PATH_TO_PHOENIX
       python tools/gen_helmdata.py phoenixtracker/helmdata.lua PATH_TO_REPO --ref phoenix/beta

The output uses Phoenix's fixed pre-WotG profile and applies its era removals. This script
parses the relevant Lua table literals without executing server code or requiring
third-party packages. Unsupported source syntax fails instead of omitting rows.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess


DATA_PATH = "scripts/globals/hobbies/helm/data.lua"
ERA_PATH = "modules/era/lua/globals/helm/helm_adjustments.lua"
TYPE_INFO = {
    1: ("harvest", "Harvesting"),
    2: ("excavate", "Excavation"),
    3: ("log", "Logging"),
    4: ("mine", "Mining"),
}
PHOENIX_ZONES = {
    1: {"WAJAOM_WOODLANDS", "BHAFLAU_THICKETS", "PASHHOW_MARSHLANDS", "WEST_SARUTABARUTA",
        "YUHTUNGA_JUNGLE", "YHOATOR_JUNGLE", "GIDDEUS"},
    2: {"ATTOHWA_CHASM", "TAHRONGI_CANYON", "KORROLOKA_TUNNEL", "MAZE_OF_SHAKHRAMI"},
    3: {"CARPENTERS_LANDING", "LUFAISE_MEADOWS", "MISAREAUX_COAST", "MAMOOK", "CAEDARVA_MIRE",
        "EAST_RONFAURE", "JUGNER_FOREST", "BUBURIMU_PENINSULA", "YUHTUNGA_JUNGLE",
        "YHOATOR_JUNGLE", "GHELSBA_OUTPOST"},
    4: {"OLDTON_MOVALPOLOS", "NEWTON_MOVALPOLOS", "MOUNT_ZHAYOLM", "HALVUNG", "YUGHOTT_GROTTO",
        "PALBOROUGH_MINES", "ZERUHN_MINES", "GUSGEN_MINES", "IFRITS_CAULDRON"},
}


class SourceError(ValueError):
    pass


class Source:
    def __init__(self, root, ref=None):
        self.root = Path(root).resolve()
        self.ref = ref
        self.cache = {}
        self.commit = self.git("rev-parse", ref or "HEAD").strip()
        if ref:
            self.paths = set(self.git("ls-tree", "-r", "--name-only", ref).splitlines())
        else:
            self.paths = {
                path.relative_to(self.root).as_posix()
                for base in ("scripts", "data", "modules")
                for path in (self.root / base).rglob("*") if path.is_file()
            }

    def git(self, *args):
        result = subprocess.run(
            ["git", "-C", str(self.root), *args], capture_output=True, check=False
        )
        if result.returncode:
            raise SourceError(result.stderr.decode("utf-8", errors="replace").strip())
        return result.stdout.decode("utf-8-sig")

    def read(self, path):
        if path not in self.paths:
            raise SourceError(f"Missing source file: {path}")
        if path not in self.cache:
            self.cache[path] = (
                self.git("show", f"{self.ref}:{path}") if self.ref
                else (self.root / path).read_text(encoding="utf-8-sig")
            )
        return self.cache[path]

    def trade_scripts(self):
        if self.ref:
            lines = self.git("grep", "-l", "-F", "xi.helm.onTrade", self.ref, "--", "scripts/zones").splitlines()
            return [line.split(":", 1)[1] for line in lines]
        return [path for path in sorted(self.paths)
                if path.startswith("scripts/zones/") and "/npcs/" in path
                and path.endswith(".lua") and "xi.helm.onTrade" in self.read(path)]


TOKEN = re.compile(
    r"(?P<skip>\s+|--\[\[.*?\]\]|--[^\n]*)"
    r"|(?P<string>'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\")"
    r"|(?P<number>-?\d+(?:\.\d+)?)"
    r"|(?P<name>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)"
    r"|(?P<symbol>[{}\[\]=,;])",
    re.S,
)


class TableParser:
    """The literal table subset used by HELM data and its enum/removal tables."""

    def __init__(self, text, start=0, refs=None, label="source"):
        self.text, self.pos, self.refs, self.label = text, start, refs or {}, label
        self.current = None
        self.next()

    def error(self, message):
        line = self.text.count("\n", 0, self.pos) + 1
        raise SourceError(f"{self.label}:{line}: {message}")

    def next(self):
        while self.pos < len(self.text):
            match = TOKEN.match(self.text, self.pos)
            if not match:
                self.error(f"Unsupported Lua syntax near {self.text[self.pos:self.pos + 24]!r}")
            self.pos = match.end()
            if match.lastgroup != "skip":
                self.current = (match.lastgroup, match.group())
                return
        self.current = ("eof", "")

    def expect(self, token):
        if self.current[1] != token:
            self.error(f"Expected {token!r}, got {self.current[1]!r}")
        self.next()

    def value(self):
        kind, value = self.current
        if value == "{":
            return self.table()
        self.next()
        if kind == "number":
            return float(value) if "." in value else int(value)
        if kind == "string":
            # Source metadata strings use plain ASCII without escape sequences.
            if "\\" in value:
                self.error("Escaped strings are unsupported in HELM source tables")
            return value[1:-1]
        if kind == "name" and value in self.refs:
            return self.refs[value]
        if value in ("true", "false"):
            return value == "true"
        self.error(f"Unknown table value {value!r}")

    def table(self):
        self.expect("{")
        result, array_index = {}, 1
        while self.current[1] != "}":
            if self.current[0] == "eof":
                self.error("Unclosed table")
            if self.current[1] == "[":
                self.next()
                key = self.value()
                self.expect("]")
                self.expect("=")
                value = self.value()
            elif self.current[0] == "name" and "." not in self.current[1]:
                key = self.current[1]
                self.next()
                self.expect("=")
                value = self.value()
            else:
                key, value = array_index, self.value()
                array_index += 1
            if key in result:
                self.error(f"Duplicate table key {key!r}")
            result[key] = value
            if self.current[1] in (",", ";"):
                self.next()
            elif self.current[1] != "}":
                self.error("Expected a field separator")
        self.expect("}")
        return result


def parse_table(text, assignment, refs=None, label="source"):
    match = re.search(r"(?<![\w.])" + assignment + r"\s*=\s*(\{)", text)
    if not match:
        raise SourceError(f"{label}: missing table {assignment}")
    parser = TableParser(text, match.start(1), refs, label)
    return parser.table()


def normalize(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def array(value, label):
    if not isinstance(value, dict) or set(value) != set(range(1, len(value) + 1)):
        raise SourceError(f"{label}: expected a contiguous Lua array")
    return [value[index] for index in range(1, len(value) + 1)]


def build(source):
    refs, enums = {}, {}
    for name in ("item", "helm_type", "emote"):
        lua_name = "helmType" if name == "helm_type" else name
        path = f"scripts/enum/{name}.lua"
        values = parse_table(source.read(path), rf"xi\.{lua_name}", label=path)
        enums[lua_name] = values
        refs.update({f"xi.{lua_name}.{key}": value for key, value in values.items()})
    zone_values = {
        match.group(1).upper(): int(match.group(2))
        for match in re.finditer(r"^\s+([a-z0-9_]+):\s+(\d+)\s*$", source.read("data/enums/zone.yaml"), re.M)
    }
    if not zone_values:
        raise SourceError("No zone enum entries found")
    refs.update({f"xi.zone.{key}": value for key, value in zone_values.items()})
    weather_values = {
        match.group(1).upper(): int(match.group(2))
        for match in re.finditer(r"^\s+([a-z_]+):\s+(\d+)\s*$", source.read("data/enums/weather.yaml"), re.M)
    }
    zone_names = {value: key for key, value in zone_values.items()}
    base = parse_table(source.read(DATA_PATH), r"xi\.helm\.dataTable", refs, DATA_PATH)
    removals = parse_table(source.read(ERA_PATH), r"local\s+removalsByContent", refs, ERA_PATH)
    if set(base) != set(enums["helmType"].values()):
        raise SourceError("HELM data and type enum disagree")

    zone_folders = {}
    for path in source.paths:
        match = re.match(r"scripts/zones/([^/]+)/IDs\.lua$", path)
        if match:
            zone_folders[normalize(match.group(1))] = match.group(1)
    yaml_folders = {}
    for path in source.paths:
        match = re.match(r"data/zones/([^/]+)/npcs\.yaml$", path)
        if match:
            yaml_folders[normalize(match.group(1))] = match.group(1)

    events = {}
    for path in source.trade_scripts():
        text = source.read(path)
        calls = re.findall(
            r"xi\.helm\.onTrade\s*\(\s*player\s*,\s*npc\s*,\s*trade\s*,\s*xi\.helmType\.(\w+)\s*,\s*(\d+)\s*[,)]", text
        )
        if len(calls) != len(re.findall(r"xi\.helm\.onTrade\s*\(", text)):
            raise SourceError(f"{path}: unsupported HELM trade/event dispatch")
        if len(calls) != 1:
            raise SourceError(f"{path}: expected one HELM event mapping")
        type_name, event = calls[0]
        events[(path.split("/")[2], Path(path).stem)] = (enums["helmType"][type_name], int(event))

    result = {"source": {"repository": "https://github.com/phoenixffxi/Phoenix", "commit": source.commit,
                         "ref": source.ref or "checkout", "profile": "Phoenix (pre-WotG)",
                         "data_path": DATA_PATH, "era_path": ERA_PATH},
              "types": {}}
    rock_names = ("RED_ROCK", "YELLOW_ROCK", "BLUE_ROCK", "GREEN_ROCK", "TRANSLUCENT_ROCK", "PURPLE_ROCK", "WHITE_ROCK", "BLACK_ROCK")
    result["rock_by_day"] = {day: enums["item"][name] for day, name in enumerate(rock_names)}

    for type_id, (key, label) in TYPE_INFO.items():
        info = base[type_id]
        target = {"key": key, "label": label, "tool": info["tool"], "zones": {}}
        result["types"][type_id] = target
        available = {zone_names[zone_id] for zone_id in info["zone"]}
        if not PHOENIX_ZONES[type_id].issubset(available):
            raise SourceError(f"Missing Phoenix {label} zones: {PHOENIX_ZONES[type_id] - available}")
        for zone_id, zone in sorted(info["zone"].items()):
            name = zone_names[zone_id]
            if name not in PHOENIX_ZONES[type_id]:
                if not (name.endswith("_S") or name.startswith("ABYSSEA_")):
                    raise SourceError(f"Unclassified HELM zone {name}: update the Phoenix profile explicitly")
                continue
            expected_fields = {"obtainRate", "breakRate", "minLevel", "drops", "points", "dailyCap", "depletion"}
            if set(zone) - expected_fields:
                raise SourceError(f"Unsupported pool fields in {name}: {set(zone) - expected_fields}")
            folder = zone_folders.get(normalize(name))
            yaml_folder = yaml_folders.get(normalize(name))
            if not folder or not yaml_folder:
                raise SourceError(f"Missing zone scripts or NPC data for {name}")
            row = {"name": folder.replace("_", " "), "obtain_rate": zone["obtainRate"],
                   "min_level": zone.get("minLevel", 0), "rows": [],
                   "daily_caps": zone.get("dailyCap", {}), "npcs": {}}
            if type_id == 1 and name == "PASHHOW_MARSHLANDS":
                row["note"] = "Quest gathering: Blazing Peppers"
            for drop in array(zone["drops"], name + " drops"):
                weight, item = array(drop, name + " drop")
                if not isinstance(weight, int) or weight <= 0 or not isinstance(item, int):
                    raise SourceError(f"Invalid drop in {name}: {drop}")
                row["rows"].append([item, weight])
            item_ids = {item for item, _ in row["rows"]}
            if len(item_ids) != len(row["rows"]) or not item_ids:
                raise SourceError(f"Empty pool or duplicate drops in {name}")
            if "depletion" in zone:
                depletion = zone["depletion"]
                row["depletion"] = {"max": depletion["max"], "pool": {
                    item: True for item in array(depletion["pool"], name + " depletion")}}
                if not set(row["depletion"]["pool"]).issubset(item_ids):
                    raise SourceError(f"Depletion references missing drops in {name}")
            if not set(row["daily_caps"]).issubset(item_ids):
                raise SourceError(f"Daily caps reference missing drops in {name}")
            removed_items = set()
            for era, types in removals.items():
                removed = types.get(type_id, {}).get(zone_id, {})
                if removed and era not in ("WOTG", "ABYSSEA"):
                    raise SourceError(f"Unsupported {era} era removal for {label}/{name}")
                for item in array(removed, name + " removals"):
                    if item not in item_ids:
                        raise SourceError(f"Era removal references missing drop {item} in {name}")
                    removed_items.add(item)
            row["rows"] = [drop for drop in row["rows"] if drop[0] not in removed_items]
            if not row["rows"]:
                raise SourceError(f"Era removals left an empty pool in {name}")

            zone_script = source.read(f"scripts/zones/{folder}/Zone.lua")
            weather_calls = re.findall(
                r"xi\.helm\.weatherChange\s*\(\s*weather\s*,\s*\{([^}]+)\}\s*,\s*ID\.npc\.(\w+)\s*\)", zone_script
            )
            if len(weather_calls) != len(re.findall(r"xi\.helm\.weatherChange\s*\(", zone_script)):
                raise SourceError(f"Unsupported HELM weather call in {name}")
            for weathers, weather_type in weather_calls:
                if weather_type == info["id"]:
                    tokens = re.findall(r"xi\.weather\.(\w+)", weathers)
                    if not tokens:
                        raise SourceError(f"Unsupported HELM weather requirement in {name}")
                    row["weathers"] = {weather_values[token]: True for token in tokens}

            npc_text = source.read(f"data/zones/{yaml_folder}/npcs.yaml")
            zone_scripts = {script: event for (zone_folder, script), (kind, event) in events.items()
                            if zone_folder == folder and kind == type_id}
            mapped_scripts = set()
            for match in re.finditer(r"^  (\d+):\s*\n(.*?)(?=^  \S|\Z)", npc_text, re.M | re.S):
                script_match = re.search(r"^    script:\s*([^\s#]+)\s*$", match.group(2), re.M)
                if script_match and script_match.group(1) in zone_scripts:
                    script = script_match.group(1)
                    row["npcs"][int(match.group(1))] = zone_scripts[script]
                    mapped_scripts.add(script)
            if not row["npcs"] or mapped_scripts != set(zone_scripts):
                raise SourceError(f"Incomplete NPC/event mapping for {label}/{name}: {zone_scripts}")
            target["zones"][zone_id] = row
    return result


def lua(value, indent=0):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=True)
    if isinstance(value, (float, int)):
        return str(value)
    if isinstance(value, list):
        if all(not isinstance(item, (dict, list)) for item in value):
            return "{ " + ", ".join(lua(item) for item in value) + " }"
        entries = [lua(item, indent + 4) for item in value]
    else:
        entries = []
        for key, item in value.items():
            formatted = key if isinstance(key, str) else f"[{key}]"
            entries.append(f"{formatted} = {lua(item, indent + 4)}")
    if not entries:
        return "{}"
    return "{\n" + "\n".join(" " * (indent + 4) + item + "," for item in entries) + "\n" + " " * indent + "}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("server", type=Path)
    parser.add_argument("--ref", help="Read committed Git objects without changing the server checkout")
    args = parser.parse_args()
    try:
        data = build(Source(args.server, args.ref))
        body = ("-- Generated by tools/gen_helmdata.py; edit the generator, not this file.\n"
                "-- Phoenix profile: pre-WotG zones and item pools, including Pashhow's quest gathering point.\n"
                "-- rows = { item ID, base weight }; npcs maps each target ID to its event ID.\n"
                + "return " + lua(data) + ";\n")
        args.output.write_text(body, encoding="utf-8", newline="\n")
    except (SourceError, OSError, KeyError) as error:
        parser.exit(1, f"gen_helmdata: {error}\n")
    count = sum(len(info["zones"]) for info in data["types"].values())
    print(f"Generated {count} HELM zone/type pools from {data['source']['commit']}")


if __name__ == "__main__":
    main()
