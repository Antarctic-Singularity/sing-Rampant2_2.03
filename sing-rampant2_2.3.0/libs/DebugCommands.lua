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
                position = {zone.tileX + zoneManager.ZONE_TILE_SIZE / 2, zone.tileY + zoneManager.ZONE_TILE_SIZE / 2},
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
            position = {target.centerX, target.centerY - size - 5},
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

    game.print("=== ZONE STATISTICS ===")
    game.print("Total zones: " .. #map.zonesByIndex)
    game.print("Global production rate: " .. string.format("%.2f", map.globalTotalRate or 0) .. " items/s")

    local activeZones = 0
    local topZones = {}

    for _, zone in ipairs(map.zonesByIndex) do
        if zone.totalRate > 0 then
            activeZones = activeZones + 1
            topZones[#topZones + 1] = zone
        end
    end

    table.sort(topZones, function(a, b) return a.totalRate > b.totalRate end)

    game.print("Active zones: " .. activeZones)
    for i = 1, math.min(5, #topZones) do
        local zone = topZones[i]
        local share = zone.relativeShare * 100
        game.print(string.format(
            "  Zone[%d,%d]: %.1f items/s (%.1f%%)",
            zone.zx, zone.zy, zone.totalRate, share
        ))
    end
end

function debugCommands.printTargets(map)
    if not map.priorityTargets or #map.priorityTargets == 0 then
        game.print("No priority targets")
        return
    end

    game.print("=== PRIORITY TARGETS ===")
    for i, target in ipairs(map.priorityTargets) do
        local share = target.relativeShare * 100
        game.print(string.format(
            "  #%d at [%.0f, %.0f]: %.1f%% (top: %s)",
            i, target.centerX, target.centerY, share, target.topItem or "none"
        ))
    end
end

function debugCommands.clearAllOverlays(player)
    for _, obj in ipairs(rendering.get_all_objects(player.index)) do
        rendering.destroy(obj)
    end
    game.print("All overlays cleared")
end

debugCommandsG = debugCommands
return debugCommands
