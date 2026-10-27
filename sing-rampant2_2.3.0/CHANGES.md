# Changes — Rampant 2 (2.3.0 Development)

Developer notes for the current state of the strike, zone, and debug systems. This file is the working record; `changelog.txt` is for players.

---

## Strike system

### One strike function
- `strikeManager.strike(map, surface, universe)` in `libs/StrikeManager.lua` is the only strike function. It picks the zone, chooses nests, and deploys the squads.
- **Natural strikes** run from `on_nth_tick(120)` in `control.lua` through `strikeManager.processStrikes`. That function checks the map and zones, requires enemy evolution of at least 20% (`STRIKE_ENABLED_EVOLUTION`), and requires the cooldown to have expired, then calls `strike`.
- **`/r2-strike`** (`r2Strike` in `control.lua`) calls `strike` with no evolution or cooldown gate. It only checks that the map and strike state exist.
- `strike` sets the cooldown to `STRIKE_COOLDOWN_DURATION` (10 minutes) after a successful deployment, for both paths.

### Target selection (`strikeTargeting.selectStrikeTarget`, `libs/StrikeTargeting.lua`)
Shared by both paths. Each invocation:
1. Recovers `strikeAllow` on every zone except the one struck in the previous invocation (+1, capped at 3).
2. Builds the eligible zones per category:
   - **products, oil, raw-resources:** producing zones (`totalRate > 0`) at or above the 70th percentile of `totalRate`.
   - **power:** generating zones (`powerGen > 0`) at or above the 70th percentile of `powerGen`.
   - **outpost:** zones with `militaryBuildingCount` that beat more than 30% of the other outposts.
3. Picks a category at random, then a zone. Products are weighted by share squared times tier value; other categories are uniform.
4. If the zone's `strikeAllow` is 0, rerolls in the same category, then in a random category. If that is also 0, the strike fails.
- The picked zone is set to `strikeAllow = 0` and remembered as the last struck zone (`markStruck`).

### Deployment
- Nests are ordered by distance to the target in bands (`MIN_NEST_DISTANCE` 300, `MAX_NEST_DISTANCE` 400), filtered by direction and zone checks, and clustered.
- Each squad spawns `strikeBitersPerSquad` biters at a nest. Each biter gets the 5-second spawn speed sticker (`strikeSpeed-sticker-rampantFixed`, 1.5x).
- Each squad records `strikeObjective`, `strikeStart`, and `strikeSpawnTick`, and gets the `strike2` force-move flag (name kept because saved squads use it).
- The console prints `X/N squads deployed` where N is the setting, not a constant.

### Settings
- `rampantFixed--strikeSquadsPerStrike`: default 3, range 1–10 (runtime-global).
- `rampantFixed--strikeBitersPerSquad`: default 60, range 1–500 (runtime-global).
- `rampantFixed--debugStrikeTargeting`: prints the target, category, output, and percentile to chat.

### Strike retreat (`libs/StrikeRetreat.lua`)
- A strike unit hit by a player-side attacker, before 75% of its spawn-to-objective trip is covered, triggers once.
- The unit gets a `go_to_location` command 10 tiles directly away from the attacker for 5 seconds. Afterwards it is sent back to the objective.
- Its speed boost (`retreatSpeed-sticker-rampantFixed`, 1.5x, 5 seconds) starts once the spawn sticker ends, so the two never stack.
- Hooks: `onUnitDamaged` in `onEntityDamaged`, and `onTick` in the 30-tick handler. Both are tagged `STRIKE RETREAT`.
- The mod's damage filter excludes fire and acid hits, so those don't trigger a retreat.

### Removed
- `libs/Strike2Manager.lua`, `libs/Strike3Manager.lua`, and `libs/Strike4Manager.lua`.
- The deprecated strike1, strike2, and strike3 command handlers.
- `strikeTargeting.selectStrikeTargetInCategory` and `strikeTargeting.hasZonesInCategory`.

---

### Strike transit (`libs/SquadAttack.lua`, `attackMove`)
- While a strike squad has covered less than 75% of its spawn-to-objective distance, its move order uses `distraction = none`, so it keeps walking when shot.
- Once 75% is covered, normal distraction behaviour returns.
- The same covered-distance rule is used by the single-unit retreat, so both systems switch at the same point.
- Risk: if player buildings block the route before 75%, the squad may stall, since it won't attack them while in transit. Not yet tested in game.

## Zone system

### Outpost detection (`strikeTargeting.getZoneCategory`)
A zone is an **outpost** when:
1. `militaryBuildingCount` is at least 8, and
2. at least 6 of its 8 neighbours have category NONE, and
3. every neighbour exists and has been scanned.

- Only category NONE counts as empty. Missing or unscanned neighbours make the check incomplete, so they are never counted as empty.
- `zoneManager.scanZonePhase1` creates all eight neighbours of any zone with military buildings, so the check has no gaps to fall into.
- The outpost check runs before power and the product, oil, and raw checks, so an outpost overrides them.
- `strikeTargeting.dominatesAdjacentZones` exists but is not used by the outpost check.

### Scan
- `processZoneScan` (regular): incremental. One zone phase per tick, skipping zones whose cache is fresh.
- `superForceRescan` (`/r2-super-rescan`): resets and scans every zone in one call. It freezes the game.

---

## Debug tools

### Zone overlay (`r2-zones-draw`, `libs/DebugCommands.lua`)
Each zone shows five label lines:
1. Coordinates and scan phase.
2. Cache status.
3. Share of the map total, items/s, and MW if the zone has power.
4. `CAT:` the category, plus its output: `VAL` (products tier value), `OUT` (oil or raw rate), `MW` (power), or `MIL` (outpost military buildings).
5. `PCT:` the production percentile. Products, oil, and raw use item output among producing zones; power uses `powerGen` among power zones; outposts use military building count among outposts. `n/a` otherwise.

- Borders are 8 px for categorized zones and 4 px for NONE zones.
- Overlay lifetime is 2400 ticks.
- `r2-clear` calls `rendering.clear(script.mod_name)`. The API has no `rendering.destroy`.

### Commands
`r2-surfaces`, `r2-aistate`, `r2-mutate`, `r2-menu`, `r2-zones`, `r2-zones-draw`, `r2-targets`, `r2-targets-draw`, `r2-clear`, `r2-structures`, `r2-rescan`, `r2-super-rescan`, `r2-scan-here`, `r2-scan-power`, `r2-status`, `r2-strike`, `r2-pause-attacks`, `r2-resume-attacks`.

---

## Compatibility
- Zone and strike fields use nil defaults (for example `strikeAllow or 3`), so saves made before these changes load without migration.
- `squad.strike2` and the setting IDs are unchanged where renaming would affect saved data. The old `strike4` setting IDs were renamed, so their saved values reset to the new defaults.

---

## Not yet verified in game
Everything in this file was checked by reading the code and by grep. None of it has been run in Factorio yet.
