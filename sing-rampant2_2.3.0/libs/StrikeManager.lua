if strikeManagerG then
    return strikeManagerG
end
local strikeManager = {}

local constants = require("libs/Constants")
local zoneManager = require("libs/ZoneManager")
local strikeTargeting = require("libs/StrikeTargeting")
local customAlerts = require("libs/CustomAlerts")
local unitGroupUtils = require("libs/UnitGroupUtils")
local chunkPropertyUtils = require("libs/ChunkPropertyUtils")
local mapUtils = require("libs/MapUtils")
local movementUtils = require("libs/MovementUtils")
local scoreChunks = require("libs/ScoreChunks")

-- Strike configuration
strikeManager.STRIKE_COOLDOWN_DURATION = 2 * 60 * 60  -- 2 minutes in ticks (60 ticks/sec) [TESTING]
strikeManager.STRIKE_ENABLED_EVOLUTION = 0.20  -- 20% evolution
strikeManager.SQUADS_PER_STRIKE = 5

function strikeManager.initStrikes(map)
    if not map then return end
    map.strikeState = {
        cooldownEndTick = 0,
        lastStrikeCategory = nil,
        lastStrikeTarget = nil,
        enabled = false
    }
end

function strikeManager.processStrikes(map, surface, universe)
    if not map or not map.strikeState or not map.zonesByIndex or #map.zonesByIndex == 0 then
        return
    end

    local tick = game.tick
    local debugPrint = settings.global["rampantFixed--debugStrikeTargeting"].value

    -- Check if strikes are enabled (at 20% evolution or higher)
    local evolution = game.forces.enemy.get_evolution_factor(surface)
    if evolution < strikeManager.STRIKE_ENABLED_EVOLUTION then
        return  -- Not enough evolution for strikes
    end

    -- Print first-time enable message (always, not just in debug)
    if not map.strikeState.enabled then
        map.strikeState.enabled = true
        game.print("Strike targeting enabled at " .. math.floor(evolution * 100) .. "% evolution")
    end

    -- Check if cooldown is still active
    if tick < map.strikeState.cooldownEndTick then
        return  -- Still on cooldown
    end

    -- Find zones by cached category
    if not map.zonesByIndex or #map.zonesByIndex == 0 then
        game.print("[Strike] No zones available to target")
        return
    end

    local categoryZones = {
        ["products"] = {},
        ["power"] = {},
        ["oil"] = {},
        ["raw-resources"] = {},
        ["outpost"] = {}
    }

    -- Organize zones by category using LIVE categorization (same as r2 draw command)
    -- This is the master designator - matches what drawZoneOverlay shows
    -- Note: outpost zones may have 0 production (only military buildings), so we
    -- categorize ALL zones, not just ones with production
    for _, zone in ipairs(map.zonesByIndex) do
        local category = strikeTargeting.getZoneCategory(zone, map)
        if category and categoryZones[category] then
            table.insert(categoryZones[category], zone)
        end
    end

    -- Find a random category with zones
    local availableCats = {}
    for cat, zones in pairs(categoryZones) do
        if #zones > 0 then
            table.insert(availableCats, cat)
        end
    end

    if #availableCats == 0 then
        game.print("[Strike] No targetable zones found")
        return
    end

    -- Pick random category
    math.randomseed(game.tick + tick)
    local selectedCat = availableCats[math.random(1, #availableCats)]
    local targetZones = categoryZones[selectedCat]

    -- Pick a zone within the category
    -- For "products" category: weighted random favoring high global % contribution + high tier value
    -- For other categories: uniform random
    local target
    if selectedCat == "products" then
        -- Compute LIVE relativeShare across ALL zones (not just products) to match
        -- what the r2 draw command shows. This guarantees fresh share data even if
        -- targetRanker hasn't run recently.
        local globalTotalRate = 0
        for _, zone in ipairs(map.zonesByIndex) do
            globalTotalRate = globalTotalRate + (zone.totalRate or 0)
        end

        -- Build weights: relativeShare squared (strong bias to top producers)
        -- combined with tier value (extra bias toward higher-tier items like blue science)
        local weights = {}
        local totalWeight = 0
        local zoneShares = {}  -- store computed shares for debug print
        for i, zone in ipairs(targetZones) do
            local share = 0
            if globalTotalRate > 0 then
                share = (zone.totalRate or 0) / globalTotalRate
            end
            zoneShares[i] = share

            local productValue = strikeTargeting.calculateProductValue(zone) or 0
            -- Squared share is the main driver (e.g. 50% share = 0.25 weight, 10% share = 0.01 weight = 25x bias)
            -- Tier value provides an additional multiplier (high-tier products get 2-3x more weight)
            local weight = (share * share) * (1 + productValue * 0.1)
            -- Floor so zones with 0 share still have a tiny chance
            if weight < 0.0001 then weight = 0.0001 end
            weights[i] = weight
            totalWeight = totalWeight + weight
        end

        -- Weighted random roll
        local roll = math.random() * totalWeight
        local cumulative = 0
        local pickedIndex = #targetZones
        target = targetZones[pickedIndex]  -- fallback to last
        for i, weight in ipairs(weights) do
            cumulative = cumulative + weight
            if roll <= cumulative then
                target = targetZones[i]
                pickedIndex = i
                break
            end
        end

        local topShare = zoneShares[pickedIndex] * 100
        local topValue = strikeTargeting.calculateProductValue(target) or 0
        game.print("[Strike] Category: products (" .. #targetZones .. " zones) - picked zone with " .. string.format("%.1f%%", topShare) .. " global share, tier value " .. math.floor(topValue))
    else
        target = targetZones[math.random(1, #targetZones)]
        game.print("[Strike] Category: " .. selectedCat .. " (" .. #targetZones .. " zones)")
    end

    -- Calculate center position of target zone
    local targetX = target.tileX + zoneManager.ZONE_TILE_SIZE / 2
    local targetY = target.tileY + zoneManager.ZONE_TILE_SIZE / 2
    local targetPos = {x = targetX, y = targetY}

    -- Always show strike announcement with target location
    game.print("[Strike] Targeting zone at [gps=" .. math.floor(targetX) .. "," .. math.floor(targetY) .. "," .. surface.name .. "]")

    -- Deploy squads with units from nearby spawners
    local squadsDeployed = 0
    local chunkX, chunkY = mapUtils.positionToChunkXY(targetPos)
    local targetChunk = mapUtils.getChunkByXY(map, chunkX, chunkY)

    if not universe or not universe.formCommand or not universe.formGroupCommand then
        if debugPrint then
            game.print("[Strike] Cannot deploy: universe commands not initialized")
        end
        return
    end

    -- Find nest chunks sorted by distance to target (closest first)
    -- Try chunkToActiveNest first (aggressive nests), fall back to chunkToNests
    local nestPool = map.chunkToActiveNest
    if not nestPool or not next(nestPool) then
        nestPool = map.chunkToNests
    end

    if not nestPool or not next(nestPool) then
        game.print("[Strike] FAILED - No nests available on map")
        return
    end

    -- Gather player positions on this surface so we can prefer nests
    -- that are FAR from any player (deeper enemy territory) but still within reach
    local playerPositions = {}
    for _, player in pairs(game.players) do
        if player.valid and player.surface.index == surface.index then
            playerPositions[#playerPositions + 1] = player.position
        end
    end

    -- Max acceptable distance from nearest player: 3 zones end-to-end
    -- (zone = 64 tiles, so cap = 192 tiles). Beyond this, strikes would take
    -- forever to walk to the target.
    local MAX_NEST_DIST_FROM_PLAYER = zoneManager.ZONE_TILE_SIZE * 3
    local MAX_NEST_DIST_SQ = MAX_NEST_DIST_FROM_PLAYER * MAX_NEST_DIST_FROM_PLAYER

    -- Helper: compute squared distance from a chunk to the nearest player
    local function distSqToNearestPlayer(chunk)
        if #playerPositions == 0 then
            return 0  -- no players, neutral score
        end
        local minSq = math.huge
        for _, pp in ipairs(playerPositions) do
            local dx = chunk.x - pp.x
            local dy = chunk.y - pp.y
            local d = dx*dx + dy*dy
            if d < minSq then minSq = d end
        end
        return minSq
    end

    -- Collect candidate nests within the player-distance cap. Track rejected
    -- nests as a fallback in case no nest fits inside the cap.
    local nestCandidates = {}
    local fallbackCandidates = {}
    for nestChunk, _ in pairs(nestPool) do
        if nestChunk and nestChunk ~= -1 then
            local dxt = nestChunk.x - targetX
            local dyt = nestChunk.y - targetY
            local distSqPlayer = distSqToNearestPlayer(nestChunk)
            local entry = {
                chunk = nestChunk,
                distSqToTarget = dxt*dxt + dyt*dyt,
                distSqToPlayer = distSqPlayer
            }
            if #playerPositions == 0 or distSqPlayer <= MAX_NEST_DIST_SQ then
                nestCandidates[#nestCandidates + 1] = entry
            else
                fallbackCandidates[#fallbackCandidates + 1] = entry
            end
        end
    end

    -- If no nests fit inside the player-distance cap, fall back to the full
    -- pool so the strike still happens (just from further out than ideal).
    local usingFallback = false
    if #nestCandidates == 0 then
        if #fallbackCandidates == 0 then
            game.print("[Strike] FAILED - No valid nest chunks")
            return
        end
        nestCandidates = fallbackCandidates
        usingFallback = true
    end

    -- Sort primarily by distance from player (descending - furthest first within cap)
    -- so strikes come from the deepest enemy territory we can still reach from.
    -- Tie-breaker: closer to target.
    table.sort(nestCandidates, function(a, b)
        if a.distSqToPlayer ~= b.distSqToPlayer then
            return a.distSqToPlayer > b.distSqToPlayer
        end
        return a.distSqToTarget < b.distSqToTarget
    end)

    local furthestDist = math.floor(math.sqrt(nestCandidates[1].distSqToPlayer))
    local closestNestToTarget = math.floor(math.sqrt(nestCandidates[1].distSqToTarget))
    local fallbackTag = usingFallback and " [fallback - no nests within " .. MAX_NEST_DIST_FROM_PLAYER .. " tiles]" or ""
    game.print("[Strike] Found " .. #nestCandidates .. " nest chunks (cap " .. MAX_NEST_DIST_FROM_PLAYER .. " from player) - top pick is " .. furthestDist .. " tiles from player, " .. closestNestToTarget .. " from target" .. fallbackTag)

    -- Deploy squads from the closest nests
    local nestIndex = 1
    for i = 1, strikeManager.SQUADS_PER_STRIKE do
        local squadCreated = false
        local attempts = 0

        -- Try up to 5 different nests if formation fails
        while not squadCreated and attempts < 5 and nestIndex <= #nestCandidates do
            attempts = attempts + 1
            local nestChunk = nestCandidates[nestIndex].chunk
            nestIndex = nestIndex + 1
            if nestIndex > #nestCandidates then
                nestIndex = 1  -- wrap around so we can reuse nests
            end

            -- Use Rampant's PROVEN formation scoring
            local squadPath, squadDirection = movementUtils.scoreNeighborsForFormation(
                mapUtils.getNeighborChunks(map, nestChunk.x, nestChunk.y),
                scoreChunks.validUnitGroupLocation,
                scoreChunks.scoreUnitGroupLocation,
                map
            )

            if squadPath == -1 then
                -- Try next nest
                game.print("[Strike] Squad " .. i .. " attempt " .. attempts .. " - no valid formation chunk near nest [gps=" .. nestChunk.x .. "," .. nestChunk.y .. "," .. surface.name .. "]")
            else
                -- positionFromDirectionAndChunk MUTATES the 3rd arg (universe.position scratch buffer)
                local formationPos = mapUtils.positionFromDirectionAndChunk(
                    squadDirection, nestChunk, universe.position, 0.98
                )
                local squadPosition = surface.find_non_colliding_position(
                    "chunk-scanner-squad-rampant", formationPos, constants.CHUNK_SIZE, 4, true
                )

                if not squadPosition then
                    game.print("[Strike] Squad " .. i .. " attempt " .. attempts .. " - no non-colliding position")
                else
                    -- Create squad using Rampant's proven pattern
                    local squad = unitGroupUtils.createSquad(squadPosition, map)
                    if squad then
                        universe.formGroupCommand.group = squad.group
                        universe.formCommand.unit_count = 40  -- 2x bigger than before
                        -- Widen search radius to find more units across nearby spawners
                        local originalDistance = universe.formCommand.unit_search_distance
                        universe.formCommand.unit_search_distance = constants.CHUNK_SIZE * 5
                        local foundUnits = surface.set_multi_command(universe.formCommand)
                        universe.formCommand.unit_search_distance = originalDistance  -- restore

                        if foundUnits > 0 then
                            squad.customTarget = {x = targetX, y = targetY}
                            squad.status = constants.SQUAD_RAIDING
                            -- Strict gathering: wait until 80% of requested units arrive
                            -- OR max 15 seconds (900 ticks), whichever comes first
                            -- Also enforce minimum 5 second wait so squads don't leave instantly
                            squad.targetMemberCount = foundUnits  -- expected member count
                            squad.formingMinUntil = tick + 600  -- always wait at least 10 sec
                            squad.formingUntil = tick + 900     -- hard cap 15 sec

                            universe.groupNumberToSquad[squad.groupNumber] = squad
                            universe.squadCount = universe.squadCount + 1

                            if targetChunk and targetChunk ~= -1 then
                                chunkPropertyUtils.addSquadToChunk(map, targetChunk, squad)
                            end

                            squadsDeployed = squadsDeployed + 1
                            squadCreated = true
                            game.print("[Strike] Squad " .. i .. " requested " .. foundUnits .. " units at [gps=" .. math.floor(squadPosition.x) .. "," .. math.floor(squadPosition.y) .. "," .. surface.name .. "]")
                        else
                            game.print("[Strike] Squad " .. i .. " attempt " .. attempts .. " - 0 units found at nest")
                            if squad.group and squad.group.valid then
                                squad.group.destroy()
                            end
                        end
                    end
                end
            end
        end

        if not squadCreated then
            game.print("[Strike] Squad " .. i .. " FAILED after " .. attempts .. " attempts")
        end
    end

    -- Always show strike deployment confirmation
    game.print("[Strike] Deployed " .. squadsDeployed .. " squads - Strike initiated!")

    -- Show alert to players - create a temporary entity for alert positioning
    local messageText = "Strike incoming!"
    local chunkX = math.floor(targetX / 32)
    local chunkY = math.floor(targetY / 32)

    -- Try to find an existing entity at target location
    local entitiesAtTarget = surface.find_entities_filtered({
        area = {{targetX - 50, targetY - 50}, {targetX + 50, targetY + 50}},
        limit = 1
    })

    local alertEntity = nil
    if #entitiesAtTarget > 0 then
        alertEntity = entitiesAtTarget[1]
    else
        -- Create a temporary entity for the alert
        alertEntity = surface.create_entity({
            name = "wooden-chest",
            position = targetPos,
            force = "enemy"
        })
    end

    if alertEntity then
        for _, force in pairs(game.forces) do
            if force.is_chunk_visible(surface, {x = chunkX, y = chunkY}) then
                for _, player in pairs(force.connected_players) do
                    local player_settings = settings.get_player_settings(player)
                    if player_settings["rampantFixed--showSquadAlert"].value then
                        player.add_custom_alert(
                            alertEntity,
                            {
                                type = "entity",
                                name = "biter-spawner"
                            },
                            messageText,
                            true
                        )
                    end
                end
            end
        end

        -- Clean up temporary entity if we created one
        if not entitiesAtTarget or #entitiesAtTarget == 0 then
            if alertEntity.valid then
                alertEntity.destroy()
            end
        end
    end

    -- Set cooldown
    map.strikeState.cooldownEndTick = tick + strikeManager.STRIKE_COOLDOWN_DURATION
    map.strikeState.lastStrikeCategory = selectedCategory
    map.strikeState.lastStrikeTarget = target

    if debugPrint then
        game.print("[Strike] Cooldown set for " .. math.floor(strikeManager.STRIKE_COOLDOWN_DURATION / 60 / 60) .. " minutes")
    end
end

strikeManagerG = strikeManager
return strikeManager
