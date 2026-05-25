if strikeManagerG then
    return strikeManagerG
end
local strikeManager = {}

local zoneManager = require("libs/ZoneManager")
local strikeTargeting = require("libs/StrikeTargeting")
local customAlerts = require("libs/CustomAlerts")
local unitGroupUtils = require("libs/UnitGroupUtils")

-- Strike configuration
strikeManager.STRIKE_COOLDOWN_DURATION = 2 * 60 * 60  -- 2 minutes in ticks (60 ticks/sec) [TESTING]
strikeManager.STRIKE_ENABLED_EVOLUTION = 0.20  -- 20% evolution
strikeManager.SQUADS_PER_STRIKE = 3

function strikeManager.initStrikes(map)
    if not map then return end
    map.strikeState = {
        cooldownEndTick = 0,
        lastStrikeCategory = nil,
        lastStrikeTarget = nil,
        enabled = false
    }
end

function strikeManager.processStrikes(map, surface)
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

    -- Print first-time enable message
    if not map.strikeState.enabled then
        map.strikeState.enabled = true
        if debugPrint then
            game.print("Strike targeting enabled at " .. math.floor(evolution * 100) .. "% evolution")
        end
    end

    -- Check if cooldown is still active
    if tick < map.strikeState.cooldownEndTick then
        return  -- Still on cooldown
    end

    -- Time to roll for a strike
    local categories = {"raw-resources", "oil", "products", "power", "outpost"}
    local availableCategories = {}

    for _, cat in ipairs(categories) do
        if strikeTargeting.hasZonesInCategory(map, cat) then
            table.insert(availableCategories, cat)
        end
    end

    if #availableCategories == 0 then
        if debugPrint then
            game.print("No target categories available for strike")
        end
        return
    end

    -- Roll random category
    local selectedCategory = availableCategories[math.random(1, #availableCategories)]
    if debugPrint then
        game.print("[Strike] Category rolled: " .. selectedCategory)
    end

    -- Find target in category
    local target = strikeTargeting.selectStrikeTargetInCategory(map, selectedCategory)
    if not target then
        if debugPrint then
            game.print("[Strike] No suitable target found in category: " .. selectedCategory)
        end
        return
    end

    -- Calculate center position of target zone
    local targetX = target.tileX + zoneManager.ZONE_TILE_SIZE / 2
    local targetY = target.tileY + zoneManager.ZONE_TILE_SIZE / 2
    local targetPos = {x = targetX, y = targetY}

    if debugPrint then
        game.print("[Strike] Target: " .. selectedCategory .. " at [gps=" .. math.floor(targetX) .. "," .. math.floor(targetY) .. "," .. surface.name .. "]")
    end

    -- Deploy squads
    local squadsDeployed = 0
    for i = 1, strikeManager.SQUADS_PER_STRIKE do
        local squad = unitGroupUtils.createSquad(targetPos, map, nil, false)
        if squad then
            squadsDeployed = squadsDeployed + 1
        end
    end

    if debugPrint then
        game.print("[Strike] Deployed " .. squadsDeployed .. " squads to target")
    end

    -- Show alert to players - create a temporary entity for alert positioning
    local messageText = "Strike incoming! Category: " .. selectedCategory
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
