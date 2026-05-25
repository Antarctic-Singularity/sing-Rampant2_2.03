# Rampant Plan #2 — New Unit & Faction Ideas
### Brainstorm + Feasibility Notes
**Status:** 🟡 Ideas Stage  
**Last Updated:** Session 4  
**Note:** Nothing here is committed. These are ideas ranked by how realistic they are to implement given Factorio's modding limits.

---

## 🔑 The Design Space (What Rampant Can Actually Do)

Before ideas, here's what the engine gives us to work with. Everything below is built from combinations of these:

**Unit types available:**
- `unit` (biter/spitter — moves, attacks, follows player)
- `turret` (worm — stationary, placed by biters)
- `unit-spawner` (nest/hive — stationary, spawns units)
- `drone` (Rampant custom — flying projectile unit launched from capsule attack)

**Attack delivery types:**
- `melee` — physical contact
- `projectile` — fired arc, can have area effect on impact
- `stream` — continuous stream (like flamethrower)
- `beam` — instant laser
- `cluster` — fires N sub-projectiles on impact
- `suicide/bomb` — unit dies, creates explosion at self
- `capsule` — fires a projectile that spawns a drone unit

**Effect modifiers stackable on any attack:**
- `slow` — sticker that reduces movement speed
- `acid` — damage-over-time puddle
- `poison` — poison cloud on impact
- `electric` — chain lightning
- `clusterDeath` — spawns sub-explosions on unit death
- `poisonDeathCloud` — spawns poison cloud on unit death

**Unit attribute modifiers (mix and match):**
- Speed: `quickMovement`, `slowMovement`, `stationary`
- Health: `lowestHealth`, `highHealth`, `highestHealth`
- Size: `smallest`, `big`, `bigger`
- Regen: `highRegen`, `highestRegen`, `unstable` (negative regen)
- Attack: `quickCooldown`, `longReach` (range ×3)
- On-death: `killsSelf`, `selfDamaging`, `fragile`, `poisonDeathCloud`
- Behavior: `followsPlayer`, `quickSpawning`, `twoUnits`

**Range reference:**
- Normal biters: melee (range 0.5–2.0)
- Normal spitters: range 11–15
- Worm turrets: range 11–15 with `longReach` possible: ~33–45
- Beam attackers: range 11–15
- Max observed in Rampant: `range 40` (beam faction numeric)

**The hard limits:**
- Units cannot be made truly stationary mid-combat — they still pathfind when idle
- Cannot make a unit that only fires once and then stops (no "fire N shots then stop" logic)
- `starting_speed` on projectiles is what controls arc height/distance, but there's a cap before it looks wrong
- Cannot make a unit that changes attack type mid-combat (it has one prototype forever)
- Cannot make biters patrol a path — they follow pheromone gradient or squad commands only

---

## 🎯 Your Idea: Artillery Spitter

**Name idea:** Bombspitter / Barrage Spitter / Siege Spitter

**What it does:** A spitter variant that lobs explosive projectiles at extreme range — effectively biter-side artillery. Stays far back from the player's walls and shells them from outside normal turret range.

**How to build it:**

This is straightforwardly doable. It uses the existing `projectile` attack type with:
- High `range` (25–40 tiles depending on tier — current spitters max at 15)
- `artillery-shell-explosion` as the impact entity (same explosion we're using for demolisher biters)
- Impact area damage via a `nested-result → area → damage` chain
- `slowMovement` attribute so it hangs back rather than rushing in
- `lowestHealth` or `fragile` — very fragile, dies easily if you reach it

**Numeric table draft:**
```lua
local artillerySpitterNumeric = {
    ["range"]   = { 20, 22, 24, 26, 28, 30, 32, 34, 36, 40 },  -- waaaay longer than normal
    ["damage"]  = { 30, 45, 65, 90, 120, 160, 210, 270, 340, 420 },
    ["radius"]  = { 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0 },
    ["cooldown"]= { 180, 175, 170, 165, 160, 155, 150, 145, 140, 135 }, -- very slow fire rate
    ["scale"]   = { 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.8 }, -- larger visual
}
```

**The key implementation detail:** The `createRangedAttack` path already supports arbitrary range. You just set a high range value and give the projectile the artillery explosion as its impact effect. The hardest part is the projectile visual — we'd reuse the vanilla acid ball projectile visual (or make a new one that looks like a blobby bomb).

**Gotcha:** At range 35+, the projectile arc becomes very flat due to how Factorio handles `starting_speed`. It may look weird. Can be mitigated by increasing `starting_speed` to create a proper lobbing arc, but too high and it overshoots. Will need tuning.

**Integration:** New `"artillery"` attack type in SwarmUtils. New faction or added to an existing faction (e.g. make it a building type in a new "Siege" faction).

---

## 💡 Other Ideas — Graded by Feasibility

---

### ✅ VERY FEASIBLE — Low implementation effort

---

#### 1. Shrapnel Biter (Cluster Suicide)
**What it does:** Normal-looking biter that, when it dies, explodes into 8–12 fast shrapnel fragments that scatter and each do small damage in a cone. Hits multiple targets per death — punishes tight formations and walls.

**How:** `clusterDeath` attribute + a custom cluster projectile. Already exists in the system. This is basically one new numeric table and hooking into the existing `clusterDeath` handler.

**Gameplay feel:** You shoot them and the death itself damages your walls. Encourages spread-out defenses.

---

#### 2. Corrosion Worm (Acid Pool Turret)
**What it does:** A stationary turret worm that instead of firing a projectile, spits a large acid puddle that lands at range and persists as a damage zone. Biters then walk through the player's defenses while turrets are standing in acid.

**How:** New turret with `acidPool` attack type (already exists) + a large radius sticker. The acid pool persists for its duration damaging anything standing in it. Reuse existing acid pool system.

**Gameplay feel:** Creates denial zones. Forces player to reposition turrets or drain the area first.

---

#### 3. Burrower Biter (Fast + Fragile + Poison Death)
**What it does:** Tiny, extremely fast biter (smallest + quickMovement + quickCooldown) that bypasses ranged defenses by being hard to hit, but dies in 1–2 hits. When it dies: `poisonDeathCloud` releases a tier-scaled poison cloud right inside your defenses.

**How:** Combine `smallest`, `quickMovement`, `fragile`, `poisonDeathCloud`. All attributes already exist. This is literally just a new faction entry with the right attribute mix.

**Gameplay feel:** The biters that individually do nothing but their deaths are what kills you.

---

#### 4. Armored Siege Spitter (slowMovement + highestHealth + longReach)
**What it does:** A slow-moving, heavily armored spitter that fires from extreme range (uses `longReach` which gives ×3 range multiplier). Basically a self-propelled artillery piece. Tanky, slow, hits very hard at long range.

**How:** `slowMovement` + `highestHealth` + `longReach` + high damage per shot. No new code — this is pure Constants.lua configuration.

**Gameplay feel:** Forces the player to push into biter territory to silence them. They won't come to you.

---

#### 5. Volatile Hive (Spawner That Explodes on Death)
**What it does:** A unit-spawner that has `clusterDeath` or custom death effects — when you destroy it, it releases a cloud of fast-spawned units and/or an explosion. "Don't blow up the nest or you'll regret it."

**How:** Spawner buildings can have `dying_trigger_effect`. Add an area trigger that creates several biters at the death position. This is data stage only — no runtime code.

**Gameplay feel:** Destroying the base becomes more dangerous. Sniper players who use artillery from afar are rewarded; direct assault gets swarmed on the kill.

---

#### 6. Infested Structure (Turret That Spawns Units)
**What it does:** A stationary "turret" (in the Factorio type sense) that instead of attacking, periodically spawns units in a small radius. Think: a stationary egg sac. It has no ranged attack — its threat is unit production. High HP and regen. Placed by hives.

**How:** This is a `unit-spawner` with `twoUnits` attribute and `stationary`-like traits, placed via the hive system like a sub-hive. Already possible — the hive system places sub-hives already.

**Gameplay feel:** Small outposts that keep re-materializing units. Can't just kill the biters — you need to destroy the source.

---

### 🟡 MEDIUM FEASIBILITY — Needs new code but no engine hacks

---

#### 7. Swarm Launcher Worm (Capsule → Drone Barrage)
**What it does:** A stationary worm-type turret that fires a capsule projectile at long range. The capsule, on impact, releases 4–6 drones that attack anything nearby. Like a drone-delivery artillery shell.

**How:** Uses the existing `capsule` attack type + `createCapsuleProjectile` + `makeDrone`. Rampant already has this for the energy-thief faction's worm-wasp. Extend it — a new worm turret with a longer range capsule and a more aggressive short-TTL drone.

**The effort:** New numeric tables, new drone variant with short TTL and high aggression. Medium effort.

**Gameplay feel:** Turrets can't kill the drones fast enough when 5 drone salvos are incoming. Forces anti-air thinking.

---

#### 8. Seismic Biter (Melee + Knockback effect)
**What it does:** A big, slow biter that, when it attacks, sends a shockwave outward from itself — a small area attack centered on the biter that damages and knocks back nearby player entities. Makes walls feel impactful to fight near.

**How:** Melee attack with a `nested-result → area → damage` wrapped around the normal hit. Creates a small explosion effect at the biter's own position on each attack. Already close to how `clusterDeath` works but on hit, not on death. Needs a new attack generator function.

**The effort:** New `"shockwave"` attack type in SwarmUtils + a new `createMeleeShockwaveAttack` function in BiterUtils. About 60 lines of new code.

---

#### 9. Mimic Biter (Follows Player Invisibly)
**What it does:** Uses `followsPlayer = true` attribute (already in the system) combined with `stationary = 0` movement but small scale. Effectively a biter that stalks the player character specifically rather than following squad commands. When it gets close, it triggers.

**How:** `followsPlayer` already exists. Combine with `smallest` for stealth feel, `poisonDeathCloud` so killing it backfires, `selfDamaging` so it auto-kills itself after a TTL.

**The effort:** Attribute combination only — no new code. The `followsPlayer` path is already implemented in BiterUtils.

---

#### 10. Breacher Biter (Wall Destroyer)
**What it does:** A large biter specifically built for destroying walls and buildings rather than players. High physical damage, high HP, fire resistance. Spawned specifically during siege AI state to "open a hole" in defenses.

**How:** `highestHealth` + `bigger` + high melee damage + `physical` resistance. This is configuration only. The behavior difference (goes for walls) is handled by the fact that walls have player pheromone and biters attack toward it — no special code needed.

**The effort:** Constants.lua configuration only. Very low.

---

### 🔴 HARD / HACKY — Requires significant engine creativity

---

#### 11. Mortar Worm (True Indirect Fire)
**What it does:** A worm that fires at a target it CANNOT see — over walls, indirectly, based on player pheromone rather than line of sight. True indirect fire.

**How:** This is actually impossible cleanly — Factorio's turret type requires line-of-sight or close proximity to fire. The workaround would be to use the `on_tick` system to manually create projectiles via `surface.create_entity` at the worm's position targeting pheromone-heavy chunks rather than the turret's own targeting. Effectively faking the attack in code.

**The effort:** Runtime code in Processor.lua — add a special "mortar worm" iterator that fires fake projectiles toward player-pheromone-heavy chunks on its own schedule. Significant effort but possible.

---

#### 12. Possessed Turret (Infects Player Buildings)
**What it does:** A special biter that, on reaching a player building, "infects" it — it starts spawning small biters from inside the player's base. The building appears to work normally but is secretly producing enemies.

**How:** `on_biter_base_built` fires when biters reach a position and build. We could hook a special squad arrival to instead of placing a nest, call `surface.create_entity` to replace a nearby player building with an "infested" copy that has enemy behavior.

**The effort:** Significant. Needs new prototype (infested assembler), new squad type, new arrival handler. Also confusing/annoying for the player potentially. Feasible but complex.

---

#### 13. Pack Hunter (Units That Get Stronger Near Each Other)
**What it does:** Biters that individually are weak but receive attack/damage bonuses based on how many of their kind are nearby. The bigger the wave, the more dangerous each individual unit.

**How:** Factorio has no native "aura" buff for biters. Would need `on_tick` scanning nearby units of the same type and dynamically applying stickers with positive effects. Expensive, messy, requires per-unit tracking.

**The effort:** Very high. Probably not worth it over the gameplay benefit.

---

## 📋 Priority Recommendations

If you want to add 3 new things that have the best gameplay-to-effort ratio:

| Priority | Unit | Reason |
|----------|------|--------|
| 1 | **Artillery Spitter** (your idea) | Unique tactical role, clean implementation, changes how players think about range |
| 2 | **Shrapnel Biter** | Punishes tight wall-spam, only ~1 new numeric table + existing clusterDeath |
| 3 | **Corrosion Worm** | Completely new threat type (area denial), reuses existing acid pool system, changes base layout decisions |

Honorable mention: **Volatile Hive** — pure data stage, zero runtime code, huge gameplay impact.

---

## 💬 Open Questions For You

1. **Artillery Spitter faction:** Should it be its own new faction or a building type in an existing faction (e.g. the siege faction gets artillery spitters as a special spawner unit)?
2. **Shrapnel Biter:** Should the death cluster do explosion damage (hurts walls) or physical damage (hurts player character more)?
3. **Artillery Spitter visual:** Reuse the existing spitter model at large scale, or try to make it look more like a mortar creature?
4. **Should the artillery spitter be a unit OR a worm turret?** As a unit it moves and repositions. As a turret it's placed permanently. Both are interesting for different reasons.


---

## 🌊 Marshland Terrain Effect (Outposts + Fortresses)

### Concept

After an outpost or fortress finishes building all its nests and worms, the ground around it becomes **boggy and waterlogged** — scattered shallow water puddles that spread out organically from the center, densest in a ring around the nest cluster, thinning out at the edges. Not a clean moat. Not a ring. Just the land looking like it got sick.

**Why scattered, not a ring:**
- Feels natural — looks like the nest has been there a long time and the ground rotted
- Still blocks turret placement (can't place on water tiles) without being a perfect wall
- Irregular shapes mean the player has to scout where the dry paths are
- Biters don't care — they pathfind around individual water tiles fine

**Why only after full construction:**
If tiles go down during building, the biters placing nests and worms can't reach the interior positions — their own construction gets blocked. Wait until `nest >= maxNests AND turret >= maxTurrets` — the exact moment the hive goes dormant.

---

### The Hook Point (Same as Before)

The `else` branch at the bottom of `processHives()` — already identified. Add one check:

```lua
else
    if hiveData.isOutpostHive or hiveData.isFortressHive then
        MarshUtils.queueMarshland(hiveData, map, tick)
    end
    Universe.activeHives[entityId] = nil
end
```

---

### Scatter Algorithm

**The core idea:** For each tile position in a ring band around the nest, roll a random number against a probability that peaks in the middle of the band and falls off toward both edges. This produces natural-looking scattered puddles — dense toward the middle of the ring, sparse at the inner and outer edges.

```lua
-- For each tile (x, y) in the scan band:
local dist = math.sqrt((x - cx)^2 + (y - cy)^2)

-- Skip clear zone (nest interior) and outer edge
if dist < MARSH_INNER_RADIUS or dist > MARSH_OUTER_RADIUS then
    -- skip
else
    -- t = 0.0 at inner edge, 1.0 at outer edge
    local t = (dist - MARSH_INNER_RADIUS) / (MARSH_OUTER_RADIUS - MARSH_INNER_RADIUS)
    
    -- sine curve: probability peaks at t=0.5 (middle of ring band), zero at both edges
    local prob = MARSH_DENSITY * math.sin(t * math.pi)
    
    if Universe.random() < prob then
        -- place water-shallow here, if no player entity is on it
        tileBatch[#tileBatch+1] = {name="water-shallow", position={x, y}}
    end
end
```

**Verified numbers (simulated):**
- ~2,000 tiles placed per outpost/fortress (varies with random seed)
- Processing: 2 rows of X per tick = ~55 ticks total = ~0.9 seconds
- Completely invisible in gameplay — no stutter

**Constants:**

| Constant | Outpost | Fortress |
|----------|---------|----------|
| `MARSH_INNER_RADIUS` | 18 tiles | 24 tiles |
| `MARSH_OUTER_RADIUS` | 48 tiles | 72 tiles |
| `MARSH_DENSITY` | 0.35 (35% max probability) | 0.45 (45% max probability) |

Fortress is wider and denser. Outpost is tighter and thinner. Both look like bog, not a wall.

---

### Batching: Row-Per-Tick Iterator

Rampant's entire codebase uses "process one thing per tick" iterators. We follow the same pattern — scan **2 rows of X coordinates per tick**:

```lua
pendingMarshland entry = {
    cx, cy,          -- center tile
    currentRow,      -- which y-offset we're on (starts at -MARSH_OUTER_RADIUS)
    isFortress,      -- controls radius/density constants
    tileBatch = {},  -- accumulated tiles for this row, flushed to surface.set_tiles()
    map,
}

-- Per tick: advance currentRow by 2, process those rows, call surface.set_tiles(tileBatch)
-- When currentRow > MARSH_OUTER_RADIUS: done, remove from pendingMarshland
```

`surface.set_tiles()` accepts an array, so we collect the whole row into a batch and make one API call per tick. Minimizes call overhead.

---

### Pre-Placement Check (Avoid Flooding Player Buildings)

Before placing any tile, check for player entities:

```lua
local checkQuery = {
    position = {x, y},
    radius = 0.4,
    force = Universe.playerForces,
    limit = 1
}
if surface.count_entities_filtered(checkQuery) == 0 then
    tileBatch[#tileBatch+1] = {name="water-shallow", position={x, y}}
end
```

This prevents the marsh from laying water tiles under player turrets that were placed after the nest formed but before the hive finished building.

---

### Gotchas

| # | Gotcha | Fix |
|---|--------|-----|
| 31 | `set_tiles` fires `script_raised_set_tiles` → Rampant rescans chunk passability for each water tile row | Correct behavior — pathfinding updates automatically. Cost: ~55 chunk rescans spread over 55 ticks. Acceptable. |
| 32 | `water-shallow` is the correct tile name in Factorio 1.1 | Verify: Rampant's own `onSurfaceTileChange` uses `sFind(tile.name, "water")` which catches it |
| 33 | `Universe.random()` is the seeded RNG — different results each game, same results on reload | Correct — each outpost/fortress gets a unique scatter pattern, deterministic on save/load |
| 34 | If the player places landfill on the marsh tiles, Rampant already listens to `script_raised_set_tiles` for landfill too — chunk passability updates | Correct behavior — player can dig out a path with landfill, which is the intended counter-play |
| 35 | `pendingMarshland`, `marshId`, `marshlandIterator` must be added to Universe in `onInit` | Standard — same as every other iterator table |
| 36 | Batching 2 rows per tick means tile placement takes ~1 second realtime | That's fine — the nest just finished building, a slow bog-spreading visual is actually cooler than instant placement |
| 37 | Outpost/fortress near map edge — some tiles in the ring will be in ungenerated chunks | `surface.set_tiles` silently skips positions in ungenerated chunks in 1.1 | Accept it — partial marsh on map edges is fine |
| 38 | `hiveData.isOutpostHive` / `isFortressHive` flags set in `OutpostBuilder` / `FortressBuilder` and stored on hiveData in `global.universe` | Persists across save/load automatically |


### Gotchas (Marshland Specific)

| # | Gotcha | Impact | Fix |
|---|--------|--------|-----|
| 31 | `surface.set_tiles` on water tiles fires `script_raised_set_tiles` which Rampant already listens to — triggers chunk passability rescan | Biter pathfinding recalculates (correct behavior, but costs a rescan) | Accept it — it's correct. Chunk passability should update. |
| 32 | Placing `water-shallow` on top of player-built structures (turrets, belts) placed AFTER a fortress is destroyed | Tiles placed under player buildings | Check `surface.count_entities_filtered` on each tile position before placing — skip tiles with player entities on them |
| 33 | `water-shallow` may not stop vehicles on all modded surfaces (Space Age, Krastorio) | Moat is passable by car | Acceptable — this is a 1.1 base game targeting. Mod compat is Phase 2 |
| 34 | Fortress land bridges at cardinal directions assume the map isn't rotated relative to the base — but biters can come from any angle | Bridge positions may not face the player | Fine — cardinal bridges are predictable, which is good UX. Player learns "fortress always has N/S/E/W bridges" |
| 35 | `pendingMarshland` must be added to `global.universe` in `onInit` | Data lost on reload | Add `pendingMarshland = {}`, `marshId = 0`, `marshlandIterator = nil` to Universe init |
| 36 | Laying 400+ tiles in one tick call would cause a visible stutter | UPS spike | Batch at 64 tiles/tick — full ring completes in ~7 ticks, imperceptible |
| 37 | Outpost marshland around a hive that was placed near water already | Double water, potential overlap with existing water | No issue — `set_tiles` on already-water tiles is a no-op effectively |
| 38 | The inner clear radius must never cover the hive itself | Hive gets flooded, becomes impassable for its own spawns | Inner clear radius = `CHUNK_SIZE` (32 tiles) hardcoded — hive spawns within 16 tiles, always inside the clear zone |
| 39 | `hiveData.isOutpostHive` must survive save/load | Flag lost, marshland never triggers | `hiveData` is stored in `Universe.hives` which is in `global` — custom fields on it persist automatically |
| 40 | Artillery spitter size: behemoth sprite needs tint swapping in data stage | New sprite sheet required | Not needed — `makeUnitSpawner`/biter prototype takes `tint` + `scale` fields. Behemoth animation is already in BiterUtils at `scale = 1.8` for tier 10. Just set `scale = 1.8` as the fixed scale for all tiers and override with a new tint. Zero new art assets. |

---

## 🎯 Artillery Spitter — Updated Notes

**Sprite:** Reuse the existing behemoth spitter animation. In BiterUtils, spitter animations are tier-scaled via `attributes.scale`. The artillery spitter just sets a fixed large scale for all tiers (e.g. `scale = 1.4` at tier 1, `scale = 1.8` at tier 10 like a behemoth). Tint from the faction color. Zero new art.

**As a unit vs turret:** Based on your goal of it hanging back and lobbing from range, **unit type is better**. A turret stays where it was placed — the player just walks around it. A unit repositions when its current position gets dangerous, which means it genuinely stays at range from the player. The slowMovement attribute keeps it far back naturally without any code.

**Stat philosophy:** Giant, slow, fragile up close. If the player reaches it, it dies fast. Its survivability comes entirely from the player never being able to reach it through normal turret defenses.

```
Artillery Spitter stat profile:
  scale:        1.4–1.8 (behemoth-sized always)
  health:       lowHealth (×0.6 vs normal spitter — it's a glass cannon)
  movement:     slowMovement (×0.35 speed — can't be chased away quickly)
  range:        20–40 (per tier, way outside normal turret range of ~18)
  damage:       high per shot
  cooldown:     very slow (180–120 ticks = 3–2 seconds between shots)
  explosion:    artillery-shell-explosion on impact
  radius:       4–7 tiles area damage
  weakness:     majorWeaknesses = {"explosion", "physical"}
```


---

## ⚔️ Player Meta Strategies & Counter-Biters

### The Dominant Strategies (What Players Actually Do)

Based on real community discussion, here are the strategies that currently "solve" deathworld/Rampant:

---

#### META 1: Pollution Suppression ("Play Quiet")
**What it is:** Keep pollution so low that biter bases never activate. Use efficiency modules everywhere, solar ASAP, hand-mine early, avoid burning fuel. Biters never attack because they never smell you.

**Why it works:** Rampant's entire attack system is triggered by pollution reaching nests. No pollution = no attacks = infinite time to build. The player essentially opts out of combat entirely until artillery.

**How broken it is:** Very. Players report running entire mid-game without a single attack wave. Rampant's smarter AI still targets players but if evolution stays low enough, the windows are huge.

**Counter-biter idea — The Seeker:**
A unit that specifically homes in on the *player character* rather than following pollution or pheromone gradients. Uses the existing `followsPlayer = true` attribute. Spawns in small groups (2–4) on a separate timer not tied to pollution at all — tied instead to game time elapsed or a low flat rate regardless of pollution level.

- Type: biter unit, `followsPlayer = true`, `smallestHealth`, `quickMovement`
- Spawned by: a new "Tracker" nest building that activates on a time-based heartbeat rather than pollution
- Counter: player can't outrun the game clock by playing quiet
- Balance: very rare, just enough to force the player to maintain at least minimal defenses
- Feasibility: `followsPlayer` already exists in the attribute system. The time-based spawn trigger needs a small runtime hook in `processBase()` — a secondary timer independent of temperament

---

#### META 2: Flamethrower Wall ("Oil Solves Everything")
**What it is:** A wall of flamethrower turrets fed by a single beaconed pumpjack. Flamethrowers do massive DPS, apply burn DoT, and use almost no oil per firing cycle (3/s while firing, nothing while idle). A single pumpjack can feed 13+ turrets. The wall becomes essentially impenetrable and self-sustaining.

**Why it works:** Flamethrowers hit everything in a cone — no targeting priority issues, no armor bypass needed. Fire damage applies to all known Rampant factions. The oil economy is so lopsided that players routinely run their entire perimeter off one or two pumpjacks.

**Counter-biter idea — The Firewalker:**
A biter with extreme fire resistance and a charge behavior that specifically punches through fire lines. High HP, `highestRegen`, major resistance to fire, and a brief immunity window when it first makes contact with a flamethrower stream (simulated by very high fire resistance at lower tiers, partial immunity at higher tiers via resistance values).

Also: **The Firebomber** — a spitter that fires projectiles which *leave oil/fire slicks behind them*, forcing the player to deal with fire on their own side of the wall. Like a reverse flamethrower — it spits fluid that burns the ground in front of the wall, making repair bots and inserters malfunction.

- Firewalker: `highestHealth`, `highestRegen`, `majorResistances = {"fire"}`, appears in fire-heavy faction builds
- Firebomber: spitter unit, `attackAttributes = {"spitFire"}` — already exists as the fire faction's spit. Just needs a variant that specifically targets the wall-adjacent tiles rather than the player
- Feasibility: Firewalker is pure attribute config. Firebomber is a renamed fire-faction spitter — no new code

---

#### META 3: Dragon's Teeth + Turret Creep ("The Standard Wall")
**What it is:** A grid of wall segments placed in front of the main wall in a staggered pattern (dragon's teeth). Biters waste time pathfinding around the teeth, giving turrets more time to fire. Then the player slowly advances this wall toward biter nests — turret creep — using the wall's construction zone to push the frontier outward.

**Why it works:** The teeth dramatically increase biter travel time from outer edge to main wall, essentially multiplying turret effective DPS by 2–3x without any extra investment. Combined with construction bots that auto-repair, the setup is near maintenance-free.

**Counter-biter idea — The Tunneler:**
A biter that specifically attacks walls rather than routing around them. It ignores the teeth entirely — its `target priority` in the unit data is set to prefer `wall` entities — and it chews through 3–4 wall segments per approach, creating a direct lane. Once it creates a gap, normal biters flood through the newly created straight path, bypassing the maze entirely.

Also: **The Blocker** — a large, slow biter that when killed creates a *new wall entity* at its death position. Essentially a biter that when it dies, plugs the gap it was walking through with its own corpse. The player's turrets kill the blocker but the body creates an obstacle they now have to deal with.

- Tunneler: standard biter unit with `highestHealth`, `majorResistances = {"physical"}` (gun turrets do physical) — so guns don't efficiently stop it. The wall-preference targeting is the tricky part: Factorio units don't have configurable target priority in the unit prototype, but the turret-creep approach means this biter is drawn to high player-pheromone areas which walls inherently have
- Blocker: on-death `create-entity` effect placing a neutral `stone-wall` entity. This is feasible via `dying_trigger_effect` in the unit prototype — already demonstrated by the volatileHive idea
- Feasibility: Tunneler is attribute config. Blocker needs a `dying_trigger_effect` that creates an entity — medium effort, doable in data stage

---

#### META 4: Artillery Denial ("Shoot First, Forever")
**What it is:** Once artillery unlocks, the player places artillery outposts on the edge of their territory. Artillery auto-fires at any nest within range, which also triggers revenge attacks — but the artillery kills the nests before the revenge wave arrives. The player essentially auto-clears a buffer zone of several hundred tiles around their base permanently.

**Why it works:** Artillery range (~56 tiles) is greater than any biter attack range. A single artillery piece at each cardinal direction creates a permanent clear zone. Biters that do respond to the shelling arrive at a defended position and die. It's a treadmill that keeps the buffer zone clean indefinitely.

**Counter-biter idea — The Artillery Scout:**
A fast, small biter that is specifically triggered by artillery fire (via `on_entity_damaged` event when the explosion entity damages a nest). It is fast enough to reach the artillery outpost before the next shell fires. Essentially a "counter-battery" unit — when you shell a base, it sends a fast unit directly toward the source of the explosion.

Also: **The Siege Nest** — a nest building that has extreme range (worm-style turret behavior) specifically to reach artillery positions. Placed deep inside biter territory as a "counter-artillery" emplacement. Very high HP. Player has to push into biter territory to destroy it rather than shelling from safety.

- Artillery Scout: `quickMovement` + `lowestHealth` + `followsPlayer = false`, spawned by `on_entity_damaged` hook in control.lua — when artillery shell hits near a nest, spawn 4–8 fast units targeting the shell origin position
- Siege Nest: a new turret prototype with `longReach` (×3 base worm range = ~45 tiles) and `highestHealth`. Placed by the Fortress building type during the fortress construction sequence
- Feasibility: Artillery Scout needs a new runtime event hook (~20 lines in control.lua). Siege Nest is configuration + a new constant in the fortress builder

---

#### META 5: Pollution Island ("Minimal Footprint")
**What it is:** The player keeps their entire factory within a tiny footprint. All pollution is absorbed by trees and land before it reaches any biter nest. Effectively creates a "safe bubble" that never expands. The player uses trains to collect resources from distant patches without bases, and the lack of local pollution keeps attacks minimal.

**Why it works:** If pollution never reaches nests, evolution barely rises and attacks are rare. The player operates indefinitely in a small defended perimeter while running train logistics out to undefended resource patches.

**Counter-biter idea — The Nest Expander:**
A settler-type squad that actively moves *toward* the player's factory rather than being drawn by pollution. Uses its existing `BASE_AI_STATE_MIGRATING` behavior but with a modified score function that weights toward `PLAYER_PHEROMONE` (player activity) instead of `RESOURCE_PHEROMONE` (ore). Essentially biters that colonize closer to you over time, shrinking your safe bubble regardless of pollution management.

Also: **The Signal Worm** — a stationary worm that, instead of attacking, emits a pollution-like signal that attracts other biter squads. Placed by migrating squads near the player's factory. Makes the player's own territory smell like pollution to other biters. Creates a feedback loop: the closer biters settle, the more "signal" builds up, the more attacks are drawn.

- Nest Expander: modify the migration score function in the BehaviorRegistry to use `(PLAYER_PHEROMONE × 50 + RESOURCE_PHEROMONE)` — biters migrate toward player activity not just ore. This is a one-line score function change
- Signal Worm: a turret-type entity with a custom `pollution_absorption_absolute = -50` (negative absorption = it *emits* pollution into the chunk). Factorio supports negative pollution absorption. Placed by settlers. The player can see it on the pollution map as a red hotspot inside their base area
- Feasibility: Nest Expander is a score function tweak. Signal Worm is a data-stage prototype with negative pollution value — novel but fully within Factorio's engine

---

### Summary Table

| Player Meta | Exploit | Counter-Biter | Feasibility |
|-------------|---------|---------------|-------------|
| Pollution suppression | No pollution = no attacks | **Seeker** — time-based spawner, ignores pollution | Low effort — `followsPlayer` exists, needs timer hook |
| Flamethrower wall | Fire solves everything | **Firewalker** (fire immune) + **Firebomber** (reverse fire) | Firewalker = attribute config. Firebomber = existing attack type |
| Dragon's teeth + turret creep | Maze trivializes approach | **Tunneler** (wall destroyer) + **Blocker** (corpse wall) | Tunneler = attributes. Blocker = `dying_trigger_effect` |
| Artillery denial | Outrange everything forever | **Artillery Scout** (counter-battery) + **Siege Nest** (counter-range) | Scout needs event hook. Siege Nest = config |
| Pollution island | Tiny footprint, no signal | **Nest Expander** (migrates toward player not ore) + **Signal Worm** (fake pollution emitter) | Expander = score function tweak. Signal Worm = negative pollution prototype |


---

## 💥 Enemy Bombardment Structures

### The Core Question: Can Biters Place an Artillery Turret?

**Short answer: not directly, but there are two viable approaches.**

**Why direct artillery-turret placement doesn't work:**
The `artillery-turret` type in Factorio has `manual_mode` by default — it only fires when a player explicitly targets something. Enemy-force entities cannot be given player-like remote control. You could place an `artillery-turret` on the enemy force via `surface.create_entity`, but it would just sit there doing nothing. Factorio's artillery firing logic only runs for player-controlled turrets.

---

### Approach A: Scripted Bombardment (Recommended)

**The cleanest solution: don't use the artillery-turret type at all. Script the shots directly.**

Factorio lets you spawn any projectile entity via `surface.create_entity`:

```lua
surface.create_entity({
    name = "artillery-projectile",   -- vanilla projectile entity
    position = structurePosition,    -- where the "cannon" is
    target = targetPosition,         -- where to aim (high-value chunk)
    speed = 1.0,
    force = "enemy"
})
```

This fires a real artillery shell from the structure's position toward a player-pheromone-heavy chunk. It travels through the air visually, lands, and creates the full artillery explosion. **The player sees an incoming arc and hears the artillery sound.** Looks and feels identical to player artillery incoming.

**The structure itself** is just a worm-type turret with zero attack range — purely decorative/targetable. The actual firing is handled by a new `processBombardment()` function in Processor.lua that runs on a slow timer (every 1800–3600 ticks = 30–60 seconds), picks a high-value chunk from `Universe.priorityTargets`, and fires 1–2 shells.

**Integrated with the Priority Targets system we already planned** — the bombardment structure uses the same `priorityTargets` list that the priority strike squads use. It shoots at the highest-production zone on the map.

---

### Approach B: Super-Worm Turret (Simpler, Less Authentic)

Use the existing `turret` type but with extreme range and slow cooldown — essentially a siege worm. Max observed range in Rampant is 40 tiles. With `longReach` (×3 multiplier) = **120 tile range**, which exceeds vanilla artillery (~56 tiles). Use an `artillery-shell-explosion` as the projectile impact. Very slow cooldown (600–1200 ticks = 10–20 seconds between shots).

This is simpler but feels less like "artillery" and more like a very long worm. The projectile arc won't look right at 120 tiles — it'll be very flat. The scripted approach produces a much better result.

---

### Structure Design

**Name: Biter Siege Mortar** (placed by fortress builders)

```
Runtime properties:
  • Worm-type entity, stationary, enemy force
  • High HP (×3 normal worm), high regen
  • No actual attack parameters — purely a target for the player
  • Placed by FortressBuilder alongside the worm ring

Bombardment behavior (scripted):
  • Fires every 1800–3600 ticks (30–60 seconds)
  • Targets the highest-scoring priorityTarget zone
  • Fires 1–2 shells per cycle
  • Stops firing if the structure is destroyed (entity.valid check)
  • Fires toward player structures but has scatter (±5 tiles deviation)
    so it's not pixel-perfect — feels like indirect fire
```

**The scatter is important.** Artillery that always hits exactly the same tile every 30 seconds is an automation problem (just put a chest there). Artillery with ±5 tile scatter hits randomly within a zone — the player has to deal with unpredictable damage rather than engineering around a fixed point.

---

### Gotchas

| # | Gotcha | Fix |
|---|--------|-----|
| 41 | `artillery-projectile` requires a `target` parameter as a position table, not an entity | Pass `{x = chunk.x + 16, y = chunk.y + 16}` (chunk center) |
| 42 | Player receives `on_entity_damaged` revenge trigger when artillery lands — Rampant already handles this (it increments `artilleryBlasts` counter for the base) | When *enemy* artillery fires, we must NOT trigger the player's own revenge logic — check `event.cause.force` before incrementing |
| 43 | `artillery-projectile` entity may not exist in all mod combinations | Check `game.entity_prototypes["artillery-projectile"]` exists on init, fall back to `cannon-shell` if missing |
| 44 | Firing at `priorityTargets` when none exist (early game) | Guard: `if Universe.priorityTargets and #Universe.priorityTargets > 0 then` |
| 45 | Multiple siege mortars all firing at the same tick = shell cluster | Stagger fire times — each mortar stores its own `nextFireTick = placedTick + (mortarId × 900)` so they fire at different offsets |
| 46 | Player can destroy the mortar before it fires — must clean up from bombardment iterator | Already handled — `entity.valid` check before firing |

