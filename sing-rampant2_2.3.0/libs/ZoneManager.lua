if zoneManagerG then
    return zoneManagerG
end
local zoneManager = {}

local constants = require("libs/Constants")

local CHUNK_SIZE = constants.CHUNK_SIZE
local mFloor = math.floor
local mMax = math.max
local mMin = math.min

-- Zone configuration
zoneManager.ZONE_CHUNK_SIZE = 10  -- 10 chunks = 320×320 tiles
zoneManager.ZONE_TILE_SIZE = zoneManager.ZONE_CHUNK_SIZE * CHUNK_SIZE
zoneManager.ZONE_RESCAN_INTERVAL = 18000  -- 5 minutes at 60 ticks/sec

function zoneManager.initZones(map)
    map.zones = {}
    map.zoneIterator = 0
    map.zonesByIndex = {}
end

function zoneManager.getZoneByPosition(map, x, y)
    local zx = mFloor(x / zoneManager.ZONE_TILE_SIZE)
    local zy = mFloor(y / zoneManager.ZONE_TILE_SIZE)
    return zoneManager.getZoneByGridCoords(map, zx, zy)
end

function zoneManager.getZoneByGridCoords(map, zx, zy)
    if not map.zones[zx] then
        map.zones[zx] = {}
    end
    if not map.zones[zx][zy] then
        local tileX = zx * zoneManager.ZONE_TILE_SIZE
        local tileY = zy * zoneManager.ZONE_TILE_SIZE
        map.zones[zx][zy] = {
            zx = zx,
            zy = zy,
            tileX = tileX,
            tileY = tileY,
            products = {},
            totalRate = 0,
            relativeShare = 0,
            densityRank = 0,
            lastScanned = 0,
            scanPhase = 0,
            playerPheromoneTotal = 0,
        }
        map.zonesByIndex[#map.zonesByIndex + 1] = map.zones[zx][zy]
    end
    return map.zones[zx][zy]
end

function zoneManager.updateZonePheromoneTotal(map, chunk)
    local zone = zoneManager.getZoneByGridCoords(map,
        mFloor(chunk.x / zoneManager.ZONE_TILE_SIZE),
        mFloor(chunk.y / zoneManager.ZONE_TILE_SIZE)
    )
    local playerPheromone = chunk[constants.PLAYER_PHEROMONE] or 0
    zone.playerPheromoneTotal = mMax(0, zone.playerPheromoneTotal + playerPheromone)
end

function zoneManager.scanZonePhase1(map, zone, surface)
    if zone.playerPheromoneTotal <= 0 then
        zone.scanPhase = 0
        return
    end

    local x0 = zone.tileX
    local y0 = zone.tileY
    local x1 = x0 + zoneManager.ZONE_TILE_SIZE
    local y1 = y0 + zoneManager.ZONE_TILE_SIZE

    local assemblers = surface.find_entities_filtered({
        area = {{x0, y0}, {x1, y1}},
        type = "assembling-machine",
        force = "enemy"
    })

    for _, entity in ipairs(assemblers) do
        if entity.valid then
            local recipe = entity.get_recipe()
            if recipe then
                local speed = entity.crafting_speed * (1 + (entity.productivity_bonus or 0))
                local energy = recipe.energy or 1
                for _, product in ipairs(recipe.products) do
                    local rate = (product.amount * speed) / energy
                    zone.products[product.name] = (zone.products[product.name] or 0) + rate
                end
            end
        end
    end

    zone.scanPhase = 2
end

function zoneManager.scanZonePhase2(map, zone, surface)
    local x0 = zone.tileX
    local y0 = zone.tileY
    local x1 = x0 + zoneManager.ZONE_TILE_SIZE
    local y1 = y0 + zoneManager.ZONE_TILE_SIZE

    local furnaces = surface.find_entities_filtered({
        area = {{x0, y0}, {x1, y1}},
        type = "furnace",
        force = "enemy"
    })

    for _, entity in ipairs(furnaces) do
        if entity.valid then
            local recipe = entity.get_recipe()
            if recipe then
                local speed = entity.crafting_speed
                local energy = recipe.energy or 1
                for _, product in ipairs(recipe.products) do
                    local rate = (product.amount * speed) / energy
                    zone.products[product.name] = (zone.products[product.name] or 0) + rate
                end
            end
        end
    end

    zone.scanPhase = 3
end

function zoneManager.scanZonePhase3(map, zone, surface)
    local x0 = zone.tileX
    local y0 = zone.tileY
    local x1 = x0 + zoneManager.ZONE_TILE_SIZE
    local y1 = y0 + zoneManager.ZONE_TILE_SIZE

    local drills = surface.find_entities_filtered({
        area = {{x0, y0}, {x1, y1}},
        type = "mining-drill",
        force = "enemy"
    })

    for _, entity in ipairs(drills) do
        if entity.valid and entity.mining_target and entity.mining_target.valid then
            local resource = entity.mining_target
            local speed = entity.prototype.mining_speed
            local miningTime = resource.prototype.mineable_properties.mining_time or 1
            local rate = speed / miningTime
            zone.products[resource.name] = (zone.products[resource.name] or 0) + rate
        end
    end

    zoneManager.compileZone(zone)
end

function zoneManager.compileZone(zone)
    local totalRate = 0
    for itemName, rate in pairs(zone.products) do
        totalRate = totalRate + rate
    end
    zone.totalRate = totalRate
    zone.lastScanned = 0
    zone.scanPhase = 0
end

function zoneManager.processZoneScan(map, surface)
    if not map.zonesByIndex then
        return
    end

    -- Scan existing zones
    if #map.zonesByIndex > 0 then
        map.zoneIterator = map.zoneIterator + 1
        if map.zoneIterator > #map.zonesByIndex then
            map.zoneIterator = 1
        end

        local zone = map.zonesByIndex[map.zoneIterator]
        if zone.scanPhase == 0 and zone.playerPheromoneTotal > 0 then
            zone.scanPhase = 1
        end

        if zone.scanPhase == 1 then
            zoneManager.scanZonePhase1(map, zone, surface)
        elseif zone.scanPhase == 2 then
            zoneManager.scanZonePhase2(map, zone, surface)
        elseif zone.scanPhase == 3 then
            zoneManager.scanZonePhase3(map, zone, surface)
        end
    else
        -- Create initial zones around enemy bases
        if map.chunkToBase then
            for chunk, base in pairs(map.chunkToBase) do
                if chunk and chunk.x and chunk.y then
                    zoneManager.getZoneByGridCoords(map,
                        mFloor(chunk.x / zoneManager.ZONE_TILE_SIZE),
                        mFloor(chunk.y / zoneManager.ZONE_TILE_SIZE)
                    )
                end
            end
        end
    end
end

zoneManagerG = zoneManager
return zoneManager
