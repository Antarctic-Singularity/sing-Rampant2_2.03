# Rampant Overhaul Plan
### Zone Intelligence + Modular AI Architecture
**Status:** 🟡 Planning — Phase 0 Complete  
**Last Updated:** Session 3  
**Factorio Version Target:** 1.1 (Rampant 3.3.4 base)

---
First GOAL: ABSTRACT RAMPANT
## 🗺️ The Three Goals

1. **Zone Scanning** — slice the map into large squares, scan each for production entities, calculate output rate per item per zone
2. **Target Ranking** — periodically compare all zones against each other and global production totals; identify and store "Priority Targets" — the zones with the highest *relative* production density
3. **Target Triggering** — when a base crosses a points/aggressiveness threshold, spawn a special squad that navigates toward a Priority Target zone instead of following vanilla pheromones

These are three separate subsystems that feed into each other in one direction:
```
Zone Scan → Target Ranking → Priority Targets → Trigger Check → Special Squad
```

---

## 📚 Deep Research: Rampant's Attack Triggering Pipeline

This is the exact chain from "base is angry" to "squad is moving":

### Step 1: Nest becomes Active
A nest chunk is moved from `chunkToNests` → `chunkToActiveNest` inside `processNestActiveness()`. This happens when:
- The chunk has `PLAYER_PHEROMONE > attackPlayerThreshold` (player is nearby), OR
- The chunk has `BASE_PHEROMONE > 0` AND has pollution reaching it

### Step 2: processAttackWaves() selects from active nests
Every tick (pick 2), `processSpawnersBody()` walks `chunkToActiveNest` one chunk at a time (iterator pattern). For each active nest chunk it calls `formSquads(chunk)`.

### Step 3: formSquads → deploySquad does gate checks
```lua
deploySquad("Squad", chunk, AI_SQUAD_COST=175, false, true)
```
Gates (ALL must pass):
- `base.unitPoints >= 175` (has enough economy points)
- `chunk[BASE_PHEROMONE] > 0.0001` OR `chunk[PLAYER_PHEROMONE] > 0.0001` (chunk has signal)
- `Universe.squadCount < AI_MAX_SQUAD_COUNT` (global squad cap not hit)
- `attackWaveValidCandidate(chunk)` (nest is in right state for current AI mode)
- `Universe.random() <= Universe.formSquadThreshold` (probability gate, scales with evolution)

### Step 4: Squad is created and dispatched
`Squad.createSquad()` makes the squad object, `surface.set_multi_command()` gathers nearby units. Squad status starts as `GUARDING`, immediately becomes `RAIDING` in the first `squadDispatch` call.

### Step 5: Squad navigates via gradient descent
Every command timeout (COMMAND_TIMEOUT ticks), `cleanSquads` calls `squadDispatch` → `attackMove` → `scoreNeighbors` → moves to highest scoring chunk neighbor.

---

## 📚 Deep Research: The Economy and Thresholds

**`base.unitPoints`** — primary currency. Accumulates each `processBase` tick:
```
points += AI_POINT_GENERATOR_AMOUNT(15) × random()
       + activeNests × 0.144
       + AI_POINT_GENERATOR_AMOUNT × max(evolutionLevel^2.5, 0.1)
```
Additional bonuses if temperament is extreme (0 or 1: +24/tick; near extreme: +14.4; etc.)
Onslaught state doubles all point generation.
Cap: `max(AI_MAX_POINTS(15500) × evolutionLevel, MINIMUM_AI_POINTS(400)) × 3` for overflow.

**`Universe.formSquadThreshold`** — probability that a squad actually deploys when called:
```
formSquadThreshold = max(0.35 × evolutionLevel, 0.1)
```
At evo 0.0: 10% chance. At evo 1.0: 35% chance. This is a soft global throttle.

**`base.temperament`** — float 0.0–1.0, derived from `temperamentScore` (-10000 to +10000):
```
temperament = (temperamentScore + 10000) / 20000
```
High temperament (>0.8) → Onslaught/Siege states
Mid temperament (0.4–0.6) → Aggressive/Raiding
Low temperament (<0.2) → Migrating/Siege (expand rather than attack)

**`base.stateAI`** — set once per `BASE_AI_MIN_STATE_DURATION(10)` to `BASE_AI_MAX_STATE_DURATION(25)` minutes (randomized). The state controls whether `canAttack()` and `canMigrate()` return true.

**Key insight for our trigger system:** The clearest "aggressiveness" signal is a combination of `base.unitPoints` (has resources saved up) + `base.temperament` (is angry) + `base.stateAI` (is in attack mode). All three together = maximum threat moment.

---

## 🏗️ System Architecture

### New Systems Overview

```
┌──────────────────────────────────────────────────────────────┐
│  ZONE SCANNER (ZoneManager.lua)                              │
│  Runs very infrequently (every ~18,000 ticks = 5 min)        │
│  • Scans assemblers, furnaces, drills per zone               │
│  • Computes items/sec per zone                               │
│  • Stores: zone.products, zone.totalRate                     │
└───────────────────────┬──────────────────────────────────────┘
                        │ feeds into
┌───────────────────────▼──────────────────────────────────────┐
│  TARGET RANKER (TargetRanker.lua)                            │
│  Runs even less frequently (every ~36,000 ticks = 10 min)    │
│  OR triggered after zone scan completes                      │
│  • Sums all zone rates → globalTotalRate                     │
│  • Computes each zone's share: zone.rate / globalTotalRate   │
│  • Ranks zones by relative density                           │
│  • Writes top N zones to Universe.priorityTargets            │
└───────────────────────┬──────────────────────────────────────┘
                        │ read by
┌───────────────────────▼──────────────────────────────────────┐
│  TRIGGER CHECKER (part of BaseUtils or new TargetTrigger.lua)│
│  Runs per base, per base AI tick (already one per tick)      │
│  • Checks: unitPoints > THRESHOLD_POINTS                     │
│    AND temperament > THRESHOLD_TEMPERAMENT                   │
│    AND stateAI is an attack state                            │
│    AND priorityTargets is not empty                          │
│  • If all pass: spawn a TargetedSquad toward best target     │
└───────────────────────┬──────────────────────────────────────┘
                        │ spawns
┌───────────────────────▼──────────────────────────────────────┐
│  TARGETED SQUAD (new behavior in BehaviorRegistry)           │
│  • Like a normal raid squad BUT score function is different  │
│  • Instead of following PLAYER_PHEROMONE gradient...         │
│  • Moves toward a stored target position (a zone center)     │
│  • On arrival: switches to normal attack behavior            │
└──────────────────────────────────────────────────────────────┘
```

---

## 📐 Zone Scanner — Detailed Design

### Zone Size Decision
- Default: **10×10 chunks = 320×320 tiles**
- Rationale: big enough to contain a meaningful factory district, small enough that a 5000×5000 map has ~240 zones — manageable
- Configurable via mod setting (5/10/15 chunks)

### What Gets Scanned Per Zone
```
Phase 1 — Assembling machines:
  surface.find_entities_filtered({area=zoneBounds, type="assembling-machine", force="player"})
  For each: get_recipe() → products[i].name, products[i].amount, recipe.energy
  rate = (product.amount × entity.crafting_speed × (1 + entity.productivity_bonus)) / recipe.energy
  Add to zone.products[itemName]

Phase 2 — Furnaces:
  Same as Phase 1 but type="furnace"
  (furnaces have recipes too — iron-plate, steel-plate, etc.)

Phase 3 — Mining drills:
  surface.find_entities_filtered({area=zoneBounds, type="mining-drill", force="player"})
  For each: entity.mining_target → if valid, use mining_target.name as "item"
  rate = entity.prototype.mining_speed / (resource_prototype.mineable_properties.mining_time)
  Add to zone.products[resourceName]

Compile:
  zone.totalRate = sum of all zone.products values
  zone.lastScanned = current tick
```

### Scanning Schedule
- Zones are scanned **one phase per tick pass** of the zone scan iterator
- A zone with 3 phases takes 3 tick slots to fully scan
- The zone scan iterator processes **1 zone per slot** (same pattern as base/nest/squad iterators)
- Full map rescan interval: configurable, default **18,000 ticks (~5 minutes)**
- Only zones with `playerPheromoneTotal > 0` are scanned (skip empty wilderness)

### Zone Data Structure
```lua
zone = {
    zx, zy,               -- zone grid index
    tileX, tileY,         -- top-left tile coordinate
    -- production data
    products = {},         -- {itemName: itemsPerSecond}
    totalRate = 0,         -- sum of all product rates
    relativeShare = 0,     -- this zone's fraction of global production (set by ranker)
    densityRank = 0,       -- rank 1 = highest density (set by ranker)
    -- scan state
    lastScanned = 0,       -- tick
    scanPhase = 0,         -- 0=idle, 1=assemblers, 2=furnaces, 3=drills
    -- dirty check (avoid scanning empty zones)
    playerPheromoneTotal = 0,  -- updated cheaply each pheromone diffusion pass
}
```

---

## 🎯 Target Ranker — Detailed Design

### What It Computes

After all zones have been scanned (or on a fixed interval), TargetRanker runs **one full pass** over all zones:

```
Step 1: Sum global production
  globalTotalRate = sum of zone.totalRate for all zones

Step 2: Compute relative shares
  for each zone:
    zone.relativeShare = zone.totalRate / globalTotalRate

Step 3: Sort zones by relativeShare descending

Step 4: Take top N zones → Universe.priorityTargets
  (N = configurable, default 3)

Step 5: For each priority target, store:
  target = {
      zone = zoneRef,
      centerX = zone.tileX + (ZONE_TILE_SIZE / 2),
      centerY = zone.tileY + (ZONE_TILE_SIZE / 2),
      relativeShare = zone.relativeShare,
      topItem = zone products sorted by rate [1].name,
      createdTick = currentTick,
  }
```

### Why Relative Share, Not Absolute Rate

**Absolute rate problem:** Early game, a zone with 10 iron furnaces might score 50/s. Late game, that's nothing — a single green circuit zone might hit 200/s. Absolute rates drift massively over the game. You'd need manual rebalancing.

**Relative share solution:** If a zone produces 40% of all global output, that's a high-value target regardless of whether it's tick 1000 or tick 1,000,000. The scale is always 0.0–1.0. A zone that makes up >10% of global production is a major target. This is self-calibrating.

### Ranking Schedule
- Runs **after** a full zone scan cycle completes (all zones scanned at least once)
- OR every **36,000 ticks (~10 minutes)** as a fallback
- **One zone processed per tick** (same iterator pattern) for the sort/compute step
- Targets persist until the next ranking run (old targets replaced, not accumulated)

### Gotcha: Global Rate = 0 at Game Start
Early game before any machines are placed, `globalTotalRate` is 0. Division by zero. Fix: if `globalTotalRate == 0` then skip ranking entirely — no targets generated, no triggered squads yet.

---

## 💥 Trigger System — Detailed Design

### The Threshold Check

Runs inside `processBase()` (already called once per tick for one base). Add a new check:

```lua
-- NEW: after normal base processing, check for priority strike opportunity
if Universe.priorityTargets
    and (#Universe.priorityTargets > 0)
    and (base.unitPoints >= PRIORITY_STRIKE_POINT_THRESHOLD)
    and (base.temperament >= PRIORITY_STRIKE_TEMPERAMENT_THRESHOLD)
    and (base.stateAI == BASE_AI_STATE_AGGRESSIVE
         or base.stateAI == BASE_AI_STATE_ONSLAUGHT
         or base.stateAI == BASE_AI_STATE_RAIDING)
    and (Universe.prioritySquadCount < Universe.PRIORITY_SQUAD_MAX)
    and (Universe.random() <= Universe.priorityStrikeChance)
then
    TargetTrigger.launchPriorityStrike(base, tick)
end
```

### Constants for the Threshold
```lua
PRIORITY_STRIKE_POINT_THRESHOLD     = 2000   -- must have saved up 2000+ unitPoints
PRIORITY_STRIKE_TEMPERAMENT_THRESHOLD = 0.65  -- must be fairly angry (0.65+)
PRIORITY_SQUAD_COST                  = 500    -- costs more than a normal squad (175)
PRIORITY_SQUAD_MAX                   = 2      -- at most 2 priority squads active globally
priorityStrikeChance                 = 0.15   -- 15% chance per eligible tick (still rare)
```

These are all mod-settings-exposed so the player can tune them.

### What `launchPriorityStrike` Does

```
1. Pick the highest-ranked priorityTarget that is reachable from base's position
   (closest target wins if multiple targets exist at same rank)

2. Deduct PRIORITY_SQUAD_COST from base.unitPoints

3. Find a deployment chunk near the base (same as normal deploySquad)

4. Call Squad.createSquad() with special metadata:
   squad.isPriorityStrike = true
   squad.priorityTarget = target  ← stores the target zone reference
   squad.priorityTargetX = target.centerX
   squad.priorityTargetY = target.centerY

5. squad.status = SQUAD_PRIORITY_RAIDING  ← new status constant

6. Universe.prioritySquadCount += 1
   Universe.groupNumberToSquad[squad.groupNumber] = squad
```

---

## 🧭 Priority Squad Navigation — Detailed Design

### The Core Difference From Normal Squads

Normal squads gradient-descend on pheromone values. They have no concept of a destination — they just follow the smell uphill.

Priority squads have a **hard destination** (the zone center) and navigate toward it explicitly, overriding the normal gradient.

### Two-Phase Navigation

**Phase 1 — Transit (squad is far from target)**

Score function: directional bias toward target + light pheromone pull
```lua
local function scorePriorityTransitLocation(neighborChunk, squad)
    -- distance to target (closer = higher score)
    local distanceScore = -euclideanDistancePoints(
        neighborChunk.x, neighborChunk.y,
        squad.priorityTargetX, squad.priorityTargetY
    )
    -- small player pheromone pull to avoid getting stuck in the middle of nowhere
    local pheromoneScore = neighborChunk[PLAYER_PHEROMONE] * 10
    -- avoid enemy pheromone (don't follow other squads' trails)
    local congestionPenalty = -neighborChunk[ENEMY_PHEROMONE] * 5
    return distanceScore + pheromoneScore + congestionPenalty
end
```

**Phase 2 — Assault (squad has arrived near target)**

When squad is within `PRIORITY_ARRIVAL_RADIUS` (e.g. 5 chunks) of the target center:
- Squad status switches from `SQUAD_PRIORITY_RAIDING` → `SQUAD_RAIDING`
- Score function switches to normal `scoreAttackLocation`
- Squad attacks normally from that position

### When the Target Disappears

If the priority target zone gets wiped out (all machines destroyed) before the squad arrives, or if `Universe.priorityTargets` is refreshed and the target drops off the list:
- Squad detects `squad.priorityTarget.relativeShare < PRIORITY_TARGET_STALE_THRESHOLD`
- Falls back to normal `SQUAD_RAIDING` behavior
- Does NOT count toward `prioritySquadCount` anymore

---

## 🧱 BehaviorRegistry — How Priority Strike Plugs In

The priority strike is a **registered squad behavior** like any other:

```lua
BehaviorRegistry.registerSquadBehavior({
    name = "priority_strike",
    displayName = "Priority Strike",
    isSettler = false,
    spawnCost = 500,
    validBaseStates = {
        BASE_AI_STATE_AGGRESSIVE,
        BASE_AI_STATE_ONSLAUGHT,
        BASE_AI_STATE_RAIDING
    },
    -- two-phase score function (reads squad.priorityTargetX/Y)
    scoreNeighbor = scorePriorityTransitLocation,
    -- on arrival, switch to normal attack
    onArrival = function(squad)
        squad.status = SQUAD_RAIDING
        squad.isPriorityStrike = false
        Universe.prioritySquadCount = Universe.prioritySquadCount - 1
    end,
    arrivalRadius = 5 * CHUNK_SIZE,  -- 160 tiles
    kamikazeThresholdMult = 1.5,     -- priority squads more likely to be kamikaze
})
```

This means: to create a *different* kind of targeted squad (e.g. one that targets the player's power grid specifically, or targets labs), you just register another behavior with a different `scoreNeighbor` function and different `validBaseStates`. No core code changes.

---

## ⚠️ Gotchas Master List

| # | Gotcha | Impact | Fix |
|---|--------|--------|-----|
| 1 | `entity.get_recipe()` returns nil if no recipe | Crash | Always nil-check before reading `.products` |
| 2 | `find_entities_filtered` on 320×320 area is slow | UPS hit | One phase per tick, one zone per tick slot |
| 3 | `LuaFlowStatistics` is force-wide in 1.1, not per-area | Wrong data | Scan entities manually |
| 4 | Mining drills don't have recipes | Wrong approach | Use `entity.mining_target.name` |
| 5 | Zones at map edge may be partially explored | Low counts | Accept it — partial data is fine for ranking |
| 6 | Zone coords must align to multiples of 32 (chunk grid) | Off-by-one nav | Always floor to nearest CHUNK_SIZE multiple |
| 7 | `entity.crafting_speed` crashes on non-assembler entities | Crash | Check `entity.type` before reading |
| 8 | Recipes with multiple products | Undercounting | Loop all `recipe.products`, sum each |
| 9 | `entity.valid` can be false mid-scan if destroyed | Crash | Check `.valid` before any property |
| 10 | `global.universe` must include zones + targets or data won't save | Silent data loss | Add `zones`, `priorityTargets`, `prioritySquadCount` to `onInit` |
| 11 | `globalTotalRate = 0` at game start | Division by zero in ranking | Skip ranking if globalTotalRate == 0 |
| 12 | Priority target zone might be destroyed before squad arrives | Squad without destination | Detect stale target via `relativeShare` threshold; fall back to normal RAIDING |
| 13 | `prioritySquadCount` must be decremented on squad death | Count leak → no more priority squads ever spawn | Hook `cleanSquads` squad cleanup to decrement if `squad.isPriorityStrike` |
| 14 | `processState` is called once per base per state window (10–25 min) — trigger check runs there too but the base only gets processed once per tick | Triggering too slowly | Trigger check belongs in `processBase()` not `processState()` — base runs every BASE_PROCESS_INTERVAL, which is more frequent |
| 15 | Priority squad gathers nearby units with `set_multi_command` — those units may be needed for normal defense | Defensive gap | Priority squads use same unit pool as normal squads — this is intentional tension |
| 16 | Two priority squads could target the same zone (PRIORITY_SQUAD_MAX=2) | Wasteful but not breaking | Acceptable for now; could add per-target lock later |
| 17 | Ranker runs over all zones — could be hundreds of iterations | UPS spike if done all at once | Use the same one-per-tick iterator pattern. Ranker takes N ticks where N = zone count |
| 18 | Zone scan during active combat = biters already attacking the target zone | Stale target while under attack | Fine — squads reinforce ongoing battles. Not a bug. |
| 19 | `entity.productivity_bonus` is only valid on crafters | Crash on drills/furnaces | Only read it after confirming `entity.type == "assembling-machine"` |
| 20 | Multiple bases could all trigger priority strikes simultaneously | Too many priority squads | `PRIORITY_SQUAD_MAX` is global and checked before every launch |

---

## 📋 Full Task Breakdown

### Phase 0 — Research ✅ Done
- [x] Read all ~9,500 lines of Rampant source
- [x] Map the full data flow: Base → Squad → Chunk → Pheromone
- [x] Understand the exact trigger pipeline for attack waves
- [x] Understand base economy (unitPoints, temperament, formSquadThreshold)
- [x] Research Factorio APIs for production scanning
- [x] Design Zone Scanner, Target Ranker, Trigger system, Priority Squad navigation

### Phase 1 — Zone Infrastructure 🔲
- [ ] Add constants: `ZONE_SIZE`, `ZONE_TILE_SIZE`, `ZONE_RESCAN_INTERVAL`
- [ ] Create `libs/ZoneManager.lua` — zone table, init, getZoneByPosition
- [ ] `ZoneManager.initZones(map)` — called from `MapUtils.addMap()`
- [ ] Add `maps[id].zones` to Universe map init in `onInit`
- [ ] Write `ZoneManager.getZoneByPosition(x, y)`
- [ ] Write `ZoneManager.updateZonePheromoneTotal(chunk)` — called cheaply during pheromone diffusion to keep dirty-check current
- [ ] **Test:** zones initialize on map load, no crash

### Phase 2 — Zone Production Scanning 🔲
- [ ] Write `ZoneManager.scanZonePhase1(zone, surface)` — assembling-machines
- [ ] Write `ZoneManager.scanZonePhase2(zone, surface)` — furnaces
- [ ] Write `ZoneManager.scanZonePhase3(zone, surface)` — mining drills
- [ ] Write `ZoneManager.compileZone(zone)` — compute totalRate, clear old data
- [ ] Add zone scan iterator to `Universe` (same pattern as base/nest)
- [ ] Hook into Processor tick loop (pick 3 or new pick slot)
- [ ] **Test:** `zone.products` and `zone.totalRate` populate correctly
- [ ] **Test:** UPS impact with `/measured-command`

### Phase 3 — Target Ranker 🔲
- [ ] Create `libs/TargetRanker.lua`
- [ ] Write `TargetRanker.runRankingPass(tick)` — one-per-tick iterator over zones
- [ ] Compute `zone.relativeShare = zone.totalRate / globalTotalRate`
- [ ] Write `TargetRanker.buildPriorityTargetList()` — sorts and takes top N
- [ ] Add `Universe.priorityTargets = {}` and `Universe.globalTotalRate = 0` to `onInit`
- [ ] Add `PRIORITY_TARGET_COUNT` constant (default 3) and mod setting
- [ ] **Test:** after 10 minutes of play, `priorityTargets` contains 3 zones with valid `relativeShare` values
- [ ] **Test:** early game (0 machines), ranking is skipped cleanly

### Phase 4 — BehaviorRegistry Core 🔲
- [ ] Create `libs/BehaviorRegistry.lua`
- [ ] Implement `registerSquadBehavior(spec)`
- [ ] Implement `registerBaseState(spec)`
- [ ] Implement `registerTemperamentBand(spec)` — replaces `processState` if/else
- [ ] Write `BehaviorRegistry.rollStateFromTemperament(base, universe)`
- [ ] Write `BehaviorRegistry.getScoreFunction(squadTypeName)`
- [ ] Wire `BehaviorRegistry.init(universe)` into `initializeLibraries()`
- [ ] **Test:** vanilla behaviors registered → game plays identically to unmodified Rampant

### Phase 5 — Migrate Existing Behaviors to Registry 🔲
- [ ] Register all 6 base AI states
- [ ] Register normal squad, settler, vengence squad, vengence settler behaviors
- [ ] Replace `processState` giant if/else tree with `rollStateFromTemperament()`
- [ ] Replace `Squad.squadDispatch` switch with registry score function lookup
- [ ] Replace `deploySquad` type checks with registry lookups
- [ ] **Test:** full regression — biters behave identically to baseline
- [ ] **Test:** save/load cycle preserves all state

### Phase 6 — Trigger System + Priority Squad 🔲
- [ ] Add constants: `PRIORITY_STRIKE_POINT_THRESHOLD`, `PRIORITY_STRIKE_TEMPERAMENT_THRESHOLD`, `PRIORITY_SQUAD_COST`, `PRIORITY_SQUAD_MAX`, `PRIORITY_ARRIVAL_RADIUS`
- [ ] Create `libs/TargetTrigger.lua`
- [ ] Write `TargetTrigger.checkBase(base, tick)` — the threshold gate
- [ ] Write `TargetTrigger.launchPriorityStrike(base, tick)` — squad creation
- [ ] Add `SQUAD_PRIORITY_RAIDING` status constant
- [ ] Register `priority_strike` behavior in BehaviorRegistry
- [ ] Write `scorePriorityTransitLocation(chunk, squad)` — distance-biased navigator
- [ ] Add arrival detection in `Squad.squadDispatch` for `SQUAD_PRIORITY_RAIDING` status
- [ ] Add `squad.isPriorityStrike` cleanup in `Squad.cleanSquads` (decrement count on death)
- [ ] Hook `TargetTrigger.checkBase` into `BaseUtils.processBase()`
- [ ] Add `Universe.prioritySquadCount = 0` to `onInit`
- [ ] **Test:** priority squads spawn and navigate toward high-production zones
- [ ] **Test:** `prioritySquadCount` never leaks (stays accurate through deaths/arrivals)

### Phase 7 — Polish 🔲
- [ ] Mod settings: Zone Size, Rescan Interval, Target Count, Strike Thresholds
- [ ] Debug visualizer: zone grid overlay with relativeShare % labels
- [ ] Debug visualizer: draw line from active priority squads to their targets
- [ ] Console command: `/rampant-targets` prints current priority targets
- [ ] Console command: `/rampant-zones` prints all zone stats
- [ ] Update changelog

---

## 🗂️ File-by-File Change Summary

| File | What changes | Risk | Phase |
|------|-------------|------|-------|
| `Constants.lua` | Zone, target, trigger constants | Low | 1, 3, 6 |
| `libs/ZoneManager.lua` | **New** — zones, scanning | New | 1–2 |
| `libs/TargetRanker.lua` | **New** — relative ranking, priority list | New | 3 |
| `libs/TargetTrigger.lua` | **New** — threshold check, strike launch | New | 6 |
| `libs/BehaviorRegistry.lua` | **New** — behavior API | New | 4 |
| `libs/MapUtils.lua` | Call `ZoneManager.initZones` on map add | Low | 1 |
| `libs/Processor.lua` | Add zone scan + ranker to tick loop | Medium | 2, 3 |
| `libs/Squad.lua` | Registry score lookup, priority arrival detection | Medium | 5, 6 |
| `libs/BaseUtils.lua` | Registry state machine, hook trigger check | High | 5, 6 |
| `libs/ChunkPropertyUtils.lua` | Call zone pheromone total update | Low | 1 |
| `libs/Upgrade.lua` | Query table alloc for registry | Low | 4 |
| `control.lua` | Require new files, init, debug commands | Medium | 4, 7 |
| `settings.lua` | Zone, target, trigger settings | Low | 7 |

---

## 💬 Open Questions

1. **Target count:** Default 3 priority targets — is that enough variety? Too many and biters feel "cheating", too few and they always hit the same spot.
2. **Zone persistence:** If the player tears down a factory and rebuilds elsewhere, old zone data persists until the next rescan. Is 5 minutes too long for this to feel wrong?
3. **Strike cost:** `PRIORITY_SQUAD_COST = 500` is ~3× a normal squad (175). Should it also drain `base.points` (special points) not just `unitPoints`?
4. **Cooldown:** Should there be a per-base cooldown on priority strikes so one base can't spam them? Or does `PRIORITY_SQUAD_MAX=2` globally handle this sufficiently?
5. **Visibility:** Should the player be able to see priority targets on the map? (A visible marker would make it strategic — "defend this or biters will target it")
6. **Backward compat:** Should the registry expose `remote.call("rampant", "registerBehavior", ...)` so other mods can register their own squad types?

---

*This document updates as work progresses. Status header tracks current phase.*

---

## 🏰 Outposts and Fortresses

### Concept Summary

Two new **structural archetypes** that exist alongside normal biter bases and hives:

| Type | Role | Worms | Spawner size | HP/Regen | Spawn rate | How placed |
|------|------|-------|-------------|----------|------------|------------|
| **Outpost** | Forward scout base — spawns waves fast, few defenses | Very few (0–1) | Smaller nests, many of them | Normal | Very fast cooldown | Migration squad reaches target |
| **Fortress** | Hardened military position — hard to kill, slow but dangerous | Many (4–8) | Larger single hive-scale nest | High HP, high regen | Normal/slow | Siege squad reaches target |

These are not just stat changes — they are fundamentally different **building layouts** placed by a custom `on_build_base_arrived`-style hook when specific squad types arrive.

---

### How Rampant's Building System Works (Relevant Recap)

**Data stage** (before game loads): `SwarmUtils.processFactions()` calls `makeUnitSpawner()` and `makeWorm()` for every faction × tier × variation combination. These generate Factorio prototypes. All entity names follow the pattern: `{faction}-{type}-v{variation}-t{tier}-rampant`.

**Runtime stage** (during play): `BaseUtils.queueCreation()` picks an entity name from the upgrade lookup tables, adds it to `Universe.pendingUpgrades`, and `Processor.processPendingUpgrades()` actually creates it on the surface one per tick.

**Hive system**: When a hive entity is placed, `registerHive()` creates a `hiveData` record with `maxNests`, `maxTurrets`, `maxHives` caps. `processHives()` fires every tick (one per tick) and calls `queueCreation()` to place nests/worms/sub-hives within `EIGHTH_CHUNK_SIZE * tier` radius of the hive center, until caps are reached.

**Builder arrival**: `on_build_base_arrived` fires when a settler squad reaches its destination. `onBuilderArrived` records the event. Factorio then calls `on_biter_base_built` once for each entity the biters actually place (vanilla engine places the initial nest). Rampant's `onBuild` intercepts this to register the entity and attach it to a base.

---

### Design: Outpost

**Gameplay intent:** A fast, disposable forward base. Lots of small nests = lots of unit waves. Almost no worm coverage = easy to destroy once you reach it, but dangerous until then.

**Prototype requirements (data stage):**
- New spawner variant: `outpost-spawner` — smaller collision box (`scale × 0.7`), faster spawn cooldown (`{180, 60}` vs default `{360, 150}`), fewer units owned (`max_count_of_owned_units = 4` vs 7), same tier/faction tint
- Worm is **vanilla** (no new prototype needed) — just placed in low quantities

**Runtime building layout (placed by OutpostBuilder):**
```
Outpost layout (placed around arrival position):
  • 3–5 biter/spitter spawners (outpost-spawner variant) in a loose cluster
  • 0–1 worms (vanilla worm, random tier-appropriate)
  • No hive
  • Spread radius: CHUNK_SIZE (32 tiles) — tight cluster
```

**Spawn conditions:**
- Migration squad that was flagged as `isOutpostBuilder = true` arrives (new squad type)
- OR: normal migration squad that lands in a zone with `relativeShare > OUTPOST_THRESHOLD` (high-value zone, biters establish forward base)
- Minimum evo: `0.15` (outposts don't appear in the very early game)

**How it integrates with migration:**
- A new `SQUAD_OUTPOST_BUILDING` status
- When an outpost-builder squad reaches its destination, instead of the vanilla `BUILD_BASE` command placing one nest, we intercept `on_build_base_arrived` and call `OutpostBuilder.buildOutpost(position, base, map, tick)`
- `OutpostBuilder.buildOutpost()` calls `queueCreation()` 3–5 times with small offsets from the center position

---

### Design: Fortress

**Gameplay intent:** A slow, heavily defended stronghold. Hard to destroy due to HP and regen. Worm-heavy = aggressive ranged defense. Spawner is large = fewer but stronger waves. Natural evolution: siege state biters build these to entrench near the player.

**Prototype requirements (data stage):**
- New spawner variant: `fortress-spawner` — larger collision box (`scale × 1.5`), higher max health (×2.5 base), higher healing_per_tick (×3), slower spawn cooldown (`{600, 300}`), more units owned (`max_count_of_owned_units = 12`), larger spawning radius (15 vs 10)
- New worm variant: `fortress-worm` — higher max health (×2), higher healing_per_tick (×2.5), no other changes (reuse existing attack animations/sounds via faction system)

**Runtime building layout (placed by FortressBuilder):**
```
Fortress layout (placed around arrival position):
  • 1 fortress-spawner (the "keep") at the center
  • 4–8 fortress-worms arranged in a ring at HALF_CHUNK_SIZE radius
  • 0–1 sub-hive (if evolution > 0.6)
  • Optional: 2–3 normal spawners as outer ring (if evolution > 0.8)
  • Spread radius: HALF_CHUNK_SIZE (16 tiles) for the ring
```

**Spawn conditions:**
- Siege squad flagged as `isFortressBuilder = true` arrives
- OR: siege squad that has been in `SQUAD_BUILDING` status for longer than `FORTRESS_BUILD_PATIENCE` ticks (it "dug in")
- Minimum evo: `0.40` (fortresses are a mid/late game threat)

**How it integrates with siege:**
- A new `SQUAD_FORTRESS_BUILDING` status
- When a fortress-builder squad reaches its destination, `FortressBuilder.buildFortress(position, base, map, tick)` is called from the `on_build_base_arrived` hook
- Worms are queued in a ring pattern using offset math (8 cardinal+diagonal directions × HALF_CHUNK_SIZE)

---

### Integration With Migration and Siege States

The key integration point is **which squad gets flagged** as an outpost/fortress builder. This happens inside `deploySquad()` (the function that creates squads from nests). We add a check after the squad is created:

```lua
-- in deploySquad, after squad is created, before returning:
if not attacker then
    -- settler squad — check if it should become an outpost builder
    if (Universe.evolutionLevel >= OUTPOST_MIN_EVO)
        and (Universe.random() < Universe.outpostBuildChance)  -- mod setting
    then
        squad.isOutpostBuilder = true
        squad.status = SQUAD_OUTPOST_SETTLING  -- new status, same navigation as SQUAD_SETTLING
    end
else
    -- attack squad from siege base — check if it should become a fortress builder
    if (base.stateAI == BASE_AI_STATE_SIEGE)
        and (Universe.evolutionLevel >= FORTRESS_MIN_EVO)
        and (Universe.random() < Universe.fortressBuildChance)  -- mod setting
    then
        squad.isFortressBuilder = true
        -- fortress builders still navigate as SQUAD_SETTLING but target zones with high threat scores
    end
end
```

**Navigation:** Both outpost and fortress builders use the existing settler navigation (`settleMove` / `scoreResourceLocation` or `scoreSiegeLocation`). No new navigation code. The differentiation is entirely at arrival time.

**The hook:** We extend `onBuilderArrived` in `control.lua`:

```lua
local function onBuilderArrived(event)
    -- ... existing code ...
    
    -- NEW: check if this is an outpost/fortress builder
    if not usingUnit and squad then
        if squad.isOutpostBuilder then
            OutpostBuilder.buildOutpost(builder.position, squad.base, map, event.tick)
            squad.isOutpostBuilder = false
        elseif squad.isFortressBuilder then
            FortressBuilder.buildFortress(builder.position, squad.base, map, event.tick)
            squad.isFortressBuilder = false
        end
    end
end
```

---

### New Files Required

```
libs/OutpostBuilder.lua    — outpost layout logic, queueCreation calls
libs/FortressBuilder.lua   — fortress layout logic, ring placement math
```

Both are thin files (~100 lines each). They only call `BaseUtils.queueCreation()` with specific positions and entity types. No new tick processing needed — the existing `processPendingUpgrades()` handles the actual placement.

**Prototype additions** (data stage, in `data.lua` or a new `prototypes/SpecialBuildings.lua`):
- `outpost-spawner` prototype per faction per tier (uses `makeUnitSpawner` with modified attributes)
- `fortress-spawner` prototype per faction per tier
- `fortress-worm` prototype per faction per tier (uses `makeWorm` with modified attributes)

These must be added to:
- `buildingHiveTypeLookup` (so Rampant tracks them as spawners/turrets)
- `buildingHiveTierLookup` (so upgrade system knows their tier)
- `BUILDING_PHEROMONES` (so pheromone system notices them)
- `COST_LOOKUP` (so base economy can charge for them)
- `UPGRADE_LOOKUP` (so they can be upgraded/mutated like normal buildings)

---

### New Constants

```lua
-- Outpost
OUTPOST_MIN_EVO              = 0.15
OUTPOST_SPAWNER_SCALE        = 0.7       -- smaller than normal
OUTPOST_SPAWN_COOLDOWN_MIN   = 60        -- very fast (1 second at max evo)
OUTPOST_SPAWN_COOLDOWN_MAX   = 180       -- fast (3 seconds at 0 evo)
OUTPOST_UNITS_OWNED          = 4
OUTPOST_WORM_COUNT_MAX       = 1
OUTPOST_NEST_COUNT           = {min=3, max=5}
OUTPOST_SPREAD_RADIUS        = CHUNK_SIZE  -- 32 tiles

-- Fortress
FORTRESS_MIN_EVO             = 0.40
FORTRESS_SPAWNER_SCALE       = 1.5       -- larger than normal
FORTRESS_HEALTH_MULT         = 2.5       -- ×2.5 base HP
FORTRESS_REGEN_MULT          = 3.0       -- ×3 healing per tick
FORTRESS_SPAWN_COOLDOWN_MIN  = 300       -- slow (5 seconds at max evo)
FORTRESS_SPAWN_COOLDOWN_MAX  = 600       -- very slow (10 seconds at 0 evo)
FORTRESS_UNITS_OWNED         = 12
FORTRESS_WORM_COUNT          = {min=4, max=8}  -- scales with tier
FORTRESS_WORM_HEALTH_MULT    = 2.0
FORTRESS_WORM_REGEN_MULT     = 2.5
FORTRESS_RING_RADIUS         = HALF_CHUNK_SIZE  -- 16 tiles
```

---

### New Gotchas (Outpost + Fortress Specific)

| # | Gotcha | Impact | Fix |
|---|--------|--------|-----|
| 21 | New prototype names must be registered in `buildingHiveTypeLookup` at runtime init, not just data stage | Rampant won't track the buildings | Add registration loop in `Upgrade.addUniverseProperties()` for outpost/fortress entity names |
| 22 | `on_build_base_arrived` fires once per squad arrival — if squad is destroyed mid-build the event may not fire | No outpost/fortress placed | Add a fallback: check `squad.isOutpostBuilder` in `cleanSquads` on squad death, place a minimal version if TTL expired |
| 23 | `queueCreation` has a `PENDING_UPGRADE_CREATION_THRESHOLD` guard — if queue is full, buildings won't be queued | Partial outpost/fortress | Use a retry queue or accept partial layouts |
| 24 | Fortress worm ring placement may land on water or cliffs | Worm not placed | `find_non_colliding_position` already handles this inside `queueCreation` — accepted |
| 25 | `outpost-spawner` and `fortress-spawner` are new entity names — all per-faction-per-tier names must be added to the lookup tables | Upgrade/mutation system ignores them | Loop through all factions × tiers in the lookup-building section of Constants.lua |
| 26 | Fortress builders use siege squad navigation — they may not stop close enough to the player to be threatening | Fortress built in wilderness | Add a minimum player-pheromone check to `isFortressBuilder` flag assignment — only flag squads from chunks with `BASE_PHEROMONE > threshold` |
| 27 | Outpost builders spawning too frequently tanks the map with nests | Balance issue | `outpostBuildChance` mod setting default very low (0.05 = 5%); player can tune |
| 28 | Fortress on top of existing player structures | Immediate conflict | `find_non_colliding_position` handles this; also fortress spawner has large `build_base_evolution_requirement` so it won't appear near player early |
| 29 | Fortresses need to be registered as a base's resource chunks (for AI point counting) | AI doesn't "know" it owns a fortress | `registerEnemyBaseStructure` already handles this for all unit-spawners and turrets — new entities are automatically picked up as long as lookup tables are populated |
| 30 | `squad.isFortressBuilder` must survive save/load (it's in `global.universe`) | Flag lost on reload | Squad table is part of `Universe.groupNumberToSquad` which is in global — fields added to squad table automatically persist |

---

## 📋 Updated Task Breakdown (Phases 8–9 Added)

### Phase 8 — Outpost System 🔲
- [ ] Add outpost constants to `Constants.lua`
- [ ] Add `outpost-spawner` prototype generation to `SwarmUtils.processFactions()` (data stage)
- [ ] Register outpost entity names in lookup tables (`buildingHiveTypeLookup`, `buildingHiveTierLookup`, etc.)
- [ ] Create `libs/OutpostBuilder.lua` — `buildOutpost(position, base, map, tick)`
- [ ] Add `isOutpostBuilder` flag assignment in `deploySquad()` (migration squads only)
- [ ] Add `SQUAD_OUTPOST_SETTLING` status constant (identical behavior to `SQUAD_SETTLING`)
- [ ] Extend `onBuilderArrived` in `control.lua` to call `OutpostBuilder.buildOutpost`
- [ ] Add `outpostBuildChance` mod setting
- [ ] **Test:** outpost builders spawn, navigate, and place multi-spawner clusters
- [ ] **Test:** outpost buildings are tracked by base and appear on map

### Phase 9 — Fortress System 🔲
- [ ] Add fortress constants to `Constants.lua`
- [ ] Add `fortress-spawner` and `fortress-worm` prototype generation (data stage)
- [ ] Register fortress entity names in all lookup tables
- [ ] Create `libs/FortressBuilder.lua` — `buildFortress(position, base, map, tick)`
- [ ] Implement ring placement math (8-directional at `FORTRESS_RING_RADIUS` for worms)
- [ ] Add `isFortressBuilder` flag assignment in `deploySquad()` (siege squads only)
- [ ] Extend `onBuilderArrived` to call `FortressBuilder.buildFortress`
- [ ] Add `fortressBuildChance` mod setting
- [ ] **Test:** fortress builders spawn from siege bases, navigate, place worm rings
- [ ] **Test:** fortress HP/regen values match constants
- [ ] **Test:** fortress entities are correctly tracked by Rampant's base system

---

## 🗂️ Updated File-by-File Change Summary

| File | What changes | Risk | Phase |
|------|-------------|------|-------|
| `Constants.lua` | Zone, target, trigger, outpost, fortress constants + lookup tables | Low | 1,3,6,8,9 |
| `libs/ZoneManager.lua` | **New** — zone scanning | New | 1–2 |
| `libs/TargetRanker.lua` | **New** — relative ranking | New | 3 |
| `libs/TargetTrigger.lua` | **New** — priority strike triggering | New | 6 |
| `libs/BehaviorRegistry.lua` | **New** — behavior API | New | 4 |
| `libs/OutpostBuilder.lua` | **New** — outpost layout | New | 8 |
| `libs/FortressBuilder.lua` | **New** — fortress layout + ring math | New | 9 |
| `libs/MapUtils.lua` | Hook zone init on map add | Low | 1 |
| `libs/Processor.lua` | Zone scan + ranker in tick loop | Medium | 2,3 |
| `libs/Squad.lua` | Registry lookup, priority arrival, outpost/fortress flags | Medium | 5,6,8,9 |
| `libs/BaseUtils.lua` | Registry state machine, trigger hook | High | 5,6 |
| `libs/ChunkPropertyUtils.lua` | Zone pheromone total update | Low | 1 |
| `libs/Upgrade.lua` | Query tables for registry; outpost/fortress lookup registration | Low | 4,8,9 |
| `prototypes/SwarmUtils.lua` | `processFactions` generates outpost/fortress variants | Medium | 8,9 |
| `control.lua` | Require new files, init, `onBuilderArrived` extension, debug commands | Medium | 4,7,8,9 |
| `settings.lua` | Zone, target, trigger, outpost, fortress settings | Low | 7,8,9 |


---

## 💣 Demolisher Biters (formerly Nuclear Biters)

### Concept Summary

The nuclear biter faction is being **completely renamed and rethemed** from nuclear to **demolisher** — living biological bombs that detonate with a massive artillery-scale explosion on contact. Everything about them changes: name, tint, lore framing, explosion type, and visual feedback. The gameplay role stays the same (suicide melee striker that deals massive area damage) but the explosion is now **artillery shell scale** instead of a scaled-down nuke.

---

### What Currently Exists (Full Audit)

**The nuclear faction is defined in exactly two places:**

**1. `libs/Constants.lua` lines 1324–1381** — the runtime faction record:
- `type = "nuclear"` — internal key used for all entity name generation
- `attackAttributes = {"nuclear"}` — routes to the nuclear suicide attack path
- Unit attributes: `lowestHealth`, `quickMovement`, `killsSelf`
- Spawner drops: `quickSpawning`, `lowUnits`
- Weakness: `majorWeaknesses = {"explosion"}`
- `evo = 0.45`, `acceptRate tierStart = 4` — late-appearing faction
- Worm attack: `"spit", "acid", "slow"` — slowing acid worm

**2. `prototypes/SwarmUtils.lua` lines 1354–1372** — the data-stage attack handler:
- `attack == "nuclear"` branch sets `template.nuclear = true`
- Calls `createSuicideAttack(attack, makeAtomicBlast(attack), ...)` — the nuke wave

**The `nuclear` attribute flag (`attributes.nuclear`) inside `createSuicideAttack` in `BiterUtils.lua`** gates the entire nuclear explosion chain (atomic bomb wave projectiles, `nuke-explosion` entity, `nuclear-ground` tiles, screen burn effect, nuclear sounds).

**The setting flag** `rampant--nuclearEnemy` in `settings.lua` controls whether the faction exists at all.

**Locale strings** across 5 languages reference "Nuclear Biter" — all need updating.

---

### What Changes, File by File

#### `libs/Constants.lua`
```lua
-- FROM:
if settings.startup["rampant--nuclearEnemy"].value then
    ...
    type = "nuclear",
    attackAttributes = {"nuclear"},
    units = {{ name = "biter", ..., attributes = {"lowestHealth", "quickMovement", "killsSelf"} }}
    ...

-- TO:
if settings.startup["rampant--demolisherEnemy"].value then
    ...
    type = "demolisher",               -- all entity names change: "demolisher-biter-v1-t3-rampant" etc.
    attackAttributes = {"demolisher"}, -- new attack key
    units = {{
        name = "biter",
        attributes = {"lowestHealth", "quickMovement", "killsSelf"},
        -- same weakness: majorWeaknesses = {"explosion"}
        -- tint changes to something more industrial/chemical: dark orange-green
    }}
    -- worm attack stays: {"spit", "acid", "slow"} — no change needed there
```

The internal `type` field change means **all entity prototype names change**. Every `demolisher-biter-v{n}-t{n}-rampant` entity is a new prototype. This is intentional — the nuclear variants simply cease to exist and demolisher variants replace them.

#### `prototypes/SwarmUtils.lua`
Replace the `attack == "nuclear"` branch with `attack == "demolisher"`:

```lua
-- FROM:
elseif (attack == "nuclear") then
    template.addon[#template.addon+1] = nuclearAttackNumeric
    template.explosionTiers = explosionTiers
    template.scorchmarkTiers = scorchmarkTiers
    template.nuclear = true
    template.attackGenerator = function (attack)
        return createSuicideAttack(attack, makeAtomicBlast(attack), ...)
    end

-- TO:
elseif (attack == "demolisher") then
    template.addon[#template.addon+1] = demolisherAttackNumeric  -- new numeric table (see below)
    template.explosionTiers = demolisherExplosionTiers           -- all tiers use artillery explosion
    template.scorchmarkTiers = demolisherScorchmarkTiers         -- all tiers use big/huge scorchmark
    template.attackGenerator = function (attack)
        return createSuicideAttack(attack, nil, ...)  -- NO makeAtomicBlast — uses non-nuclear path
    end
```

**Key difference:** We use the `else` branch of `createSuicideAttack` (the non-nuclear path), not the nuclear path. The non-nuclear path reads `attributes.attackExplosion` and `attributes.radius` to do an area damage blast. We set `attackExplosion` to `"artillery-shell-explosion"` — a vanilla Factorio entity that already exists and has the correct visual scale.

#### New numeric table: `demolisherAttackNumeric`
```lua
local demolisherAttackNumeric = {
    -- damage per tier — high single-hit, not repeated like nuclear
    ["damage"] = { 150, 225, 300, 400, 525, 650, 800, 975, 1150, 1400 },
    -- radius per tier — artillery shell scale (artillery shell has radius ~5-7 in vanilla)
    ["radius"] = { 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 9.0 },
    -- explosion distance and count for the non-nuclear path
    ["explosionDistance"] = { 2.0, 2.0, 2.5, 2.5, 3.0, 3.0, 3.5, 3.5, 4.0, 4.0 },
    ["explosionCount"] = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }
}
```

Compare to nuclear `nuclearAttackNumeric`:
- Nuclear: `damage 15–55`, `repeatCount 150–600`, `radius 5–20` — many weak hits over a huge area
- Demolisher: `damage 150–1400`, `radius 4–9`, single hit — one massive concentrated blast, exactly like an artillery shell landing

#### New explosion tier tables
```lua
local demolisherExplosionTiers = {
    "artillery-shell-explosion",  -- tier 1–2: artillery shell
    "artillery-shell-explosion",
    "artillery-shell-explosion",  -- tier 3–6: same, radius just grows
    "artillery-shell-explosion",
    "artillery-shell-explosion",
    "artillery-shell-explosion",
    "artillery-shell-explosion",  -- tier 7–10: still artillery but max radius
    "artillery-shell-explosion",
    "artillery-shell-explosion",
    "artillery-shell-explosion"
}

local demolisherScorchmarkTiers = {
    "medium-scorchmark",
    "medium-scorchmark",
    "big-scorchmark",
    "big-scorchmark",
    "big-scorchmark",
    "big-scorchmark",
    "huge-scorchmark",
    "huge-scorchmark",
    "huge-scorchmark",
    "huge-scorchmark"
}
```

The `artillery-shell-explosion` entity is defined in the vanilla Factorio base game — no new prototype creation needed. It has the right visuals: smoke, fire, debris, the correct audio, and the right scale.

#### `settings.lua`
```lua
-- FROM:
name = "rampant--nuclearEnemy"

-- TO:
name = "rampant--demolisherEnemy"
```

#### `locale/en/locale.cfg` (and all other locale files)
```
-- FROM:
rampant--nuclearEnemy=Nuclear Biter Enemy
rampant--nuclearTints=World: Nuclear Biter Faction Colors

-- TO:
rampant--demolisherEnemy=Demolisher Biter Enemy
rampant--demolisherTints=World: Demolisher Biter Faction Colors
```

All 5 locale files (en, ru, pl, ko, zh-CN) need updating.

---

### What Does NOT Change

- Unit stats (health, movement speed, attack cooldown) — same multipliers via `lowestHealth`, `quickMovement`, `killsSelf`
- Spawner stats (HP, regen, spawn rate)
- Worm attacks — still acid/slow worms
- `evo = 0.45`, `acceptRate tierStart = 4` — still late-game faction
- Weakness to explosion damage — still `majorWeaknesses = {"explosion"}`
- The `killsSelf` attribute (`entity.healthDamage = entity.health * 3`) — still instantly kills itself on detonation
- The `createSuicideAttack` function itself — we just switch it from the nuclear branch to the non-nuclear branch

---

### Why Artillery Shell, Not a New Custom Explosion

**Option A (what we're doing):** Use vanilla `artillery-shell-explosion` entity. Zero new prototype work. Looks and sounds exactly right — the player immediately recognizes the scale. Visually distinct from the nuke (no screen-burn, no mushroom cloud, no nuclear tiles).

**Option B (alternative):** Create a custom `demolisher-explosion-rampant` entity with tweaked radius. More work, marginal difference in appearance.

Option A is correct. The whole point is it *feels like an artillery shell landed on you*, not a tactical nuke. Players know that sound and that visual. Using the vanilla entity makes this immediately legible.

---

### Migration / Save Compatibility

⚠️ **This is a breaking rename.** Existing saves with nuclear biters will have orphaned entity references when the mod updates. The entity names change from `nuclear-*-rampant` to `demolisher-*-rampant`.

Factorio handles this via **migrations** (JSON files in `/migrations/`). We need a migration that:
1. Destroys all `nuclear-*-rampant` entities on the surface
2. Their owning base loses `builtEnemyBuilding` count accordingly
3. Base alignment `nuclear` becomes `demolisher`

Rampant already has two migration files as examples (`rampant-0.17.25.json`, `rampant-3.2.0.json`). We add a new one: `rampant-3.4.0.json` (or whatever the next version is).

---

### New Gotchas (Demolisher Specific)

| # | Gotcha | Impact | Fix |
|---|--------|--------|-----|
| 31 | `artillery-shell-explosion` is a vanilla entity — verify it exists in 1.1 base game | Crash if missing | It does — it's used by vanilla artillery. Safe to reference. |
| 32 | `createSuicideAttack` non-nuclear path reads `attributes.attackExplosion` — must be set correctly | Wrong explosion or nil crash | `attributes.attackExplosion` is set via `entity.explosionTiers[tier]` via the `explosionTiers` key in the template |
| 33 | `template.nuclear = true` must NOT be set for demolisher | Will fall into nuclear blast path in `createSuicideAttack` | Simply don't set it — the `else` branch fires automatically |
| 34 | Setting rename `rampant--nuclearEnemy` → `rampant--demolisherEnemy` breaks existing player configs | Setting reset to default on update | Acceptable — it's a startup setting, player just re-enables it |
| 35 | All entity names change — `buildingHiveTypeLookup` and `buildingHiveTierLookup` populated via faction `type` field — automatically correct once `type` changes | None — it's automatic | Verify by checking the loop at line 1754 of Constants.lua |
| 36 | `BASE_ALIGNMENT_NUCLEAR = 3` constant is referenced by number in old saves | Migration needed | Add to migration file; or just rename the constant to `BASE_ALIGNMENT_DEMOLISHER = 3` (same value, just a label) |
| 37 | `FACTIONS_BY_DAMAGE_TYPE["impact"]` and `["poison"]` both reference `"nuclear"` — must change to `"demolisher"` | Mutation system mutates to wrong faction name | Find-replace `"nuclear"` → `"demolisher"` in `FACTIONS_BY_DAMAGE_TYPE` assignments |
| 38 | Locale files in 5 languages need updating | Players see old "Nuclear" label | Update all 5: en, ru, pl, ko, zh-CN |

---

## 📋 Updated Task Breakdown (Phase 10 Added)

### Phase 10 — Demolisher Biter Refactor 🔲
- [ ] Rename `rampant--nuclearEnemy` → `rampant--demolisherEnemy` in `settings.lua`
- [ ] Rename `rampant--nuclearTints` → `rampant--demolisherTints` in `settings.lua`
- [ ] Rename `BASE_ALIGNMENT_NUCLEAR` → `BASE_ALIGNMENT_DEMOLISHER` in `Constants.lua`
- [ ] Change faction `type = "nuclear"` → `type = "demolisher"` in `Constants.lua`
- [ ] Change `attackAttributes = {"nuclear"}` → `{"demolisher"}` in `Constants.lua`
- [ ] Change `FACTIONS_BY_DAMAGE_TYPE` references: `"nuclear"` → `"demolisher"`
- [ ] Write new `demolisherAttackNumeric` table in `SwarmUtils.lua`
- [ ] Write `demolisherExplosionTiers` and `demolisherScorchmarkTiers` tables
- [ ] Replace `attack == "nuclear"` branch with `attack == "demolisher"` in `SwarmUtils.lua`
- [ ] Remove `template.nuclear = true` (routes to non-nuclear `createSuicideAttack` path)
- [ ] Set `template.explosionTiers = demolisherExplosionTiers`
- [ ] Update locale strings in all 5 locale files (en, ru, pl, ko, zh-CN)
- [ ] Write migration file `rampant-X.Y.Z.json` to handle `nuclear-*-rampant` → `demolisher-*-rampant` rename
- [ ] **Test:** demolisher biters spawn and detonate with artillery-shell-explosion visual
- [ ] **Test:** explosion radius matches artillery shell (roughly 5–7 tiles at mid tiers)
- [ ] **Test:** no screen-burn, no nuclear tiles placed (confirms non-nuclear path is taken)
- [ ] **Test:** existing save migration runs without crash

---

## 🗂️ Final File-by-File Change Summary

| File | What changes | Risk | Phase |
|------|-------------|------|-------|
| `Constants.lua` | Zone/target/trigger/outpost/fortress constants; demolisher rename | Low–Med | 1,3,6,8,9,10 |
| `libs/ZoneManager.lua` | **New** — zone scanning | New | 1–2 |
| `libs/TargetRanker.lua` | **New** — relative ranking | New | 3 |
| `libs/TargetTrigger.lua` | **New** — priority strike | New | 6 |
| `libs/BehaviorRegistry.lua` | **New** — behavior API | New | 4 |
| `libs/OutpostBuilder.lua` | **New** — outpost layout | New | 8 |
| `libs/FortressBuilder.lua` | **New** — fortress layout | New | 9 |
| `libs/MapUtils.lua` | Zone init hook | Low | 1 |
| `libs/Processor.lua` | Zone scan + ranker | Medium | 2,3 |
| `libs/Squad.lua` | Registry, priority nav, outpost/fortress flags | Medium | 5,6,8,9 |
| `libs/BaseUtils.lua` | Registry state machine, trigger hook | High | 5,6 |
| `libs/ChunkPropertyUtils.lua` | Zone pheromone total | Low | 1 |
| `libs/Upgrade.lua` | Query tables, outpost/fortress lookups | Low | 4,8,9 |
| `prototypes/SwarmUtils.lua` | Demolisher attack branch; outpost/fortress variants | Medium | 8,9,10 |
| `prototypes/utils/BiterUtils.lua` | No changes needed | — | — |
| `prototypes/utils/BombUtils.lua` | No changes needed | — | — |
| `control.lua` | New files, `onBuilderArrived` extension, debug commands | Medium | 4,7,8,9 |
| `settings.lua` | All new settings + demolisher rename | Low | 7,8,9,10 |
| `locale/*/locale.cfg` (×5) | Demolisher string rename | Low | 10 |
| `migrations/rampant-X.Y.Z.json` | **New** — entity rename migration | New | 10 |

