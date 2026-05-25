if targetRankerG then
    return targetRankerG
end
local targetRanker = {}

local zoneManager = require("libs/ZoneManager")

function targetRanker.buildPriorityTargetList(map, maxTargets)
    if not map.zonesByIndex or #map.zonesByIndex == 0 then
        return {}
    end

    maxTargets = maxTargets or 3
    local globalTotalRate = 0

    for _, zone in ipairs(map.zonesByIndex) do
        globalTotalRate = globalTotalRate + zone.totalRate
    end

    if globalTotalRate == 0 then
        return {}
    end

    for _, zone in ipairs(map.zonesByIndex) do
        zone.relativeShare = zone.totalRate / globalTotalRate
    end

    table.sort(map.zonesByIndex, function(a, b)
        return a.relativeShare > b.relativeShare
    end)

    local targets = {}
    for i = 1, math.min(maxTargets, #map.zonesByIndex) do
        local zone = map.zonesByIndex[i]
        if zone.totalRate > 0 then
            targets[i] = {
                zone = zone,
                centerX = zone.tileX + (zoneManager.ZONE_TILE_SIZE / 2),
                centerY = zone.tileY + (zoneManager.ZONE_TILE_SIZE / 2),
                relativeShare = zone.relativeShare,
                topItem = nil,
                createdTick = game.tick,
            }

            local maxRate = 0
            local maxItem = nil
            for itemName, rate in pairs(zone.products) do
                if rate > maxRate then
                    maxRate = rate
                    maxItem = itemName
                end
            end
            targets[i].topItem = maxItem
        end
    end

    return targets
end

function targetRanker.processRanking(map, maxTargets)
    map.priorityTargets = targetRanker.buildPriorityTargetList(map, maxTargets)
    map.globalTotalRate = 0
    if map.zonesByIndex then
        for _, zone in ipairs(map.zonesByIndex) do
            map.globalTotalRate = map.globalTotalRate + zone.totalRate
        end
    end
end

targetRankerG = targetRanker
return targetRanker
