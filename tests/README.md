Run the regression checks from the repository root:

```console
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -v
```

The tests execute the addon Lua modules with Lupa's LuaJIT 2.1 runtime. Synthetic
Ashita packets and configurable clock, character, animation, and inventory state
exercise the public module events. Ashita, ImGui, settings, and disk access are
stubbed; saved Lua data is parsed back and rendering captures displayed statistics.
No game client, server connection, or existing addon settings are required.

These checks cover the fishing and digging counts, carrying over old Fish Track
data, the gathering data, counting a find only once it reaches your inventory,
rare-item fatigue, zoning, midnight resets, keeping each character's counts
separate, and the six tabs and their commands. They do not replace an
in-game check of animation timing, packet ordering, or window appearance.
