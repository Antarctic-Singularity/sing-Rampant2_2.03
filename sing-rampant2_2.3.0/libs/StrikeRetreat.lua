-- Strike retreat: a strike unit hit before it has covered 75% of its trip gets a
-- speed boost and runs straight away from its attacker for 5 seconds.
-- Each unit can trigger once.
--
-- To remove this feature: delete this file and every line tagged "STRIKE RETREAT"
-- (control.lua, libs/StrikeManager.lua, prototypes/Stickers.lua).

local strikeRetreat = {}

local ENABLED = true
local COVERED_LIMIT = 0.75          -- trigger only while less of the trip than this is covered
local RETREAT_TICKS = 5 * 60
local RETREAT_DISTANCE = 10         -- tiles away from the attacker
local SPAWN_BOOST_TICKS = 5 * 60    -- length of the spawn speed sticker in StrikeManager
local SPEED_STICKER = "retreatSpeed-sticker-rampantFixed"

local function getState()
    storage.strikeRetreat = storage.strikeRetreat or {}
    return storage.strikeRetreat
end

function strikeRetreat.onUnitDamaged(event, universe)
    if not ENABLED then return end
    local unit = event.entity
    local cause = event.cause
    if not (unit and unit.valid and cause and cause.valid) then return end
    if not event.force or event.force.name == "enemy" then return end

    local state = getState()
    if state[unit.unit_number] then return end -- once per unit

    local group = unit.commandable and unit.commandable.parent_group
    local squad = group and universe.groupNumberToSquad[group.unique_id]
    if not (squad and squad.strikeObjective and squad.strikeStart) then return end

    local objective = squad.strikeObjective
    local start = squad.strikeStart
    local total = math.sqrt((start.x - objective.x) ^ 2 + (start.y - objective.y) ^ 2)
    if total <= 0 then return end
    local remaining = math.sqrt((unit.position.x - objective.x) ^ 2 + (unit.position.y - objective.y) ^ 2)
    if 1 - remaining / total >= COVERED_LIMIT then return end

    local tick = game.tick
    -- The speed boost waits until the spawn sticker has ended, so the two never stack
    local speedAt = math.max(tick, (squad.strikeSpawnTick or tick) + SPAWN_BOOST_TICKS)

    -- Run straight away from the attacker
    local retreatEnd = nil
    local dx = unit.position.x - cause.position.x
    local dy = unit.position.y - cause.position.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0.01 and unit.commandable then
        local target = {
            x = unit.position.x + dx / length * RETREAT_DISTANCE,
            y = unit.position.y + dy / length * RETREAT_DISTANCE,
        }
        local retreatPos = unit.surface.find_non_colliding_position(unit.name, target, 6, 1, true)
        if retreatPos then
            unit.commandable.set_command({
                type = defines.command.go_to_location,
                destination = retreatPos,
                distraction = defines.distraction.none,
                radius = 1,
            })
            retreatEnd = tick + RETREAT_TICKS
        end
    end

    state[unit.unit_number] = {
        unit = unit,
        objective = objective,
        speedAt = speedAt,
        speedDone = false,
        retreatEnd = retreatEnd,
    }
end

-- Called every 30 ticks from the existing on_nth_tick(30) handler
function strikeRetreat.onTick()
    if not ENABLED or not storage.strikeRetreat then return end
    local tick = game.tick
    local state = storage.strikeRetreat
    for unitNumber, entry in pairs(state) do
        local unit = entry.unit
        if not (unit and unit.valid) then
            state[unitNumber] = nil
        else
            if not entry.speedDone and tick >= entry.speedAt then
                entry.speedDone = true
                unit.surface.create_entity({
                    name = SPEED_STICKER,
                    target = unit,
                    position = unit.position,
                    force = "enemy",
                })
            end
            if entry.retreatEnd and tick >= entry.retreatEnd then
                entry.retreatEnd = nil
                if unit.commandable then
                    unit.commandable.set_command({
                        type = defines.command.go_to_location,
                        destination = entry.objective,
                        distraction = defines.distraction.by_enemy,
                        radius = 3,
                    })
                end
            end
        end
    end
end

return strikeRetreat
