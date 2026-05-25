# Rampant 2: Advanced AI & Enemy Overhaul

**Version:** 2.3.0 (Development)  
**Factorio Version:** 2.0+  
**Maintained by:** Antarctic_Singularity

## Overview

Rampant 2 is a comprehensive overhaul of enemy AI in Factorio 2.0, building on the foundation of Rampant 1.1.1 by Veden and significantly expanded by Dimm2101 for Space Age. The mod implements advanced enemy tactics including:

- **Improved Enemy AI** — Potential fields, pheromones, and tactical decision-making
- **Unit Swarming** — Coordinated group behavior and squad formations
- **Tactical Retreats** — Intelligent defensive positioning and regrouping
- **Breaching Behavior** — Strategic assault patterns against player defenses
- **Learning AI** — Biters learn and adapt to player defense structures
- **Multi-Planet Support** — Works across Nauvis, Gleba, and Vulcanus

## Current Features (v2.3.0)

### Phase 1: Zone Intelligence System
The mod now analyzes the game world through a strategic zone-based system:

- **Zone Scanning** — Map divided into 320×320 tile zones for production analysis
- **Production Analysis** — Automatically scans assemblers, furnaces, mining drills, and power generation
- **Zone Categorization** — Zones classified as raw-resources, oil, products, power, or outposts
- **Product Tier Weighting** — Advanced items (blue science, processing units) prioritized over basic items
- **Priority Targeting** — Identifies the top 3 highest-production zones as priority targets
- **Real-time Updates** — Continuous scanning with ranking refresh every ~2.7 minutes
- **Strike System** — Coordinated AI attacks on high-value production zones (enabled at 20% evolution)
  - Random category selection from available zone types
  - Multi-squad deployment (3 squads per strike)
  - 15-minute cooldown between strikes
  - Alert notifications to players with GPS links

### Debug System
Comprehensive debug tools for development and testing:

```
r2-zones        Print zone production statistics
r2-zones-draw   Draw zone grid overlay on map (with category, production, cache status)
r2-targets      Print priority target details
r2-targets-draw Draw priority target circles with rankings
r2-clear        Clear all debug overlays
r2-status       Print zone scanning and strike system status
r2-scan-here    Scan entities at player location and show zone state
r2-scan-power   Scan total power generation on surface
r2-rescan       Force immediate zone rescan (queued over 4 passes)
r2-super-rescan DANGER: Rescan ALL zones instantly (game will freeze)
r2-structures   Find enemy production structures
r2-menu         Open debug GUI
r2-surfaces     Configure which surfaces to process
r2-aistate      Set AI aggression state (1-8)
r2-mutate       Force all bases to mutate
```

## Dependencies

**Required:**
- base >= 2.0.0

**Optional:**
- space-age (for Vulcanus/Gleba planet features)
- Arachnids, ArmouredBiters, Explosive_biters (faction support)
- Krastorio2, RampantArsenalFork, SchallAlienLoot

**Incompatible:**
- Rampant (original 1.x)
- combat-mechanics-overhaul
- intelligent-enemy

## Development Roadmap

The mod is implementing a 10-phase overhaul plan:

- **Phase 1-3** ✅ Zone Intelligence (COMPLETE)
  - Zone scanning and production analysis
  - Target ranking system
  - Debug visualization tools

- **Phase 4-7** 🔄 Modular AI Architecture (PLANNED)
  - BehaviorRegistry for pluggable AI tactics
  - Priority squad deployment system
  - Flexible squad behavior configuration

- **Phase 8-9** 🔄 Structural Systems (PLANNED)
  - Outposts: Fast, disposable forward bases
  - Fortresses: Heavily defended siege strongholds

- **Phase 10** 🔄 Enemy Refinement (PLANNED)
  - Demolisher Biters (nuclear → artillery-scale explosions)
  - Balance tuning across all enemy types

## Configuration

### Mod Settings
- Zone size (default: 10×10 chunks = 320×320 tiles)
- Production analysis interval
- Priority target count (default: 3)
- Enable/disable specific enemy types

See `settings.lua` for all available startup and runtime settings.

## Technical Details

### Architecture
- **One-per-tick Iterator Pattern** — Zones and ranking use low-cost incremental processing
- **Save/Load Compatible** — Full support for existing saves
- **Factorio 2.0 API** — Uses `prototypes`, `storage`, `rendering` system

### File Structure
```
libs/
  ZoneManager.lua       Zone grid, 4-phase scanning (assemblers, furnaces, drills, power)
  StrikeTargeting.lua   Zone categorization, target ranking, product tier weighting
  StrikeManager.lua     Coordinated strike deployment with cooldowns and alerts
  DebugCommands.lua     Overlays and console output
  Constants.lua         Zone configuration constants
  [existing libs...]
  
control.lua            Main event handlers, tick loop integration
settings.lua           Mod settings (including debug strike info option)
locale/en/locale.cfg   Localization strings
info.json              Mod metadata and dependencies
changelog.txt          Version history
```

## Changelog

See [changelog.txt](changelog.txt) for full version history.

**v2.03.0** — Zone Intelligence System (May 2026)
- Zone scanning and production analysis
- Target ranking with relative share calculation
- Debug system with map overlays
- Concise debug commands (r2-*)

**v2.02.05-2.02.02** — Various balance and bugfixes

## Contributing

This is a community project under development. Contributions and feedback are welcome!

## License

GNU General Public License v3.0 - See LICENSE.md for details

## Credits

- **Original Rampant** — Veden
- **Space Age Port & Expansion** — Dimm2101
- **Current Maintenance** — Antarctic_Singularity
- **Phase 1 Implementation** — Claude Code + Nathan Ramos (2026)
