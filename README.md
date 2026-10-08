# Phoenix Tracker

Phoenix Tracker keeps track of fishing, chocobo digging, harvesting, logging, mining and excavation on Phoenix XI. It started as Skold's Phoenix Fish Track and now has a tab for each activity, using Phoenix's item pools and gathering rules.

Phoenix limits each account to 200 catches and 100 chocobo dig finds a day. The addon counts each one toward its limit, shows when the count resets, and keeps a running tally of your items. The four gathering tabs track their own finds and logging/mining rare-item fatigue; they do not use the chocobo digging allowance.

## Features

### Fishing

- **Daily count:** catches out of 200 with a progress bar, how many you have left, and a countdown to the reset.
- **Rod and bait:** what you have equipped, with the bait left in the stack and across your inventory and wardrobes.
- **On the line:** when something bites, lists what it could be and the odds of each, based on where you are standing, your rod, your bait and your fishing skill. It never reads the server's hidden fishing packets, so it only knows what you can see yourself.
- **Session stats:** casts, bites, catches, empty casts, cancellations, hit rate, catches per hour, time left to reach 200, your fishing skill and how much you've gained this session.
- **Today's catch:** everything you've landed today and how many of each.
- **Vibrate on hook:** optional controller rumble when something bites, with separate toggles for small fish, big fish, items and monsters, plus an optional buzz when nothing is caught.
- **Fish you want to catch:** choose which hook types (small fish, big fish, items, monsters) you want. Anything else shows as a red "Bad Catch - Not Wanted".

### Digging

- **Daily count:** finds out of 100 with a progress bar, how many you have left, and a countdown to the reset.
- **Zone and greens:** whether you can dig where you are, the current weather, how many Gysahl Greens are in your inventory, and a countdown to your next dig.
- **Session stats:** greens used, greens still needed to reach 100, digs that found nothing, hit rate, finds per hour, time left to reach 100, the hit rate to expect at your rank, and digs wasted by digging too close to your last spot.
- **Wing skill:** your level and rank, experience gained this session, a bar toward your next level, and roughly how many finds and digs it will take to get there.
- **Possible finds:** everything that can be dug up where you are, with the odds and experience of each at your rank.
- **Today's dig:** everything you've dug up today and how many of each, plus anything thrown away because your bags were full.

### Harvesting, Logging, Mining and Excavation

- **Zone and tools:** the current gathering area, sickles, hatchets or pickaxes in your inventory, and any main job level requirement.
- **Session stats:** attempts, confirmed finds, nothing found, broken tools, full bags, hit rate, finds per hour and the expected chance to find something.
- **Possible finds:** Phoenix's current item pools, with conditional item odds. Logging and Mining compare fresh odds with the odds after your tracked rare-item fatigue.
- **Rare-item fatigue:** logging pools in Lufaise Meadows, Misareaux Coast and Ghelsba Outpost; mining pools in Halvung, Gusgen Mines and Ifrit's Cauldron; and Mount Zhayolm's separate Adaman and Khroma caps. Unknown prior progress stays visibly unknown.
- **Today's items:** confirmed finds and quantities, saved separately for each character and activity.

### Window

- **Tabs:** Fishing and Digging are on the first row; Harvesting, Logging, Mining and Excavation are on the second. By default the window switches to the activity you are doing.
- **Settings:** the cog at the top right opens scale and opacity sliders, Lock, Reset Position, Reset Session and the automatic tab switch. All six tabs share the same window, colours and settings.

## Installing

Requires [Ashita v4](https://github.com/AshitaXI/Ashita-v4beta).

1. Click **Code → Download ZIP** on this page and extract it.
2. Copy the `phoenixtracker` folder into your Ashita `addons` folder, so you end up with `addons/phoenixtracker/phoenixtracker.lua`.
3. In game, type `/addon load phoenixtracker`.

To load it every time you play, add `/addon load phoenixtracker` to your Ashita startup script.

If you used Phoenix Fish Track before, unload it with `/addon unload phoenixfishtrack`, take it out of your startup script and delete its folder. Today's catch count carries over, including the shared account name configured with `/pfish account`. Keep the old files in `config/addons/phoenixfishtrack` until the count has carried over.

## Commands

`/ptrack` works on whichever tab is open. `/pfish`, `/pdig`, `/pharvest`, `/plog`, `/pmine` and `/pexcavate` always work on their own activity.

| Command | What it does |
|---|---|
| `/ptrack` | Show or hide the window |
| `/ptrack fish` / `dig` / `harvest` / `log` / `mine` / `excavate` | Open that tab; full activity names also work |
| `/pfish` / `/pdig` / `/pharvest` / `/plog` / `/pmine` / `/pexcavate` | Open that tab, or hide the window if it's already showing it |
| `/ptrack show` / `/ptrack hide` | Show or hide the window |
| `/ptrack scale <0.5-3>` | Change the window size |
| `/ptrack auto` | Turn automatic tab switching on or off |
| `/pfish set <count>` / `/pdig set <count>` | Correct today's count |
| `/pfish account <name>` / `/pdig account <name>` | Share one count between characters on the same account |
| `/pfish account` / `/pdig account` | Count this character on its own again |
| `/pfish reset` / `/pdig reset` | Clear that tab's session stats |
| `/pfish pool` | List what can bite where you are standing |
| `/pdig pool` | List what can be dug up here |
| `/pdig skill <level>` | Set your wing skill level |
| `/pdig xp reset` | Forget the wing skill experience estimate |
| `/pharvest pool` / `/plog pool` / `/pmine pool` / `/pexcavate pool` | List possible finds and current odds here |
| `/pharvest reset` / `/plog reset` / `/pmine reset` / `/pexcavate reset` | Clear that activity's session stats, keeping daily totals and fatigue |
| `/plog fatigue <count>` / `/pmine fatigue <count>` | Set a known rare-pool count for this activity and zone |
| `/pmine cap <item-id> <count>` | Set a known capped-item count in Mount Zhayolm: Adaman `646`, Khroma `685` |

`/phoenixtracker` works in place of `/ptrack`. Click the cog at the top right of the window to open its settings: scale and opacity sliders, Lock, Reset Position (moves both windows back to their starting spots), Reset Session (for the open tab) and the automatic tab switch. It works with a left click, so it's usable on a controller or Steam Deck. The same options, plus Hide, are also in the right-click menu.

## How catches are counted

- Every fish or item you land counts as one catch, including a multi-catch.
- Items with no sell value don't count. They still appear in today's list, marked "no point".
- Monsters, chests, and catches lost because your bags were full don't count.
- The count resets at midnight Japan time (JST). The window shows the reset in your local time.

The 200 limit is shared by every character on your account. The addon can't see which account a character belongs to, so it counts each character separately by default. To share one count, run `/pfish account <name>` with the same name on each character from that account.

If the count ever drifts, for example because you fished with the addon unloaded, fix it with `/pfish set <count>`.

Session **Casts** includes empty casts and cancellations. **Nothing** counts casts where nothing bites; **Cancelled** includes giving up with a lure and casts interrupted before a result. These do not use the daily catch allowance. A cast that ends without a result message may take a moment to appear as cancelled.

## What's on the line

When the hook message appears (small fish, large fish, item or monster), a small "On the Line" popup lists everything that could be on the line. When the feeling message follows, a bar shows whether to reel it in.

Phoenix decides whether your rod breaks or your line snaps the moment the fish bites, and picks the feeling message to match. A rod that will break always gets a Terrible Feeling, and a line that will snap always gets a Bad Feeling. So the bar follows the feeling:

| Feeling | Warn on Rod Breaks | Warn on Rod + Line Breaks |
|---|---|---|
| Good Feeling, Keen Angler's Sense, any "not enough skill" message | Good Catch - No Break | Good Catch - No Break |
| Bad Feeling | Good Catch - No Break | Bad Catch - Could Snap |
| Terrible Feeling | Bad Catch - Could Break | Bad Catch - Could Break |
| Epic-catch message | Epic Catch - Unknown | Epic Catch - Unknown |

The epic-catch message shows on a near-record large fish in place of the feeling, even a Terrible one, so it can't tell you whether your rod is safe. If the hook type is switched off under "On Hook Display" in the main window, the bar shows **Bad Catch - Not Wanted** straight away.

"Warn on" under "On Hook Display" chooses how careful the bar is. Pick one: **Rod Breaks** (the default) only warns when your rod could break. **Rod + Line Breaks** also warns when your line could snap, which loses the catch and your bait but not the rod.

The popup closes when the catch is landed or lost, when you give up, or when fishing is interrupted, and you can drag it wherever you like. It works this out the same way the Phoenix server picks a catch, using only what you can see yourself: your zone and position, your rod and bait, your body armour, your fishing skill, the moon phase, and the hook message. It never reads the hidden fishing packets the server sends, so it can't tell you exactly which fish is on the line.

Each row shows the name, the skill the catch needs and its odds. Legendary fish are shown in gold.

- **Fish** are the ones in your fishing spot that bite your bait and match the size in the hook message. Fish more than 100 skill above yours never bite, so they aren't listed, and neither are fish that need a key item you don't have. The odds follow the server's hook chance, which depends on how much the fish likes your bait, your skill, your rod size and the fish's rarity. With Lu Shang's or Ebisu, fish well below your skill are a little more likely. Rain and squalls make fish more likely too, which the addon can't see, so with those two rods the odds can be slightly off in bad weather.
- **Items** are the ones that can be pulled up in your spot. Items only available during a quest are marked "quest".
- **Monsters** have no odds, because they depend on which ones are already spawned. Notorious monsters are marked "NM", or "quest" if they are only there for a quest. A notorious monster that needs a particular bait is only listed when you're using that bait.

If you are standing outside any fishing spot the server knows about, the popup says "Area unknown" and lists everything for the whole zone. Use `/pfish pool` to check which spot you are in before you cast.

The fish data comes from the [Phoenix server code](https://github.com/phoenixffxi/Phoenix). When Phoenix changes its fishing, the data is updated in a new release.

`fishdata.lua` keeps one table for each of the server's fishing tables, sorted by ID with the columns lined up:

| Table | What it holds |
|---|---|
| `fish` | Every fish and item that can be caught: name, skill, size, rarity, and whether it is an item, shellfish, legendary, needs a key item or is for a quest |
| `groups` | The fish and items in each catch group |
| `catch` | The catch group for each fishing spot in a zone |
| `areas` | Each zone's fishing spots, with their centre, radius, height and outline |
| `zones` | City zones and zones with extra difficulty |
| `affinity` | How much each fish likes each bait, from 1 to 3 |
| `baits` | Each bait's name, type and flags |
| `rods` | Each rod's name, size, and whether it is legendary |
| `mobs` | The monsters that can be fished up in each zone |

## Controller rumble

Rumble works with a DualSense connected by USB cable, and with Xbox-style (XInput) controllers. A DualSense connected by Bluetooth isn't supported. If no supported controller is found, the window says so.

## How finds are counted

- Every item you dig up counts as one find.
- An item thrown away because your bags were full still counts. It shows in today's list as "Thrown away".
- Digs that find nothing don't count, but they still use a bunch of Gysahl Greens.
- Once you reach 100, every dig finds nothing until the reset, and still uses greens. The Session section shows how many greens you spent after the limit.
- The count resets at midnight Japan time (JST). The window shows the reset in your local time.

The 100 limit is shared by every character on your account. The addon can't see which account a character belongs to, so it counts each character separately by default. To share one count, run `/pdig account <name>` with the same name on each character from that account.

A dig counts toward the day it started, even if its result arrives after midnight. Its item and experience still count in the session.

If the count ever drifts, for example because you dug with the addon unloaded, fix it with `/pdig set <count>`.

## What you can dig up

Phoenix rolls each dig in two steps. First it decides whether you find anything at all, then it picks the item.

Whether you find anything depends only on your rank. The moon doesn't change it. Session shows this as **Expected**, next to your real hit rate:

| Rank | Wing skill | Chance to find something |
|---|---|---|
| Amateur | 0-9 | 30% |
| Recruit | 10-19 | 34% |
| Initiate | 20-29 | 38% |
| Novice | 30-39 | 42% |
| Apprentice | 40-49 | 46% |
| Journeyman | 50-59 | 50% |
| Craftsman to Expert | 60-100 | 51% to 55% |

Two things always find nothing, whatever your rank:

- Digging within 4 yalms of your last dig. Move before you dig again. These show in Session as **Too close**.
- Digging after you've reached 100 for the day.

When you do find something, the item is picked from your zone's table. Each item has a weight for each rank, so common items get a little less likely as you rank up and rare ones a lot more likely. **Possible Finds** turns those weights into odds for where you are standing:

- **Seeds** only turn up at night, from 20:00 to 4:00 Vana'diel time.
- **Crystals and clusters** come from the weather. A single weather adds its crystal, and a double weather adds its cluster.
- **Elemental ores** need Journeyman rank, elemental weather and a waxing crescent moon, in the zones that have them. The addon doesn't track the moon, so they aren't listed, but a note says when your zone and rank can have them.

The odds follow your rank, not your exact level, so they only change every 10 levels. They are the odds of each item once a dig finds something, not per dig. For the chance per dig, multiply by the Expected rate.

You also have to wait before you can dig again. After zoning it's 60 seconds at Amateur, 5 seconds less for each rank down to 10. Between digs it's 15 seconds at Amateur, 10 at Recruit, 5 at Initiate and 3 from Novice up. The window counts this down next to your greens.

The dig data comes from the [Phoenix server code](https://github.com/phoenixffxi/Phoenix), which replaces the standard digging rules with its own in `modules/phoenix/lua/globals/hobbies/chocobo_digging/`. When Phoenix changes its digging, the data is updated in a new release. `digdata.lua` is built from the server source by `tools/gen_digdata.py`:

| Table | What it holds |
|---|---|
| `xp_to_level` | The experience each wing skill level needs |
| `xp_per_rank` | The experience a find gives, by the item's rank |
| `accuracy` | The chance to find something at each rank |
| `crystal_weight`, `cluster_weight`, `ore_weight` | How likely crystals, clusters and elemental ores are at each rank |
| `crystal_by_weather`, `cluster_by_weather`, `ore_by_day` | Which crystal, cluster or ore each weather or day gives |
| `ore_zones` | The zones where elemental ores can be dug up |
| `night_only` | The seeds that only turn up at night |
| `zones` | Each zone's name, its dig message IDs, and its items with their rank and weight at each rank |

## Wing skill

Wing skill is hidden on Phoenix. The server blanks it in the skill list it sends the game, so the addon can't read it from your character the way it reads fishing skill. It learns your level three ways:

- **Talk to a chocobo stable clerk.** Arvilauge in Southern San d'Oria, Gonija in Bastok Mines or Kiria-Romaria in Windurst Woods. The server sends your exact wing skill with that conversation, and the addon picks it up.
- **Level up.** The "Your wing skill improved" message sets it, even if the level the addon had was wrong.
- **Type it** with `/pdig skill <level>`.

The level is saved for each character, so you only need to do this once. Until it's known, the Wing Skill section says so in red and Possible Finds shows Amateur odds.

Phoenix doesn't use tenths of a skill point for digging. Wing skill goes up one whole level at a time, from experience you can't see. Every find gives experience for that item's rank in the zone's table, from 30 for common items to 100 for the rarest, and each level needs a set amount, from 155 for level 1 up to 52,200 for level 100. Possible Finds shows the experience for each item.

The addon knows how much experience each find gives, but not how much you had when you set your skill. So the experience bar starts out as a rough range and gets more accurate the more you dig:

- When you first set your skill, the bar could be anywhere in the level. The solid part is the least you could have and the faint part is how much more you might have. Each find moves the solid part up, so the range narrows as you dig.
- When you level up, the addon learns where you are. The range shrinks to less than the find that levelled you, so from then on the bar is right to within a single find.

So don't worry if the bar looks vague at first. Keep digging and it sharpens up on its own, and after your first level-up it stays accurate.

The estimate is saved for each character and carries over between sessions. If your level changes without the addon seeing it, the estimate starts over. `/pdig xp reset` starts it over by hand.

The addon only reads what the server sends to you: the dig animation, the dig messages for your zone, the wing skill message, the stable clerk conversation and the weather. "Obtained" messages only count when they arrive just after one of your digs, so items from NPCs or trades aren't counted.

## Phoenix gathering rules

The gathering data covers Phoenix's six regular harvesting areas and the special Blazing Peppers point in Pashhow Marshlands, eleven logging areas, nine mining areas and four excavation areas. It applies Phoenix's era removals automatically, including ginger, dyer's woad and plumbago where excluded, plus Butterpear, Aquilaria and Kapor from jungle logging. Colored rocks follow the current Vana'diel day. Yuhtunga and Yhoator harvesting points require rain or squalls; logging there does not.

An attempt counts when the server sends the result from a matching gathering point. Finds count after the item is confirmed in your inventory. A broken tool can accompany a find or a failed attempt, so **Broken** is an additional statistic. Full bags prevent an award and do not consume rare-item allowances. If an award cannot be confirmed, it is shown as **unconfirmed**, and any affected rare-item count becomes unknown.

Today's observed totals reset at JST midnight. Rare-item fatigue follows different rules:

| Activity and area | Rare items | How the odds change | Reset |
|---|---|---|---|
| Logging: Lufaise Meadows | Elm, Oak | Shared pool of 20; each find reduces both weights | Zone out |
| Logging: Misareaux Coast | Elm, Oak | Shared pool of 20; each find reduces both weights | Zone out |
| Logging: Ghelsba Outpost | Elm | Pool of 20; each find reduces its weight | Zone out |
| Mining: Halvung | Luminium, Orichalcum | Shared pool of 5; each find reduces both weights | Zone out |
| Mining: Gusgen Mines | Darksteel, Gold | Shared pool of 32; each find reduces both weights | Zone out |
| Mining: Ifrit's Cauldron | Darksteel, Adaman, Orichalcum | Shared pool of 20; each find reduces all three weights | Zone out |
| Mining: Mount Zhayolm | Adaman (10), Khroma (2) | Each item's weight is divided by its own count plus one; zero at its cap | Enter the zone after the next JST midnight |

Shared-pool weights use Phoenix's rounding, and all item odds are recalculated after a rare find. Waiting in the same zone does not restore rare items. Logging out does not reset shared pools. Harvesting, excavation and the remaining logging/mining areas have no equivalent rare-item depletion in Phoenix's source.

The addon cannot read hidden server counters. If loaded midway through a visit, it shows fresh odds as a reference and leaves current fatigue odds unknown until it observes the relevant reset or you enter a known count. Counts are saved per character, but reloading conservatively marks their certainty unknown because gathering or zoning may have happened while tracking was unloaded. Reset Session never resets server fatigue.

The displayed item odds are conditional on finding something. **Expected** is the area's chance to find an item per attempt, including its main job level gate. Repeatedly using a relocated point can increase tool breakage on Phoenix; gear also affects breakage. These hidden point conditions are not presented as an exact break forecast or mixed into rare-item odds.

`helmdata.lua` is generated from the [Phoenix server code](https://github.com/phoenixffxi/Phoenix), including its HELM tables, era overrides, NPC scripts and NPC IDs. Its header records the source commit. To regenerate from a local checkout or a pinned Git ref:

```console
python tools/gen_helmdata.py phoenixtracker/helmdata.lua PATH_TO_PHOENIX
python tools/gen_helmdata.py phoenixtracker/helmdata.lua PATH_TO_REPO --ref phoenix/beta
```

## Files

| File | What it holds |
|---|---|
| `phoenixtracker.lua` | The window, header, tabs, settings panel and commands |
| `ui.lua` | The colours and drawing helpers every tab shares |
| `fishing.lua` | The Fishing tab |
| `fishdata.lua`, `catchpool.lua`, `offsets.lua`, `rumble.lua` | Fishing data and helpers |
| `digging.lua` | The Digging tab |
| `digdata.lua` | Digging data, built by `tools/gen_digdata.py` |
| `harvesting.lua`, `logging.lua`, `mining.lua`, `excavation.lua` | Gathering tab definitions |
| `helm.lua`, `helm_model.lua` | Shared gathering display, result tracking and Phoenix fatigue logic |
| `helmdata.lua` | Phoenix gathering pools and event identities, built by `tools/gen_helmdata.py` |

Today's counts are saved in Ashita's `config/addons/phoenixtracker` folder, in `fish_daily.lua`, `dig_daily.lua` and `helm_daily.lua`. Gathering fatigue observations are in `helm_state.lua`; the wing skill estimate is in `wing.lua`.

### Adding a tab

Each tab is a module that returns a table with `key`, `label`, `defaults` and the functions `init`, `ready`, `day`, `account`, `fit_width`, `draw`, `render_popups`, `reset_session`, `reset_positions`, `reload`, `help`, `command`, `packet_in`, `present` and `unload`. Register it in `TABS`, `TAB_ROWS` and the command maps in `phoenixtracker.lua`. Use `COLOR` and the helpers in `ui.lua` so it matches the rest of the window.
