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
zoneManager.ZONE_CHUNK_SIZE = 2  -- 2 chunks = 64×64 tiles
zoneManager.ZONE_TILE_SIZE = zoneManager.ZONE_CHUNK_SIZE * CHUNK_SIZE
zoneManager.ZONE_SCAN_INTERVAL = 60   -- ticks between zone scan advances (~1 scan/sec)
zoneManager.ZONE_INIT_RADIUS = 2      -- zone grid radius around player (5×5 grid = 25 zones, ~320 tiles, expands as needed)

function zoneManager.initZones(map)
    map.zones = {}
    map.zoneIterator = 0
    map.zonesByIndex = {}
    map.scanMode = "normal"  -- "normal" (slow) or "fast" (/r2-rescan)
    map.zoneCacheExpiry = 1800  -- rescan cached zones every 30 seconds
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
            powerGen = 0,  -- power generation in MW
            powerBuildingCount = 0,  -- number of power buildings
            militaryBuildingCount = 0,  -- number of turrets/walls/military buildings
            -- cache fields
            lastScanTick = 0,
            nextRescanTick = 0,
            isDirty = true,  -- mark new zones as needing initial scan
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

local function addRecipeProducts(zone, entity)
    local recipe = entity.get_recipe()
    if not recipe then return end
    local speed = entity.crafting_speed or 1
    local energy = recipe.energy or 1
    for _, product in ipairs(recipe.products or {}) do
        local amount = product.amount
        if not amount then
            amount = ((product.amount_min or 0) + (product.amount_max or 0)) * 0.5
        end
        if amount and amount > 0 then
            local rate = (amount * speed) / energy * (product.probability or 1)
            zone.products[product.name] = (zone.products[product.name] or 0) + rate
        end
    end
end

function zoneManager.scanZonePhase1(map, zone, surface)
    zone.products = {}  -- clear at start of each new scan cycle
    zone.powerGen = 0
    zone.militaryBuildingCount = 0
    local x0 = zone.tileX
    local y0 = zone.tileY
    local x1 = x0 + zoneManager.ZONE_TILE_SIZE
    local y1 = y0 + zoneManager.ZONE_TILE_SIZE
    local playerForces = map.universe and map.universe.activePlayerForces or {"player"}

    local assemblers = surface.find_entities_filtered({
        area = {{x0, y0}, {x1, y1}},
        type = "assembling-machine",
        force = playerForces
    })

    for _, entity in ipairs(assemblers) do
        if entity.valid then
            addRecipeProducts(zone, entity)
        end
    end

    -- Count military buildings (turrets, walls, etc.)
    local militaryTypes = {"gun-turret", "laser-turret", "flamethrower-turret", "artillery-turret", "radar", "wall", "gate"}
    for _, buildingType in ipairs(militaryTypes) do
        local buildings = surface.find_entities_filtered({
            area = {{x0, y0}, {x1, y1}},
            type = buildingType,
            force = playerForces
        })
        zone.militaryBuildingCount = zone.militaryBuildingCount + #buildings
    end

    zone.scanPhase = 2
end

function zoneManager.scanZonePhase2(map, zone, surface)
    local x0 = zone.tileX
    local y0 = zone.tileY
    local x1 = x0 + zoneManager.ZONE_TILE_SIZE
    local y1 = y0 + zoneManager.ZONE_TILE_SIZE
    local playerForces = map.universe and map.universe.activePlayerForces or {"player"}

    local furnaces = surface.find_entities_filtered({
        area = {{x0, y0}, {x1, y1}},
        type = "furnace",
        force = playerForces
    })

    for _, entity in ipairs(furnaces) do
        if entity.valid then
            addRecipeProducts(zone, entity)
        end
    end

    zone.scanPhase = 3
end

function zoneManager.scanZonePhase3(map, zone, surface)
    local x0 = zone.tileX
    local y0 = zone.tileY
    local x1 = x0 + zoneManager.ZONE_TILE_SIZE
    local y1 = y0 + zoneManager.ZONE_TILE_SIZE
    local playerForces = map.universe and map.universe.activePlayerForces or {"player"}

    local drills = surface.find_entities_filtered({
        area = {{x0, y0}, {x1, y1}},
        type = "mining-drill",
        force = playerForces
    })

    for _, entity in ipairs(drills) do
        if entity.valid then
            local miningTarget = entity.mining_target
            if miningTarget and miningTarget.valid then
                local props = miningTarget.prototype.mineable_properties
                local miningTime = props and props.mining_time or 1
                local speed = entity.prototype.mining_speed or 1
                zone.products[miningTarget.name] = (zone.products[miningTarget.name] or 0) + speed / miningTime
            else
                zone.products["mining-drill"] = (zone.products["mining-drill"] or 0) + 1
            end
        end
    end

    zone.scanPhase = 4
end

function zoneManager.scanZonePhase4(map, zone, surface)
    local x0 = zone.tileX
    local y0 = zone.tileY
    local x1 = x0 + zoneManager.ZONE_TILE_SIZE
    local y1 = y0 + zoneManager.ZONE_TILE_SIZE

    -- Power buildings are only built by the player force
    local playerForce = "player"

    -- Scan power generation: solar panels, generators (steam-engine, steam-turbine), nuclear reactors
    local powerGenTypes = {"solar-panel", "generator", "reactor"}
    local totalPower = 0
    local buildingCount = 0

    for _, buildingType in ipairs(powerGenTypes) do
        local buildings = surface.find_entities_filtered({
            area = {{x0, y0}, {x1, y1}},
            type = buildingType,
            force = playerForce
        })

        for _, entity in ipairs(buildings) do
            if entity.valid and entity.prototype then
                local maxPower = entity.prototype.max_power_output or 0
                totalPower = totalPower + maxPower
                buildingCount = buildingCount + 1
            end
        end
    end

    zone.powerGen = totalPower / 1e6  -- convert to MW
    zone.powerBuildingCount = buildingCount

    zoneManager.compileZone(zone, game.tick)
end

function zoneManager.compileZone(zone, tick)
    local totalRate = 0
    for itemName, rate in pairs(zone.products) do
        totalRate = totalRate + rate
    end
    zone.totalRate = totalRate
    zone.lastScanned = 0
    zone.scanPhase = 0
    zone.lastScanTick = tick or 0
    zone.isDirty = false
    -- Next rescan in 30 seconds (1800 ticks at 60 ticks/sec)
    zone.nextRescanTick = (tick or 0) + 1800
end

local function createZonesAroundPlayers(map, surface)
    local r = zoneManager.ZONE_INIT_RADIUS
    for _, player in pairs(game.players) do
        if player.valid and player.surface.index == surface.index then
            local cx = mFloor(player.position.x / zoneManager.ZONE_TILE_SIZE)
            local cy = mFloor(player.position.y / zoneManager.ZONE_TILE_SIZE)
            for dx = -r, r do
                for dy = -r, r do
                    zoneManager.getZoneByGridCoords(map, cx + dx, cy + dy)
                end
            end
        end
    end
end

function zoneManager.processZoneScan(map, surface)
    if not map.zonesByIndex then return end
    local tick = game.tick

    -- Initialize missing map-level fields (save migration)
    if not map.zoneIterator then
        map.zoneIterator = 0
    end

    -- Dynamic zone expansion based on player position (every scan tick)
    local r = zoneManager.ZONE_INIT_RADIUS
    for _, player in pairs(game.players) do
        if player.valid and player.surface.index == surface.index then
            local cx = mFloor(player.position.x / zoneManager.ZONE_TILE_SIZE)
            local cy = mFloor(player.position.y / zoneManager.ZONE_TILE_SIZE)
            for dx = -r, r do
                for dy = -r, r do
                    zoneManager.getZoneByGridCoords(map, cx + dx, cy + dy)
                end
            end
        end
    end

    -- Initialize missing cache fields for old zones (save migration)
    for _, zone in ipairs(map.zonesByIndex) do
        if not zone.nextRescanTick then
            zone.nextRescanTick = tick + 1800
        end
        if zone.isDirty == nil then
            zone.isDirty = false
        end
        if not zone.lastScanTick then
            zone.lastScanTick = 0
        end
        if not zone.powerGen then
            zone.powerGen = 0
        end
        if not zone.powerBuildingCount then
            zone.powerBuildingCount = 0
        end
        if not zone.militaryBuildingCount then
            zone.militaryBuildingCount = 0
        end
    end

    if #map.zonesByIndex > 0 then
        -- Ensure iterator is in valid range before using it
        if map.zoneIterator >= #map.zonesByIndex then
            map.zoneIterator = 0
        end

        local zone = map.zonesByIndex[map.zoneIterator + 1]  -- peek at next zone
        if not zone then return end  -- no zone at this position, skip

        -- Skip zone if cache is fresh and not dirty (unless in fast scan mode)
        -- BUT always rescan phase 4 (power) even if items are cached
        if not map.zoneForceScan and not zone.isDirty and tick < zone.nextRescanTick and zone.scanPhase == 0 then
            -- Cache is valid and fully compiled, skip to next zone
            map.zoneIterator = map.zoneIterator + 1
            if map.zoneIterator > #map.zonesByIndex then
                map.zoneIterator = 1
                createZonesAroundPlayers(map, surface)
            end
            return  -- Skip this zone, come back later
        end

        -- Zone needs update, proceed with scan
        map.zoneIterator = map.zoneIterator + 1
        if map.zoneIterator > #map.zonesByIndex then
            map.zoneIterator = 1
            if map.zoneForceScan then
                map.zoneForceScanPasses = (map.zoneForceScanPasses or 0) + 1
                if map.zoneForceScanPasses >= 4 then
                    map.zoneForceScan = nil
                    map.zoneForceScanPasses = nil
                    game.print("Zone force rescan complete")
                end
            end
            createZonesAroundPlayers(map, surface)
        end

        local zone = map.zonesByIndex[map.zoneIterator]
        if zone.scanPhase == 0 then
            zone.scanPhase = 1
        end

        if zone.scanPhase == 1 then
            zoneManager.scanZonePhase1(map, zone, surface)
        elseif zone.scanPhase == 2 then
            zoneManager.scanZonePhase2(map, zone, surface)
        elseif zone.scanPhase == 3 then
            zoneManager.scanZonePhase3(map, zone, surface)
        elseif zone.scanPhase == 4 then
            zoneManager.scanZonePhase4(map, zone, surface)
        end
    else
        createZonesAroundPlayers(map, surface)
    end
end

function zoneManager.markZoneDirty(map, position)
    -- Mark a zone as needing immediate rescan when player entity is built/destroyed
    if not map or not position then return end
    local zx = mFloor(position.x / zoneManager.ZONE_TILE_SIZE)
    local zy = mFloor(position.y / zoneManager.ZONE_TILE_SIZE)
    local zone = map.zones and map.zones[zx] and map.zones[zx][zy]
    if zone then
        zone.isDirty = true
        zone.nextRescanTick = 0  -- rescan immediately
    end
end

function zoneManager.forceRescan(map)
    for _, zone in ipairs(map.zonesByIndex or {}) do
        zone.scanPhase = 0
        zone.products = {}
        zone.totalRate = 0
    end
    map.zoneIterator = 0
    map.zoneNextScanTick = 0
    map.zoneForceScan = true
    game.print("Zone force rescan started: " .. #(map.zonesByIndex or {}) .. " zones queued")
end

function zoneManager.superForceRescan(map, surface)
    -- DANGEROUS: Scan everything immediately, no rate limiting
    -- WARNING: This will freeze the game while scanning
    if not map or not map.zonesByIndex or not surface then
        return
    end

    game.print("SUPER RESCAN STARTING - Game will freeze temporarily")
    local tick = game.tick

    for _, zone in ipairs(map.zonesByIndex) do
        zone.scanPhase = 0
        zone.products = {}
        zone.totalRate = 0
        zone.powerGen = 0
        zone.isDirty = true
    end

    -- Execute all 4 phases for every zone back-to-back
    for phase = 1, 4 do
        for _, zone in ipairs(map.zonesByIndex) do
            if phase == 1 then
                zoneManager.scanZonePhase1(map, zone, surface)
            elseif phase == 2 then
                zoneManager.scanZonePhase2(map, zone, surface)
            elseif phase == 3 then
                zoneManager.scanZonePhase3(map, zone, surface)
            elseif phase == 4 then
                zoneManager.scanZonePhase4(map, zone, surface)
            end
        end
    end

    -- Calculate global totals and relative shares for visualization
    local globalTotalRate = 0
    for _, zone in ipairs(map.zonesByIndex) do
        globalTotalRate = globalTotalRate + (zone.totalRate or 0)
    end
    map.globalTotalRate = globalTotalRate

    -- Set relative share for each zone
    for _, zone in ipairs(map.zonesByIndex) do
        if globalTotalRate > 0 then
            zone.relativeShare = (zone.totalRate or 0) / globalTotalRate
        else
            zone.relativeShare = 0
        end
    end

    map.zoneIterator = 0
    game.print("SUPER RESCAN COMPLETE - " .. #map.zonesByIndex .. " zones fully scanned, " .. string.format("%.1f", globalTotalRate) .. " items/s global")
end

zoneManagerG = zoneManager
return zoneManager
