# Changes Made - Strike System Implementation (May 2026)

## Summary
Complete implementation of the Strike Targeting System for Rampant 2, enabling coordinated AI attacks on player production zones with cooldowns, category-based targeting, and player alerts.

---

## NEW FILES CREATED

### `libs/StrikeManager.lua` (171 lines)
**Purpose:** Manage coordinated strike deployment with cooldowns and alerts

**Key Functions:**
- `strikeManager.initStrikes(map)` - Initialize strike state on map creation
- `strikeManager.processStrikes(map, surface)` - Main strike processing loop
  - Checks evolution threshold (20% = enabled)
  - Validates cooldown (15 min between strikes)
  - Randomly rolls category from available zones
  - Selects best target in category via `strikeTargeting.selectStrikeTargetInCategory()`
  - Deploys 3 squads via `unitGroupUtils.createSquad()`
  - Creates alert with GPS coordinates
  - Sets cooldown and logs debug info

**Configuration Constants:**
- `STRIKE_COOLDOWN_DURATION = 54000` ticks (15 minutes)
- `STRIKE_ENABLED_EVOLUTION = 0.20` (20%)
- `SQUADS_PER_STRIKE = 3`
- `STRIKE_ICON = "rampant-strike-icon"`

**Strike State Tracking (map.strikeState):**
- `cooldownEndTick` - When cooldown expires
- `lastStrikeCategory` - Category of last strike
- `lastStrikeTarget` - Target zone of last strike
- `enabled` - Whether strikes are active

---

## MODIFIED FILES

### `control.lua`

#### Line 45: Added Import
```lua
local strikeManager = require("libs/StrikeManager")
```

#### Lines 226-228: Initialization in on_init
```lua
if not map.zones then
    zoneManager.initZones(map)
    strikeManager.initStrikes(map)
    map.priorityTargets = {}
```

#### Lines 339-341: Initialization in on_load
```lua
zoneManager.initZones(map)
strikeManager.initStrikes(map)
map.priorityTargets = {}
```

#### Lines 1525-1527: Processing in on_nth_tick(120)
```lua
if universe and universe.activeMap then
    zoneManager.processZoneScan(universe.activeMap, universe.activeMap.surface)
    strikeManager.processStrikes(universe.activeMap, universe.activeMap.surface)
```

#### Lines 2107-2115: New /r2-status Command
```lua
local function r2StatusCmd(event)
    local map = universe.activeMap
    if not map then
        game.print("No active map")
        return
    end
    debugCommands.printScanStatus(map)
end
commands.add_command('r2-status', "Print zone scanning and strike system status", r2StatusCmd)
```

### `libs/DebugCommands.lua`

#### Lines 179-186: Added Defensive Initialization in printZoneStats()
```lua
for _, zone in ipairs(map.zonesByIndex) do
    zone.scanPhase = zone.scanPhase or 0
    zone.totalRate = zone.totalRate or 0
    zone.powerGen = zone.powerGen or 0
    scanPhases[zone.scanPhase + 1] = scanPhases[zone.scanPhase + 1] + 1
```
**Reason:** Prevents "attempt to perform arithmetic on nil" error when loading old saves without these fields.

#### Lines 385-452: New Function - printScanStatus()
```lua
function debugCommands.printScanStatus(map)
```
**Prints:**
- Total zones and iterator position
- Phase distribution (0/1/2/3)
- Cached/expired/dirty zone counts
- Current zone being scanned
- Force rescan status
- Strike cooldown remaining time
- Strikes enabled status

### `settings.lua`

#### Lines 618-624: New Debug Setting
```lua
{
    type = "bool-setting",
    name = "rampantFixed--debugStrikeTargeting",
    setting_type = "runtime-global",
    default_value = false,
    order = "m[total]-d5[ai]zz",
    per_user = false
},
```
**Purpose:** Enable/disable strike debug output to chat

### `locale/en/locale.cfg`

#### Line 207: Added Setting Name
```
rampantFixed--debugStrikeTargeting=DEBUG: Print Strike Targeting Information to Chat
```

#### Line 328: Added Setting Description
```
rampantFixed--debugStrikeTargeting=Prints strike targeting information to chat including category rolls, target selection, squad deployment, and cooldown tracking.
```

### `README.md`

#### Lines 20-30: Updated Phase 1 Features
Added Strike System documentation:
- Strike activation at 20% evolution
- Random category selection
- 3-squad deployment
- 15-minute cooldown
- Alert notifications with GPS links

#### Lines 28-42: Expanded Debug Commands
Added new commands:
- `r2-status` - Scanning and strike status
- `r2-scan-here` - Scan at player position
- `r2-scan-power` - Power generation audit
- `r2-rescan` - Queued rescan
- `r2-super-rescan` - Instant rescan

#### Lines 97-110: Updated File Structure
Added:
- `StrikeManager.lua` - Strike deployment
- `StrikeTargeting.lua` - Category and ranking

### `changelog.txt`

#### Lines 7-50: Comprehensive v2.3.0 Entry
**Features section:**
- Zone categorization system
- Product tier weighting details
- Strike System with all mechanics
- Outpost detection logic
- Power override behavior

**Infrastructure section:**
- All new modules listed
- Integration details
- Save/load compatibility notes

**Debug Commands section:**
- Complete command reference
- r2-status command details

**Settings section:**
- New debug setting documented

---

## BEHAVIORAL CHANGES

### Strike System Logic
1. **Disabled until 20% evolution** - Strikes remain inactive in early game
2. **Category validation** - Only rolls from categories with actual zones (prevents invalid strikes)
3. **Cooldown enforcement** - 15 minutes between strikes (prevents spam)
4. **Target prioritization** - Selects highest-value target in chosen category
5. **Multi-squad deployment** - Always deploys exactly 3 squads to target location
6. **Player alerts** - Shows notification with GPS link and custom icon
7. **Debug output** - Prints strike info when `rampantFixed--debugStrikeTargeting` is enabled

### Debug Output When Enabled
```
Strike targeting enabled at XX% evolution
[Strike] Category rolled: [category name]
[Strike] Target: [category] at [gps=X,Y,surface]
[Strike] Deployed 3 squads to target
[Strike] Cooldown set for 15 minutes
```

### Scanning Diagnostics
`/r2-status` output includes:
```
=== ZONE SCANNING STATUS ===
Total zones: N
Current iterator: X / N
Phase distribution: 0=X 1=Y 2=Z 3=W
Cached zones (current): N
Expired zones (need rescan): N
Dirty zones (immediate): N
Current zone: [zx,zy] phase=X
Force rescan: [status]
Strike cooldown: X min remaining
Strikes enabled: [yes/no]
```

---

## SAVE COMPATIBILITY

**Defensive Initialization Added:**
- `DebugCommands.lua` - printZoneStats() now safely handles missing zone fields
- `StrikeManager.lua` - initStrikes() creates strikeState with all required fields
- All field accesses use `field = field or default_value` pattern

**Result:** Old saves load without errors, new fields auto-initialized on first access.

---

## CONFIGURATION SUMMARY

**New Settings:**
- `rampantFixed--debugStrikeTargeting` (bool, default: false, runtime-global)

**New Constants (in StrikeManager):**
- `STRIKE_COOLDOWN_DURATION` = 54,000 ticks (15 minutes at 60 ticks/sec)
- `STRIKE_ENABLED_EVOLUTION` = 0.20 (20% evolution)
- `SQUADS_PER_STRIKE` = 3
- `STRIKE_ICON` = "rampant-strike-icon"

**New Commands:**
- `/r2-status` - Print zone scanning and strike system status

---

## TESTING CHECKLIST

- [ ] Delete `sing-rampant2_2.3.0.zip` from mods folder (fixes loading error)
- [ ] Load existing save - verify no errors, new fields initialized
- [ ] Reach 20% evolution - verify "Strike targeting enabled" message
- [ ] Run `/r2-status` - verify all diagnostics print correctly
- [ ] Wait for strike - verify cooldown expires and strike deploys
- [ ] Enable debug setting - verify strike info prints to chat
- [ ] Run `/r2-zones` - verify no "attempt to perform arithmetic on nil" error
- [ ] Check zone with no category - verify strikes don't roll missing categories

---

## Integration Points

**Tick Loop Integration:**
- `on_nth_tick(120)` - Runs every 2 seconds alongside zone scanning

**Map Initialization:**
- `on_init` event - Creates strikeState
- `on_load` event - Restores strikeState

**State Persistence:**
- Stored in `map.strikeState` (auto-saved with game)

**Dependencies:**
- Requires: `ZoneManager`, `StrikeTargeting`, `UnitGroupUtils`, `CustomAlerts`
- Used by: Strike category rolling, target selection, squad creation, alerts

---

## Bug Fixes

**Evolution Factor API Access (Fixed)**
- **Issue:** Incorrect API usage for accessing evolution factor in Factorio 2.0
- **Error:** "LuaForce doesn't contain key evolution_factor" / "LuaForce doesn't contain key evolution"
- **Root Cause:** Evolution factor is not a direct property; requires method call with surface parameter
- **Fix:** Changed to `game.forces.enemy.get_evolution_factor(surface)`
- **Location:** StrikeManager.lua line 36
- **Reference:** Matches AIPlanning.lua line 92 (existing codebase pattern)
- **Commits:** 
  - c078b9d "Fix evolution factor property name in StrikeManager"
  - 9bb1f3a "Fix evolution factor access to use correct Factorio 2.0 API"

**Alert Icon Specification (Fixed - Multiple Attempts)**
- **Attempt 1 Issue:** Used non-existent virtual icon name "rampant-strike-icon"
  - **Error:** "Unknown virtual-signal name: rampant-strike-icon"
  - **Fix:** Removed non-existent virtual icon, removed STRIKE_ICON constant
  - **Commit:** 1ae9eb3 "Fix alert icon - use entity icon instead of non-existent virtual signal"

- **Attempt 2 Issue:** Passed `nil` for required icon parameter
  - **Error:** "value for required parameter 2 (icon) is missing"
  - **Fix:** Changed to valid entity icon specification: `{type = "entity", name = "biter-spawner"}`
  - **Location:** StrikeManager.lua line 136-141
  - **Commit:** 6528d34 "Fix alert icon specification - use valid entity icon"
  
- **Root Cause:** `add_custom_alert()` requires icon parameter (cannot be nil or invalid)

---

## Code Quality Notes

**Defensive Programming:**
- All zone field accesses check for nil (save migration safety)
- Early returns prevent invalid strikes (no categories)
- Checks for valid targets before deployment
- Validates entity validity before using for alerts

**Performance:**
- Strike processing runs every 120 ticks (minimal overhead)
- No full-map scanning for strikes (uses existing zone data)
- Alert creation uses temporary entity (cleaned up immediately)

**Debugging:**
- Comprehensive debug output when setting enabled
- GPS coordinates for all strikes (easy navigation)
- Status command shows full system state
