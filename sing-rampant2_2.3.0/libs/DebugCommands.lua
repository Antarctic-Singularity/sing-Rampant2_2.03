if debugCommandsG then
    return debugCommandsG
end
local debugCommands = {}

local zoneManager = require("libs/ZoneManager")
local constants = require("libs/Constants")

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
        if zone.totalRate > 0 then
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

        local label
        if zone.totalRate > 0 then
            local share = zone.relativeShare * 100
            label = string.format("%.0f%%\n%.1f/s", share, zone.totalRate)
        else
            label = "0"
        end

        rendering.draw_text({
            text = label,
            surface = surface,
            target = {x = cx, y = cy},
            color = zone.totalRate > 0 and {r=0.2, g=1, b=0.2, a=1} or {r=0.5, g=0.5, b=0.5, a=0.8},
            scale = 3,
            alignment = "center",
            time_to_live = 600,
            render_mode = "chart",
            scale_with_zoom = false
        })
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

    local activeZones = 0
    local topZones = {}
    local scanPhases = {0, 0, 0, 0}

    for _, zone in ipairs(map.zonesByIndex) do
        scanPhases[zone.scanPhase + 1] = scanPhases[zone.scanPhase + 1] + 1
        if zone.totalRate > 0 then
            activeZones = activeZones + 1
            topZones[#topZones + 1] = zone
        end
    end

    table.insert(lines, "Scan phase distribution: Phase0=" .. scanPhases[1] .. " Phase1=" .. scanPhases[2] .. " Phase2=" .. scanPhases[3] .. " Phase3=" .. scanPhases[4])
    table.insert(lines, "Active zones: " .. activeZones)

    table.sort(topZones, function(a, b) return a.totalRate > b.totalRate end)

    for i = 1, math.min(5, #topZones) do
        local zone = topZones[i]
        local share = zone.relativeShare * 100
        table.insert(lines, string.format(
            "  Zone[%d,%d]: %.1f items/s (%.1f%%)",
            zone.zx, zone.zy, zone.totalRate, share
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

debugCommandsG = debugCommands
return debugCommands
