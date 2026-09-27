# Phoenix Fish Track

Phoenix Fish Track is a lightweight fishing addon for keeping track of your daily fishing results on Phoenix XI.

Phoenix limits each account to 200 catches a day. The addon counts your catches toward that limit, shows when the count resets, and keeps a running tally of what you've landed.

## Features

- **Daily count:** catches out of 200 with a progress bar, how many you have left, and a countdown to the reset.
- **Rod and bait:** what you have equipped, with the bait left in the stack and across your inventory and wardrobes.
- **Session stats:** casts, bites, catches, hit rate, catches per hour, time left to reach 200, your fishing skill and how much you've gained this session.
- **Today's catch:** everything you've landed today and how many of each.
- **Vibrate on hook:** optional controller rumble when something bites, with separate toggles for small fish, big fish, items and monsters.

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

`/phoenixfishtrack` works in place of `/pfish`. Right-click the window to lock it in place, reset the session or hide it.

## How catches are counted

- Every fish or item you land counts as one catch, including a multi-catch.
- Items with no sell value don't count. They still appear in today's list, marked "no point".
- Monsters, chests, and catches lost because your bags were full don't count.
- The count resets at midnight Japan time (JST). The window shows the reset in your local time.

The 200 limit is shared by every character on your account. The addon can't see which account a character belongs to, so it counts each character separately by default. To share one count, run `/pfish account <name>` with the same name on each character from that account.

If the count ever drifts, for example because you fished with the addon unloaded, fix it with `/pfish set <count>`.

## Controller rumble

Rumble works with a DualSense connected by USB cable, and with Xbox-style (XInput) controllers. A DualSense connected by Bluetooth isn't supported. If no supported controller is found, the window says so.
