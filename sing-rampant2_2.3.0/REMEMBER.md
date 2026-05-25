# REMEMBER — sing-rampant2 Gotchas

Frequently messed up things specific to this mod. Read before touching anything.

---

## Coordinate Systems

**`chunk.x` / `chunk.y` in Rampant internals = TILE coordinates** (multiples of 32).
`surface.get_chunks()` iterator returns CHUNK INDEX coordinates — multiply by 32 to get tiles.

```lua
-- Rampant internal chunk: chunk.x is already tile position
zone at chunk.x / ZONE_TILE_SIZE   -- correct

-- surface.get_chunks() chunk: chunk.x is chunk index
tileX = chunk.x * CHUNK_SIZE       -- must convert
```

---

## Zone System (libs/ZoneManager.lua) — Optimized for Performance

### Caching & Dirty Flagging
- **Cache expiry**: Zones cached for 30 seconds (`zone.nextRescanTick`). Only rescan if dirty or cache expired.
- **Dirty flag**: `zone.isDirty = true` when player entity is built/destroyed in that zone (event-driven).
- **Immediate rescan**: Dirty zones are rescanned first, skipping stale zones.
- **Result**: Stable factories scan ~95% less, only dirty zones get frequent updates.

### Event-driven updates
- `on_built_entity`: Marks zone dirty when player force building is placed
- `on_entity_destroyed`: Marks zone dirty when player force building is destroyed
- Dirty zones reset `nextRescanTick = 0` for immediate rescan

### Dedicated scan tick
- Zone scanning moved from `pick == 0` (every 8 ticks) to `script.on_nth_tick(120)` (every 120 ticks)
- Reduces contention on the hot main AI loop
- Frees up 15 ticks/second of main-loop CPU for AI processing

## Zone System (libs/ZoneManager.lua)

- **Zone size**: 2 chunks = 64×64 tiles (`ZONE_CHUNK_SIZE = 2`)
- **Zones track PLAYER production**: assemblers, furnaces, drills, power-gen (solar/steam/nuclear/turbine)
- **Initial radius**: 2 = 5×5 grid = 25 zones covering ~320 tiles around player, expands dynamically
- **Scan phases**: 1=assemblers, 2=furnaces, 3=drills, 4=power-gen. Each zone cycles through all 4 phases.

---

## Debug Commands (libs/DebugCommands.lua + control.lua)

| Command | What it does |
|---|---|
| `/r2-zones` | Print zone stats (active count, phase distribution, top zones) |
| `/r2-zones-draw` | Draw zone grid on the MAP view (chart render mode) |
| `/r2-targets` | Print priority attack targets |
| `/r2-targets-draw` | Draw target circles on MAP view |
| `/r2-clear` | Clear all debug overlays |
| `/r2-structures` | Count assemblers/furnaces/drills on surface |
| `/r2-rescan` | Force immediate zone rescan (bypasses rate limit) |
| `/r2-scan-here` | Scan entities at player position, show zone state |

---

## Rendering API

- `rendering.draw_text` requires `target = {x=..., y=...}` — NOT `position`
- `render_mode = "chart"` to show on map view
- `rendering.get_all_objects(player)` — pass the player object directly, NOT `player.index` or `player.name`
- `game.write_file` does NOT exist — use `game.print()`

---

## universe.activeMap

Commands that need a map use `universe.activeMap`. This is set by the main tick loop and can be any map. If the player is on Nauvis and `universe.activeMap` is also Nauvis, fine. But don't assume — `r2-scan-here` now prints both surface names to catch mismatches.

---

## Performance

- `find_entities_filtered` on a 64×64 area is cheap but was previously running on 320×320 areas (10-chunk zones) every 8 ticks — that caused lag.
- `processZoneScan` is called at `tick % 8 == 0` (every 8 ticks). Rate-limited to 1 zone scan per 60 ticks normally.
- Don't scan all generated chunks at init — too many zones. Use player-position radius instead.
