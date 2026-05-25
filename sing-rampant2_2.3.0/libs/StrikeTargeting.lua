if strikeTargetingG then
    return strikeTargetingG
end
local strikeTargeting = {}

local constants = require("libs/Constants")

-- Item-to-category mapping
strikeTargeting.ITEM_CATEGORIES = {
    -- Raw Resources (ores and mining)
    ["iron-ore"] = "raw-resources",
    ["copper-ore"] = "raw-resources",
    ["stone"] = "raw-resources",
    ["uranium-ore"] = "raw-resources",
    ["coal"] = "raw-resources",
    ["mining-drill"] = "raw-resources",  -- fallback when drill has no target

    -- Military/Defensive (turrets and walls)
    ["gun-turret"] = "outpost",
    ["laser-turret"] = "outpost",
    ["flamethrower-turret"] = "outpost",
    ["artillery-turret"] = "outpost",
    ["radar"] = "outpost",
    ["wall"] = "outpost",
    ["gate"] = "outpost",

    -- Oil Production
    ["crude-oil"] = "oil",
    ["petroleum-gas"] = "oil",
    ["light-oil"] = "oil",
    ["heavy-oil"] = "oil",

    -- Power (tracked separately via zone.powerGen, but include for completeness)
    ["power-gen"] = "power",

    -- Products - with tier weights
    -- Early game (tier 1): green science
    ["automation-science-pack"] = "products",
    ["green-circuit"] = "products",

    -- Mid game (tier 2): red science, basic intermediates
    ["logistic-science-pack"] = "products",
    ["red-circuit"] = "products",
    ["iron-plate"] = "products",
    ["steel-plate"] = "products",
    ["copper-plate"] = "products",

    -- Late game (tier 3-4): advanced circuits, blue science, plastic
    ["advanced-circuit"] = "products",
    ["processing-unit"] = "products",
    ["chemical-science-pack"] = "products",
    ["plastic-bar"] = "products",
    ["battery"] = "products",

    -- Space Age / expensive (tier 5): highest priority
    ["blue-science-pack"] = "products",
    ["military-science-pack"] = "products",
    ["production-science-pack"] = "products",
    ["utility-science-pack"] = "products",
}

-- Tier weighting for products: how much to prioritize striking them
-- Based on recipe complexity and production chain depth from Factorio Wiki
--
-- SCIENCE PACKS (by progression, what the player needs to research):
--   automation/logistic = tier 0 (needs just basic crafting)
--   military = tier 1 (needs some combat items)
--   chemical = tier 2 (needs oil processing + advanced circuits)
--   production = tier 3 (needs modules, electric furnaces, rails - big infrastructure)
--   utility = tier 4 (needs flying robots, processing units - end-game complexity)
--
-- INTERMEDIATES (by how many production chains feed into them):
--   green/red circuit = simple (just raw materials + crafting)
--   advanced circuit = medium (needs plastic + copper coordinated)
--   processing unit = complex (needs circuits + plastic + sulfur all converging)
--   flying robot frame = very complex (needs batteries + frames + electronics all at once)
--
strikeTargeting.PRODUCT_TIER_WEIGHTS = {
    -- SCIENCE PACKS - Tier 0 (early game, not priority)
    ["automation-science-pack"] = 1,
    ["logistic-science-pack"] = 1,

    -- SCIENCE PACKS - Tier 1 (military science, unlocks red tech)
    ["military-science-pack"] = 3,

    -- BASIC INTERMEDIATES (feeds tier 0-1)
    ["green-circuit"] = 1,
    ["red-circuit"] = 2,  -- requires transport belts + inserters
    ["iron-gear-wheel"] = 1,  -- basic, low priority
    ["copper-cable"] = 1,

    -- SCIENCE PACKS - Tier 2 (chemical science, unlocks plastic + oil processing)
    -- Recipe: 1 sulfur + 3 advanced-circuits + 2 engine-units
    ["chemical-science-pack"] = 8,

    -- MID INTERMEDIATES (feeds tier 2)
    -- Advanced circuit needs: 3 copper, 2 plastic, 1 electronic circuit
    ["advanced-circuit"] = 5,
    ["plastic-bar"] = 4,  -- requires oil processing, bottleneck item
    ["sulfur"] = 3,  -- requires oil processing
    ["engine-unit"] = 3,  -- needs copper + iron + gears + circuits
    ["battery"] = 3,

    -- SCIENCE PACKS - Tier 3 (production science, needs modules + furnaces)
    -- Recipe: 30 rails + 1 electric-furnace + 1 productivity-module
    ["production-science-pack"] = 12,

    -- ADVANCED INTERMEDIATES (feeds tier 3)
    -- Processing unit needs: 1 advanced circuit + 1 plastic + 1 sulfur
    ["processing-unit"] = 10,  -- convergence point, very important
    ["productivity-module"] = 9,  -- needs processing units + rare materials
    ["electric-furnace"] = 4,  -- needs advanced circuits
    ["rail"] = 2,  -- fairly simple chain

    -- SCIENCE PACKS - Tier 4 (utility science, needs flying robots + structures)
    -- Recipe: 2 processing-units + 1 flying-robot-frame + 3 low-density-structure
    ["utility-science-pack"] = 15,

    -- END-GAME INTERMEDIATES (feeds tier 4)
    ["flying-robot-frame"] = 12,  -- very complex: needs batteries + circuits + frames all at once
    ["low-density-structure"] = 7,  -- needs copper + steel + plastic all coordinated

    -- SPACE AGE (if applicable)
    ["space-science-pack"] = 20,  -- hardest to produce, end-game only
}

function strikeTargeting.countAdjacentEmptyZones(map, zone)
    -- Count how many adjacent zones (of 8 neighbors) have no category
    if not map or not map.zones or not zone then
        return 0
    end

    local emptyCount = 0
    local zx, zy = zone.zx, zone.zy

    -- Check all 8 adjacent positions
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then  -- skip self
                local neighborZone = map.zones[zx + dx] and map.zones[zx + dx][zy + dy]
                if neighborZone then
                    local neighborCat = strikeTargeting.getZoneCategory(neighborZone)
                    if not neighborCat then
                        emptyCount = emptyCount + 1
                    end
                else
                    -- No zone generated = empty
                    emptyCount = emptyCount + 1
                end
            end
        end
    end

    return emptyCount
end

function strikeTargeting.getZoneCategory(zone, map)
    -- Returns the PRIMARY category this zone belongs to
    if not zone then
        return nil
    end

    -- If zone has 8+ military buildings AND 6+ adjacent empty zones, it's an outpost
    if zone.militaryBuildingCount and zone.militaryBuildingCount >= 8 and map then
        local emptyAdjacent = strikeTargeting.countAdjacentEmptyZones(map, zone)
        if emptyAdjacent >= 6 then
            return "outpost"
        end
    end

    -- If zone has 10+ power buildings, it's a power zone regardless of other production
    if zone.powerBuildingCount and zone.powerBuildingCount > 10 then
        return "power"
    end

    local hasRaw = false
    local hasOil = false
    local hasProducts = false
    local hasPower = false

    -- Check products
    if zone.products then
        for itemName, rate in pairs(zone.products) do
            if rate > 0 then
                local cat = strikeTargeting.ITEM_CATEGORIES[itemName]
                if cat == "raw-resources" then
                    hasRaw = true
                elseif cat == "oil" then
                    hasOil = true
                elseif cat == "products" then
                    hasProducts = true
                elseif cat == nil then
                    -- Unmapped item: if it's not mining-drill or a raw resource name, treat as product
                    -- This catches assembler outputs not in the tier list
                    if not string.match(itemName, "ore$") and itemName ~= "mining-drill" and itemName ~= "stone" and itemName ~= "coal" then
                        hasProducts = true
                    end
                end
            end
        end
    end

    -- Check power
    if zone.powerGen and zone.powerGen > 0 then
        hasPower = true
    end

    -- Return priority order: products > oil > raw-resources > power
    if hasProducts then return "products" end
    if hasOil then return "oil" end
    if hasRaw then return "raw-resources" end
    if hasPower then return "power" end

    return nil
end

function strikeTargeting.calculateProductValue(zone)
    -- For a zone in the Products category, calculate its "value"
    -- Higher tier products = higher value
    -- This allows the AI to adapt: blue circuits > advanced circuits > red circuits > green circuits
    -- Even items not in the tier list get a small baseline value (assemblers are always somewhat valuable)

    if not zone or not zone.products then
        return 0
    end

    local totalValue = 0
    for itemName, rate in pairs(zone.products) do
        if rate > 0 then
            local cat = strikeTargeting.ITEM_CATEGORIES[itemName]

            -- Include items that are explicitly products
            if cat == "products" then
                local weight = strikeTargeting.PRODUCT_TIER_WEIGHTS[itemName] or 0.5
                totalValue = totalValue + (rate * weight)
            -- Also include unmapped items that are likely products (not ore/raw/mining-drill)
            elseif cat == nil then
                if not string.match(itemName, "ore$") and itemName ~= "mining-drill" and itemName ~= "stone" and itemName ~= "coal" then
                    -- This is an unmapped product - give it baseline weight
                    local weight = strikeTargeting.PRODUCT_TIER_WEIGHTS[itemName] or 0.5
                    totalValue = totalValue + (rate * weight)
                end
            end
        end
    end

    return totalValue
end

function strikeTargeting.selectStrikeTargetInCategory(map, category)
    -- Find the best zone to strike in a given category
    if not map or not map.zonesByIndex then
        return nil
    end

    local bestZone = nil
    local bestScore = 0

    for _, zone in ipairs(map.zonesByIndex) do
        if zone.totalRate > 0 then
            local zoneCat = strikeTargeting.getZoneCategory(zone)

            if zoneCat == category then
                local score = 0

                if category == "products" then
                    -- For products, score = tier-weighted value
                    score = strikeTargeting.calculateProductValue(zone)
                else
                    -- For other categories, score = production rate
                    score = zone.totalRate
                end

                if score > bestScore then
                    bestScore = score
                    bestZone = zone
                end
            end
        end
    end

    return bestZone
end

function strikeTargeting.hasZonesInCategory(map, category)
    -- Check if any zones exist in this category
    if not map or not map.zonesByIndex then
        return false
    end

    for _, zone in ipairs(map.zonesByIndex) do
        if zone.totalRate > 0 and strikeTargeting.getZoneCategory(zone) == category then
            return true
        end
    end

    return false
end

strikeTargetingG = strikeTargeting
return strikeTargeting
