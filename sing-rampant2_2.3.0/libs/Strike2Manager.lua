if strike2ManagerG then
    return strike2ManagerG
end
local strike2Manager = {}

local constants = require("libs/Constants")
local zoneManager = require("libs/ZoneManager")
local strikeTargeting = require("libs/StrikeTargeting")
local customAlerts = require("libs/CustomAlerts")
local unitGroupUtils = require("libs/UnitGroupUtils")
local chunkPropertyUtils = require("libs/ChunkPropertyUtils")
local mapUtils = require("libs/MapUtils")
local movementUtils = require("libs/MovementUtils")
local scoreChunks = require("libs/ScoreChunks")

-- Strike2 configuration
strike2Manager.STRIKE2_ENABLED_EVOLUTION = 0.20
strike2Manager.SQUADS_PER_STRIKE2 = 5
strike2Manager.MIN_NEST_DISTANCE = 800  -- Minimum distance from objective (ensures distant nests for directional approach)
strike2Manager.STRIKE_COOLDOWN_ON_STRIKE2 = 10 * 60 * 60  -- 10 minutes in ticks

-- Direction vectors: N, NE, E, SE, S, SW, W, NW
local DIRECTIONS = {
    {dx = 0, dy = -1, name = "N"},
    {dx = 1, dy = -1, name = "NE"},
    {dx = 1, dy = 0, name = "E"},
    {dx = 1, dy = 1, name = "SE"},
    {dx = 0, dy = 1, name = "S"},
    {dx = -1, dy = 1, name = "SW"},
    {dx = -1, dy = 0, name = "W"},
    {dx = -1, dy = -1, name = "NW"},
}

-- Determine which direction has the most empty adjacent zones
-- Returns direction vector and empty zone count
local function determineStrikeDirection(map, targetZone)
    if not targetZone then
        return nil, 0
    end

    local zx, zy = targetZone.zx, targetZone.zy
    local bestDir = nil
    local maxEmpty = -1
    local directionScores = {}

    -- For each of 8 directions, count empty zones in that quadrant
    -- (target zone + adjacent zones in that direction + 2nd order adjacent)
    for _, dir in ipairs(DIRECTIONS) do
        local emptyCount = 0
        -- Check primary direction
        local px, py = zx + dir.dx, zy + dir.dy
        if not map.zones[px] or not map.zones[px][py] then
            emptyCount = emptyCount + 1
        elseif not strikeTargeting.getZoneCategory(map.zones[px][py], map, true) then
            emptyCount = emptyCount + 1
        end

        -- Check 2nd order adjacent in the same direction (e.g., for E direction: NE and SE)
        local perp1X, perp1Y = zx + dir.dx, zy + dir.dy - dir.dx
        local perp2X, perp2Y = zx + dir.dx, zy + dir.dy + dir.dx

        if not map.zones[perp1X] or not map.zones[perp1X][perp1Y] then
            emptyCount = emptyCount + 1
        elseif not strikeTargeting.getZoneCategory(map.zones[perp1X][perp1Y], map, true) then
            emptyCount = emptyCount + 1
        end

        if not map.zones[perp2X] or not map.zones[perp2X][perp2Y] then
            emptyCount = emptyCount + 1
        elseif not strikeTargeting.getZoneCategory(map.zones[perp2X][perp2Y], map, true) then
            emptyCount = emptyCount + 1
        end

        directionScores[dir.name] = emptyCount
        if emptyCount > maxEmpty then
            maxEmpty = emptyCount
            bestDir = dir
        end
    end

    return bestDir, maxEmpty, directionScores
end

-- Check if a nest is in the correct direction from target AND not in player zones
local function nestIsValidForStrike(nestChunk, targetZone, strikeDirection, map)
    if not strikeDirection or not targetZone or not map then
        return false
    end

    -- Convert zone coords to tile coords (center)
    local targetX = targetZone.tileX + zoneManager.ZONE_TILE_SIZE / 2
    local targetY = targetZone.tileY + zoneManager.ZONE_TILE_SIZE / 2

    -- Convert nest chunk to tile coords
    local nestX = nestChunk.x * 32
    local nestY = nestChunk.y * 32

    -- Vector from target to nest
    local dx = nestX - targetX
    local dy = nestY - targetY

    local TILE_TOLERANCE = 250  -- ±250 tile deviation from primary direction axis

    -- Strict directional check: nest must be in the correct PRIMARY direction
    if strikeDirection.dx ~= 0 then
        -- Primary axis is X (East/West)
        if strikeDirection.dx > 0 and dx <= 0 then return false end  -- Must be East
        if strikeDirection.dx < 0 and dx >= 0 then return false end  -- Must be West
        -- Y deviation limited to ±250 tiles
        if math.abs(dy) > TILE_TOLERANCE then return false end
    end

    if strikeDirection.dy ~= 0 then
        -- Primary axis is Y (North/South)
        if strikeDirection.dy > 0 and dy <= 0 then return false end  -- Must be South
        if strikeDirection.dy < 0 and dy >= 0 then return false end  -- Must be North
        -- X deviation limited to ±250 tiles
        if math.abs(dx) > TILE_TOLERANCE then return false end
    end

    -- Check if nest is surrounded by player-controlled zones
    -- Convert chunk to zone coordinates
    local nestTileX = nestChunk.x * 32
    local nestTileY = nestChunk.y * 32
    local nestZoneX = math.floor(nestTileX / zoneManager.ZONE_TILE_SIZE)
    local nestZoneY = math.floor(nestTileY / zoneManager.ZONE_TILE_SIZE)

    -- Check 5x5 zone square, but only interior 3x3 (excluding edges)
    for zx = nestZoneX - 1, nestZoneX + 1 do
        for zy = nestZoneY - 1, nestZoneY + 1 do
            local zone = map.zones[zx] and map.zones[zx][zy]
            if zone then
                -- If zone is player-controlled (has any category), reject this nest
                local category = strikeTargeting.getZoneCategory(zone, map, true)
                if category then
                    return false  -- Too close to player-controlled zone
                end
            end
        end
    end

    return true
end

function strike2Manager.initiateStrike2(map, surface, universe)
    if not map or not map.strikeState or not map.zonesByIndex or #map.zonesByIndex == 0 then
        game.print("[Strike2] Cannot initiate: map or zones not ready")
        return false
    end

    local tick = game.tick
    local debugPrint = settings.global["rampantFixed--debugStrikeTargeting"].value

    -- Check evolution
    local evolution = game.forces.enemy.get_evolution_factor(surface)
    if evolution < strike2Manager.STRIKE2_ENABLED_EVOLUTION then
        if debugPrint then
            game.print("[Strike2] Disabled: evolution " .. math.floor(evolution * 100) .. "% < " .. math.floor(strike2Manager.STRIKE2_ENABLED_EVOLUTION * 100) .. "%")
        end
        return false
    end

    -- Select target using same logic as regular Strike
    local categoryZones = {
        ["products"] = {},
        ["power"] = {},
        ["oil"] = {},
        ["raw-resources"] = {},
        ["outpost"] = {}
    }

    for _, zone in ipairs(map.zonesByIndex) do
        local category = strikeTargeting.getZoneCategory(zone, map)
        if category and categoryZones[category] then
            table.insert(categoryZones[category], zone)
        end
    end

    local availableCats = {}
    for cat, zones in pairs(categoryZones) do
        if #zones > 0 then
            table.insert(availableCats, cat)
        end
    end

    if #availableCats == 0 then
        if debugPrint then
            game.print("[Strike2] No targetable zones found")
        end
        return false
    end

    math.randomseed(game.tick + tick)
    local selectedCat = availableCats[math.random(1, #availableCats)]
    local targetZones = categoryZones[selectedCat]
    local target

    if selectedCat == "products" then
        local globalTotalRate = 0
        for _, zone in ipairs(map.zonesByIndex) do
            globalTotalRate = globalTotalRate + (zone.totalRate or 0)
        end

        local weights = {}
        local totalWeight = 0
        for i, zone in ipairs(targetZones) do
            local share = 0
            if globalTotalRate > 0 then
                share = (zone.totalRate or 0) / globalTotalRate
            end
            local productValue = strikeTargeting.calculateProductValue(zone) or 0
            local weight = (share * share) * (1 + productValue * 0.1)
            if weight < 0.0001 then weight = 0.0001 end
            weights[i] = weight
            totalWeight = totalWeight + weight
        end

        local roll = math.random() * totalWeight
        local cumulative = 0
        target = targetZones[#targetZones]
        for i, weight in ipairs(weights) do
            cumulative = cumulative + weight
            if roll <= cumulative then
                target = targetZones[i]
                break
            end
        end
    else
        target = targetZones[math.random(1, #targetZones)]
    end

    if not target then
        if debugPrint then
            game.print("[Strike2] Failed to select target zone")
        end
        return false
    end

    local targetX = target.tileX + zoneManager.ZONE_TILE_SIZE / 2
    local targetY = target.tileY + zoneManager.ZONE_TILE_SIZE / 2
    local targetPos = {x = targetX, y = targetY}

    -- Determine strike direction based on empty adjacent zones
    local strikeDirection, emptyCount, directionScores = determineStrikeDirection(map, target)
    if not strikeDirection then
        if debugPrint then
            game.print("[Strike2] No valid strike direction found")
        end
        return false
    end

    game.print("[Strike2] Targeting zone at [gps=" .. math.floor(targetX) .. "," .. math.floor(targetY) .. "," .. surface.name .. "] from direction " .. strikeDirection.name .. " (empty adjacent zones: " .. emptyCount .. ")")

    -- Debug: show direction analysis
    if debugPrint then
        local dirStr = ""
        for _, dir in ipairs(DIRECTIONS) do
            dirStr = dirStr .. dir.name .. ":" .. (directionScores[dir.name] or 0) .. " "
        end
        game.print("[Strike2] Direction scores: " .. dirStr)
    end

    -- Find valid nest pool
    local nestPool = map.chunkToActiveNest
    if not nestPool or not next(nestPool) then
        nestPool = map.chunkToNests
    end

    if not nestPool or not next(nestPool) then
        game.print("[Strike2] FAILED - No nests available on map")
        return false
    end

    -- Filter nests: must be in correct direction, far enough, and not near player zones
    local nestCandidates = {}
    local rejectedNests = {}  -- Track rejections for debug visualization
    local minDistSq = strike2Manager.MIN_NEST_DISTANCE * strike2Manager.MIN_NEST_DISTANCE

    for nestChunk, _ in pairs(nestPool) do
        if nestChunk and nestChunk ~= -1 then
            -- Check distance
            local nestX = nestChunk.x * 32
            local nestY = nestChunk.y * 32
            local dx = nestX - targetX
            local dy = nestY - targetY
            local distSq = dx * dx + dy * dy

            if distSq < minDistSq then
                rejectedNests[#rejectedNests + 1] = {
                    chunk = nestChunk,
                    reason = "too_close",
                    dist = math.sqrt(distSq)
                }
            elseif not nestIsValidForStrike(nestChunk, target, strikeDirection, map) then
                rejectedNests[#rejectedNests + 1] = {
                    chunk = nestChunk,
                    reason = "wrong_direction_or_player_zone",
                    dist = math.sqrt(distSq)
                }
            else
                nestCandidates[#nestCandidates + 1] = {
                    chunk = nestChunk,
                    distSqToTarget = distSq
                }
            end
        end
    end

    -- Debug visualization: show 20% of rejected nests with detailed map icons
    if #rejectedNests > 0 then
        local rejectCount = #rejectedNests
        local visualCount = math.max(1, math.floor(rejectCount * 0.2))
        game.print("[Strike2] Debug: " .. rejectCount .. " nests rejected, visualizing ~" .. visualCount .. " with map markers")

        for i = 1, visualCount do
            local idx = math.random(1, #rejectedNests)
            local rejected = rejectedNests[idx]
            local nestPos = {x = rejected.chunk.x * 32, y = rejected.chunk.y * 32}

            -- Draw red circle on map at rejected nest location (30 second duration)
            rendering.draw_circle({
                color = {1, 0, 0},  -- Red
                radius = 20,
                width = 3,
                surface = surface,
                target = nestPos,
                time_to_live = 1800,  -- 30 seconds
                draw_on_ground = true
            })

            -- Create detailed label based on rejection reason
            local labelText = ""
            if rejected.reason == "too_close" then
                labelText = string.format("TOO CLOSE\n%.0f tiles\n(need %d)", rejected.dist, strike2Manager.MIN_NEST_DISTANCE)
            else
                -- wrong_direction_or_player_zone - calculate which direction it actually is
                local dx = nestPos.x - targetX
                local dy = nestPos.y - targetY
                local actualDir = "?"
                if math.abs(dx) > math.abs(dy) then
                    actualDir = dx > 0 and "E" or "W"
                else
                    actualDir = dy > 0 and "S" or "N"
                end
                labelText = string.format("INVALID\nActual: %s\nNeed: %s", actualDir, strikeDirection.name)
            end

            -- Draw text label with more detail
            rendering.draw_text({
                text = labelText,
                surface = surface,
                target = nestPos,
                color = {1, 0, 0},
                scale = 1,
                time_to_live = 1800,
                alignment = "center",
                vertical_alignment = "middle"
            })

            -- Log detailed rejection reason
            local reason = rejected.reason == "too_close" and
                string.format("TOO_CLOSE (%.0f/need %d)", rejected.dist, strike2Manager.MIN_NEST_DISTANCE) or
                "WRONG_DIR_OR_PLAYER_ZONE"
            game.print(string.format("[Strike2] REJECT [gps=%d,%d] %s",
                nestPos.x, nestPos.y, reason))

            table.remove(rejectedNests, idx)
        end
    end

    if #nestCandidates == 0 then
        game.print("[Strike2] FAILED - No nests passed all filters")
        return false
    end

    -- Sort by distance to target (closest first)
    table.sort(nestCandidates, function(a, b)
        return a.distSqToTarget < b.distSqToTarget
    end)

    local closestNestToTarget = math.floor(math.sqrt(nestCandidates[1].distSqToTarget))
    local furthestNestToTarget = math.floor(math.sqrt(nestCandidates[#nestCandidates].distSqToTarget))
    game.print("[Strike2] Found " .. #nestCandidates .. " valid nest chunks in direction " .. strikeDirection.name .. ", range: " .. closestNestToTarget .. "-" .. furthestNestToTarget .. " tiles from target")

    if debugPrint then
        local poolCount = 0
        for _ in pairs(nestPool) do poolCount = poolCount + 1 end
        game.print("[Strike2] Nest pool size: " .. poolCount .. ", Rejected: " .. #rejectedNests .. ", Accepted: " .. #nestCandidates)
    end

    -- Deploy squads
    local squadsDeployed = 0
    local chunkX, chunkY = mapUtils.positionToChunkXY(targetPos)
    local targetChunk = mapUtils.getChunkByXY(map, chunkX, chunkY)

    if not universe or not universe.formCommand or not universe.formGroupCommand then
        if debugPrint then
            game.print("[Strike2] Cannot deploy: universe commands not initialized")
        end
        return false
    end

    local nestIndex = 1
    for i = 1, strike2Manager.SQUADS_PER_STRIKE2 do
        local squadCreated = false
        local attempts = 0

        while not squadCreated and attempts < 5 and nestIndex <= #nestCandidates do
            attempts = attempts + 1
            local nestChunk = nestCandidates[nestIndex].chunk
            nestIndex = nestIndex + 1
            if nestIndex > #nestCandidates then
                nestIndex = 1
            end

            local squadPath, squadDirection = movementUtils.scoreNeighborsForFormation(
                mapUtils.getNeighborChunks(map, nestChunk.x, nestChunk.y),
                scoreChunks.validUnitGroupLocation,
                scoreChunks.scoreUnitGroupLocation,
                map
            )

            if squadPath == -1 then
                if debugPrint then
                    game.print("[Strike2] Squad " .. i .. " attempt " .. attempts .. " - no valid formation chunk")
                end
            else
                local formationPos = mapUtils.positionFromDirectionAndChunk(
                    squadDirection, nestChunk, universe.position, 0.98
                )
                local squadPosition = surface.find_non_colliding_position(
                    "chunk-scanner-squad-rampant", formationPos, constants.CHUNK_SIZE, 4, true
                )

                if not squadPosition then
                    if debugPrint then
                        game.print("[Strike2] Squad " .. i .. " attempt " .. attempts .. " - no non-colliding position")
                    end
                else
                    local squad = unitGroupUtils.createSquad(squadPosition, map)
                    if squad then
                        universe.formGroupCommand.group = squad.group
                        universe.formCommand.unit_count = 40
                        local originalDistance = universe.formCommand.unit_search_distance
                        universe.formCommand.unit_search_distance = constants.CHUNK_SIZE * 5
                        local foundUnits = surface.set_multi_command(universe.formCommand)
                        universe.formCommand.unit_search_distance = originalDistance

                        if foundUnits > 0 then
                            -- Strike2-specific behavior
                            squad.customTarget = {x = targetX, y = targetY}
                            squad.status = constants.SQUAD_RAIDING
                            squad.strike2 = true  -- Flag for special behavior in SquadAttack
                            squad.strikeObjective = {x = targetX, y = targetY}

                            -- Gathering window
                            squad.targetMemberCount = foundUnits
                            squad.formingMinUntil = tick + 600  -- 10 sec minimum
                            squad.formingUntil = tick + 900     -- 15 sec hard cap

                            universe.groupNumberToSquad[squad.groupNumber] = squad
                            universe.squadCount = universe.squadCount + 1

                            if targetChunk and targetChunk ~= -1 then
                                chunkPropertyUtils.addSquadToChunk(map, targetChunk, squad)
                            end

                            squadsDeployed = squadsDeployed + 1
                            squadCreated = true
                            game.print("[Strike2] Squad " .. i .. " deployed from [gps=" .. math.floor(squadPosition.x) .. "," .. math.floor(squadPosition.y) .. "," .. surface.name .. "]")
                        else
                            if squad.group and squad.group.valid then
                                squad.group.destroy()
                            end
                        end
                    end
                end
            end
        end

        if not squadCreated and debugPrint then
            game.print("[Strike2] Squad " .. i .. " FAILED after " .. attempts .. " attempts")
        end
    end

    game.print("[Strike2] Deployed " .. squadsDeployed .. " squads - Directional strike initiated!")

    -- Set regular strike cooldown to 10 minutes
    map.strikeState.cooldownEndTick = tick + strike2Manager.STRIKE_COOLDOWN_ON_STRIKE2
    if debugPrint then
        game.print("[Strike2] Regular strike cooldown set to 10 minutes")
    end

    -- Show alert to players
    local entitiesAtTarget = surface.find_entities_filtered({
        area = {{targetX - 50, targetY - 50}, {targetX + 50, targetY + 50}},
        limit = 1
    })

    local alertEntity = nil
    if #entitiesAtTarget > 0 then
        alertEntity = entitiesAtTarget[1]
    else
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
                            "Strike2 incoming - Directional attack!",
                            true
                        )
                    end
                end
            end
        end

        if not entitiesAtTarget or #entitiesAtTarget == 0 then
            if alertEntity.valid then
                alertEntity.destroy()
            end
        end
    end

    return true
end

strike2ManagerG = strike2Manager
return strike2Manager
