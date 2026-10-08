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

These checks cover accounting and migration behavior. They do not replace an
in-game check of animation timing, packet ordering, or window appearance.
