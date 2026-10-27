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
    -- Counts adjacent zones (of 8 neighbors) with category NONE. Returns the count and whether
    -- every neighbor exists and has been scanned. A missing or unscanned neighbor is not counted
    -- as empty; the caller treats the result as incomplete.
    if not map or not map.zones or not zone then
        return 0, false
    end

    local emptyCount = 0
    local complete = true
    local zx, zy = zone.zx, zone.zy

    -- Check all 8 adjacent positions
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then  -- skip self
                local neighborZone = map.zones[zx + dx] and map.zones[zx + dx][zy + dy]
                if not neighborZone or neighborZone.isDirty then
                    complete = false
                elseif not strikeTargeting.getZoneCategory(neighborZone, map, true) then
                    emptyCount = emptyCount + 1
                end
            end
        end
    end

    return emptyCount, complete
end

function strikeTargeting.dominatesAdjacentZones(map, zone)
    -- Check if zone has at least 20% more military buildings than EACH adjacent zone
    -- Returns true only if zone dominates all adjacent zones individually
    if not map or not map.zones or not zone then
        return false
    end

    local zx, zy = zone.zx, zone.zy
    local zoneBuildings = zone.militaryBuildingCount or 0

    if zoneBuildings < 8 then
        return false  -- Need at least 8 buildings minimum
    end

    -- Check all 8 adjacent positions
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then  -- skip self
                local neighborZone = map.zones[zx + dx] and map.zones[zx + dx][zy + dy]
                if neighborZone then
                    local neighborBuildings = neighborZone.militaryBuildingCount or 0
                    -- Must have more than 20% more than each neighbor's buildings
                    if zoneBuildings <= neighborBuildings * 1.2 then
                        return false  -- Doesn't dominate this neighbor
                    end
                end
            end
        end
    end

    return true  -- Dominates all adjacent zones
end

function strikeTargeting.getZoneCategory(zone, map, skipOutpostCheck)
    -- Returns the PRIMARY category this zone belongs to
    if not zone then
        return nil
    end

    -- If zone has 8+ military buildings AND 6+ empty adjacent zones, it's an outpost
    -- Skip this check if we're being called recursively to avoid infinite loops
    if map and not skipOutpostCheck and zone.militaryBuildingCount and zone.militaryBuildingCount >= 8 then
        local emptyAdjacent, complete = strikeTargeting.countAdjacentEmptyZones(map, zone)
        if complete and emptyAdjacent >= 6 then
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

-- ── Shared strike target selection (/r2-strike and natural strikes use this) ───
-- strikeAllow: a zone struck by any strike drops to 0 and can't be picked until it recovers.
-- Each invocation recovers +1 on every zone except the one struck in the previous invocation,
-- so that zone stays at 0 for one invocation. Nil means full allowance.
strikeTargeting.STRIKE_ALLOW_MAX = 3

function strikeTargeting.getStrikeAllow(zone)
    return zone.strikeAllow or strikeTargeting.STRIKE_ALLOW_MAX
end

function strikeTargeting.markStruck(map, zone)
    zone.strikeAllow = 0
    map.strikeAllowLastStruck = zone
end

-- Picks the zone for one strike invocation. Returns target, selectedCat, and the
-- populations used by the percentile rules. Returns nil if no zone can be struck.
-- Does not mark the zone; the caller marks it once the strike is committed.
function strikeTargeting.selectStrikeTarget(map, label)
    -- Recover strikeAllow for this invocation, except the zone struck in the previous one
    for _, zone in ipairs(map.zonesByIndex) do
        if zone ~= map.strikeAllowLastStruck then
            zone.strikeAllow = math.min(strikeTargeting.STRIKE_ALLOW_MAX, strikeTargeting.getStrikeAllow(zone) + 1)
        end
    end
    map.strikeAllowLastStruck = nil

    local categoryZones = {
        ["products"] = {}, ["power"] = {}, ["oil"] = {},
        ["raw-resources"] = {}, ["outpost"] = {}
    }
    -- Products, oil, and raw-resources need producing zones at or above the 70th percentile
    -- of item output. Power zones need generating zones at or above the 70th percentile of
    -- power generation. Outpost zones need to beat more than 30% of the other outposts on military buildings.
    local zoneCats = {}
    local producingRates = {}
    local powerRates = {}
    local outpostRates = {}
    for i, zone in ipairs(map.zonesByIndex) do
        local cat = strikeTargeting.getZoneCategory(zone, map)
        zoneCats[i] = cat
        if cat and cat ~= "power" and cat ~= "outpost" and (zone.totalRate or 0) > 0 then
            producingRates[#producingRates + 1] = zone.totalRate
        elseif cat == "power" and (zone.powerGen or 0) > 0 then
            powerRates[#powerRates + 1] = zone.powerGen
        elseif cat == "outpost" then
            outpostRates[#outpostRates + 1] = zone.militaryBuildingCount or 0
        end
    end
    table.sort(producingRates)
    table.sort(powerRates)
    table.sort(outpostRates)
    local minRate = producingRates[math.ceil(0.7 * #producingRates)] or math.huge
    local minPower = powerRates[math.ceil(0.7 * #powerRates)] or math.huge
    local minOutpost = outpostRates[math.floor(0.30 * #outpostRates) + 1] or math.huge

    for i, zone in ipairs(map.zonesByIndex) do
        local cat = zoneCats[i]
        if cat and categoryZones[cat] then
            local eligible
            if cat == "outpost" then
                eligible = (zone.militaryBuildingCount or 0) >= minOutpost
            elseif cat == "power" then
                eligible = (zone.powerGen or 0) > 0 and zone.powerGen >= minPower
            else
                eligible = (zone.totalRate or 0) > 0 and zone.totalRate >= minRate
            end
            if eligible then
                table.insert(categoryZones[cat], zone)
            end
        end
    end

    local availableCats = {}
    for cat, zones in pairs(categoryZones) do
        if #zones > 0 then table.insert(availableCats, cat) end
    end
    if #availableCats == 0 then
        game.print(label .. " No targetable zones found")
        return nil
    end

    -- Picks a zone within a category (products are weighted by share of output)
    local function pickZoneInCategory(cat)
        local targetZones = categoryZones[cat]
        if cat ~= "products" then
            return targetZones[math.random(1, #targetZones)]
        end
        local globalTotalRate = 0
        for _, zone in ipairs(map.zonesByIndex) do
            globalTotalRate = globalTotalRate + (zone.totalRate or 0)
        end
        local weights, totalWeight = {}, 0
        for i, zone in ipairs(targetZones) do
            local share = (globalTotalRate > 0) and ((zone.totalRate or 0) / globalTotalRate) or 0
            local w = (share * share) * (1 + (strikeTargeting.calculateProductValue(zone) or 0) * 0.1)
            if w < 0.0001 then w = 0.0001 end
            weights[i] = w
            totalWeight = totalWeight + w
        end
        local roll, cumulative = math.random() * totalWeight, 0
        local chosen = targetZones[#targetZones]
        for i, w in ipairs(weights) do
            cumulative = cumulative + w
            if roll <= cumulative then chosen = targetZones[i]; break end
        end
        return chosen
    end

    math.randomseed(game.tick + game.tick)
    local selectedCat = availableCats[math.random(1, #availableCats)]
    local target = pickZoneInCategory(selectedCat)

    -- Picked zone is at 0 allowance: reroll in the same category, then in a random category
    if strikeTargeting.getStrikeAllow(target) == 0 then
        target = pickZoneInCategory(selectedCat)
    end
    if strikeTargeting.getStrikeAllow(target) == 0 then
        selectedCat = availableCats[math.random(1, #availableCats)]
        target = pickZoneInCategory(selectedCat)
    end
    if strikeTargeting.getStrikeAllow(target) == 0 then
        game.print(label .. " Failed: rerolled zones are all at 0 strike allowance")
        return nil
    end

    return target, selectedCat, {producingRates = producingRates, powerRates = powerRates, outpostRates = outpostRates}
end

strikeTargetingG = strikeTargeting
return strikeTargeting
