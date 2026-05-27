if strike2ManagerG then
    return strike2ManagerG
end
local strike2Manager = {}

local constants = require("libs/Constants")
local zoneManager = require("libs/ZoneManager")
local strikeTargeting = require("libs/StrikeTargeting")
local unitGroupUtils = require("libs/UnitGroupUtils")
local chunkPropertyUtils = require("libs/ChunkPropertyUtils")
local mapUtils = require("libs/MapUtils")
local movementUtils = require("libs/MovementUtils")
local scoreChunks = require("libs/ScoreChunks")

-- ── CONFIG ────────────────────────────────────────────────────────────────────
strike2Manager.STRIKE2_ENABLED_EVOLUTION  = 0.20
strike2Manager.SQUADS_PER_STRIKE2         = 5
strike2Manager.MIN_NEST_DISTANCE          = 300   -- minimum tile distance from objective
strike2Manager.MAX_NEST_DISTANCE          = 800   -- maximum tile distance from objective
strike2Manager.STRIKE_COOLDOWN_ON_STRIKE2 = 10 * 60 * 60  -- 10 min in ticks

-- Direction vectors: N, NE, E, SE, S, SW, W, NW
local DIRECTIONS = {
    {dx = 0,  dy = -1, name = "N"},
    {dx = 1,  dy = -1, name = "NE"},
    {dx = 1,  dy =  0, name = "E"},
    {dx = 1,  dy =  1, name = "SE"},
    {dx = 0,  dy =  1, name = "S"},
    {dx = -1, dy =  1, name = "SW"},
    {dx = -1, dy =  0, name = "W"},
    {dx = -1, dy = -1, name = "NW"},
}

-- ── DIRECTION & ZONE CHECKS ───────────────────────────────────────────────────

local function determineStrikeDirection(map, targetZone)
    if not targetZone then return nil, 0 end

    local zx, zy = targetZone.zx, targetZone.zy
    local bestDir, maxEmpty = nil, -1
    local directionScores = {}

    for _, dir in ipairs(DIRECTIONS) do
        local emptyCount = 0
        local px, py = zx + dir.dx, zy + dir.dy

        if not map.zones[px] or not map.zones[px][py] then
            emptyCount = emptyCount + 1
        elseif not strikeTargeting.getZoneCategory(map.zones[px][py], map, true) then
            emptyCount = emptyCount + 1
        end

        local p1x, p1y = zx + dir.dx, zy + dir.dy - dir.dx
        local p2x, p2y = zx + dir.dx, zy + dir.dy + dir.dx

        if not map.zones[p1x] or not map.zones[p1x][p1y] then
            emptyCount = emptyCount + 1
        elseif not strikeTargeting.getZoneCategory(map.zones[p1x][p1y], map, true) then
            emptyCount = emptyCount + 1
        end

        if not map.zones[p2x] or not map.zones[p2x][p2y] then
            emptyCount = emptyCount + 1
        elseif not strikeTargeting.getZoneCategory(map.zones[p2x][p2y], map, true) then
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

-- Returns "ok", "wrong_direction", or "player_zone"
local function nestPassesDirectionAndZoneCheck(nestChunk, targetZone, strikeDirection, map)
    if not strikeDirection or not targetZone or not map then
        return "wrong_direction"
    end

    local targetX = targetZone.tileX + zoneManager.ZONE_TILE_SIZE / 2
    local targetY = targetZone.tileY + zoneManager.ZONE_TILE_SIZE / 2
    local dx = nestChunk.x - targetX
    local dy = nestChunk.y - targetY
    local TILE_TOLERANCE = 250

    if (strikeDirection.dx == 0) or (strikeDirection.dy == 0) then
        -- Cardinal: one axis pinned, other constrained by tolerance
        if strikeDirection.dx == 0 then
            if strikeDirection.dy > 0 and dy <= 0 then return "wrong_direction" end
            if strikeDirection.dy < 0 and dy >= 0 then return "wrong_direction" end
            if math.abs(dx) > TILE_TOLERANCE         then return "wrong_direction" end
        else
            if strikeDirection.dx > 0 and dx <= 0 then return "wrong_direction" end
            if strikeDirection.dx < 0 and dx >= 0 then return "wrong_direction" end
            if math.abs(dy) > TILE_TOLERANCE         then return "wrong_direction" end
        end
    else
        -- Diagonal: both axes must be in the correct quadrant
        if strikeDirection.dx > 0 and dx <= 0 then return "wrong_direction" end
        if strikeDirection.dx < 0 and dx >= 0 then return "wrong_direction" end
        if strikeDirection.dy > 0 and dy <= 0 then return "wrong_direction" end
        if strikeDirection.dy < 0 and dy >= 0 then return "wrong_direction" end
    end

    -- Reject if any interior 3×3 zone around the nest is player-controlled
    local nestZoneX = math.floor(nestChunk.x / zoneManager.ZONE_TILE_SIZE)
    local nestZoneY = math.floor(nestChunk.y / zoneManager.ZONE_TILE_SIZE)
    for zx = nestZoneX - 1, nestZoneX + 1 do
        for zy = nestZoneY - 1, nestZoneY + 1 do
            local zone = map.zones[zx] and map.zones[zx][zy]
            if zone and strikeTargeting.getZoneCategory(zone, map, true) then
                return "player_zone"
            end
        end
    end

    return "ok"
end

-- ── SQUAD HELPERS ─────────────────────────────────────────────────────────────

-- Return all nests passing direction+zone checks within [minDist, maxDist], closest-first.
local function getNestCandidatesFiltered(nestPool, targetX, targetY, targetZone, strikeDirection, map, minDist, maxDist)
    local candidates = {}
    local minDistSq = minDist * minDist
    local maxDistSq = maxDist * maxDist
    for nestChunk, _ in pairs(nestPool) do
        if nestChunk and nestChunk ~= -1 then
            local dx = nestChunk.x - targetX
            local dy = nestChunk.y - targetY
            local distSq = dx * dx + dy * dy
            if distSq >= minDistSq and distSq <= maxDistSq then
                if nestPassesDirectionAndZoneCheck(nestChunk, targetZone, strikeDirection, map) == "ok" then
                    candidates[#candidates+1] = {chunk = nestChunk, distSq = distSq}
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.distSq < b.distSq end)
    return candidates
end

-- Try to form a squad via normal unit gathering.
-- Returns: squad, squadPos, foundUnits  OR  nil, nil, failReason
local function tryNestFormation(surface, map, universe, nestChunk)
    local neighbors = mapUtils.getNeighborChunks(map, nestChunk.x, nestChunk.y)
    local squadPath, squadDirection = movementUtils.scoreNeighborsForFormation(
        neighbors, scoreChunks.validUnitGroupLocation, scoreChunks.scoreUnitGroupLocation, map
    )
    if squadPath == -1 then return nil, nil, "no_formation" end

    local formPos = mapUtils.positionFromDirectionAndChunk(squadDirection, nestChunk, universe.position, 0.98)
    local squadPos = surface.find_non_colliding_position(
        "chunk-scanner-squad-rampant", formPos, constants.CHUNK_SIZE, 4, true
    )
    if not squadPos then return nil, nil, "no_position" end

    local squad = unitGroupUtils.createSquad(squadPos, map)
    if not squad then return nil, nil, "no_squad" end

    universe.formGroupCommand.group = squad.group
    universe.formCommand.unit_count = 40
    local origDist = universe.formCommand.unit_search_distance
    universe.formCommand.unit_search_distance = constants.CHUNK_SIZE * 5
    local found = surface.set_multi_command(universe.formCommand)
    universe.formCommand.unit_search_distance = origDist

    if found > 0 then
        return squad, squadPos, found
    end
    if squad.group and squad.group.valid then squad.group.destroy() end
    return nil, nil, "no_units"
end

-- Spawn biters directly from nest prototype into squad group — bypasses gather timeout.
-- Returns number of biters actually spawned into the group.
local function spawnBitersForSquad(surface, nestChunk, squad, count)
    local nestX, nestY = nestChunk.x, nestChunk.y

    -- Determine unit types from nearby spawner
    local spawners = surface.find_entities_filtered{
        type  = "unit-spawner",
        area  = {{nestX - 48, nestY - 48}, {nestX + 48, nestY + 48}},
        limit = 3
    }
    local unitTypes = {}
    for _, spawner in ipairs(spawners) do
        if spawner.valid then
            local ru = spawner.prototype.result_units
            if ru then
                for _, def in ipairs(ru) do
                    unitTypes[#unitTypes+1] = def.unit
                end
            end
        end
    end
    -- Fallback by evolution if no spawner is loaded in this chunk
    if #unitTypes == 0 then
        local evo = game.forces.enemy.get_evolution_factor(surface)
        if evo < 0.3 then
            unitTypes = {"small-biter"}
        elseif evo < 0.6 then
            unitTypes = {"small-biter", "medium-biter"}
        elseif evo < 0.8 then
            unitTypes = {"medium-biter", "big-biter"}
        else
            unitTypes = {"big-biter", "behemoth-biter"}
        end
    end

    local spawned = 0
    local anchor = {x = nestX + 8, y = nestY + 8}
    for _ = 1, count do
        local utype = unitTypes[math.random(1, #unitTypes)]
        local pos = surface.find_non_colliding_position(utype, anchor, 32, 4, true)
        if pos then
            local unit = surface.create_entity({name = utype, position = pos, force = "enemy"})
            if unit and unit.valid then
                squad.group.add_member(unit)
                spawned = spawned + 1
            end
        end
    end
    return spawned
end

-- ── MAIN ENTRY POINT ─────────────────────────────────────────────────────────

function strike2Manager.initiateStrike2(map, surface, universe)
    if not map or not map.strikeState or not map.zonesByIndex or #map.zonesByIndex == 0 then
        game.print("[Strike2] Cannot initiate: map or zones not ready")
        return false
    end

    local tick = game.tick
    local debugPrint = settings.global["rampantFixed--debugStrikeTargeting"].value

    local evolution = game.forces.enemy.get_evolution_factor(surface)
    if evolution < strike2Manager.STRIKE2_ENABLED_EVOLUTION then
        game.print("[Strike2] Disabled: evolution " .. math.floor(evolution * 100) .. "% < "
            .. math.floor(strike2Manager.STRIKE2_ENABLED_EVOLUTION * 100) .. "%")
        return false
    end

    -- ── Target selection (same logic as StrikeManager) ────────────────────────
    local categoryZones = {
        ["products"]      = {},
        ["power"]         = {},
        ["oil"]           = {},
        ["raw-resources"] = {},
        ["outpost"]       = {}
    }
    for _, zone in ipairs(map.zonesByIndex) do
        local category = strikeTargeting.getZoneCategory(zone, map)
        if category and categoryZones[category] then
            table.insert(categoryZones[category], zone)
        end
    end

    local availableCats = {}
    for cat, zones in pairs(categoryZones) do
        if #zones > 0 then table.insert(availableCats, cat) end
    end
    if #availableCats == 0 then
        game.print("[Strike2] No targetable zones found")
        return false
    end

    math.randomseed(game.tick + tick)
    local selectedCat  = availableCats[math.random(1, #availableCats)]
    local targetZones  = categoryZones[selectedCat]
    local target

    if selectedCat == "products" then
        local globalTotalRate = 0
        for _, zone in ipairs(map.zonesByIndex) do
            globalTotalRate = globalTotalRate + (zone.totalRate or 0)
        end
        local weights, totalWeight = {}, 0
        for i, zone in ipairs(targetZones) do
            local share = (globalTotalRate > 0) and ((zone.totalRate or 0) / globalTotalRate) or 0
            local w = (share * share) * (1 + (strikeTargeting.calculateProductValue(zone) or 0) * 0.1)
            if w < 0.0001 then w = 0.0001 end
            weights[i] = w
            totalWeight = totalWeight + w
        end
        local roll, cumulative = math.random() * totalWeight, 0
        target = targetZones[#targetZones]
        for i, w in ipairs(weights) do
            cumulative = cumulative + w
            if roll <= cumulative then target = targetZones[i]; break end
        end
    else
        target = targetZones[math.random(1, #targetZones)]
    end

    if not target then
        game.print("[Strike2] Failed to select target zone")
        return false
    end

    local targetX   = target.tileX + zoneManager.ZONE_TILE_SIZE / 2
    local targetY   = target.tileY + zoneManager.ZONE_TILE_SIZE / 2
    local targetPos = {x = targetX, y = targetY}

    -- ── Direction ─────────────────────────────────────────────────────────────
    local strikeDirection, emptyCount, directionScores = determineStrikeDirection(map, target)
    if not strikeDirection then
        game.print("[Strike2] No valid strike direction found")
        return false
    end

    game.print("[Strike2] Target [gps=" .. math.floor(targetX) .. "," .. math.floor(targetY)
        .. "," .. surface.name .. "] | direction " .. strikeDirection.name
        .. " (empty adjacent zones: " .. emptyCount .. ")")

    if debugPrint then
        local dirStr = ""
        for _, dir in ipairs(DIRECTIONS) do
            dirStr = dirStr .. dir.name .. ":" .. (directionScores[dir.name] or 0) .. " "
        end
        game.print("[Strike2] Direction scores: " .. dirStr)
    end

    -- ── Nest pool ─────────────────────────────────────────────────────────────
    local nestPool = map.chunkToNests
    if not nestPool or not next(nestPool) then
        game.print("[Strike2] FAILED - No nests available on map")
        return false
    end

    -- Initial full-pool scan for the rejection summary + debug markers
    local rejectCounts = {too_close = 0, too_far = 0, wrong_direction = 0, player_zone = 0}
    local rejectedNests = {}
    local poolCount = 0
    local initialAccepted = 0
    local minDistSq = strike2Manager.MIN_NEST_DISTANCE * strike2Manager.MIN_NEST_DISTANCE
    local maxDistSq = strike2Manager.MAX_NEST_DISTANCE * strike2Manager.MAX_NEST_DISTANCE

    for nestChunk, _ in pairs(nestPool) do
        if nestChunk and nestChunk ~= -1 then
            poolCount = poolCount + 1
            local dx = nestChunk.x - targetX
            local dy = nestChunk.y - targetY
            local distSq = dx * dx + dy * dy
            local dist = math.sqrt(distSq)
            local reason
            if distSq < minDistSq then
                reason = "too_close"
            elseif distSq > maxDistSq then
                reason = "too_far"
            else
                reason = nestPassesDirectionAndZoneCheck(nestChunk, target, strikeDirection, map)
            end
            if reason == "ok" then
                initialAccepted = initialAccepted + 1
            else
                rejectCounts[reason] = (rejectCounts[reason] or 0) + 1
                rejectedNests[#rejectedNests+1] = {chunk = nestChunk, reason = reason, dist = dist}
            end
        end
    end

    game.print(string.format("[Strike2] Pool: %d | too_close: %d | too_far: %d | wrong_dir: %d | player_zone: %d | accepted: %d (300-800 band)",
        poolCount, rejectCounts.too_close, rejectCounts.too_far, rejectCounts.wrong_direction, rejectCounts.player_zone, initialAccepted))

    -- Debug markers: up to 5 per rejection category
    local COLORS = {
        too_close       = {0, 0.5, 1},
        too_far         = {1, 0.5, 0},
        wrong_direction = {1, 0, 0},
        player_zone     = {1, 0, 1},
    }
    local shown = {too_close = 0, too_far = 0, wrong_direction = 0, player_zone = 0}
    for _, rej in ipairs(rejectedNests) do
        local cat = rej.reason
        if (shown[cat] or 0) >= 5 then goto continue_viz end
        shown[cat] = shown[cat] + 1
        local nestPos = {x = rej.chunk.x, y = rej.chunk.y}
        local color   = COLORS[cat] or {1, 1, 1}

        rendering.draw_circle({color = color, radius = 20, width = 3,
            surface = surface, target = nestPos, time_to_live = 1800})

        local adx = nestPos.x - targetX
        local ady = nestPos.y - targetY
        local actualDir
        if math.abs(adx) > math.abs(ady) then
            actualDir = adx > 0 and "E" or "W"
        else
            actualDir = ady > 0 and "S" or "N"
        end
        local lbl
        if cat == "too_close" then
            lbl = string.format("TOO CLOSE\n%.0f/min %d", rej.dist, strike2Manager.MIN_NEST_DISTANCE)
        elseif cat == "too_far" then
            lbl = string.format("TOO FAR\n%.0f/max %d", rej.dist, strike2Manager.MAX_NEST_DISTANCE)
        elseif cat == "wrong_direction" then
            lbl = string.format("WRONG DIR\nActual:%s Need:%s\n%.0f tiles", actualDir, strikeDirection.name, rej.dist)
        else
            lbl = string.format("PLAYER ZONE\n%.0f tiles", rej.dist)
        end
        rendering.draw_text({text = lbl, surface = surface, target = nestPos,
            color = color, scale = 1, time_to_live = 1800, alignment = "center"})

        ::continue_viz::
    end

    -- ── Squad deployment with progressive broadening ──────────────────────────
    --
    --  Band 1 : initial range        (MIN      – MAX)
    --  Band 2 : expand both by 100   (MIN-100  – MAX+100)
    --  Band 3 : expand max only      (MIN-100  – MAX+200)
    --  Band 4 :                      (MIN-100  – MAX+300)
    --  Band 5 :                      (MIN-100  – MAX+400)
    --  Fallback: spawn biters directly from closest qualifying nest
    --
    local BASE_MIN = strike2Manager.MIN_NEST_DISTANCE
    local BASE_MAX = strike2Manager.MAX_NEST_DISTANCE
    local BANDS = {
        {minD = BASE_MIN,       maxD = BASE_MAX},
        {minD = BASE_MIN - 100, maxD = BASE_MAX + 100},
        {minD = BASE_MIN - 100, maxD = BASE_MAX + 200},
        {minD = BASE_MIN - 100, maxD = BASE_MAX + 300},
        {minD = BASE_MIN - 100, maxD = BASE_MAX + 400},
    }

    local squadsDeployed = 0
    local chunkX, chunkY = mapUtils.positionToChunkXY(targetPos)
    local targetChunk    = mapUtils.getChunkByXY(map, chunkX, chunkY)

    if not universe or not universe.formCommand or not universe.formGroupCommand then
        game.print("[Strike2] Cannot deploy: universe commands not initialized")
        return false
    end

    for i = 1, strike2Manager.SQUADS_PER_STRIKE2 do
        local squad, squadPos, foundUnits, wasSpawned
        local lastCandidates = nil

        -- Try each broadening band
        for bandIdx, band in ipairs(BANDS) do
            if squad then break end
            local minD = math.max(50, band.minD)
            local bandCandidates = getNestCandidatesFiltered(
                nestPool, targetX, targetY, target, strikeDirection, map, minD, band.maxD
            )
            lastCandidates = bandCandidates

            if bandIdx > 1 and #bandCandidates > 0 then
                game.print(string.format("[Strike2] Squad %d: broadening to min=%d max=%d (%d candidates)",
                    i, minD, band.maxD, #bandCandidates))
            end

            for _, candidate in ipairs(bandCandidates) do
                if squad then break end
                local s, sp, found = tryNestFormation(surface, map, universe, candidate.chunk)
                if s then
                    squad = s; squadPos = sp; foundUnits = found
                end
            end
        end

        -- Fallback: spawn biters directly from the closest nest in the widest band
        if not squad and lastCandidates and #lastCandidates > 0 then
            local fallbackNest = lastCandidates[1].chunk
            local fallbackPos  = surface.find_non_colliding_position(
                "chunk-scanner-squad-rampant",
                {x = fallbackNest.x + 8, y = fallbackNest.y + 8},
                constants.CHUNK_SIZE, 8, true
            )
            if fallbackPos then
                local s = unitGroupUtils.createSquad(fallbackPos, map)
                if s then
                    local spawned = spawnBitersForSquad(surface, fallbackNest, s, 40)
                    if spawned > 0 then
                        squad      = s
                        squadPos   = fallbackPos
                        foundUnits = spawned
                        wasSpawned = true
                        game.print(string.format("[Strike2] Squad %d: SPAWNED %d biters from [gps=%d,%d,%s]",
                            i, spawned, math.floor(fallbackNest.x), math.floor(fallbackNest.y), surface.name))
                    else
                        if s.group and s.group.valid then s.group.destroy() end
                    end
                end
            end
        end

        if squad then
            squad.customTarget     = {x = targetX, y = targetY}
            squad.status           = constants.SQUAD_RAIDING
            squad.strike2          = true
            squad.strikeObjective  = {x = targetX, y = targetY}
            squad.targetMemberCount = foundUnits

            if wasSpawned then
                -- Biters are already in the group — skip the gathering window entirely
                squad.formingMinUntil = nil
                squad.formingUntil    = nil
            else
                squad.formingMinUntil = tick + 600   -- wait at least 10 sec
                squad.formingUntil    = tick + 900   -- hard cap 15 sec
            end

            universe.groupNumberToSquad[squad.groupNumber] = squad
            universe.squadCount = universe.squadCount + 1

            if targetChunk and targetChunk ~= -1 then
                chunkPropertyUtils.addSquadToChunk(map, targetChunk, squad)
            end

            squadsDeployed = squadsDeployed + 1
            game.print(string.format("[Strike2] Squad %d deployed%s at [gps=%d,%d,%s]",
                i, wasSpawned and " (spawned)" or "",
                math.floor(squadPos.x), math.floor(squadPos.y), surface.name))
        else
            game.print("[Strike2] Squad " .. i .. " FAILED — all bands and spawn fallback exhausted")
        end
    end

    game.print("[Strike2] " .. squadsDeployed .. "/" .. strike2Manager.SQUADS_PER_STRIKE2
        .. " squads deployed — directional strike incoming!")

    -- Set regular strike on cooldown for 10 minutes
    map.strikeState.cooldownEndTick = tick + strike2Manager.STRIKE_COOLDOWN_ON_STRIKE2

    -- Alert players near the target
    local chunkVisible = false
    for _, force in pairs(game.forces) do
        if force.is_chunk_visible(surface, {x = chunkX, y = chunkY}) then
            chunkVisible = true
            break
        end
    end
    if chunkVisible then
        local nearby = surface.find_entities_filtered{
            area  = {{targetX - 50, targetY - 50}, {targetX + 50, targetY + 50}},
            limit = 1
        }
        local alertEntity = nearby[1]
        local tempCreated = false
        if not alertEntity then
            alertEntity = surface.create_entity{name = "wooden-chest", position = targetPos, force = "enemy"}
            tempCreated = alertEntity ~= nil
        end
        if alertEntity then
            for _, force in pairs(game.forces) do
                for _, player in pairs(force.connected_players) do
                    local ps = settings.get_player_settings(player)
                    if ps["rampantFixed--showSquadAlert"].value then
                        player.add_custom_alert(alertEntity,
                            {type = "entity", name = "biter-spawner"},
                            "Strike2 — directional assault incoming!", true)
                    end
                end
            end
            if tempCreated and alertEntity.valid then alertEntity.destroy() end
        end
    end

    return true
end

strike2ManagerG = strike2Manager
return strike2Manager
