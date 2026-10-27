if strikeManagerG then
    return strikeManagerG
end
local strikeManager = {}

local constants = require("libs/Constants")
local zoneManager = require("libs/ZoneManager")
local strikeTargeting = require("libs/StrikeTargeting")
local unitGroupUtils = require("libs/UnitGroupUtils")
local chunkPropertyUtils = require("libs/ChunkPropertyUtils")
local mapUtils = require("libs/MapUtils")

-- Strike configuration
strikeManager.STRIKE_ENABLED_EVOLUTION = 0.20           -- natural strikes only (20% evolution)
strikeManager.STRIKE_COOLDOWN_DURATION = 10 * 60 * 60   -- set after each strike, natural or command

function strikeManager.initStrikes(map)
    if not map then return end
    map.strikeState = {
        cooldownEndTick = 0,
        lastStrikeCategory = nil,
        lastStrikeTarget = nil,
        enabled = false
    }
end
-- ── CONFIG ────────────────────────────────────────────────────────────────────
strikeManager.MIN_NEST_DISTANCE          = 300
strikeManager.MAX_NEST_DISTANCE          = 400

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

local function nestPassesDirectionAndZoneCheck(nestChunk, targetZone, strikeDirection, map)
    if not strikeDirection or not targetZone or not map then return "wrong_direction" end
    local targetX = targetZone.tileX + zoneManager.ZONE_TILE_SIZE / 2
    local targetY = targetZone.tileY + zoneManager.ZONE_TILE_SIZE / 2
    local dx = nestChunk.x - targetX
    local dy = nestChunk.y - targetY
    local TILE_TOLERANCE = 250
    if (strikeDirection.dx == 0) or (strikeDirection.dy == 0) then
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
        if strikeDirection.dx > 0 and dx <= 0 then return "wrong_direction" end
        if strikeDirection.dx < 0 and dx >= 0 then return "wrong_direction" end
        if strikeDirection.dy > 0 and dy <= 0 then return "wrong_direction" end
        if strikeDirection.dy < 0 and dy >= 0 then return "wrong_direction" end
    end
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

-- ── SPAWN HELPER ──────────────────────────────────────────────────────────────

-- Relative chance of a spawner's result unit at the given evolution. Reads the
-- prototype's spawn_points curve (linear between points), so tiers outside the
-- current evolution get weight 0 instead of being picked as max-level biters.
local function unitWeightAtEvo(spawnPoints, evo)
    if not spawnPoints then return 1 end
    local prev
    for _, point in ipairs(spawnPoints) do
        if point.evolution_factor > evo then
            if not prev then return point.weight end
            local t = (evo - prev.evolution_factor) / (point.evolution_factor - prev.evolution_factor)
            return prev.weight + (point.weight - prev.weight) * t
        end
        prev = point
    end
    return prev and prev.weight or 0
end

local function getUnitTypesForNest(surface, nestChunk)
    local nestX, nestY = nestChunk.x, nestChunk.y
    local evo = game.forces.enemy.get_evolution_factor(surface)
    local spawners = surface.find_entities_filtered{
        type  = "unit-spawner",
        area  = {{nestX - 48, nestY - 48}, {nestX + 48, nestY + 48}},
        limit = 3
    }
    local unitTypes, weights = {}, {}
    for _, spawner in ipairs(spawners) do
        if spawner.valid then
            local ru = spawner.prototype.result_units
            if ru then
                for _, def in ipairs(ru) do
                    local weight = unitWeightAtEvo(def.spawn_points, evo)
                    if weight > 0 then
                        unitTypes[#unitTypes+1] = def.unit
                        weights[#weights+1] = weight
                    end
                end
            end
        end
    end
    if #unitTypes == 0 then
        if evo < 0.3 then
            unitTypes = {"small-biter"}
        elseif evo < 0.6 then
            unitTypes = {"small-biter", "medium-biter"}
        elseif evo < 0.8 then
            unitTypes = {"medium-biter", "big-biter"}
        else
            unitTypes = {"big-biter", "behemoth-biter"}
        end
        weights = {}
        for i = 1, #unitTypes do weights[i] = 1 end
    end
    return unitTypes, weights
end

local function pickWeighted(unitTypes, weights)
    local total = 0
    for _, w in ipairs(weights) do total = total + w end
    local roll = math.random() * total
    for i, w in ipairs(weights) do
        roll = roll - w
        if roll <= 0 then return unitTypes[i] end
    end
    return unitTypes[#unitTypes]
end

local function spawnSquadAtNest(surface, nestChunk, squad, count)
    local unitTypes, weights = getUnitTypesForNest(surface, nestChunk)
    local anchor = {x = nestChunk.x + 8, y = nestChunk.y + 8}
    local spawned = 0
    for _ = 1, count do
        local utype = pickWeighted(unitTypes, weights)
        local pos = surface.find_non_colliding_position(utype, anchor, constants.CHUNK_SIZE * 2, 8, true)
        if pos then
            local unit = surface.create_entity({name = utype, position = pos, force = "enemy"})
            if unit and unit.valid then
                squad.group.add_member(unit)
                surface.create_entity({name = "strikeSpeed-sticker-rampantFixed", target = unit, position = unit.position, force = "enemy"})
                spawned = spawned + 1
            end
        end
    end
    return spawned
end

local function findBestCluster(candidates, count)
    if #candidates <= count then return candidates end

    local bestAnchorIdx = 1
    local bestAvgDist   = math.huge

    for i, anchor in ipairs(candidates) do
        local dists = {}
        for j, other in ipairs(candidates) do
            if j ~= i then
                local dx = anchor.chunk.x - other.chunk.x
                local dy = anchor.chunk.y - other.chunk.y
                dists[#dists+1] = math.sqrt(dx*dx + dy*dy)
            end
        end
        table.sort(dists)

        local k = math.min(count - 1, #dists)
        local sum = 0
        for n = 1, k do sum = sum + dists[n] end
        local avg = k > 0 and (sum / k) or 0

        if avg < bestAvgDist then
            bestAvgDist   = avg
            bestAnchorIdx = i
        end
    end

    local anchor = candidates[bestAnchorIdx]
    local withDist = {}
    for _, c in ipairs(candidates) do
        local dx = anchor.chunk.x - c.chunk.x
        local dy = anchor.chunk.y - c.chunk.y
        withDist[#withDist+1] = {candidate = c, d = dx*dx + dy*dy}
    end
    table.sort(withDist, function(a, b) return a.d < b.d end)

    local result = {}
    for n = 1, math.min(count, #withDist) do
        result[#result+1] = withDist[n].candidate
    end
    return result, math.floor(bestAvgDist)
end

-- ── MAIN ENTRY POINT ─────────────────────────────────────────────────────────

-- Path check: for each direction (best score first), take the nearest nest that passes the
-- direction and zone rules inside the nest distance band. The line from that nest to the target
-- may cross at most one other zone that has a category. Zones that are missing or NONE don't count.
-- Zones are walked exactly with a grid traversal; a line through a zone corner may count either
-- neighbour. Every direction is tried until one passes.

-- Zones in the order a straight line from (fromX, fromY) to (toX, toY) enters them
-- (Amanatides-Woo grid traversal)
local function zonesAlongLine(fromX, fromY, toX, toY, tileSize)
    local x0, y0 = fromX / tileSize, fromY / tileSize
    local x1, y1 = toX / tileSize, toY / tileSize
    local zx, zy = math.floor(x0), math.floor(y0)
    local endZX, endZY = math.floor(x1), math.floor(y1)
    local dx, dy = x1 - x0, y1 - y0
    local stepX = (dx >= 0) and 1 or -1
    local stepY = (dy >= 0) and 1 or -1
    local tDeltaX = (dx ~= 0) and math.abs(1 / dx) or math.huge
    local tDeltaY = (dy ~= 0) and math.abs(1 / dy) or math.huge
    local tMaxX = (dx > 0 and (zx + 1 - x0) * tDeltaX) or (dx < 0 and (x0 - zx) * tDeltaX) or math.huge
    local tMaxY = (dy > 0 and (zy + 1 - y0) * tDeltaY) or (dy < 0 and (y0 - zy) * tDeltaY) or math.huge
    local zones = {{zx = zx, zy = zy}}
    local guard = 0
    while not (zx == endZX and zy == endZY) and guard < 1000 do
        guard = guard + 1
        if tMaxX < tMaxY then
            zx = zx + stepX
            tMaxX = tMaxX + tDeltaX
        else
            zy = zy + stepY
            tMaxY = tMaxY + tDeltaY
        end
        zones[#zones + 1] = {zx = zx, zy = zy}
    end
    return zones
end

-- Output value used for a zone's percentile in its own category
local function zoneOutputValue(zone, cat)
    if cat == "power" then return zone.powerGen or 0 end
    if cat == "outpost" then return zone.militaryBuildingCount or 0 end
    return zone.totalRate or 0 -- products, oil, raw-resources
end

-- Output values per category, for zones that have a category and output above 0
local function buildOutputPopulations(map)
    local pops = {}
    for _, zone in ipairs(map.zonesByIndex) do
        local cat = strikeTargeting.getZoneCategory(zone, map)
        local value = cat and zoneOutputValue(zone, cat) or 0
        if cat and value > 0 then
            pops[cat] = pops[cat] or {}
            table.insert(pops[cat], value)
        end
    end
    return pops
end

-- True if the zone beats more than 10% of the other zones in its category
local function isAboveTenthPercentile(zone, cat, pops)
    local list = pops[cat]
    local value = zoneOutputValue(zone, cat)
    if not list or #list < 2 or value <= 0 then return false end
    local below = 0
    for _, other in ipairs(list) do
        if other < value then below = below + 1 end
    end
    return below > 0.10 * (#list - 1)
end

-- Counts zones with a category that the line crosses (excluding start and end), and whether any
-- crossed zone is above the 10th percentile of its category
local function countCrossedZones(map, fromPos, toPos, pops)
    local tileSize = zoneManager.ZONE_TILE_SIZE
    local startZX, startZY = math.floor(fromPos.x / tileSize), math.floor(fromPos.y / tileSize)
    local endZX, endZY = math.floor(toPos.x / tileSize), math.floor(toPos.y / tileSize)
    local count, blocked = 0, false
    for _, z in ipairs(zonesAlongLine(fromPos.x, fromPos.y, toPos.x, toPos.y, tileSize)) do
        local isEnd = (z.zx == startZX and z.zy == startZY) or (z.zx == endZX and z.zy == endZY)
        if not isEnd then
            local zone = map.zones[z.zx] and map.zones[z.zx][z.zy]
            local cat = zone and strikeTargeting.getZoneCategory(zone, map)
            if cat then
                count = count + 1
                if isAboveTenthPercentile(zone, cat, pops) then blocked = true end
            end
        end
    end
    return count, blocked
end

-- Directions for a target, best score first (ties keep DIRECTIONS order)
local function rankedDirections(map, target)
    local _, _, scores = determineStrikeDirection(map, target)
    local ranked = {}
    for i, dir in ipairs(DIRECTIONS) do
        ranked[#ranked + 1] = {dir = dir, score = (scores and scores[dir.name]) or 0, index = i}
    end
    table.sort(ranked, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.index < b.index
    end)
    local out = {}
    for _, r in ipairs(ranked) do out[#out + 1] = r.dir end
    return out
end

-- Nearest nest inside the distance band that passes the direction and zone rules for this direction
local function firstNestFor(map, target, dir, targetX, targetY)
    local minDistSq = strikeManager.MIN_NEST_DISTANCE * strikeManager.MIN_NEST_DISTANCE
    local maxDistSq = strikeManager.MAX_NEST_DISTANCE * strikeManager.MAX_NEST_DISTANCE
    local best, bestDistSq = nil, nil
    for nestChunk in pairs(map.chunkToNests or {}) do
        if nestChunk and nestChunk ~= -1 then
            local dx, dy = nestChunk.x - targetX, nestChunk.y - targetY
            local distSq = dx * dx + dy * dy
            if distSq >= minDistSq and distSq <= maxDistSq and (not bestDistSq or distSq < bestDistSq)
                and nestPassesDirectionAndZoneCheck(nestChunk, target, dir, map) == "ok" then
                best, bestDistSq = nestChunk, distSq
            end
        end
    end
    return best
end

-- Returns passed, direction. A line fails if it crosses more than one zone with a category, or
-- any zone above the 10th percentile of its category (even the first one). If no direction has a
-- nest to test, passes with no direction so the nest search decides.
local function pathCheck(map, target, pops)
    local tileSize = zoneManager.ZONE_TILE_SIZE
    local targetX = target.tileX + tileSize / 2
    local targetY = target.tileY + tileSize / 2
    local anyNest = false
    for _, dir in ipairs(rankedDirections(map, target)) do
        local nest = firstNestFor(map, target, dir, targetX, targetY)
        if nest then
            anyNest = true
            local count, blocked = countCrossedZones(map, {x = nest.x, y = nest.y}, {x = targetX, y = targetY}, pops)
            if not blocked and count <= 1 then
                return true, dir
            end
        end
    end
    if not anyNest then return true, nil end
    return false
end

function strikeManager.strike(map, surface, universe)
    if not map or not map.strikeState or not map.zonesByIndex or #map.zonesByIndex == 0 then
        game.print("[Strike] Cannot initiate: map or zones not ready")
        return false
    end

    local tick = game.tick
    local debugPrint = settings.global["rampantFixed--debugStrikeTargeting"].value
    local squadsPerStrike = settings.global["rampantFixed--strikeSquadsPerStrike"].value
    local bitersPerSquad = settings.global["rampantFixed--strikeBitersPerSquad"].value

    -- ── Target selection (shared with natural strikes) ────────────────────────
    local validatedZone, validatedDir
    local outputPops = buildOutputPopulations(map)
    local target, selectedCat, populations = strikeTargeting.selectStrikeTarget(map, "[Strike]", function(candidate)
        local ok, dir = pathCheck(map, candidate, outputPops)
        if ok then validatedZone, validatedDir = candidate, dir end
        return ok
    end)
    if not target then
        return false
    end
    local producingRates = populations.producingRates
    local powerRates = populations.powerRates
    local outpostRates = populations.outpostRates

    local targetX   = target.tileX + zoneManager.ZONE_TILE_SIZE / 2
    local targetY   = target.tileY + zoneManager.ZONE_TILE_SIZE / 2
    local targetPos = {x = targetX, y = targetY}

    -- ── Direction ─────────────────────────────────────────────────────────────
    local strikeDirection, emptyCount, directionScores = determineStrikeDirection(map, target)
    if validatedZone == target and validatedDir then strikeDirection = validatedDir end
    if not strikeDirection then
        game.print("[Strike] No valid strike direction found")
        return false
    end

    strikeTargeting.markStruck(map, target)

    game.print("[Strike] Target [gps=" .. math.floor(targetX) .. "," .. math.floor(targetY)
        .. "," .. surface.name .. "] | direction " .. strikeDirection.name
        .. " (empty zones: " .. emptyCount .. ")")

    if debugPrint then
        -- Percentile = share of eligible-population zones whose output is at or below this zone's
        local value, population, unit = target.totalRate or 0, producingRates, "/s"
        if selectedCat == "power" then
            value, population, unit = target.powerGen or 0, powerRates, "MW"
        elseif selectedCat == "outpost" then
            value, population, unit = target.militaryBuildingCount or 0, outpostRates, "MIL"
        end
        local percentileText = "n/a"
        if value > 0 then
            local atOrBelow = 0
            for _, rate in ipairs(population) do
                if rate <= value then atOrBelow = atOrBelow + 1 end
            end
            percentileText = string.format("%.0f%%", atOrBelow / #population * 100)
        end
        game.print(string.format("[Strike debug] Zone [%d,%d] | cat: %s | output: %.1f%s | percentile: %s",
            target.zx, target.zy, selectedCat, value, unit, percentileText))
    end

    if debugPrint then
        local s = ""
        for _, dir in ipairs(DIRECTIONS) do s = s .. dir.name .. ":" .. (directionScores[dir.name] or 0) .. " " end
        game.print("[Strike] Direction scores: " .. s)
    end

    -- ── Nest pool ─────────────────────────────────────────────────────────────
    local nestPool = map.chunkToNests
    if not nestPool or not next(nestPool) then
        game.print("[Strike] FAILED - No nests on map")
        return false
    end

    -- Initial scan for debug summary (300-800 band)
    local rejectCounts = {too_close = 0, too_far = 0, wrong_direction = 0, player_zone = 0}
    local rejectedNests, poolCount, initialAccepted = {}, 0, 0
    local minDistSq = strikeManager.MIN_NEST_DISTANCE * strikeManager.MIN_NEST_DISTANCE
    local maxDistSq = strikeManager.MAX_NEST_DISTANCE * strikeManager.MAX_NEST_DISTANCE

    for nestChunk, _ in pairs(nestPool) do
        if nestChunk and nestChunk ~= -1 then
            poolCount = poolCount + 1
            local dx = nestChunk.x - targetX
            local dy = nestChunk.y - targetY
            local distSq = dx * dx + dy * dy
            local dist = math.sqrt(distSq)
            local reason
            if distSq < minDistSq then reason = "too_close"
            elseif distSq > maxDistSq then reason = "too_far"
            else reason = nestPassesDirectionAndZoneCheck(nestChunk, target, strikeDirection, map)
            end
            if reason == "ok" then
                initialAccepted = initialAccepted + 1
            else
                rejectCounts[reason] = (rejectCounts[reason] or 0) + 1
                rejectedNests[#rejectedNests+1] = {chunk = nestChunk, reason = reason, dist = dist}
            end
        end
    end

    game.print(string.format("[Strike] Pool: %d | too_close: %d | too_far: %d | wrong_dir: %d | player_zone: %d | accepted: %d",
        poolCount, rejectCounts.too_close, rejectCounts.too_far, rejectCounts.wrong_direction, rejectCounts.player_zone, initialAccepted))

    -- Debug markers
    local COLORS = {
        too_close = {0,0.5,1}, too_far = {1,0.5,0},
        wrong_direction = {1,0,0}, player_zone = {1,0,1}
    }
    local shown = {too_close=0, too_far=0, wrong_direction=0, player_zone=0}
    for _, rej in ipairs(rejectedNests) do
        local cat = rej.reason
        if (shown[cat] or 0) >= 5 then goto continue_viz end
        shown[cat] = shown[cat] + 1
        local nestPos = {x = rej.chunk.x, y = rej.chunk.y}
        local color = COLORS[cat] or {1,1,1}
        rendering.draw_circle({color=color, radius=20, width=3, surface=surface, target=nestPos, time_to_live=1800})
        local adx, ady = nestPos.x - targetX, nestPos.y - targetY
        local actualDir = math.abs(adx) > math.abs(ady) and (adx > 0 and "E" or "W") or (ady > 0 and "S" or "N")
        local lbl
        if cat == "too_close" then lbl = string.format("TOO CLOSE\n%.0f/min %d", rej.dist, strikeManager.MIN_NEST_DISTANCE)
        elseif cat == "too_far" then lbl = string.format("TOO FAR\n%.0f/max %d", rej.dist, strikeManager.MAX_NEST_DISTANCE)
        elseif cat == "wrong_direction" then lbl = string.format("WRONG DIR\nActual:%s Need:%s\n%.0f", actualDir, strikeDirection.name, rej.dist)
        else lbl = string.format("PLAYER ZONE\n%.0f tiles", rej.dist) end
        rendering.draw_text({text=lbl, surface=surface, target=nestPos, color=color, scale=1, time_to_live=1800, alignment="center"})
        ::continue_viz::
    end

    -- ── Build candidate list with broadening fallback ─────────────────────────
    local candidates = nil
    local usedMin, usedMax = strikeManager.MIN_NEST_DISTANCE, strikeManager.MAX_NEST_DISTANCE
    local BANDS = {
        {minD = usedMin,       maxD = usedMax},
        {minD = usedMin - 100, maxD = usedMax + 100},
        {minD = usedMin - 100, maxD = usedMax + 200},
        {minD = usedMin - 100, maxD = usedMax + 300},
        {minD = usedMin - 100, maxD = usedMax + 400},
    }
    for bandIdx, band in ipairs(BANDS) do
        local minD = math.max(50, band.minD)
        local c = getNestCandidatesFiltered(nestPool, targetX, targetY, target, strikeDirection, map, minD, band.maxD)
        if #c >= squadsPerStrike or bandIdx == #BANDS then
            if bandIdx > 1 then
                game.print(string.format("[Strike] Broadened to min=%d max=%d → %d candidates", minD, band.maxD, #c))
            end
            candidates = c
            break
        end
    end

    if not candidates or #candidates == 0 then
        game.print("[Strike] FAILED - No qualifying nests found in any band")
        return false
    end

    -- Cluster: pick the tightest group of nests so squads arrive together
    local clusterAvgDist
    candidates, clusterAvgDist = findBestCluster(candidates, squadsPerStrike)
    game.print(string.format("[Strike] Cluster selected: %d nests, avg inter-nest dist ~%d tiles",
        #candidates, clusterAvgDist or 0))

    -- ── Deploy squads — always spawn, never gather ────────────────────────────
    local squadsDeployed = 0
    local chunkX, chunkY = mapUtils.positionToChunkXY(targetPos)
    local targetChunk    = mapUtils.getChunkByXY(map, chunkX, chunkY)

    for i = 1, squadsPerStrike do
        local nestCandidate = candidates[((i - 1) % #candidates) + 1]
        local nestChunk = nestCandidate.chunk

        local nestCenter = {x = nestChunk.x + 16, y = nestChunk.y + 16}
        local spawnPos = surface.find_non_colliding_position(
            "chunk-scanner-squad-rampant", nestCenter, constants.CHUNK_SIZE * 3, 16, true
        ) or nestCenter
        do
            local squad = unitGroupUtils.createSquad(spawnPos, map)
            if squad then
                local spawned = spawnSquadAtNest(surface, nestChunk, squad, bitersPerSquad)
                if spawned > 0 then
                    squad.customTarget    = {x = targetX, y = targetY}
                    squad.status          = constants.SQUAD_RAIDING
                    squad.strike2         = true   -- reuse force-move flag in SquadAttack
                    squad.strikeObjective = {x = targetX, y = targetY}
                    squad.strikeStart = {x = spawnPos.x, y = spawnPos.y} -- STRIKE RETREAT
                    squad.strikeSpawnTick = game.tick -- STRIKE RETREAT
                    squad.formingMinUntil = nil
                    squad.formingUntil    = nil

                    universe.groupNumberToSquad[squad.groupNumber] = squad
                    universe.squadCount = universe.squadCount + 1

                    if targetChunk and targetChunk ~= -1 then
                        chunkPropertyUtils.addSquadToChunk(map, targetChunk, squad)
                    end

                    squadsDeployed = squadsDeployed + 1
                    game.print(string.format("[Strike] Squad %d: %d biters spawned from [gps=%d,%d,%s]",
                        i, spawned, math.floor(nestChunk.x), math.floor(nestChunk.y), surface.name))
                else
                    if squad.group and squad.group.valid then squad.group.destroy() end
                    game.print("[Strike] Squad " .. i .. " FAILED - spawn produced 0 biters")
                end
            end
        end  -- do
    end

    game.print("[Strike] " .. squadsDeployed .. "/" .. squadsPerStrike
        .. " squads deployed — spawn strike incoming!")

    map.strikeState.cooldownEndTick = tick + strikeManager.STRIKE_COOLDOWN_DURATION

    -- Alert players
    local chunkVisible = false
    for _, force in pairs(game.forces) do
        if force.is_chunk_visible(surface, {x = chunkX, y = chunkY}) then chunkVisible = true; break end
    end
    if chunkVisible then
        local nearby = surface.find_entities_filtered{
            area = {{targetX-50, targetY-50}, {targetX+50, targetY+50}}, limit = 1
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
                            "Strike: spawn strike incoming!", true)
                    end
                end
            end
            if tempCreated and alertEntity.valid then alertEntity.destroy() end
        end
    end

    return true
end


-- Natural strike: the periodic on_tick path. Same strike as /r2-strike; only these gates apply.
function strikeManager.processStrikes(map, surface, universe)
    if not map or not map.strikeState or not map.zonesByIndex or #map.zonesByIndex == 0 then
        return
    end
    local evolution = game.forces.enemy.get_evolution_factor(surface)
    if evolution < strikeManager.STRIKE_ENABLED_EVOLUTION then
        return
    end
    if not map.strikeState.enabled then
        map.strikeState.enabled = true
        game.print("Strike targeting enabled at " .. math.floor(evolution * 100) .. "% evolution")
    end
    if game.tick < map.strikeState.cooldownEndTick then
        return
    end
    strikeManager.strike(map, surface, universe)
end

strikeManagerG = strikeManager
return strikeManager
