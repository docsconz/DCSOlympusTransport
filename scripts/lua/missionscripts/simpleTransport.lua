-- simpleTransport: load ground groups (infantry and mortars) into transports and unload them again.
--
-- Add this file to a mission with a "DO SCRIPT FILE" trigger (mission start). It works on its own, through
-- the F10 radio menu of human players, and it exposes a function API (simpleTransport.load / unload / ...)
-- that other scripts, such as Olympus, can call. The F10 menu and the API share the same state, so a group
-- loaded through one can be unloaded through the other.
--
-- Loading destroys the group and keeps its definition in memory; unloading respawns the group in front of the
-- transport. The state is lost when the mission restarts. Respawned units get new unit IDs.
--
-- Requirements: DCS scripting environment. MIST is used only to look up a unit's skill (optional).
--
-- Allowlists of unit types are generated from the Olympus databases. To change them, edit
-- simpleTransport_overrides.txt and run simpleTransport_generate_lists.py (see the GENERATED section below).

simpleTransport = {}
simpleTransport.apiVersion = 1

-- ---------------------------------------------------------------------------------------------
-- User-tunable constants
-- ---------------------------------------------------------------------------------------------
local MAX_PICKUP_DISTANCE = 50        -- meters from the transport to the nearest living unit of the group
local SPAWN_DISTANCE = 20             -- meters in front of the transport where the group is placed
local SPAWN_UNIT_SPACING = 8          -- meters between units of the respawned group (placed in a row)
local MENU_POLL_INTERVAL = 1          -- seconds between scans for new human players / dead transports
local DEFAULT_UNIT_WEIGHT = 200       -- kg, used when a unit type is not in simpleTransport.unitWeights
local MOVING_SPEED_THRESHOLD = 0.05   -- m/s; a PLAYER unit faster than this counts as "not stopped"
local FAR_FACTOR = 5                  -- groups farther than FAR_FACTOR * MAX_PICKUP_DISTANCE are not suggested

-- Approximate unit weights in kg, by DCS type name. Recorded for information only; no limit is enforced.
simpleTransport.unitWeights = {
    ["tt_KORD"] = 3500,
    ["VAZ Car"] = 1000,
    ["HL_ZU-23"] = 2500,
    ["Mi-24P"] = 8500,
    ["Ka-50_3"] = 7800,
    ["CH-47Fbl1"] = 10600,
    ["OH58D"] = 2300,
    ["M978 HEMTT Tanker"] = 12000,
    ["M1043 HMMWV Armament"] = 3900,
    ["M1045 HMMWV TOW"] = 3900,
    ["M1134 Stryker ATGM"] = 18600,
    ["BRDM-2"] = 7000,
    ["MTLB"] = 9700,
    ["HL_KORD"] = 2500,
    ["HL_DSHK"] = 2500,
    ["tt_DSHK"] = 3500,
    ["BMP-2"] = 14300,
    ["Soldier AK"] = 90,
    ["Soldier RPG"] = 95,
    ["Soldier M249"] = 95,
    ["Soldier stinger"] = 90,
    ["BTR-60"] = 10300,
    ["2B11 mortar"] = 210,
    ["Ural-375"] = 8400,
    ["SKP-11"] = 9000,
    ["ATZ-10"] = 10000,
    ["Land_Rover_109_S3"] = 1900,
    ["Hummer"] = 3300,
    ["AH-64D_BLK_II"] = 5200,
    ["UH-1H"] = 2300,
    ["M 818"] = 7000,
    ["CH-47D"] = 10600,
    ["KAMAZ Truck"] = 9000,
    ["ZIL-4331"] = 7000,
    ["UAZ-469"] = 1700,
    ["MAZ-6303"] = 10000,
    ["GAZ-66"] = 3600,
    ["Ural-375 ZU-23 Insurgent"] = 8500,
    ["Infantry AK Ins"] = 90,
    ["BMP-1"] = 13200,
    ["T-55"] = 36000,
    ["Strela-1 9P31"] = 7000,
    ["GAZ-3307"] = 3700,
    ["LAZ Bus"] = 9000,
    ["S-60_Type59_Artillery"] = 4800
}

-- BEGIN GENERATED (do not edit by hand; regenerate with scripts/lua/missionscripts/simpleTransport_generate_lists.py) --
-- Source: databases/units/*.json. Overrides file: simpleTransport_overrides.txt.
-- While true, the lists below are the generator's best guesses and still need the owner's confirmation.
simpleTransport.allowlistsProvisional = true

-- Groups made only of these unit types can be loaded (infantry plus the 2B11 mortar).
simpleTransport.passengerTypes = {
    ["2B11 mortar"] = true,
    ["Infantry AK"] = true,
    ["Infantry AK Ins"] = true,
    ["Infantry AK ver2"] = true,
    ["Infantry AK ver3"] = true,
    ["JTAC"] = true,
    ["Paratrooper AKS-74"] = true,
    ["Paratrooper RPG-16"] = true,
    ["Soldier AK"] = true,
    ["Soldier M249"] = true,
    ["Soldier M4"] = true,
    ["Soldier M4 GRG"] = true,
    ["Soldier RPG"] = true,
    ["soldier_mauser98"] = true,
    ["soldier_wwii_br_01"] = true,
    ["soldier_wwii_us"] = true,
}

-- Units of these types can act as transports. "ground" = ground vehicle, "air" = aircraft/helicopter.
simpleTransport.transportTypes = {
    ["AAV7"] = "ground",
    ["An-26B"] = "air",
    ["An-30M"] = "air",
    ["BMD-1"] = "ground",
    ["BMP-1"] = "ground",
    ["BMP-2"] = "ground",
    ["BMP-3"] = "ground",
    ["BRDM-2"] = "ground",
    ["BTR-80"] = "ground",
    ["BTR-82A"] = "ground",
    ["BTR_D"] = "ground",
    ["Bedford_MWD"] = "ground",
    ["Blitz_36-6700A"] = "ground",
    ["C-130"] = "air",
    ["C-130J-30"] = "air",
    ["C-17A"] = "air",
    ["C-47"] = "air",
    ["CCKW_353"] = "ground",
    ["CH-47D"] = "air",
    ["CH-47Fbl1"] = "air",
    ["CH-53E"] = "air",
    ["CHAP_M1083"] = "ground",
    ["CHAP_M1130"] = "ground",
    ["CHAP_MATV"] = "ground",
    ["Cobra"] = "ground",
    ["GAZ-3307"] = "ground",
    ["GAZ-3308"] = "ground",
    ["GAZ-66"] = "ground",
    ["HL_DSHK"] = "ground",
    ["HL_KORD"] = "ground",
    ["Horch_901_typ_40_kfz_21"] = "ground",
    ["Hummer"] = "ground",
    ["IKARUS Bus"] = "ground",
    ["IL-76MD"] = "air",
    ["KAMAZ Truck"] = "ground",
    ["Ka-27"] = "air",
    ["KrAZ6322"] = "ground",
    ["Kubelwagen_82"] = "ground",
    ["LARC-V"] = "ground",
    ["LAV-25"] = "ground",
    ["LAZ Bus"] = "ground",
    ["Land_Rover_101_FC"] = "ground",
    ["Land_Rover_109_S3"] = "ground",
    ["LiAZ Bus"] = "ground",
    ["M 818"] = "ground",
    ["M-113"] = "ground",
    ["M-2 Bradley"] = "ground",
    ["M1043 HMMWV Armament"] = "ground",
    ["M1045 HMMWV TOW"] = "ground",
    ["M1126 Stryker ICV"] = "ground",
    ["M1134 Stryker ATGM"] = "ground",
    ["M2A1_halftrack"] = "ground",
    ["M30_CC"] = "ground",
    ["MAZ-6303"] = "ground",
    ["MCV-80"] = "ground",
    ["MTLB"] = "ground",
    ["Marder"] = "ground",
    ["MaxxPro_MRAP"] = "ground",
    ["Mi-26"] = "air",
    ["Mi-8MT"] = "air",
    ["SH-3W"] = "air",
    ["SH-60B"] = "air",
    ["Sd_Kfz_2"] = "ground",
    ["Sd_Kfz_251"] = "ground",
    ["Sd_Kfz_7"] = "ground",
    ["TPZ"] = "ground",
    ["Tigr_233036"] = "ground",
    ["Trolley bus"] = "ground",
    ["Type_94_Truck"] = "ground",
    ["Type_98_So_Da"] = "ground",
    ["UAZ-469"] = "ground",
    ["UH-1H"] = "air",
    ["UH-60A"] = "air",
    ["Ural-375"] = "ground",
    ["Ural-4320-31"] = "ground",
    ["Ural-4320T"] = "ground",
    ["VAB_Mephisto"] = "ground",
    ["VAZ Car"] = "ground",
    ["Willys_MB"] = "ground",
    ["Yak-40"] = "air",
    ["ZBD04A"] = "ground",
    ["ZIL-4331"] = "ground",
    ["gaz-66_civil"] = "ground",
    ["kamaz_tent_civil"] = "ground",
    ["tt_DSHK"] = "ground",
    ["tt_KORD"] = "ground",
    ["ural_4230_civil_b"] = "ground",
    ["ural_4230_civil_t"] = "ground",
    ["zil-131_civil"] = "ground",
}
-- END GENERATED --

-- ---------------------------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------------------------
-- Loaded groups, by transport unit NAME: { groupName, side, country, groupData, weight }.
-- Both the F10 menu and the API use this table.
simpleTransport.loaded = {}

-- Human players that already have an F10 menu, by unit name: { groupId, path, gone }.
simpleTransport.menus = {}

local _sf = string.format

local function log(msg)
    env.info("simpleTransport: " .. msg)
end

-- ---------------------------------------------------------------------------------------------
-- Small helpers (plain vector math so the script does not depend on MIST for it)
-- ---------------------------------------------------------------------------------------------
local function distance(p1, p2)
    local dx, dy, dz = p1.x - p2.x, (p1.y or 0) - (p2.y or 0), p1.z - p2.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function speedOf(unit)
    local v = unit:getVelocity()
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[deepCopy(k)] = deepCopy(v)
    end
    return copy
end

-- Calls callback(vehicleGroup) for every vehicle group of the mission file (all coalitions, all countries) and
-- returns the first non-nil value the callback returns.
local function forEachMizVehicleGroup(callback)
    local mission = env.mission
    if not (mission and mission.coalition) then
        return nil
    end
    for _, coalitionData in pairs(mission.coalition) do
        if type(coalitionData) == "table" and type(coalitionData.country) == "table" then
            for _, countryData in ipairs(coalitionData.country) do
                local vehicle = countryData.vehicle
                local vehicleGroups = vehicle and vehicle.group or {}
                for _, vehicleGroup in ipairs(vehicleGroups) do
                    local result = callback(vehicleGroup)
                    if result ~= nil then
                        return result
                    end
                end
            end
        end
    end
    return nil
end

-- Player-drivable vehicle slots (Combined Arms) are not returned by coalition.getPlayers (Hoggit wiki), and
-- getPlayerName may not work for them, so they are recognised from the mission file: units whose skill is
-- "Client" or "Player". UNVERIFIED in game: check that this matches how your mission defines vehicle slots.
local function scanClientSlots()
    local slots = {}
    forEachMizVehicleGroup(function(vehicleGroup)
        for _, unit in ipairs(vehicleGroup.units or {}) do
            if unit.skill == "Client" or unit.skill == "Player" then
                slots[unit.name] = true
            end
        end
        return nil
    end)
    return slots
end
simpleTransport.clientSlots = scanClientSlots()

local function isPlayerControlled(unit)
    return unit:getPlayerName() ~= nil or simpleTransport.clientSlots[unit:getName()] == true
end

-- A unit counts as usable when it exists, is active and has life left.
local function isAlive(unit)
    return unit ~= nil and unit:isExist() and unit:isActive() and unit:getLife() > 0
end

local function getUnit(unitName)
    local unit = unitName and Unit.getByName(unitName)
    if unit and isAlive(unit) then
        return unit
    end
    return nil
end

local function getLivingUnits(group)
    local living = {}
    local units = group:getUnits()
    if units then
        for _, unit in ipairs(units) do
            if unit:isExist() and unit:getLife() > 0 then
                table.insert(living, unit)
            end
        end
    end
    return living
end

-- Weight of one unit in kg, by its DCS type name.
local function getWeight(unit)
    return simpleTransport.unitWeights[unit:getTypeName()] or DEFAULT_UNIT_WEIGHT
end

-- Returns "ground" or "air" when the unit's type is an allowed transport, otherwise nil.
local function transportKind(unit)
    return simpleTransport.transportTypes[unit:getTypeName()]
end

-- CTLD reports that DCS can say a unit is in the air while it is actually on the ground, so for PLAYER units
-- the speed is checked too. AI units rely on inAir() alone, so an AI vehicle that is driving is NOT refused.
local function isInAir(unit)
    local isPlayer = isPlayerControlled(unit)
    return unit:inAir() or (isPlayer and speedOf(unit) >= MOVING_SPEED_THRESHOLD)
end

-- Shortest distance from a unit to any living unit of the group, or nil when the group has none.
local function groupDistance(group, unit)
    local best
    local here = unit:getPoint()
    for _, member in ipairs(getLivingUnits(group)) do
        local d = distance(here, member:getPoint())
        if not best or d < best then
            best = d
        end
    end
    return best
end

-- Returns nil when every living unit is an allowed passenger, otherwise the type name of the first that is not.
-- Also returns "player" as a second value when a living unit is controlled by a human.
local function firstNonPassenger(group)
    for _, unit in ipairs(getLivingUnits(group)) do
        if isPlayerControlled(unit) then
            return unit:getTypeName(), "player"
        end
        if not simpleTransport.passengerTypes[unit:getTypeName()] then
            return unit:getTypeName()
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------------------------
-- Group definitions
-- ---------------------------------------------------------------------------------------------
-- Looks the group up in the mission file (all coalitions, all countries). Groups that were spawned during the
-- mission (for example by Olympus) are not in it.
local function findGroupInMiz(groupName)
    return forEachMizVehicleGroup(function(vehicleGroup)
        if vehicleGroup.name == groupName then
            return vehicleGroup
        end
    end)
end


local function findUnitInList(unitName, unitList)
    for _, unit in ipairs(unitList or {}) do
        if unit.name == unitName then
            return unit
        end
    end
    return nil
end

local function getHeading(position)
    return math.atan2(position.x.z, position.x.x)
end

local function getSkill(unit)
    -- mist.getUnitSkill returns the skill string, or false when the unit is not in its database
    if mist and mist.getUnitSkill then
        local ok, skill = pcall(mist.getUnitSkill, unit:getName())
        if ok and type(skill) == "string" then
            return skill
        end
    end
    return "Excellent"
end

-- Builds a unit definition from a live unit (used when the group is not in the mission file).
local function makeUnitFromLive(unit)
    local position = unit:getPosition()
    return {
        ["name"] = unit:getName(),
        ["type"] = unit:getTypeName(),
        ["x"] = position.p.x,
        ["y"] = position.p.z,
        ["heading"] = getHeading(position),
        ["skill"] = getSkill(unit),
        ["playerCanDrive"] = true
    }
end

-- Collects what is needed to respawn the group later. Uses the mission file definition when the group is in it
-- (keeps its route and task), otherwise rebuilds the definition from the living units.
local function collectGroupDetails(group)
    local groupName = group:getName()
    local living = getLivingUnits(group)
    local mizGroup = findGroupInMiz(groupName)

    local groupData
    if mizGroup then
        groupData = deepCopy(mizGroup)
        groupData.units = {}
    else
        groupData = {
            ["visible"] = false,
            ["hidden"] = false,
            ["units"] = {},
            ["name"] = groupName,
            -- coalition.addGroup requires the master task as a string (Hoggit wiki)
            ["task"] = "Ground Nothing"
        }
    end

    local weight = 0
    for _, unit in ipairs(living) do
        local mizUnit = mizGroup and findUnitInList(unit:getName(), mizGroup.units)
        -- the mission file entry is only trusted if it describes the same type of unit
        if mizUnit and mizUnit.type == unit:getTypeName() then
            table.insert(groupData.units, deepCopy(mizUnit))
        else
            table.insert(groupData.units, makeUnitFromLive(unit))
        end
        weight = weight + getWeight(unit)
    end

    return {
        ["groupName"] = groupName,
        ["side"] = group:getCoalition(),
        ["country"] = living[1] and living[1]:getCountry(),
        ["groupData"] = groupData,
        ["weight"] = weight
    }
end

-- Places the group's units in a row 20 m in front of the transport and spawns the group.
-- Returns true on success, or false and a reason. Works on a copy: the stored details are never modified.
local function spawnGroup(transportUnit, details)
    local groupData = deepCopy(details.groupData)
    local units = groupData.units
    if #units == 0 then
        return false, "the stored group has no units"
    end

    local position = transportUnit:getPosition()
    local heading = getHeading(position)
    local forward = position.x   -- unit vector pointing forward
    local right = position.z     -- unit vector pointing to the right
    local count = #units - 1

    -- centre the row on the transport's forward axis
    local startX = position.p.x + forward.x * SPAWN_DISTANCE - right.x * SPAWN_UNIT_SPACING * count / 2
    local startZ = position.p.z + forward.z * SPAWN_DISTANCE - right.z * SPAWN_UNIT_SPACING * count / 2

    local route = groupData.route
    if route and route["points"] and #(route["points"]) > 0 then
        -- the first waypoint is the group's start position: move it to the new place
        local first = route["points"][1]
        first["alt"] = 0
        first["alt_type"] = "RADIO"
        first["x"] = startX
        first["y"] = startZ
    end

    for index, unit in ipairs(units) do
        unit["x"] = startX + right.x * SPAWN_UNIT_SPACING * (index - 1)
        unit["y"] = startZ + right.z * SPAWN_UNIT_SPACING * (index - 1)
        unit["heading"] = heading
    end

    local country = details.country or transportUnit:getCountry()
    local ok, result = pcall(coalition.addGroup, country, Group.Category.GROUND, groupData)
    if not ok then
        return false, "the game could not spawn the group (" .. tostring(result) .. ")"
    end
    if not result then
        return false, "the game could not spawn the group"
    end
    return true
end

-- Internal cargo weight only exists for aircraft and helicopters; the call is protected because it can fail
-- for other unit types.
local function setInternalCargo(transportUnitName, weight)
    local ok, err = pcall(trigger.action.setUnitInternalCargo, transportUnitName, weight)
    if not ok then
        log("setUnitInternalCargo failed for " .. transportUnitName .. ": " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------------------------
-- Checks that the transport unit exists and may carry a group. Returns the unit, or nil and a reason.
local function checkTransport(transportUnitName)
    local unit = getUnit(transportUnitName)
    if not unit then
        return nil, _sf("transport unit '%s' was not found or is not alive", tostring(transportUnitName))
    end
    if not transportKind(unit) then
        return nil, _sf("%s units cannot transport groups", unit:getTypeName())
    end
    return unit
end

-- Checks everything about a group except the distance. Returns the group, or nil and a reason.
local function checkGroup(transportUnit, groupName)
    local group = groupName and Group.getByName(groupName)
    if not (group and group:isExist()) then
        return nil, _sf("group '%s' was not found", tostring(groupName))
    end
    if group:getCategory() ~= Group.Category.GROUND then
        return nil, _sf("group '%s' is not a ground group", groupName)
    end
    if #getLivingUnits(group) == 0 then
        return nil, _sf("group '%s' has no living units", groupName)
    end
    if group:getCoalition() ~= transportUnit:getCoalition() then
        return nil, _sf("group '%s' belongs to a different coalition", groupName)
    end
    local badType, why = firstNonPassenger(group)
    if why == "player" then
        return nil, _sf("group '%s' is controlled by a player", groupName)
    end
    if badType then
        return nil, _sf("group '%s' contains %s, only infantry and mortars can be loaded", groupName, badType)
    end
    return group
end

-- Full check for one named group.
local function checkLoad(transportUnitName, groupName)
    local unit, reason = checkTransport(transportUnitName)
    if not unit then
        return nil, nil, reason
    end
    local carried = simpleTransport.loaded[transportUnitName]
    if carried then
        return nil, nil, _sf("already transporting %s", carried.groupName)
    end
    local group
    group, reason = checkGroup(unit, groupName)
    if not group then
        return nil, nil, reason
    end
    local dist = groupDistance(group, unit)
    if dist > MAX_PICKUP_DISTANCE then
        return nil, nil, _sf("group '%s' is %.0f m away, you need to get %.0f m closer (limit %.0f m)",
            groupName, dist, dist - MAX_PICKUP_DISTANCE, MAX_PICKUP_DISTANCE)
    end
    return unit, group
end

-- Finds the closest group that could be loaded (ignoring distance). Returns the group and its distance, or nil.
local function findNearestLoadableGroup(unit)
    local best, bestDist
    for _, group in ipairs(coalition.getGroups(unit:getCoalition(), Group.Category.GROUND) or {}) do
        if group:isExist() and checkGroup(unit, group:getName()) then
            local dist = groupDistance(group, unit)
            if dist and (not bestDist or dist < bestDist) then
                best, bestDist = group, dist
            end
        end
    end
    return best, bestDist
end

-- Can this transport load this group right now? Returns ok, reason.
function simpleTransport.canLoad(transportUnitName, groupName)
    local unit, group, reason = checkLoad(transportUnitName, groupName)
    if not unit then
        return false, reason
    end
    return true, _sf("can load %s", group:getName())
end

-- Loads a group into the transport. When groupName is nil, the nearest loadable group is used.
-- Returns ok, message.
function simpleTransport.load(transportUnitName, groupName)
    if not groupName then
        local unit, reason = checkTransport(transportUnitName)
        if not unit then
            return false, reason
        end
        if simpleTransport.loaded[transportUnitName] then
            return false, _sf("already transporting %s", simpleTransport.loaded[transportUnitName].groupName)
        end
        local nearest, dist = findNearestLoadableGroup(unit)
        if not nearest or dist >= MAX_PICKUP_DISTANCE * FAR_FACTOR then
            return false, _sf("cannot find any group to pick up; get within %.0f m of the group", MAX_PICKUP_DISTANCE)
        end
        groupName = nearest:getName()
    end

    local unit, group, reason = checkLoad(transportUnitName, groupName)
    if not unit then
        return false, reason
    end

    -- capture the definition first: if that fails nothing has been destroyed
    local okCollect, details = pcall(collectGroupDetails, group)
    if not okCollect or not details or #details.groupData.units == 0 then
        return false, _sf("could not read the definition of group '%s'", groupName)
    end

    simpleTransport.loaded[transportUnitName] = details
    local okDestroy, err = pcall(function() group:destroy() end)
    if not okDestroy then
        simpleTransport.loaded[transportUnitName] = nil
        return false, _sf("could not remove group '%s' (%s)", groupName, tostring(err))
    end

    if transportKind(unit) == "air" then
        setInternalCargo(transportUnitName, details.weight)
    end
    return true, _sf("picked up %s", groupName)
end

-- Respawns the loaded group in front of the transport. Returns ok, message.
function simpleTransport.unload(transportUnitName)
    local unit, reason = checkTransport(transportUnitName)
    if not unit then
        return false, reason
    end
    local details = simpleTransport.loaded[transportUnitName]
    if not details then
        return false, "not transporting any group"
    end
    if isInAir(unit) then
        return false, "you must come to a stop on the ground before unloading"
    end
    local existing = Group.getByName(details.groupName)
    if existing and existing:isExist() then
        return false, _sf("a group named '%s' already exists, cannot unload", details.groupName)
    end

    -- the stored state is only discarded after the spawn succeeded
    local ok, why = spawnGroup(unit, details)
    if not ok then
        return false, _sf("could not unload %s: %s", details.groupName, why)
    end
    simpleTransport.loaded[transportUnitName] = nil
    if transportKind(unit) == "air" then
        setInternalCargo(transportUnitName, 0)
    end
    return true, _sf("group %s deployed", details.groupName)
end

-- Name of the group the transport carries, or nil.
function simpleTransport.getLoadedGroupName(transportUnitName)
    local details = simpleTransport.loaded[transportUnitName]
    return details and details.groupName or nil
end

-- ---------------------------------------------------------------------------------------------
-- F10 menu (thin wrappers over the API)
-- ---------------------------------------------------------------------------------------------
local function tellUnit(unitName, msg)
    local unit = Unit.getByName(unitName)
    if unit then
        trigger.action.outTextForUnit(unit:getID(), msg, 10)
    end
end

local function capitalize(text)
    return (text:gsub("^%l", string.upper))
end

local function runMenuAction(action)
    -- important: the menu hands over the unit NAME, because a respawned slot is a new unit object
    return function(unitName)
        local ok, result, message = pcall(action, unitName)
        if not ok then
            log("menu action failed: " .. tostring(result))
            tellUnit(unitName, "Transport menu error, see dcs.log")
            return
        end
        tellUnit(unitName, capitalize(message or tostring(result)))
    end
end

local menuLoad = runMenuAction(function(unitName)
    local _, message = simpleTransport.load(unitName, nil)
    return nil, message
end)

local menuUnload = runMenuAction(function(unitName)
    local _, message = simpleTransport.unload(unitName)
    return nil, message
end)

local menuStatus = runMenuAction(function(unitName)
    if not getUnit(unitName) then
        return nil, "transport unit not found"
    end
    local name = simpleTransport.getLoadedGroupName(unitName)
    if name then
        return nil, _sf("group %s is onboard", name)
    end
    return nil, "not transporting any group"
end)

-- Unit:getGroup() is the normal way; MIST's unit database is a fallback for the cases where it fails.
local function getGroupIdOfUnit(unit)
    local ok, group = pcall(function() return unit:getGroup() end)
    if ok and group then
        local okId, id = pcall(function() return group:getID() end)
        if okId and id then
            return id, group
        end
    end
    if mist and mist.DBs and mist.DBs.unitsById then
        local entry = mist.DBs.unitsById[tonumber(unit:getID())]
        if entry and entry.groupId then
            return entry.groupId
        end
    end
    return nil
end

local function addMenuForUnit(unit)
    local unitName = unit:getName()
    local groupId, group = getGroupIdOfUnit(unit)
    if not groupId then
        return
    end

    -- a group can hold several human slots; they share the group's F10 menu, so each gets its own submenu
    local title = "Transport"
    if group and group:getSize() > 1 then
        title = "Transport (" .. unitName .. ")"
    end

    local path = missionCommands.addSubMenuForGroup(groupId, title)
    missionCommands.addCommandForGroup(groupId, "Load group", path, menuLoad, unitName)
    missionCommands.addCommandForGroup(groupId, "Unload group", path, menuUnload, unitName)
    missionCommands.addCommandForGroup(groupId, "Check load status", path, menuStatus, unitName)
    simpleTransport.menus[unitName] = { groupId = groupId, path = path, gone = false }
end

-- Called for every human-controlled unit found by the poll.
local function ensureMenuForPlayer(unit)
    if not transportKind(unit) then
        return   -- not an eligible transport (for example a tank): no menu
    end
    local unitName = unit:getName()
    local entry = simpleTransport.menus[unitName]
    if entry and not entry.gone then
        return
    end
    if entry and entry.gone then
        -- the slot was respawned: its group menus may be gone, so remove the old entry and add it again
        pcall(missionCommands.removeItemForGroup, entry.groupId, entry.path)
        simpleTransport.menus[unitName] = nil
    end
    addMenuForUnit(unit)
end

-- Runs every MENU_POLL_INTERVAL seconds: adds menus for new human players, and drops the state of transports
-- that no longer exist (a loaded group is lost when its transport is destroyed or its slot vanishes).
local function poll()
    for _, side in pairs(coalition.side) do
        for _, unit in ipairs(coalition.getPlayers(side) or {}) do
            if isAlive(unit) then
                ensureMenuForPlayer(unit)
            end
        end
    end

    for unitName in pairs(simpleTransport.clientSlots) do
        local unit = getUnit(unitName)
        if unit then
            ensureMenuForPlayer(unit)
        end
    end

    for unitName, entry in pairs(simpleTransport.menus) do
        if not getUnit(unitName) then
            entry.gone = true
        end
    end

    for unitName, details in pairs(simpleTransport.loaded) do
        if not getUnit(unitName) then
            log(_sf("transport %s is gone, group %s is lost", unitName, details.groupName))
            simpleTransport.loaded[unitName] = nil
        end
    end
end

local function pollHandler(_, time)
    local ok, err = pcall(poll)
    if not ok then
        log("poll failed: " .. tostring(err))
    end
    return time + MENU_POLL_INTERVAL
end

-- Test hooks (not part of the API).
simpleTransport._internal = {
    getWeight = getWeight,
    isInAir = isInAir,
    collectGroupDetails = collectGroupDetails,
    poll = poll,
}

timer.scheduleFunction(pollHandler, nil, timer.getTime() + MENU_POLL_INTERVAL)
log("loaded, API version " .. simpleTransport.apiVersion)
