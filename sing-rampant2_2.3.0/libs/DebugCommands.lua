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

    local renderingObjects = {}

    for _, zone in ipairs(map.zonesByIndex) do
        local x0 = zone.tileX
        local y0 = zone.tileY
        local x1 = x0 + zoneManager.ZONE_TILE_SIZE
        local y1 = y0 + zoneManager.ZONE_TILE_SIZE

        local color = {r = 0.5, g = 0.5, b = 0.5, a = 0.3}
        if zone.playerPheromoneTotal > 0 then
            color = {r = 0.2, g = 0.8, b = 0.2, a = 0.3}
        end

        rendering.draw_rectangle({
            color = color,
            filled = true,
            left_top = {x0, y0},
            right_bottom = {x1, y1},
            surface = surface,
            players = {player.index}
        })

        if zone.totalRate > 0 then
            local share = zone.relativeShare * 100
            local text = string.format("%.1f%%\n%.0f/s", share, zone.totalRate)
            rendering.draw_text({
                text = text,
                surface = surface,
                target = {zone.tileX + zoneManager.ZONE_TILE_SIZE / 2, zone.tileY + zoneManager.ZONE_TILE_SIZE / 2},
                color = {r = 1, g = 1, b = 1},
                scale = 1.5,
                alignment = "center",
                players = {player.index}
            })
        end
    end

    game.print("Zone overlay drawn. Total zones: " .. #map.zonesByIndex)
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
        local color = {r = 1, g = 0, b = 0, a = 0.8}
        local size = 20 + i * 5

        rendering.draw_circle({
            color = color,
            radius = size,
            filled = false,
            surface = surface,
            target = {x = target.centerX, y = target.centerY},
            players = {player.index}
        })

        local share = target.relativeShare * 100
        local text = "#" .. i .. " (" .. string.format("%.1f%%", share) .. ")"
        rendering.draw_text({
            text = text,
            surface = surface,
            target = {target.centerX, target.centerY - size - 5},
            color = color,
            scale = 2,
            alignment = "center",
            players = {player.index}
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
