# RampantFixed Mod Settings Documentation

A comprehensive guide to all mod settings for RampantFixed 2.02.04. This document provides detailed explanations of what each setting does and how it affects gameplay.

---

## Table of Contents
1. [Wave Attack Settings](#wave-attack-settings)
2. [Squad & Builder Control](#squad--builder-control)
3. [Corpse & Fade Settings](#corpse--fade-settings)
4. [Enemy Type Selection](#enemy-type-selection)
5. [Enemy Tier Configuration](#enemy-tier-configuration)
6. [Enemy Faction Settings](#enemy-faction-settings)
7. [AI Behavior & Difficulty](#ai-behavior--difficulty)
8. [AI Special Abilities](#ai-special-abilities)
9. [Building Safety Settings](#building-safety-settings)
10. [Optimization Settings](#optimization-settings)
11. [Unit Stats Scaling](#unit-stats-scaling)
12. [Player Interface Settings](#player-interface-settings)
13. [Compatibility & Advanced](#compatibility--advanced)

---

## Wave Attack Settings

### `rampantFixed--disableCollidingProjectiles`
**In-Game Name:** Projectiles: Non biter force colliding projectiles  
**Better Name:** Disable Biter Projectile Collisions  
**Type:** Boolean (True/False)  
**Default:** Enabled (True)  
**Scope:** Startup  
**Description:**
When enabled, biter projectiles (acid spit, etc.) will NOT collide with other biters, worms, or nests. This means biter attacks pass through their own units to reach the player's defenses. Player structures and the player themselves still collide with all projectiles. Useful for realistic battle physics where enemies don't accidentally damage allies.

---

### `rampantFixed--attackWaveMaxSize`
**In-Game Name:** Attack Wave: Max biter group size that can be directly formed  
**Better Name:** Maximum Attack Wave Group Size  
**Type:** Integer  
**Default:** 75  
**Range:** 20 - 600  
**Scope:** Runtime-Global  
**Description:**
Controls the maximum number of biters that can be in a single attack group. This is the base size before evolution scaling is applied. Larger values make attacks bigger and more threatening. Does NOT affect vanilla biter waves, only Rampant's AI attacks. Increasing this makes late-game attacks significantly harder. Recommended values: 50-100 for casual, 200+ for hardcore.

---

### `rampantFixed--attackWaveMaxSizeEvoPercent`
**In-Game Name:** Attack Wave: The maximum wave size starts with the % of evolution  
**Better Name:** Evolution Percentage for Max Wave Size  
**Type:** Integer  
**Default:** 100  
**Range:** 5% - 100%  
**Scope:** Runtime-Global  
**Description:**
Determines at what evolution percentage the attack waves reach their maximum size. Lower values mean max-sized attacks start appearing earlier in the game. At 100%, waves reach max size at 100% evolution. At 50%, waves reach max size at 50% evolution. This affects difficulty progression throughout your game.

---

### `rampantFixed--agressiveStart`
**In-Game Name:** Attack Wave: agressive start  
**Better Name:** Early Game Aggressive Attacks  
**Type:** Boolean (True/False)  
**Default:** Disabled (False)  
**Scope:** Runtime-Global  
**Description:**
When enabled, the AI calculates attack wave frequency and size as if the game has 30% evolution from the start. This 30% threshold is normally reached after about 1 hour of gameplay. Enabling this makes early-game attacks much more frequent and dangerous, effectively removing the early game "grace period." Only recommended for experienced players.

---

### `rampantFixed--attackWaveGenerationUsePlayerProximity`
**In-Game Name:** Attack Wave: Use Player Proximity as attack trigger  
**Better Name:** Player Proximity Affects Attack Triggers  
**Type:** Boolean (True/False)  
**Default:** Enabled (True)  
**Scope:** Runtime-Global  
**Description:**
When enabled, the player's presence and activities ("pheromones") contribute to the likelihood of attack waves spawning in nearby chunks. Disabling this means attacks are triggered purely by pollution, not by player presence. With this enabled, hiding far away from your factory can reduce attack frequency. Useful for exploration-focused play.

---

### `rampantFixed--attackPlayerThreshold`
**In-Game Name:** Attack Wave: Player score contribution threshold  
**Better Name:** Player Pheromone Impact Threshold  
**Type:** Double  
**Default:** 20  
**Range:** 0 and above  
**Scope:** Runtime-Global  
**Description:**
Controls how much the player's activities contribute to attack generation. Higher values reduce player pheromone impact on attacks. If set to 100, player presence has minimal effect on triggering attacks. The default of 20 means player activities significantly increase attack likelihood in nearby chunks. Increase this to make distance more effective at avoiding attacks.

---

## Squad & Builder Control

### `rampantFixed--maxNumberOfSquads`
**In-Game Name:** Attack Wave: Max number of attack groups that can be active at once  
**Better Name:** Maximum Simultaneous Attack Squads  
**Type:** Integer  
**Default:** 30  
**Range:** 1 - 30  
**Scope:** Runtime-Global  
**Description:**
Limits the maximum number of independent attack groups (squads) that can exist simultaneously on the map. Each squad is a group of biters attacking different targets. Higher values mean more simultaneous attacks happening at once, making combat more chaotic and difficult. This directly affects CPU/UPS usage. Values above 15 can cause noticeable performance issues on large maps.

---

### `rampantFixed--maxNumberOfBuilders`
**In-Game Name:** Attack Wave: Max number of settler groups that can be active at once  
**Better Name:** Maximum Simultaneous Builder Groups  
**Type:** Integer  
**Default:** 35  
**Range:** 1 - 120  
**Scope:** Runtime-Global  
**Description:**
Limits the maximum number of "builder" groups (biters that are constructing nests and expanding territory) active at once. These groups expand biter bases toward the player and along pollution clouds. Higher values mean faster biter expansion and more aggressive nest building. This heavily impacts UPS. Lowering this to 10-20 can improve performance significantly without much difficulty loss.

---

## Corpse & Fade Settings

### `rampantFixed--unitAndSpawnerFadeTime`
**In-Game Name:** Biter, Spitter, Worm, Nest, and Hive Corpse Fade Time  
**Better Name:** Corpse Despawn Duration (in ticks)  
**Type:** Integer  
**Default:** 300 (5 minutes)  
**Range:** 1 - 1,800,000,000 ticks  
**Scope:** Startup  
**Description:**
Controls how long dead biters, spitters, worms, nests, and hives remain on the map before disappearing. Value is in game ticks (60 ticks = 1 second). Default of 300 ticks = 5 seconds. Higher values = bodies stay longer. This affects visual clutter and memory usage in long games. Set to 1 for immediate despawn, 18000 (5 minutes) for realistic decay.

---

### `rampantFixed--enableFadeTime`
**In-Game Name:** Enable corpse fade time  
**Better Name:** Enable Automatic Corpse Despawn  
**Type:** Boolean (True/False)  
**Default:** Enabled (True)  
**Scope:** Startup  
**Description:**
Master toggle for corpse despawning. When enabled, dead units disappear according to the fade time setting above. When disabled, corpses persist indefinitely. Disabling improves visibility of battles and makes it easier to see unit diversity, but can cause lag in prolonged battles with many corpses.

---

## Enemy Type Selection

### `rampantFixed--newEnemies`
**In-Game Name:** World: Enable new enemies  
**Better Name:** Enable Rampant Unique Enemy Factions  
**Type:** Boolean (True/False)  
**Default:** Enabled (True)  
**Scope:** Startup  
**Description:**
Master toggle for all new enemy types added by RampantFixed (Acid, Laser, Electric, Fire, Poison, etc.). When disabled, only vanilla Factorio biters appear. Enabling adds significant variety and challenge. Each faction has unique behaviors, resistances, and abilities. Disabling saves RAM (can require 2-9GB additional RAM depending on variations/tiers). Only works in new games.

---

### `rampantFixed--allowOtherEnemies`
**In-Game Name:** World: Allow other enemies, new factions only from the specified side  
**Better Name:** Allow Non-Rampant Mods' Enemies to Spawn  
**Type:** Boolean (True/False)  
**Default:** Disabled (False)  
**Scope:** Startup  
**Description:**
When enabled, allows other mods' enemy types to spawn naturally in the world (respects the side restriction below). When disabled, vanilla nests are replaced with Rampant factions. Only works in new games. Useful if you want enemies from other mods mixed with Rampant's. The `newEnemiesSide` setting controls which side of the map each faction appears on.

---

### `rampantFixed--newEnemiesSide`
**In-Game Name:** World: settle the factions on the selected side  
**Better Name:** Map Side Distribution for Enemy Factions  
**Type:** String (Dropdown)  
**Default:** MIXED  
**Allowed Values:** MIXED, NORTH, EAST, SOUTH, WEST, NORTH-EAST, SOUTH-EAST, SOUTH-WEST, NORTH-WEST  
**Scope:** Startup  
**Description:**
Determines which map direction(s) the new enemy factions spawn in. MIXED means factions spawn everywhere. Directional options concentrate specific factions to certain parts of the map. Only works when `allowOtherEnemies` is enabled. Useful for creating regional threats or separating enemy types. NORTH = factions primarily north of starting position.

---

## Enemy Tier Configuration

### `rampantFixed--tierStart`
**In-Game Name:** World: Beginning enemy level  
**Better Name:** Minimum Enemy Tier Level  
**Type:** Integer  
**Default:** 1  
**Range:** 1 - 10  
**Scope:** Startup  
**Description:**
Controls the weakest enemy tier that can appear in the game. Tier 1 biters have ~15 HP, Tier 5 have ~1000 HP, Tier 10 have ~30,000 HP. Starting with tier 2+ makes early game harder. This setting scales linearly with evolution - as evolution increases, enemy tiers gradually advance from `tierStart` to `tierEnd`. Only works with new enemies enabled.

---

### `rampantFixed--tierEnd`
**In-Game Name:** World: Ending enemy level (recommended = 5)  
**Better Name:** Maximum Enemy Tier Level  
**Type:** Integer  
**Default:** 5  
**Range:** 1 - 10  
**Scope:** Startup  
**Description:**
Controls the strongest enemy tier that can appear. Tier 5 is slightly weaker than vanilla biters at 100% evolution, Tier 10 is extreme. As evolution increases from 0% to 100%, enemies gradually advance from `tierStart` tier to `tierEnd` tier. Setting to 5 is recommended for a balanced experience. Higher tiers make late-game exponentially harder. Only works with new enemies enabled.

---

### `rampantFixed--max-evo-dist`
**In-Game Name:** World: Threshold for maximum evolution factor by distance  
**Better Name:** Distance Modifier for Max Tier Spawning  
**Type:** Integer  
**Default:** 9600 (160 chunks from center)  
**Range:** 1000 - 1,000,000  
**Scope:** Startup  
**Description:**
Controls how far from the center of the map biters must be to spawn at maximum tier level. Lower values mean top-tier enemies appear close to start. Higher values mean they only appear far away. Set in tiles (1 chunk = 32 tiles). Default 9600 tiles = 300 chunks. Useful for controlling where you encounter the toughest enemies.

---

### `rampantFixed--newEnemyVariations`
**In-Game Name:** World: Enemy Variations (highly recommended = 1). Obsolete  
**Better Name:** Visual Variations Per Enemy Tier (Obsolete)  
**Type:** Integer  
**Default:** 1  
**Range:** 1 - 20  
**Scope:** Startup  
**Description:**
OBSOLETE SETTING - No longer affects gameplay. Kept for compatibility. In older versions, this controlled how many visual variations of each enemy type existed. Set to 1 for best compatibility.

---

## Enemy Faction Settings

These settings enable/disable specific custom enemy factions. All are startup settings and only work with "Enable new enemies" active.

### Tier 1 Enemies

#### `rampantFixed--acidEnemy`
**In-Game Name:** World: T1 Acidic Biter Faction  
**Better Name:** Enable Acid Biters  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Biters and Spitters that are immune to acid damage and resistant to poison. Weak to fire and laser. Their acid attacks ignore armor.

---

### Tier 2 Enemies

#### `rampantFixed--laserEnemy`
**In-Game Name:** World: T2 Laser Biter Faction  
**Better Name:** Enable Laser Biters  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Both Biters and Spitters with major laser resistance and minor electric resistance. Have overdamage protection (25% max HP damage limit). Weak to physical damage.

---

#### `rampantFixed--electricEnemy`
**In-Game Name:** World: T2 Electric Biter Faction  
**Better Name:** Enable Electric Biters  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Only Biters with short-range attacks that hit multiple entities in a line (chain lightning). Major resistance to electrical damage, minor laser resistance. Building immunity setting protects against their attacks.

---

#### `rampantFixed--fastEnemy`
**In-Game Name:** World: T2 Fast Biter Faction  
**Better Name:** Enable Fast Movement Biters  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Fast-moving biters with minor explosive resistance. Have overdamage protection (25% max HP) and long-range immunity (20+ tile range attacks are 90% blocked). Harder to kite.

---

#### `rampantFixed--suicideEnemy`
**In-Game Name:** World: T2 Suicide Biter Faction  
**Better Name:** Enable Exploding Biters  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Biters that explode when attacking, dealing area damage. Fast, low HP, minor poison/fire resistance, major explosive weakness. Long-range immunity (18+). Prioritize with long-range weapons.

---

### Tier 3 Enemies

#### `rampantFixed--waspEnemy`
**In-Game Name:** World: T3 Wasp Biter Faction  
**Better Name:** Enable Wasp Spitter Faction  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Spitters only. Each spitter attack spawns small flying drone units. These drones can reach areas walls can't protect. Very threatening when multiple spawners are active.

---

#### `rampantFixed--spawnerEnemy`
**In-Game Name:** World: T3 Spawner Biter Faction  
**Better Name:** Enable Egg-Laying Spitter Faction  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Spitters that lay eggs which hatch into biters. Only spawns spitter units. Have long-range immunity (30+ range attacks are heavily reduced). Hives are the main threat, not individual biters.

---

#### `rampantFixed--trollEnemy`
**In-Game Name:** World: T3 Regenerative Biter Faction  
**Better Name:** Enable Self-Healing Biters  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Biters with extremely high health regeneration. Major fire weakness, minor physical resistance. Have overdamage protection (20% max HP). Fire and acid attacks are essential for killing them.

---

#### `rampantFixed--energyThiefEnemy`
**In-Game Name:** World: T3 Sapper Biter Faction  
**Better Name:** Enable Power-Draining Sappers  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Biters with major electric and minor laser resistance. When you destroy their powered structures, they leave behind energy-draining crystals that damage your power network. Dangerous for base sabotage.

---

### Tier 4 Enemies

#### `rampantFixed--fireEnemy`
**In-Game Name:** World: T4 Fire Biter Faction  
**Better Name:** Enable Fire Stream Biters  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Biters and Spitters that attack with fire streams, igniting everything. Fire and acid immune. Laser weakness. Major acid resistance. Extremely dangerous with flamethrowers disabled.

---

#### `rampantFixed--ArachnidsEnemy`
**In-Game Name:** World: T4 Arachnids Biter Faction  
**Better Name:** Enable Spider-Like Arachnids  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Spider-looking enemies (requires Arachnids mod graphics to look right). 2x vulnerable to physical damage. On death, lay eggs that hatch into biters after 5 seconds. Eggs are physically weak. Designed to force ammunition consumption.

---

### Tier 5 Enemies

#### `rampantFixed--physicalEnemy`
**In-Game Name:** World: T5 Armored Biter Faction  
**Better Name:** Enable Heavily Armored Biters  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Only Biters with extreme physical and explosive armor. Minor fire weakness, minor laser/electric weakness. Have overdamage protection (50% max HP limit). Explosive and laser weapons highly recommended.

---

### Tier 6 Enemies

#### `rampantFixed--infernoEnemy`
**In-Game Name:** World: T6 Inferno Biter Faction  
**Better Name:** Enable Flaming Acid Spitters  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Spitters only that spit flaming acid, burning everything. Extreme resistance to fire and acid. Weak to poison. Major laser weakness. Poison turrets are most effective. Very dangerous in groups.

---

#### `rampantFixed--poisonEnemy`
**In-Game Name:** World: T6 Poison Biter Faction  
**Better Name:** Enable Poison Cloud Biters  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Only Biters. On death, create healing poison clouds that restore other biter health while damaging player structures. Major poison resistance, minor fire resistance. Weak to laser and electric. Must destroy quickly.

---

### Tier 7 Enemies

#### `rampantFixed--nuclearEnemy`
**In-Game Name:** World: T7 Nuclear Biter Faction  
**Better Name:** Enable Exploding Nuclear Biters  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Only Biters that explode like atomic bombs. Fast, low HP, major acid/fire resistance, major explosive weakness. Have overdamage protection (20% max HP). Explosive weapons highly recommended. High-risk, high-reward targets.

---

### Tier 9 Enemies

#### `rampantFixed--JuggernautEnemy`
**In-Game Name:** World: T9 Juggernaut Biter Faction  
**Better Name:** Enable Juggernaut Boss Biters  
**Type:** Boolean  
**Default:** Enabled  
**Description:** Slowly-moving, massive biters with extreme physical, acid, and fire resistance. Use cloud attacks that heal allies and damage enemies. Ultimate DPS check - requires concentrated laser fire or extreme firepower. Appear at 82%+ evolution.

---

### Special Features

#### `rampantFixed--unitSpawnerBreath`
**In-Game Name:** World: Unit Nest breath air  
**Better Name:** Nests Affected by Environmental Damage  
**Type:** Boolean (Startup)  
**Default:** Enabled  
**Scope:** Startup  
**Description:** When enabled, nests "breathe" air and are affected by things like poison capsules. Poison gas damage becomes effective against nests. Disabling makes nests immune to poison environmental effects.

---

#### `rampantFixed--enableSwarm`
**In-Game Name:** Attack Wave: Enable the swarm  
**Better Name:** Enable Swarm Behavior (Reduced Unit Collision)  
**Type:** Boolean  
**Default:** Enabled  
**Scope:** Startup  
**Description:** When enabled, reduces the collision size of units, allowing them to move through each other more easily. This creates smoother, less-clunky attack waves and improves pathfinding. Has significant performance benefits. Disabling makes attacks more "chunky" but increases collision interactions.

---

#### `rampantFixed--enableShrinkNestsAndWorms`
**In-Game Name:** Attack Wave: Shrink Nests and Worms  
**Better Name:** Reduce Nest/Worm Collision Box Size  
**Type:** Boolean  
**Default:** Enabled  
**Scope:** Startup  
**Description:** Reduces the collision hitbox of nests and worms by 50%. Makes them smaller targets but can cause visual overlapping since the collision box is now smaller than the graphics. Useful for squeezing more nests into areas without them blocking each other.

---

#### `rampantFixed--oldRedEnemyMapColor`
**In-Game Name:** Map: Revert Enemy Map Color  
**Better Name:** Use Vanilla Red Map Color for Enemies  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Startup  
**Description:** Uses the original vanilla Factorio red color for enemies on the map instead of the default purple. Purely cosmetic preference.

---

## AI Behavior & Difficulty

### `rampantFixed--aiDifficulty`
**In-Game Name:** AI: Difficulty  
**Better Name:** Overall AI Difficulty Level  
**Type:** String (Dropdown)  
**Default:** Hard  
**Allowed Values:** Hard, Lite  
**Scope:** Runtime-Global  
**Description:**
Controls overall AI aggression and response quality.
- **Hard:** Default difficulty with full AI capabilities. Enemies respond quickly to player actions and attacks.
- **Lite:** Reduced AI intelligence. Fewer attacks, slower response times, attacks less frequent. Better for casual play.

---

### `rampantFixed--aiPointsScaler`
**In-Game Name:** AI: Action points scaling  
**Better Name:** AI Action Points Multiplier  
**Type:** Double  
**Default:** 1.0  
**Range:** 0.0 - 100.0  
**Scope:** Runtime-Global  
**Description:**
Multiplies the action points the AI gets per game tick to perform actions (spawn attacks, build nests, etc.). 
- 0.3 = Very Easy
- 0.75 = Easy
- 1.0 = Medium (default)
- 1.25+ = Hard
Fractional values provide fine-tuning. Increase for more aggressive AI with faster decision-making and attacks.

---

### `rampantFixed--permanentNocturnal`
**In-Game Name:** AI: Nocturnal Mode  
**Better Name:** Force Night-Only Attacks  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Runtime-Global  
**Description:** When enabled, Rampant attack waves only spawn during night time (respects day/night cycles). Useful with mods that extend night duration. Doesn't affect vanilla biters. Works better with Extended Daylight or Clockwork mods.

---

### `rampantFixed--allowDaytimePlayerHunting`
**In-Game Name:** AI: Daytime player hunting (including in peaceful mode)  
**Better Name:** Allow Attacks While Player Is Active (Day)  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Runtime-Global  
**Description:** When enabled, biters hunt the player during daytime, even if other settings would normally prevent it. Overrides peaceful mode protections. Creates constant threat environment.

---

### `rampantFixed--allowDaytimeNonRampantActions`
**In-Game Name:** AI: Daytime non-rampant actions (including in peaceful mode)  
**Better Name:** Allow Standard Attacks During Day  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Runtime-Global  
**Description:** Allows standard AI expansion and territory building during daytime (pollution expansion, settlement of nearby nests, responses to other mod actions). Doesn't affect Rampant special attacks. Creates constant expansion pressure.

---

### `rampantFixed--enableMigration`
**In-Game Name:** AI: Enable Migration (survival mode!)  
**Better Name:** Enable Hive Migration & Territory Takeover  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Runtime-Global  
**Description:** HARD MODE. When enabled, the AI actively tries to capture and migrate across the entire map. Biters will siege your position and gradually expand to claim territory. Respects vanilla expansion settings but makes them much more aggressive. Only recommended for experienced players. Can be toggled in-game.

---

## AI Special Abilities

### `rampantFixed--raidAIToggle`
**In-Game Name:** AI: Enable Raiding AI  
**Better Name:** Enable Distant Nest Raiding  
**Type:** Boolean  
**Default:** Enabled  
**Scope:** Runtime-Global  
**Description:** When enabled, AI sends raiding parties from distant nests to attack targets far from their origin. Disabling makes the AI more localized - only nests near the player can attack. Significantly reduces threat in large maps with distant nests.

---

### `rampantFixed--siegeAIToggle`
**In-Game Name:** AI: Enable Siege AI  
**Better Name:** Enable Settlement & Siege Tactics  
**Type:** Boolean  
**Default:** Enabled  
**Scope:** Runtime-Global  
**Description:** When enabled, AI creates siege parties that settle near the player and dig in with fortified positions. Creates a different threat - localized permanent bases rather than roaming attacks. Disabling prevents long-term enemy settlement near your base.

---

### `rampantFixed--undergroundAttack`
**In-Game Name:** AI: Underground attacks  
**Better Name:** Enable Underground Tunneling Attacks  
**Type:** Boolean  
**Default:** Enabled  
**Scope:** Runtime-Global  
**Description:** When enabled, some biters dig underground to bypass your surface defenses. Hard surfaces (high friction tiles, 150+ friction) delay digging for ~1 minute. Visible on radar. Can be intercepted by turrets. Adds a new attack dimension requiring surface-level defense strategies.

---

### `rampantFixed--undergroundAttackProbability`
**In-Game Name:** AI: Probability of underground attack  
**Better Name:** Frequency of Underground Attack Attempts  
**Type:** Double  
**Default:** 0.15 (15%)  
**Range:** 0.01 - 0.50  
**Scope:** Runtime-Global  
**Description:** Probability (0-1 scale) that biters will attempt underground attacks. Scales with evolution - higher evolution = higher chance. At 0.15, roughly 15% of attacks attempt underground routes. Increase for more underground threat, decrease to make surface defenses more effective.

---

### `rampantFixed--demolisherAttack_AdditionalTime`
**In-Game Name:** AI: additional time between attacks of Demolishers (Vulcan), min  
**Better Name:** Extra Delay Between Worm Attacks (minutes)  
**Type:** Integer  
**Default:** 0  
**Range:** 0 - 120  
**Scope:** Runtime-Global  
**Description:** Adds additional minutes to the interval between worm (demolisher) attacks. These massive biters normally attack on a calculated schedule - this setting delays them further. Adding 30+ minutes makes worms much less threatening. Useful for reducing lategame stress.

---

## Building Safety Settings

### `rampantFixed--safeBuildings`
**In-Game Name:** Safety: Enable safety settings  
**Better Name:** Enable Protected Building Mode  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Runtime-Global  
**Description:** Master toggle for all safe building settings below. Must be enabled for any safety settings to work. When enabled, designated buildings become invulnerable (destroyed ones auto-rebuild if needed). Previously placed buildings can be destroyed, but will be automatically restored and become invulnerable after rebuild.

---

### `rampantFixed--safeBuildings-straightRail`
**In-Game Name:** Safety: Make railroad safe from biters  
**Better Name:** Protect Railroad Rails from Damage  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Runtime-Global  
**Description:** When `safeBuildings` is enabled, makes all straight rails invulnerable to biter damage. Requires Master toggle above. Useful if your rails are constantly destroyed - prevents train network sabotage.

---

### `rampantFixed--safeBuildings-bigElectricPole`
**In-Game Name:** Safety: Make big electric poles safe from biters  
**Better Name:** Protect Large Power Poles from Damage  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Runtime-Global  
**Description:** When `safeBuildings` is enabled, makes all large electric poles invulnerable. Prevents biters from destroying your power network by targeting poles. Extremely useful for preventing blackouts from biter attacks.

---

### `rampantFixed--safeBuildings-lamps`
**In-Game Name:** Safety: Make lamps safe from biters  
**Better Name:** Protect Light Fixtures from Damage  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Runtime-Global  
**Description:** When `safeBuildings` is enabled, makes all lamps invulnerable. Prevents biters from destroying your lighting network. Less critical than poles but useful for maintaining visibility.

---

### `rampantFixed--addWallResistanceAcid`
**In-Game Name:** Safety; Increase acid, poison and explosion wall resistance  
**Better Name:** Boost Wall Resistances to Acid & Poison  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Startup  
**Description:** When enabled, adds special resistances to all walls:
- 60% acid resistance
- 75% poison resistance  
- 30 additional explosion damage reduction
Makes walls much more effective against acid and poison enemies. Only applies to new game or startup - can't be changed mid-game.

---

## Optimization Settings

### `rampantFixed--removeBloodParticles`
**In-Game Name:** Optimization: Remove blood particles (Reduces lag spikes)  
**Better Name:** Disable Blood Particle Effects  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Startup  
**Description:** When enabled, removes blood particles created when biters die. Blood particles can cause significant UPS spikes during large battles. Disabling particles improves performance, especially in late-game with many simultaneous deaths. Purely visual - doesn't affect gameplay balance.

---

### `rampantFixed--fireSafety-flamethrower`
**In-Game Name:** Optimization: fire safety of hand flamethrowers  
**Better Name:** Disable Fire Spread from Hand Flamethrowers  
**Type:** Boolean  
**Default:** Enabled  
**Scope:** Startup  
**Description:** When enabled, hand flamethrowers deal direct area damage instead of spreading fire. Fire spread causes extreme lag during battles - disabling it significantly improves performance when fighting with flamethrowers. Flamethrower turrets unaffected by this setting.

---

### `rampantFixed--flamethrowerTurretsRebalance`
**In-Game Name:** Optimization: rebalance of stationary flamethrowers  
**Better Name:** Rebalance Turret Flamethrowers (Attack Speed)  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Startup  
**Description:** When enabled, reduces flamethrower turret attack speed while maintaining overall DPS. Particularly effective for Arsenal Rampant flamethrowers which cause severe lag. Creates fewer fire instances = less lag. Balances damage while improving performance.

---

### `rampantFixed--unkillableLogisticRobots`
**In-Game Name:** World: Unkillable logistic bots  
**Better Name:** Make Logistic Robots Invulnerable  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Startup  
**Description:** When enabled, logistic robots (yellow/orange bots) become immune to all damage from biters. Prevents biters from sabotaging your logistics network. Useful if your logistics are constantly being disrupted.

---

### `rampantFixed--unkillableConstructionRobots`
**In-Game Name:** World: Unkillable construction bots  
**Better Name:** Make Construction Robots Invulnerable  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Startup  
**Description:** When enabled, construction robots (blue bots) become immune to all damage. Prevents biters from stopping your building projects. Useful for maintaining base expansions without robot disruption.

---

## Unit Stats Scaling

All unit stat scalers multiply the base stat by the percentage entered. Default 1.0 = no scaling. 2.0 = double strength. 0.5 = half strength.

### Biter Stats

#### `rampantFixed--unitBiterHealthScaler`
**In-Game Name:** Modifier: Biter Health Scaler  
**Better Name:** Biter Total Hit Points Multiplier  
**Type:** Double | Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitBiterSpeedScaler`
**In-Game Name:** Modifier: Biter Speed Scaler  
**Better Name:** Biter Movement Speed Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitBiterDamageScaler`
**In-Game Name:** Modifier: Biter Damage Scaler  
**Better Name:** Biter Attack Damage Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitBiterRangeScaler`
**In-Game Name:** Modifier: Biter Range Scaler  
**Better Name:** Biter Attack Range Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitBiterHealingScaler`
**In-Game Name:** Modifier: Biter Healing Scaler  
**Better Name:** Biter Health Regeneration Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

### Spitter Stats

#### `rampantFixed--unitSpitterHealthScaler`
**In-Game Name:** Modifier: Spitter Health Scaler  
**Better Name:** Spitter Total Hit Points Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitSpitterSpeedScaler`
**In-Game Name:** Modifier: Spitter Speed Scaler  
**Better Name:** Spitter Movement Speed Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitSpitterDamageScaler`
**In-Game Name:** Modifier: Spitter Damage Scaler  
**Better Name:** Spitter Attack Damage Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitSpitterRangeScaler`
**In-Game Name:** Modifier: Spitter Range Scaler  
**Better Name:** Spitter Attack Range Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitSpitterHealingScaler`
**In-Game Name:** Modifier: Spitter Healing Scaler  
**Better Name:** Spitter Health Regeneration Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

### Drone Stats (from Wasp & Spawner Factions)

#### `rampantFixed--unitDroneHealthScaler`
**In-Game Name:** Modifier: Drone Health Scaler  
**Better Name:** Drone Hit Points Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0  
**Description:** Affects flying drones spawned by Wasp and Spawner factions.

---

#### `rampantFixed--unitDroneSpeedScaler`
**In-Game Name:** Modifier: Drone Speed Scaler  
**Better Name:** Drone Movement Speed Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitDroneDamageScaler`
**In-Game Name:** Modifier: Drone Damage Scaler  
**Better Name:** Drone Attack Damage Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitDroneRangeScaler`
**In-Game Name:** Modifier: Drone Range Scaler  
**Better Name:** Drone Attack Range Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitDroneHealingScaler`
**In-Game Name:** Modifier: Drone Healing Scaler  
**Better Name:** Drone Health Regeneration Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

### Worm Stats

#### `rampantFixed--unitWormHealthScaler`
**In-Game Name:** Modifier: Worm Health Scaler  
**Better Name:** Worm Total Hit Points Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitWormDamageScaler`
**In-Game Name:** Modifier: Worm Damage Scaler  
**Better Name:** Worm Attack Damage Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitWormRangeScaler`
**In-Game Name:** Modifier: Worm Range Scaler  
**Better Name:** Worm Attack Range Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitWormHealingScaler`
**In-Game Name:** Modifier: Worm Healing Scaler  
**Better Name:** Worm Health Regeneration Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

### Spawner (Nest) Stats

> **Important Distinction:** Spawner settings affect **regular nests** (biter spawners, spitter spawners) scattered across the map. **Hive** settings (below) affect only **hive buildings** — rarer, larger, tougher central structures that Rampant places. They are two separate scaling tracks. Also note: `RespawnScaler` affects how quickly units spawn, not attack frequency.

#### `rampantFixed--unitSpawnerHealthScaler`
**In-Game Name:** Modifier: Unit Spawner Health Scaler  
**Better Name:** Spawner Nest Hit Points Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitSpawnerHealingScaler`
**In-Game Name:** Modifier: Unit Spawner Healing Scaler  
**Better Name:** Spawner Nest Health Regeneration Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitSpawnerOwnedScaler`
**In-Game Name:** Modifier: Unit Spawner Owned Count Scaler  
**Better Name:** Max Units Per Spawner Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0  
**Description:** Controls how many units a single spawner can control at once.

---

#### `rampantFixed--unitSpawnerSpawnScaler`
**In-Game Name:** Modifier: Unit Spawner Spawn Count Scaler  
**Better Name:** Spawned Units Per Batch Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0  
**Description:** Controls how many units spawn at once when a spawner creates units.

---

#### `rampantFixed--unitSpawnerRespawnScaler`
**In-Game Name:** Modifier: Unit Spawner Respawn Rate Scaler  
**Better Name:** Spawner Unit Spawn Speed Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0  
**Description:** Controls how quickly spawners produce new units. Higher = faster reproduction.

---

### Hive Stats

> **What are Hives?** Hives are rare, central boss-like buildings placed by Rampant (separate from regular nests). They only have Health, Healing, and Respawn scaling — no Owned or Spawn scalers.

#### `rampantFixed--unitHiveHealthScaler`
**In-Game Name:** Modifier: Hive Health Scaler  
**Better Name:** Hive Total Hit Points Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitHiveHealingScaler`
**In-Game Name:** Modifier: Hive Healing Scaler  
**Better Name:** Hive Health Regeneration Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

#### `rampantFixed--unitHiveRespawnScaler`
**In-Game Name:** Modifier: Hive Respawn Scaler  
**Better Name:** Hive Unit Spawn Speed Multiplier  
**Type:** Double | **Default:** 1.0 | **Range:** 0.0001 - 100000.0

---

## Player Interface Settings

### `rampantFixed--showAdminMenu`
**In-Game Name:** Show the button to open the menu of additional administrator options  
**Better Name:** Show Admin Control Panel Button  
**Type:** Boolean  
**Default:** Disabled  
**Scope:** Runtime-Per-User  
**Description:** When enabled (singleplayer or admin player only), adds a button to the top of the screen. Opens an admin menu allowing you to:
- Replace Rampant enemies with vanilla enemies
- Specify which surfaces/planets to ignore
- Manage AI per-planet settings

---

### `rampantFixed--showPlanetAISettings`
**In-Game Name:** Show AI planet settings  
**Better Name:** Show Per-Planet AI Configuration  
**Type:** Boolean  
**Default:** Enabled  
**Scope:** Runtime-Per-User  
**Description:** When enabled, shows a dialog allowing you to configure which planets/surfaces the AI processes. Useful in Space Age with multiple planets - you can disable AI on certain planets for easier expansion.

---

### `rampantFixed--showSquadAlert`
**In-Game Name:** Show squad alert  
**Better Name:** Display Active Squad Alerts  
**Type:** Boolean  
**Default:** Enabled  
**Scope:** Runtime-Per-User  
**Description:** When enabled, displays chat notifications when Rampant squads are detected nearby. Shows squad size and location. Useful for tracking threats, disable for quieter gameplay.

---

## Compatibility & Advanced

### `rampantFixed--allowLongRangeImmunity`
**In-Game Name:** World: Long range immunity for some factions  
**Better Name:** Enable Long-Range Attack Immunity  
**Type:** Boolean  
**Default:** Enabled  
**Scope:** Startup  
**Description:** When enabled, certain factions (Laser, Fast, Suicide, Spawner) have long-range immunity - attacks from beyond a certain range do 10% damage. Fire and acid attacks ignore this immunity. Disabling makes these factions too weak. Only affects new enemies.

---

### `rampantFixed--longRangeImmunity_efficiency`
**In-Game Name:** Efficiency of long range protection  
**Better Name:** Long-Range Immunity Strength Percentage  
**Type:** Integer  
**Default:** 95  
**Range:** 10 - 100  
**Scope:** Startup  
**Description:** Controls how effective long-range immunity is. 
- 100% = Immune to damage from Range N+ (90% reduced damage)
- 50% = 50% damage reduction from long range
- 10% = Takes 90% damage from long range (nearly useless)

---

### `rampantFixed--allowOneshotProtection`
**In-Game Name:** World: Oneshot protection for some factions  
**Better Name:** Enable Overdamage Protection  
**Type:** Boolean  
**Default:** Enabled  
**Scope:** Startup  
**Description:** When enabled, certain factions (Laser, Fast, Suicide, Nuclear, Troll, Armored) have overdamage protection - the most damage they can take in one hit is limited to a percentage of their max HP. Fire and acid ignore this protection. Disabling makes these factions much weaker.

---

### `rampantFixed--oneshotProtection_efficiency`
**In-Game Name:** Efficiency of overdamage protection  
**Better Name:** Max Damage Per Hit Percentage  
**Type:** Integer  
**Default:** 100  
**Range:** 10 - 100  
**Scope:** Startup  
**Description:** Controls overdamage protection effectiveness.
- 100% = Damage per hit capped at max HP (can't kill in single hit)
- 50% = Single hit capped at 50% max HP
- 10% = Single hit capped at 10% max HP (weak protection)

---

### `rampantFixed--buildingsImmuneToElectic`
**In-Game Name:** Biter buildings are immune to electrical damage  
**Better Name:** Nests & Worms Immune to Electric Damage  
**Type:** Boolean  
**Default:** Enabled  
**Scope:** Startup  
**Description:** When enabled, nests and worms take no damage from electric/laser attacks. Makes electric defenses less effective against buildings. Disabling allows laser/electric to damage nest and worm structures.

---

### `rampantFixed--settlementsProbability`
**In-Game Name:** AI: settlements probability in siege/migration mode  
**Better Name:** Settlement vs. Attack Ratio  
**Type:** Double  
**Default:** 0.40 (40%)  
**Range:** 0.001 - 1.0  
**Scope:** Runtime-Global  
**Description:** Only affects siege/migration modes. Controls probability of settling new territory vs. attacking.
- 0.4 = 40% settle, 60% attack
- 0.2 = 20% settle, 80% attack (very aggressive)
- 0.8 = 80% settle, 20% attack (slow expansion)

---

### `rampantFixed--vengenceProbabilityPercent`
**In-Game Name:** AI: basic vengence probability per kill  
**Better Name:** Base Revenge Attack Trigger Chance  
**Type:** Double  
**Default:** 0.04 (4%)  
**Range:** 0.0 - 1.0  
**Scope:** Runtime-Global  
**Description:** Probability that killing a biter triggers a revenge attack. At 0.04, each kill has 4% chance to trigger a vengeance squad. Set to 0 to disable revenge attacks entirely.

---

### `rampantFixed--chainVengenceCoefficient`
**In-Game Name:** AI: probability of forming a sequence of vengence squads  
**Better Name:** Chained Revenge Attack Multiplier  
**Type:** Double  
**Default:** 0.6  
**Range:** 0.0 - 1.0  
**Scope:** Runtime-Global  
**Description:** Multiplier for forming additional revenge squads after one is already triggered. At 0.6, each successive revenge squad has 60% of the previous chance. Affects vengeance chain length. Higher values = longer revenge chains.

---

### Debug & Chat Notifications

#### `rampantFixed--aiPointsPrintGainsToChat`
**In-Game Name:** AI: Print Point Gains to Chat  
**Better Name:** Display AI Point Generation Messages  
**Type:** Boolean | **Default:** Disabled | **Scope:** Runtime-Global  
**Description:** Prints chat messages whenever the AI gains action points. Can spam chat during busy battles. Useful for understanding AI economy but disable for competitive advantage.

---

#### `rampantFixed--aiPointsPrintSpendingToChat`
**In-Game Name:** AI: Print Point Spending to Chat  
**Better Name:** Display AI Action Spending Messages  
**Type:** Boolean | **Default:** Disabled | **Scope:** Runtime-Global  
**Description:** Prints chat messages whenever the AI spends points (creates attacks, builds nests). Includes GPS coordinates. Can fill chat quickly. Disable for hardest experience.

---

#### `rampantFixed--printAIStateChanges`
**In-Game Name:** AI: Print State Changes to Chat  
**Better Name:** Display AI Behavior State Changes  
**Type:** Boolean | **Default:** Disabled | **Scope:** Runtime-Global  
**Description:** Prints messages when Rampant AI changes states (Peaceful → Aggressive, etc.). Shows per-surface. Useful for learning AI behavior, disable for purest experience.

---

#### `rampantFixed--debugTemperament`
**In-Game Name:** DEBUG: Print Temperament Changes to Chat  
**Better Name:** Debug Mood/Temperament Changes  
**Type:** Boolean | **Default:** Disabled | **Scope:** Runtime-Global  
**Description:** Advanced debugging. Prints AI temperament information that controls AI state probability rolls. Only useful for mod developers.

---

## Settings Summary by Type

### Startup (Can only be changed at game creation)
- `disableCollidingProjectiles`, `oldRedEnemyMapColor`, `unitAndSpawnerFadeTime`, `enableFadeTime`
- `enableSwarm`, `enableShrinkNestsAndWorms`, `unitSpawnerBreath`
- `newEnemies`, `allowOtherEnemies`, `newEnemiesSide`, `newEnemyVariations`
- `tierStart`, `tierEnd`, `max-evo-dist`
- `allowLongRangeImmunity`, `longRangeImmunity_efficiency`
- `allowOneshotProtection`, `oneshotProtection_efficiency`
- `buildingsImmuneToElectic`, `addWallResistanceAcid`
- All enemy faction toggles (acid, laser, electric, fire, etc.)
- All unit stat scalers (biter, spitter, drone, worm, spawner, hive)
- `removeBloodParticles`, `fireSafety-flamethrower`, `flamethrowerTurretsRebalance`
- `unkillableLogisticRobots`, `unkillableConstructionRobots`

### Runtime-Global (Can be changed during gameplay, affects all players)
- `attackWaveMaxSize`, `attackWaveMaxSizeEvoPercent`, `agressiveStart`
- `maxNumberOfSquads`, `maxNumberOfBuilders`
- `safeBuildings*`, all safe building toggles
- `enableMigration`, `raidAIToggle`, `siegeAIToggle`
- `undergroundAttack`, `undergroundAttackProbability`, `demolisherAttack_AdditionalTime`
- `permanentNocturnal`, `allowDaytimePlayerHunting`, `allowDaytimeNonRampantActions`
- `aiPointsScaler`, `aiDifficulty`
- `aiPointsPrintGainsToChat`, `aiPointsPrintSpendingToChat`, `printAIStateChanges`, `debugTemperament`
- `settlementsProbability`, `vengenceProbabilityPercent`, `chainVengenceCoefficient`
- `attackWaveGenerationUsePlayerProximity`, `attackPlayerThreshold`

### Runtime-Per-User (Each player has their own setting)
- `showAdminMenu`, `showPlanetAISettings`, `showSquadAlert`

---

## Quick Setup Recommendations

### Peaceful/Casual Play
- `aiDifficulty` = Lite
- `aiPointsScaler` = 0.5
- `attackWaveMaxSize` = 30
- `allowDaytimeNonRampantActions` = False
- `safeBuildings` = Enable + all options

### Normal/Standard Play
- `aiDifficulty` = Hard
- `aiPointsScaler` = 1.0
- `attackWaveMaxSize` = 75
- `maxNumberOfSquads` = 20
- `maxNumberOfBuilders` = 20

### Hard/Competitive Play
- `aiDifficulty` = Hard
- `aiPointsScaler` = 1.5
- `attackWaveMaxSize` = 200+
- `maxNumberOfSquads` = 30
- `maxNumberOfBuilders` = 50+
- `enableMigration` = True
- `raidAIToggle` = True
- `siegeAIToggle` = True
- `undergroundAttack` = True

### Performance Optimization
- `removeBloodParticles` = True
- `fireSafety-flamethrower` = True
- `flamethrowerTurretsRebalance` = True
- `enableSwarm` = True
- `enableShrinkNestsAndWorms` = True
- `maxNumberOfSquads` = 10-15
- `maxNumberOfBuilders` = 10-15

---

## Notes
- Startup settings require creating a new game to take effect
- Runtime settings can be changed mid-game
- Per-user settings are per-player in multiplayer
- Many scalers accept decimal values (1.5 = 150%, 0.75 = 75%)
- All settings default to balanced values for 1.0x difficulty
