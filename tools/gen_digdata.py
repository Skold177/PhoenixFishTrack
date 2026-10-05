# Regenerates phoenixtracker/digdata.lua from a Phoenix server checkout.
# Usage: python3 gen_digdata.py phoenixtracker/digdata.lua <path to Phoenix repo>
import re, os, sys
P = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser('~/Phoenix')
src = open(f'{P}/modules/phoenix/lua/globals/hobbies/chocobo_digging/pxi_digging_data.lua').read()
items = dict((m.group(1), int(m.group(2))) for m in re.finditer(r'^\s*([A-Z0-9_]+)\s*=\s*(\d+)', open(f'{P}/scripts/enum/item.lua').read(), re.M))
ranks = dict((m.group(1), int(m.group(2))) for m in re.finditer(r'^\s*([A-Z_]+)\s*=\s*(\d+)', open(f'{P}/scripts/enum/craft_rank.lua').read(), re.M))
zones = dict((m.group(1).upper(), int(m.group(2))) for m in re.finditer(r'^\s+([a-z0-9_]+):\s+(\d+)', open(f'{P}/data/enums/zone.yaml').read(), re.M))
weathers = dict((m.group(1).upper(), int(m.group(2))) for m in re.finditer(r'^\s+([a-z_]+):\s+(\d+)', open(f'{P}/data/enums/weather.yaml').read(), re.M))
days = {'FIRESDAY':0,'EARTHSDAY':1,'WATERSDAY':2,'WINDSDAY':3,'ICEDAY':4,'LIGHTNINGDAY':5,'LIGHTSDAY':6,'DARKSDAY':7}

def block(name):
    m = re.search(r'xi\.chocoboDig\.' + name + r'\s*=\s*(?:set)?\{(.*?)\n\}', src, re.S)
    return m.group(1)

def kv(name, keyenum, valenum):
    out = {}
    for m in re.finditer(r'\[\s*([\w.]+)\s*\]\s*=\s*([\w.]+)', block(name)):
        k, v = m.group(1), m.group(2)
        out[resolve(k, keyenum)] = resolve(v, valenum)
    return out

def resolve(tok, enum):
    if tok.isdigit(): return int(tok)
    t = tok.split('.')[-1]
    return enum[t]

xp_to_level = kv('xpToLevel', None, None)
xp_per_rank = kv('experiencePerItem', ranks, None)
accuracy = kv('accuracy', ranks, None)
ore_weight = kv('elementalOreWeight', ranks, None)
crystal_weight = kv('crystalWeight', ranks, None)
cluster_weight = kv('clusterWeight', ranks, None)
ore_by_day = kv('elementalOreByDay', days, items)
crystal_by_weather = kv('crystalByWeather', weathers, items)
cluster_by_weather = kv('clusterByWeather', weathers, items)
ore_zones = sorted(zones[t.split('.')[-1]] for t in re.findall(r'xi\.zone\.\w+', block('elementalOreZones')))
night_only = sorted(items[t.split('.')[-1]] for t in re.findall(r'xi\.item\.\w+', block('nightOnlyItems')))

zt = block('zoneTable')
zone_rows = {}
names = {}
for zm in re.finditer(r'\[xi\.zone\.(\w+)\]\s*=\s*\{(.*?)\n    \}', zt, re.S):
    zid = zones[zm.group(1)]
    rows = []
    for rm in re.finditer(r'\{\s*xi\.item\.(\w+),\s*xi\.craftRank\.(\w+),([\d,\s]+)\}', zm.group(2)):
        w = [int(x) for x in rm.group(3).split(',') if x.strip()]
        assert len(w) == 11, rm.group(0)
        rows.append((items[rm.group(1)], ranks[rm.group(2)], w, rm.group(1)))
    zone_rows[zid] = rows
    names[zid] = zm.group(1)

# Message IDs from each zone's IDs.lua
folders = {re.sub(r'[^a-z0-9]', '', d.lower()): d for d in os.listdir(f'{P}/scripts/zones')}
msgs = {}
for zid, zname in names.items():
    d = folders[re.sub(r'[^a-z0-9]', '', zname.lower())]
    t = open(f'{P}/scripts/zones/{d}/IDs.lua').read()
    def g(k):
        m = re.search(r'^\s*' + k + r'\s*=\s*(\d+)', t, re.M)
        return int(m.group(1))
    msgs[zid] = (d.replace('_', ' '), g('ITEM_OBTAINED'), g('DIG_THROW_AWAY'), g('FIND_NOTHING'), g('BEASTMEN_CACHE_OFFSET'))

def tbl(d, w=3):
    return '\n'.join(f'    [{k:>{w}}] = {v},' for k, v in sorted(d.items()))

o = []
o.append('-- Generated from the Phoenix server source (github.com/phoenixffxi/Phoenix):')
o.append('--   modules/phoenix/lua/globals/hobbies/chocobo_digging/pxi_digging_data.lua')
o.append('--   scripts/zones/*/IDs.lua (message IDs)')
o.append('-- Ranks are craft ranks 0-10 (Amateur to Expert). Item names come from the client at runtime.')
o.append('local d = {};\n')
o.append('-- Experience needed to reach each wing skill level.\nd.xp_to_level = {\n' + tbl(xp_to_level) + '\n};\n')
o.append('-- Experience for each item found, by the item\'s rank in the zone table.\nd.xp_per_rank = {\n' + tbl(xp_per_rank, 2) + '\n};\n')
o.append('-- Chance (%) that a dig finds anything, by your rank.\nd.accuracy = {\n' + tbl(accuracy, 2) + '\n};\n')
o.append('d.crystal_weight = {\n' + tbl(crystal_weight, 2) + '\n};\n')
o.append('d.cluster_weight = {\n' + tbl(cluster_weight, 2) + '\n};\n')
o.append('d.ore_weight = {\n' + tbl(ore_weight, 2) + '\n};\n')
o.append('-- Weather ID -> crystal / cluster item ID.\nd.crystal_by_weather = {\n' + tbl(crystal_by_weather, 2) + '\n};\n')
o.append('d.cluster_by_weather = {\n' + tbl(cluster_by_weather, 2) + '\n};\n')
o.append('-- Vana\'diel weekday (0 = Firesday) -> elemental ore item ID.\nd.ore_by_day = {\n' + tbl(ore_by_day, 1) + '\n};\n')
o.append('d.ore_zones = { ' + ' '.join(f'[{z}] = true,' for z in ore_zones) + ' };\n')
o.append('-- Seeds only turn up between 20:00 and 4:00 Vana\'diel time.\nd.night_only = { ' + ' '.join(f'[{i}] = true,' for i in night_only) + ' };\n')
o.append('-- Each zone: message IDs, then { item ID, item rank, weight at rank 0 .. rank 10 }.')
o.append('d.zones = {')
for zid in sorted(zone_rows):
    name, item, throw, nothing, cache = msgs[zid]
    o.append(f'    [{zid}] = {{')
    o.append(f'        name = {name!r}.replace("\'", \'"\'),' if False else f'        name = "{name}",')
    o.append(f'        msg  = {{ obtained = {item}, throw_away = {throw}, nothing = {nothing}, cache = {cache} }},')
    o.append('        rows = {')
    for iid, rk, w, nm in zone_rows[zid]:
        o.append(f'            {{ {iid:>5}, {rk:>2}, {", ".join(f"{x:>4}" for x in w)} }}, -- {nm}')
    o.append('        },')
    o.append('    },')
o.append('};\n\nreturn d;')
open(sys.argv[1], 'w').write('\n'.join(o) + '\n')
print(len(zone_rows), 'zones')
for z in sorted(msgs): print(z, msgs[z])
