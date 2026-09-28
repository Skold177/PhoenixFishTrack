# Phoenix Fish Track

Phoenix Fish Track is a lightweight fishing addon for keeping track of your daily fishing results on Phoenix XI.

Phoenix limits each account to 200 catches a day. The addon counts your catches toward that limit, shows when the count resets, and keeps a running tally of what you've landed.

## Features

- **Daily count:** catches out of 200 with a progress bar, how many you have left, and a countdown to the reset.
- **Rod and bait:** what you have equipped, with the bait left in the stack and across your inventory and wardrobes.
- **On the line:** when something bites, lists what it could be and the odds of each, based on where you are standing, your rod, your bait and your fishing skill. It never reads the server's hidden fishing packets, so it only knows what you can see yourself.
- **Session stats:** casts, bites, catches, hit rate, catches per hour, time left to reach 200, your fishing skill and how much you've gained this session.
- **Today's catch:** everything you've landed today and how many of each.
- **Vibrate on hook:** optional controller rumble when something bites, with separate toggles for small fish, big fish, items and monsters, plus an optional buzz when nothing is caught.
- **Fish you want to catch:** choose which hook types (small fish, big fish, items, monsters) you want. Anything else shows as a red "Bad Catch - Not Wanted".

## Installing

Requires [Ashita v4](https://github.com/AshitaXI/Ashita-v4beta).

1. Click **Code → Download ZIP** on this page and extract it.
2. Copy the `phoenixfishtrack` folder into your Ashita `addons` folder, so you end up with `addons/phoenixfishtrack/phoenixfishtrack.lua`.
3. In game, type `/addon load phoenixfishtrack`.

To load it every time you play, add `/addon load phoenixfishtrack` to your Ashita startup script.

## Commands

| Command | What it does |
|---|---|
| `/pfish` | Show or hide the window |
| `/pfish show` / `/pfish hide` | Show or hide the window |
| `/pfish set <count>` | Correct today's catch count |
| `/pfish account <name>` | Share one count between characters on the same account |
| `/pfish account` | Count this character on its own again |
| `/pfish scale <0.5-3>` | Change the window size |
| `/pfish reset` | Clear the session stats |
| `/pfish pool` | List everything that can bite where you are standing |

`/phoenixfishtrack` works in place of `/pfish`. Right-click the window to lock it in place, reset the session or hide it.

## How catches are counted

- Every fish or item you land counts as one catch, including a multi-catch.
- Items with no sell value don't count. They still appear in today's list, marked "no point".
- Monsters, chests, and catches lost because your bags were full don't count.
- The count resets at midnight Japan time (JST). The window shows the reset in your local time.

The 200 limit is shared by every character on your account. The addon can't see which account a character belongs to, so it counts each character separately by default. To share one count, run `/pfish account <name>` with the same name on each character from that account.

If the count ever drifts, for example because you fished with the addon unloaded, fix it with `/pfish set <count>`.

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

The fish data comes from the [Phoenix server code](https://github.com/phoenixffxi/Phoenix). To update it after Phoenix changes its fishing, clone that repository and run:

```
powershell -ExecutionPolicy Bypass -File tools\build_fishdata.ps1 -Phoenix C:\path\to\Phoenix
```

This rewrites `fishdata.lua`. Reload the addon to use it.

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
