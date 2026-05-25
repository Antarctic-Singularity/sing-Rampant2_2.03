if debugCommandsG then
    return debugCommandsG
end
local debugCommands = {}

local zoneManager = require("libs/ZoneManager")
local constants = require("libs/Constants")
local strikeTargeting = require("libs/StrikeTargeting")

function debugCommands.drawZoneOverlay(player, map)
    if not map.zonesByIndex then
        game.print("No zones initialized")
        return
    end

    local surface = player.surface
    if surface.index ~= map.surface.index then
        game.print("Must be on the same surface as the map")
        return
    end

    for _, zone in ipairs(map.zonesByIndex) do
        local x0 = zone.tileX
        local y0 = zone.tileY
        local x1 = x0 + zoneManager.ZONE_TILE_SIZE
        local y1 = y0 + zoneManager.ZONE_TILE_SIZE
        local cx = (x0 + x1) / 2
        local cy = (y0 + y1) / 2

        local color = {r=0.4, g=0.4, b=0.4, a=0.8}
        if zone.isDirty then
            color = {r=0.8, g=0.3, b=0.1, a=0.9}  -- red/orange for dirty zones
        elseif zone.totalRate > 0 then
            local intensity = math.min(1.0, zone.relativeShare * 5)
            color = {r=0.1, g=0.4+intensity*0.5, b=0.1, a=0.9}
        end

        rendering.draw_rectangle({
            color = color,
            filled = false,
            width = 4,
            left_top = {x0, y0},
            right_bottom = {x1, y1},
            surface = surface,
            time_to_live = 600,
            render_mode = "chart"
        })

        local cacheStatus = ""
        if zone.isDirty then
            cacheStatus = "DIRTY"
        elseif game.tick < zone.nextRescanTick then
            local ticksLeft = zone.nextRescanTick - game.tick
            cacheStatus = "cached(" .. math.ceil(ticksLeft / 60) .. "s)"
        else
            cacheStatus = "expired"
        end

        -- Get category and value
        local category = strikeTargeting.getZoneCategory(zone, map)
        local categoryStr = category or "none"

        -- Line 1: Coordinates and phase
        local line1 = string.format("[%d,%d] P:%d", zone.zx, zone.zy, zone.scanPhase)

        -- Line 2: Cache status
        local line2 = cacheStatus

        -- Line 3: Production data
        local line3 = ""
        local powerGen = zone.powerGen or 0
        if zone.totalRate > 0 or powerGen > 0 then
            local share = zone.relativeShare * 100
            local powerStr = powerGen > 0 and string.format(" %gMW", powerGen) or ""
            line3 = string.format("%.0f%% %.1f/s%s", share, zone.totalRate, powerStr)
        else
            line3 = "0/s"
        end

        -- Line 4: Category and value
        local line4 = "CAT:" .. categoryStr
        if category == "products" then
            local value = strikeTargeting.calculateProductValue(zone)
            line4 = line4 .. string.format(" VAL:%d", math.floor(value))
        end

        -- Draw each line at different vertical positions
        local yOffset = -12  -- start above center
        for _, lineText in ipairs({line1, line2, line3, line4}) do
            rendering.draw_text({
                text = lineText,
                surface = surface,
                target = {x = cx, y = cy + yOffset},
                color = {r=1, g=1, b=1, a=1},
                scale = 10,
                alignment = "center",
                time_to_live = 600,
                render_mode = "chart",
                scale_with_zoom = false
            })
            yOffset = yOffset + 8  -- move down for next line
        end
    end

    game.print("Zone overlay drawn on map. Total zones: " .. #map.zonesByIndex)
end

function debugCommands.drawTargetOverlay(player, map)
    if not map.priorityTargets then
        game.print("No priority targets yet")
        return
    end

    local surface = player.surface
    if surface.index ~= map.surface.index then
        game.print("Must be on the same surface as the map")
        return
    end

    for i, target in ipairs(map.priorityTargets) do
        local alpha = 1.0 - (i - 1) * 0.2
        local color = {r=1, g=0.1*(i-1), b=0, a=alpha}
        local size = 80 - i * 10

        rendering.draw_circle({
            color = color,
            radius = size,
            filled = false,
            width = 4,
            surface = surface,
            target = {x = target.centerX, y = target.centerY},
            time_to_live = 600,
            render_mode = "chart"
        })

        local share = target.relativeShare * 100
        local text = "#" .. i .. " " .. string.format("%.0f%%", share)
        rendering.draw_text({
            text = text,
            surface = surface,
            target = {x = target.centerX, y = target.centerY},
            color = color,
            scale = 4,
            alignment = "center",
            time_to_live = 600,
            render_mode = "chart",
            scale_with_zoom = false
        })
    end

    game.print("Target overlay drawn. Priority targets: " .. #map.priorityTargets)
end

function debugCommands.printZoneStats(map)
    if not map.zonesByIndex then
        game.print("No zones")
        return
    end

    local lines = {}
    table.insert(lines, "=== ZONE STATISTICS ===")
    table.insert(lines, "Total zones: " .. #map.zonesByIndex)
    table.insert(lines, "Global production rate: " .. string.format("%.2f", map.globalTotalRate or 0) .. " items/s")

    -- Count zones by category
    local catCounts = {raw = 0, oil = 0, products = 0, power = 0, outpost = 0, none = 0}
    for _, zone in ipairs(map.zonesByIndex) do
        local cat = strikeTargeting.getZoneCategory(zone, map)
        if cat == "raw-resources" then catCounts.raw = catCounts.raw + 1
        elseif cat == "oil" then catCounts.oil = catCounts.oil + 1
        elseif cat == "products" then catCounts.products = catCounts.products + 1
        elseif cat == "power" then catCounts.power = catCounts.power + 1
        elseif cat == "outpost" then catCounts.outpost = catCounts.outpost + 1
        else catCounts.none = catCounts.none + 1
        end
    end
    table.insert(lines, "Categories: raw=" .. catCounts.raw .. " oil=" .. catCounts.oil .. " products=" .. catCounts.products .. " power=" .. catCounts.power .. " outpost=" .. catCounts.outpost .. " none=" .. catCounts.none)

    local activeZones = 0
    local topZones = {}
    local scanPhases = {0, 0, 0, 0}
    local totalPowerMW = 0

    for _, zone in ipairs(map.zonesByIndex) do
        if not zone then goto continue end
        zone.scanPhase = type(zone.scanPhase) == "number" and zone.scanPhase or 0
        zone.totalRate = type(zone.totalRate) == "number" and zone.totalRate or 0
        zone.powerGen = type(zone.powerGen) == "number" and zone.powerGen or 0

        local phase = zone.scanPhase
        if phase >= 0 and phase <= 3 then
            scanPhases[phase + 1] = scanPhases[phase + 1] + 1
        end

        if zone.totalRate > 0 then
            activeZones = activeZones + 1
            topZones[#topZones + 1] = zone
        end
        if zone.powerGen and zone.powerGen > 0 then
            totalPowerMW = totalPowerMW + zone.powerGen
        end
        ::continue::
    end

    table.insert(lines, "Scan phase distribution: Phase0=" .. scanPhases[1] .. " Phase1=" .. scanPhases[2] .. " Phase2=" .. scanPhases[3] .. " Phase3=" .. scanPhases[4])
    table.insert(lines, "Active zones: " .. activeZones)
    table.insert(lines, "Total power generation: " .. string.format("%.1f", totalPowerMW) .. " MW")

    table.sort(topZones, function(a, b) return a.totalRate > b.totalRate end)

    for i = 1, math.min(5, #topZones) do
        local zone = topZones[i]
        local share = zone.relativeShare * 100
        local powerStr = zone.powerGen and zone.powerGen > 0 and string.format(" + %.0fMW", zone.powerGen) or ""
        table.insert(lines, string.format(
            "  Zone[%d,%d]: %.1f items/s (%.1f%%)%s",
            zone.zx, zone.zy, zone.totalRate, share, powerStr
        ))
    end

    if activeZones == 0 and scanPhases[1] == #map.zonesByIndex then
        table.insert(lines, "WARNING: All zones still in Phase 0. Scanning may not be running.")
    end

    for _, line in ipairs(lines) do
        game.print(line)
    end
end

function debugCommands.printTargets(map)
    if not map.priorityTargets or #map.priorityTargets == 0 then
        game.print("No priority targets")
        return
    end

    local lines = {}
    table.insert(lines, "=== PRIORITY TARGETS ===")
    for i, target in ipairs(map.priorityTargets) do
        local share = target.relativeShare * 100
        table.insert(lines, string.format(
            "  #%d at [%.0f, %.0f]: %.1f%% (top: %s)",
            i, target.centerX, target.centerY, share, target.topItem or "none"
        ))
    end

    for _, line in ipairs(lines) do
        game.print(line)
    end
end

function debugCommands.clearAllOverlays(player)
    for _, obj in ipairs(rendering.get_all_objects(player)) do
        rendering.destroy(obj)
    end
    game.print("All overlays cleared")
end

function debugCommands.findEnemyStructures(player)
    local surface = player.surface

    local allPlayer = surface.find_entities_filtered({force = "player"})
    local allEnemy = surface.find_entities_filtered({force = "enemy"})

    local lines = {}
    table.insert(lines, "=== ENTITY COUNTS ===")
    table.insert(lines, "Player force total: " .. #allPlayer)
    table.insert(lines, "Enemy force total: " .. #allEnemy)

    local assemblers = surface.find_entities_filtered({type = "assembling-machine"})
    local furnaces = surface.find_entities_filtered({type = "furnace"})
    local drills = surface.find_entities_filtered({type = "mining-drill"})

    table.insert(lines, "All production buildings (any force):")
    table.insert(lines, "  Assemblers: " .. #assemblers)
    table.insert(lines, "  Furnaces: " .. #furnaces)
    table.insert(lines, "  Drills: " .. #drills)

    if #assemblers > 0 then
        table.insert(lines, "  First assembler force: " .. assemblers[1].force.name)
    end
    if #furnaces > 0 then
        table.insert(lines, "  First furnace force: " .. furnaces[1].force.name)
    end
    if #drills > 0 then
        table.insert(lines, "  First drill force: " .. drills[1].force.name)
    end

    for _, line in ipairs(lines) do
        game.print(line)
    end
end

function debugCommands.scanHere(player, map)
    local surface = player.surface
    local pos = player.position
    local r = 128

    local lines = {}
    table.insert(lines, "=== SCAN HERE [" .. math.floor(pos.x) .. "," .. math.floor(pos.y) .. "] ===")
    table.insert(lines, "Player surface: " .. surface.name)
    if map then
        table.insert(lines, "Map surface: " .. (map.surface and map.surface.name or "nil"))
        if map.surface and map.surface.name ~= surface.name then
            table.insert(lines, "WARNING: player surface != map surface!")
        end
    end

    -- Direct entity search around player, no force filter
    local assemblers = surface.find_entities_filtered({area = {{pos.x-r, pos.y-r}, {pos.x+r, pos.y+r}}, type = "assembling-machine"})
    local furnaces   = surface.find_entities_filtered({area = {{pos.x-r, pos.y-r}, {pos.x+r, pos.y+r}}, type = "furnace"})
    local drills     = surface.find_entities_filtered({area = {{pos.x-r, pos.y-r}, {pos.x+r, pos.y+r}}, type = "mining-drill"})

    -- Check power buildings
    local powerGenTypes = {"solar-panel", "generator", "reactor"}
    local powerBuildings = 0
    for _, buildingType in ipairs(powerGenTypes) do
        local count = #surface.find_entities_filtered({area = {{pos.x-r, pos.y-r}, {pos.x+r, pos.y+r}}, type = buildingType})
        powerBuildings = powerBuildings + count
    end

    table.insert(lines, "Within " .. r .. " tiles (any force):")
    table.insert(lines, "  Assemblers: " .. #assemblers .. (assemblers[1] and (" force=" .. assemblers[1].force.name) or ""))
    table.insert(lines, "  Furnaces:   " .. #furnaces   .. (furnaces[1]   and (" force=" .. furnaces[1].force.name)   or ""))
    table.insert(lines, "  Drills:     " .. #drills     .. (drills[1]     and (" force=" .. drills[1].force.name)     or ""))
    table.insert(lines, "  Power buildings: " .. powerBuildings)

    -- Show which zone the player is in and scan that exact zone area
    if map then
        local zoneSize = zoneManager.ZONE_TILE_SIZE
        local zx = math.floor(pos.x / zoneSize)
        local zy = math.floor(pos.y / zoneSize)
        local tileX = zx * zoneSize
        local tileY = zy * zoneSize
        local tileX1 = tileX + zoneSize
        local tileY1 = tileY + zoneSize
        table.insert(lines, "Zone [" .. zx .. "," .. zy .. "] covers {" .. tileX .. "," .. tileY .. "} to {" .. tileX1 .. "," .. tileY1 .. "}")

        -- Scan the exact zone area so we can compare with zone scan results
        local za = surface.find_entities_filtered({area = {{tileX, tileY}, {tileX1, tileY1}}, type = "assembling-machine"})
        local zf = surface.find_entities_filtered({area = {{tileX, tileY}, {tileX1, tileY1}}, type = "furnace"})
        local zd = surface.find_entities_filtered({area = {{tileX, tileY}, {tileX1, tileY1}}, type = "mining-drill"})
        table.insert(lines, "In zone area: assemblers=" .. #za .. " furnaces=" .. #zf .. " drills=" .. #zd)

        local zone = map.zones and map.zones[zx] and map.zones[zx][zy]
        if zone then
            table.insert(lines, "Zone state: phase=" .. zone.scanPhase .. " totalRate=" .. string.format("%.2f", zone.totalRate))
        else
            table.insert(lines, "Zone NOT created at this position yet")
        end
    end

    for _, line in ipairs(lines) do
        game.print(line)
    end
end

function debugCommands.scanPower(player, map)
    local surface = player.surface

    local lines = {}
    table.insert(lines, "=== POWER SCAN (player force only) ===")
    table.insert(lines, "Surface: " .. surface.name)

    local powerGenTypes = {"solar-panel", "generator", "reactor"}
    local totalPower = 0
    local totalBuildings = 0

    for _, buildingType in ipairs(powerGenTypes) do
        local buildings = surface.find_entities_filtered({
            type = buildingType,
            force = "player"
        })

        local buildingPower = 0
        for _, entity in ipairs(buildings) do
            if entity.valid and entity.prototype then
                local maxPower = entity.prototype.max_power_output or 0
                buildingPower = buildingPower + maxPower
                totalBuildings = totalBuildings + 1
            end
        end

        totalPower = totalPower + buildingPower
        local powerMW = buildingPower / 1e6
        table.insert(lines, buildingType .. ": " .. #buildings .. " = " .. string.format("%.1f", powerMW) .. " MW")
    end

    table.insert(lines, "---")
    table.insert(lines, "Total: " .. totalBuildings .. " buildings, " .. string.format("%.1f", totalPower / 1e6) .. " MW")

    for _, line in ipairs(lines) do
        game.print(line)
    end
end

function debugCommands.printScanStatus(map)
    if not map.zonesByIndex then
        game.print("No zones initialized")
        return
    end

    local lines = {}
    table.insert(lines, "=== ZONE SCANNING STATUS ===")
    table.insert(lines, "Total zones: " .. #map.zonesByIndex)
    table.insert(lines, "Current iterator: " .. (map.zoneIterator or 0) .. " / " .. #map.zonesByIndex)

    local tick = game.tick

    -- Count zones by scan phase
    local phaseCount = {0, 0, 0, 0}
    local cachedCount = 0
    local dirtyCount = 0
    local expiredCount = 0

    for _, zone in ipairs(map.zonesByIndex) do
        zone.scanPhase = zone.scanPhase or 0
        zone.nextRescanTick = zone.nextRescanTick or tick
        zone.isDirty = zone.isDirty or false

        phaseCount[zone.scanPhase + 1] = phaseCount[zone.scanPhase + 1] + 1

        if zone.isDirty then
            dirtyCount = dirtyCount + 1
        elseif tick >= zone.nextRescanTick then
            expiredCount = expiredCount + 1
        elseif zone.scanPhase == 0 then
            cachedCount = cachedCount + 1
        end
    end

    table.insert(lines, "Phase distribution: 0=" .. phaseCount[1] .. " 1=" .. phaseCount[2] .. " 2=" .. phaseCount[3] .. " 3=" .. phaseCount[4])
    table.insert(lines, "Cached zones (current): " .. cachedCount)
    table.insert(lines, "Expired zones (need rescan): " .. expiredCount)
    table.insert(lines, "Dirty zones (immediate): " .. dirtyCount)

    -- Current zone being scanned
    if map.zoneIterator and map.zoneIterator > 0 and map.zoneIterator <= #map.zonesByIndex then
        local currentZone = map.zonesByIndex[map.zoneIterator]
        if currentZone then
            table.insert(lines, "Current zone: [" .. currentZone.zx .. "," .. currentZone.zy .. "] phase=" .. (currentZone.scanPhase or 0))
        end
    end

    -- Force scan status
    if map.zoneForceScan then
        local passes = map.zoneForceScanPasses or 0
        table.insert(lines, "Force rescan in progress: pass " .. passes .. " / 4")
    else
        table.insert(lines, "Force rescan: not active")
    end

    -- Strike system status
    if map.strikeState then
        local cooldownTicks = math.max(0, map.strikeState.cooldownEndTick - tick)
        local cooldownMin = math.ceil(cooldownTicks / 60 / 60)
        table.insert(lines, "Strike cooldown: " .. cooldownMin .. " min remaining")
        table.insert(lines, "Strikes enabled: " .. (map.strikeState.enabled and "yes" or "no"))
    end

    for _, line in ipairs(lines) do
        game.print(line)
    end
end

debugCommandsG = debugCommands
return debugCommands
