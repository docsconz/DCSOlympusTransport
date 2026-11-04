-- Tests for simpleTransport.lua, run outside DCS with stubbed DCS globals.
--
-- Run from the repository root with a Lua 5.1 interpreter (DCS uses Lua 5.1):
--   lua5.1 scripts/lua/missionscripts/simpleTransport_test.lua
-- The stubs are simplified models of the DCS API calls the script uses; passing here does NOT prove the script
-- works in DCS, it only checks the script's own logic.

local scriptDir = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local SCRIPT = scriptDir .. "/simpleTransport.lua"

local failures, checks = 0, 0
local function check(name, condition, detail)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        print("FAIL: " .. name .. (detail and (" -- " .. tostring(detail)) or ""))
    end
end

local function near(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-6)
end

local function contains(text, part)
    return type(text) == "string" and text:find(part, 1, true) ~= nil
end

-- ---------------------------------------------------------------------------------------------
-- A tiny fake DCS world
-- ---------------------------------------------------------------------------------------------
local RED, BLUE = 1, 2
local function copy(value)
    if type(value) ~= "table" then return value end
    local c = {}
    for k, v in pairs(value) do c[copy(k)] = copy(v) end
    return c
end

local W  -- the current world
local undefinedReads = {}

local function newWorld(options)
    options = options or {}
    W = {
        nextId = 1000, units = {}, groups = {}, spawns = {}, texts = {}, cargo = {}, menus = {}, removed = {},
        timers = {}, now = 0, failSpawn = nil, failCargo = false, logs = {},
    }
    local world = W

    -- ---- objects
    local UnitMT, GroupMT = {}, {}
    UnitMT.__index = UnitMT
    GroupMT.__index = GroupMT

    function UnitMT:getName() return self.name end
    function UnitMT:getTypeName() return self.type end
    function UnitMT:getCoalition() return self.group.side end
    function UnitMT:getCountry() return self.country end
    function UnitMT:getID() return self.id end
    function UnitMT:getGroup() return self.group end
    function UnitMT:getLife() return self.life end
    function UnitMT:isExist() return self.exists end
    function UnitMT:isActive() return self.exists and self.active end
    function UnitMT:inAir() return self.air end
    function UnitMT:getPlayerName() return self.player end
    function UnitMT:getVelocity() return { x = self.speed or 0, y = 0, z = 0 } end
    function UnitMT:getPoint() return { x = self.x, y = self.y or 0, z = self.z } end
    function UnitMT:getPosition()
        local c, s = math.cos(self.heading), math.sin(self.heading)
        return {
            p = { x = self.x, y = self.y or 0, z = self.z },
            x = { x = c, y = 0, z = s },     -- forward
            y = { x = 0, y = 1, z = 0 },
            z = { x = -s, y = 0, z = c },    -- right
        }
    end

    function GroupMT:getName() return self.name end
    function GroupMT:getID() return self.id end
    function GroupMT:getCategory() return self.category end
    function GroupMT:getCoalition() return self.side end
    function GroupMT:isExist() return self.exists end
    function GroupMT:getSize() return #self.units end
    function GroupMT:getUnits()
        local list = {}
        for _, u in ipairs(self.units) do if u.exists then table.insert(list, u) end end
        return list
    end
    function GroupMT:destroy()
        self.exists = false
        for _, u in ipairs(self.units) do u.exists = false end
    end

    -- ---- builders used by the tests
    function world.addGroup(spec)
        world.nextId = world.nextId + 1
        local g = setmetatable({ name = spec.name, id = world.nextId, side = spec.side,
                                 category = spec.category or 2, exists = true, units = {} }, GroupMT)
        for _, us in ipairs(spec.units) do
            world.nextId = world.nextId + 1
            local u = setmetatable({
                name = us.name, type = us.type, id = world.nextId, group = g, country = us.country or spec.country or 2,
                x = us.x or 0, z = us.z or 0, y = us.y or 0, heading = us.heading or 0, life = 1, exists = true, active = true,
                air = us.air or false, player = us.player, speed = us.speed or 0,
            }, UnitMT)
            table.insert(g.units, u)
            world.units[u.name] = u
        end
        world.groups[g.name] = g
        return g
    end

    -- ---- DCS globals
    Unit = { getByName = function(n) return world.units[n] end, Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND_UNIT = 2 } }
    Group = { getByName = function(n) return world.groups[n] end,
              Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND = 2, SHIP = 3 } }
    coalition = {
        side = { NEUTRAL = 0, RED = RED, BLUE = BLUE },
        getGroups = function(side, category)
            local list = {}
            for _, g in pairs(world.groups) do
                if g.exists and g.side == side and (category == nil or g.category == category) then table.insert(list, g) end
            end
            return list
        end,
        getPlayers = function(side)
            local list = {}
            for _, u in pairs(world.units) do
                if u.exists and u.player and u.group.side == side then table.insert(list, u) end
            end
            return list
        end,
        addGroup = function(country, category, data)
            table.insert(world.spawns, { country = country, category = category, data = copy(data) })
            if world.failSpawn == "nil" then return nil end
            if world.failSpawn == "error" then error("spawn exploded") end
            local spec = { name = data.name, side = world.countrySide and world.countrySide[country] or BLUE,
                           country = country, category = category, units = {} }
            for _, us in ipairs(data.units) do
                table.insert(spec.units, { name = us.name, type = us.type, x = us.x, z = us.y, heading = us.heading, country = country })
            end
            -- the old group object (if any) is replaced in the registry, the way a respawn works
            return world.addGroup(spec)
        end,
    }
    trigger = { action = {
        outTextForUnit = function(id, text, time) table.insert(world.texts, { id = id, text = text }) end,
        setUnitInternalCargo = function(name, mass)
            if world.failCargo then error("cargo not supported") end
            world.cargo[name] = mass
        end,
    } }
    missionCommands = {
        addSubMenuForGroup = function(groupId, name, parent)
            local path = { name }
            table.insert(world.menus, { kind = "sub", groupId = groupId, name = name, path = path })
            return path
        end,
        addCommandForGroup = function(groupId, name, path, handler, arg)
            table.insert(world.menus, { kind = "cmd", groupId = groupId, name = name, path = path, handler = handler, arg = arg })
        end,
        removeItemForGroup = function(groupId, path)
            table.insert(world.removed, { groupId = groupId, path = path })
            for i = #world.menus, 1, -1 do
                local m = world.menus[i]
                if m.groupId == groupId and (m.path == path) then table.remove(world.menus, i) end
            end
        end,
    }
    timer = {
        getTime = function() return world.now end,
        scheduleFunction = function(fn, arg, when) table.insert(world.timers, { fn = fn, arg = arg, when = when }) end,
    }
    env = { info = function(m) table.insert(world.logs, m) end, error = function(m) table.insert(world.logs, "ERROR " .. m) end,
            mission = options.mission or { coalition = {} } }
    if options.mist == false then mist = nil else mist = { getUnitSkill = function() return false end } end

    -- load a fresh copy of the script
    simpleTransport = nil
    local chunk, err = loadfile(SCRIPT)
    assert(chunk, err)
    chunk()
    -- from here on, remember every read of a global that does not exist (catches use-before-define mistakes)
    setmetatable(_G, { __index = function(_, key) undefinedReads[key] = true end })
    return world
end

-- helper: find a menu command and run it the way DCS would
local function pressMenu(world, groupId, commandName)
    for _, m in ipairs(world.menus) do
        if m.kind == "cmd" and m.groupId == groupId and m.name == commandName then
            m.handler(m.arg)
            return true
        end
    end
    return false
end

local function lastText(world)
    local t = world.texts[#world.texts]
    return t and t.text
end

local function menusFor(world, groupId)
    local list = {}
    for _, m in ipairs(world.menus) do if m.groupId == groupId then table.insert(list, m) end end
    return list
end

-- standard fixtures ---------------------------------------------------------------------------
local function infantry(world, name, x, z, side)
    return world.addGroup({ name = name, side = side or BLUE, units = {
        { name = name .. "-1", type = "Soldier AK", x = x, z = z },
        { name = name .. "-2", type = "Soldier RPG", x = x + 3, z = z },
        { name = name .. "-3", type = "2B11 mortar", x = x + 6, z = z },
    } })
end
local function apc(world, name, x, z, extra)
    local u = { name = name, type = "BMP-2", x = x, z = z, heading = 0 }
    for k, v in pairs(extra or {}) do u[k] = v end
    return world.addGroup({ name = name .. " group", side = (extra and extra.side) or BLUE, units = { u } })
end

-- ===============================================================================================
-- 1. Basic load / unload
-- ===============================================================================================
do
    local w = newWorld()
    check("api version", simpleTransport.apiVersion == 1)
    check("poll timer scheduled at load", #w.timers == 1)
    infantry(w, "Inf A", 100, 100)
    apc(w, "APC 1", 110, 100)

    local ok, why = simpleTransport.canLoad("APC 1", "Inf A")
    check("canLoad ok", ok == true, why)

    ok, why = simpleTransport.load("APC 1", "Inf A")
    check("load by name succeeds", ok == true, why)
    check("load message", contains(why, "Inf A"), why)
    check("group destroyed after load", w.groups["Inf A"].exists == false)
    check("loaded group name reported", simpleTransport.getLoadedGroupName("APC 1") == "Inf A")
    check("no internal cargo call for a ground vehicle", w.cargo["APC 1"] == nil)

    -- unload
    local oldIds = {}
    for _, u in ipairs(w.groups["Inf A"].units) do oldIds[u.id] = true end
    ok, why = simpleTransport.unload("APC 1")
    check("unload succeeds", ok == true, why)
    check("state cleared after unload", simpleTransport.getLoadedGroupName("APC 1") == nil)
    local g = w.groups["Inf A"]
    check("group respawned", g and g.exists and #g.units == 3)
    local spawn = w.spawns[#w.spawns]
    check("spawn category is ground", spawn.category == Group.Category.GROUND)
    check("spawn country comes from the group", spawn.country == 2)
    -- transport at (110,100) facing heading 0 -> forward = +x, right = +z
    local us = spawn.data.units
    check("units 20 m in front (centre unit)", near(us[2].x, 130) and near(us[2].y, 100), us[2].x .. "," .. us[2].y)
    check("units 8 m apart", near(us[1].y - us[2].y, -8) and near(us[3].y - us[2].y, 8), us[1].y .. "," .. us[3].y)
    check("units keep the transport heading", near(us[1].heading, 0))
    check("respawned units have new IDs", not oldIds[g.units[1].id])
end

-- unload with a rotated transport: distance and spacing are measured along the transport's own axes
do
    local w = newWorld()
    infantry(w, "Inf R", 0, 0)
    apc(w, "APC R", 5, 0, { heading = math.pi / 2 })   -- facing +z
    assert(simpleTransport.load("APC R", "Inf R"))
    local ok, why = simpleTransport.unload("APC R")
    check("rotated unload ok", ok, why)
    local us = w.spawns[#w.spawns].data.units
    check("rotated: centre unit 20 m ahead", near(us[2].x, 5, 1e-6) and near(us[2].y, 20, 1e-6), us[2].x .. "," .. us[2].y)
    check("rotated: spacing along the right vector", near(math.sqrt((us[1].x - us[3].x) ^ 2 + (us[1].y - us[3].y) ^ 2), 16, 1e-6))
end

-- load with no group name picks the nearest eligible group (the F10 behaviour)
do
    local w = newWorld()
    infantry(w, "Far Inf", 140, 0)
    infantry(w, "Near Inf", 20, 0)
    apc(w, "APC N", 0, 0)
    local ok, why = simpleTransport.load("APC N", nil)
    check("nearest group loaded", ok and simpleTransport.getLoadedGroupName("APC N") == "Near Inf", why)
    check("other group untouched", w.groups["Far Inf"].exists)
end

-- ===============================================================================================
-- 2. Refusals
-- ===============================================================================================
do
    local w = newWorld()
    infantry(w, "Inf Far", 200, 0)
    apc(w, "APC 1", 0, 0)
    local ok, why = simpleTransport.load("APC 1", "Inf Far")
    check("out of range refused", ok == false)
    check("out of range message has distance", contains(why, "200 m") and contains(why, "150 m closer"), why)
    check("group not destroyed when refused", w.groups["Inf Far"].exists)
    ok, why = simpleTransport.canLoad("APC 1", "Inf Far")
    check("canLoad also refuses out of range", ok == false and contains(why, "away"), why)

    -- load without a name when nothing is near
    ok, why = simpleTransport.load("APC 1", nil)
    check("nameless load with the nearest group 200 m away is refused with a distance", ok == false and contains(why, "200 m"), why)
    infantry(w, "Inf Very Far", 5000, 0)
    w.groups["Inf Far"]:destroy()
    ok, why = simpleTransport.load("APC 1", nil)
    check("nameless load with nothing nearby", ok == false and contains(why, "cannot find any group"), why)
end

do
    local w = newWorld()
    infantry(w, "Inf 1", 10, 0)
    infantry(w, "Inf 2", 12, 0)
    apc(w, "APC 1", 0, 0)
    assert(simpleTransport.load("APC 1", "Inf 1"))
    local ok, why = simpleTransport.load("APC 1", "Inf 2")
    check("already carrying refused", ok == false and contains(why, "already transporting Inf 1"), why)
    check("second group untouched", w.groups["Inf 2"].exists)
    ok, why = simpleTransport.load("APC 1", nil)
    check("nameless load refused when already carrying", ok == false and contains(why, "already transporting"), why)
end

do
    local w = newWorld()
    w.addGroup({ name = "Mixed", side = BLUE, units = {
        { name = "m1", type = "Soldier AK", x = 5, z = 0 }, { name = "m2", type = "T-72B", x = 8, z = 0 } } })
    apc(w, "APC 1", 0, 0)
    local ok, why = simpleTransport.load("APC 1", "Mixed")
    check("mixed group refused", ok == false and contains(why, "T-72B"), why)
    check("mixed group untouched", w.groups["Mixed"].exists)
    ok, why = simpleTransport.load("APC 1", nil)
    check("nameless load ignores the mixed group", ok == false, why)
end

do
    local w = newWorld()
    infantry(w, "Red Inf", 5, 0, RED)
    apc(w, "APC 1", 0, 0)
    local ok, why = simpleTransport.load("APC 1", "Red Inf")
    check("different coalition refused", ok == false and contains(why, "different coalition"), why)
end

do
    local w = newWorld()
    infantry(w, "Inf 1", 5, 0)
    w.addGroup({ name = "Tank grp", side = BLUE, units = { { name = "Tank 1", type = "M-1 Abrams", x = 0, z = 0 } } })
    local ok, why = simpleTransport.load("Tank 1", "Inf 1")
    check("tank is not a transport", ok == false and contains(why, "cannot transport"), why)
    ok, why = simpleTransport.load("No such unit", "Inf 1")
    check("unknown transport", ok == false and contains(why, "not found"), why)
    apc(w, "APC 1", 0, 0)
    ok, why = simpleTransport.load("APC 1", "No such group")
    check("unknown group", ok == false and contains(why, "not found"), why)
    ok, why = simpleTransport.unload("APC 1")
    check("unload with nothing loaded", ok == false and contains(why, "not transporting"), why)
    ok, why = simpleTransport.unload("Tank 1")
    check("unload on a tank refused", ok == false)
end

do -- a group with a human-controlled unit cannot be loaded; non-ground groups neither
    local w = newWorld()
    w.addGroup({ name = "Human grp", side = BLUE, units = { { name = "h1", type = "Soldier AK", x = 5, z = 0, player = "Pilot" } } })
    w.addGroup({ name = "Heli grp", side = BLUE, category = 1, units = { { name = "heli1", type = "Soldier AK", x = 5, z = 0 } } })
    apc(w, "APC 1", 0, 0)
    local ok, why = simpleTransport.load("APC 1", "Human grp")
    check("player-controlled group refused", ok == false and contains(why, "controlled by a player"), why)
    ok, why = simpleTransport.load("APC 1", "Heli grp")
    check("non-ground group refused", ok == false and contains(why, "not a ground group"), why)
end

-- ===============================================================================================
-- 3. Unload conditions and failure handling
-- ===============================================================================================
do
    local w = newWorld()
    infantry(w, "Inf 1", 5, 0)
    w.addGroup({ name = "Heli grp", side = BLUE, category = 1, units = { { name = "Hook-1", type = "UH-1H", x = 0, z = 0, player = "Joe" } } })
    local ok, why = simpleTransport.load("Hook-1", "Inf 1")
    check("helicopter loads", ok, why)
    check("internal cargo set for a helicopter", w.cargo["Hook-1"] == 90 + 95 + 210, w.cargo["Hook-1"])

    w.units["Hook-1"].air = true
    ok, why = simpleTransport.unload("Hook-1")
    check("unload refused while airborne", ok == false and contains(why, "stop on the ground"), why)
    check("state kept after refusal", simpleTransport.getLoadedGroupName("Hook-1") == "Inf 1")

    w.units["Hook-1"].air = false
    w.units["Hook-1"].speed = 5   -- DCS may report a moving player as on the ground
    ok, why = simpleTransport.unload("Hook-1")
    check("unload refused while a player unit is moving", ok == false, why)

    w.units["Hook-1"].speed = 0
    ok, why = simpleTransport.unload("Hook-1")
    check("unload ok once stopped", ok, why)
    check("internal cargo reset", w.cargo["Hook-1"] == 0)
end

do -- AI vehicles: the speed check only applies to players (original behaviour)
    local w = newWorld()
    infantry(w, "Inf 1", 5, 0)
    apc(w, "APC 1", 0, 0, { speed = 8 })
    assert(simpleTransport.load("APC 1", "Inf 1"))
    local ok, why = simpleTransport.unload("APC 1")
    check("moving AI vehicle is not refused (only inAir counts)", ok, why)
end

do -- failed respawn keeps the state
    local w = newWorld()
    infantry(w, "Inf 1", 5, 0)
    apc(w, "APC 1", 0, 0)
    assert(simpleTransport.load("APC 1", "Inf 1"))

    w.failSpawn = "nil"
    local ok, why = simpleTransport.unload("APC 1")
    check("failed spawn reported", ok == false and contains(why, "could not"), why)
    check("state kept after failed spawn", simpleTransport.getLoadedGroupName("APC 1") == "Inf 1")

    w.failSpawn = "error"
    ok, why = simpleTransport.unload("APC 1")
    check("spawn error reported", ok == false and contains(why, "spawn exploded"), why)
    check("state kept after spawn error", simpleTransport.getLoadedGroupName("APC 1") == "Inf 1")

    w.failSpawn = nil
    ok, why = simpleTransport.unload("APC 1")
    check("retry succeeds", ok, why)
end

do -- a live group with the same name blocks unloading
    local w = newWorld()
    infantry(w, "Inf 1", 5, 0)
    apc(w, "APC 1", 0, 0)
    assert(simpleTransport.load("APC 1", "Inf 1"))
    infantry(w, "Inf 1", 500, 500)   -- someone spawned a group with that name meanwhile
    local ok, why = simpleTransport.unload("APC 1")
    check("name clash refused", ok == false and contains(why, "already exists"), why)
    check("state kept after name clash", simpleTransport.getLoadedGroupName("APC 1") == "Inf 1")
end

do -- cargo call failing must not break loading
    local w = newWorld()
    w.failCargo = true
    infantry(w, "Inf 1", 5, 0)
    w.addGroup({ name = "Heli grp", side = BLUE, category = 1, units = { { name = "Hook-1", type = "UH-1H", x = 0, z = 0 } } })
    local ok, why = simpleTransport.load("Hook-1", "Inf 1")
    check("load survives a failing setUnitInternalCargo", ok, why)
end

-- ===============================================================================================
-- 4. Group definitions: dynamic groups and mission-file groups
-- ===============================================================================================
do -- group not in the mission file (spawned by a script / Olympus)
    local w = newWorld()
    w.addGroup({ name = "Dyn Inf", side = BLUE, country = 5, units = {
        { name = "Dyn-1", type = "Soldier M4", x = 12, z = 3, heading = 1.0 },
        { name = "Dyn-2", type = "Soldier M249", x = 14, z = 3, heading = 1.0 } } })
    apc(w, "APC 1", 0, 0)
    local ok, why = simpleTransport.load("APC 1", "Dyn Inf")
    check("dynamic group loads", ok, why)
    local d = simpleTransport.loaded["APC 1"]
    check("rebuilt definition has both units", #d.groupData.units == 2)
    check("rebuilt unit has type, name, skill", d.groupData.units[1].type == "Soldier M4" and d.groupData.units[1].name == "Dyn-1"
          and d.groupData.units[1].skill == "Excellent" and d.groupData.units[1].playerCanDrive == true)
    check("country taken from the units", d.country == 5)
    check("rebuilt group has a string master task", d.groupData.task == "Ground Nothing")
    ok, why = simpleTransport.unload("APC 1")
    check("dynamic group unloads", ok, why)
    local spawn = w.spawns[#w.spawns]
    check("dynamic respawn keeps types", spawn.data.units[1].type == "Soldier M4" and spawn.data.units[2].type == "Soldier M249")
    check("dynamic respawn uses the group country", spawn.country == 5)
end

do -- group in the mission file, RED coalition, not the first country: route and task kept
    local mission = { coalition = {
        blue = { country = { { name = "USA", vehicle = { group = {} } } } },
        red = { country = { { name = "Russia" }, { name = "Insurgents", vehicle = { group = { {
            name = "Red Mission Inf", task = "Ground Nothing", groupId = 77,
            route = { points = { { x = 1, y = 2, type = "Turning Point" }, { x = 500, y = 500, type = "Turning Point" } } },
            units = {
                { name = "ri-1", type = "Infantry AK Ins", x = 1, y = 2, heading = 0, skill = "Random", playerCanDrive = false },
                { name = "ri-2", type = "Infantry AK Ins", x = 3, y = 2, heading = 0, skill = "Random", playerCanDrive = false } } } } } } } } } }
    local w = newWorld({ mission = mission })
    w.addGroup({ name = "Red Mission Inf", side = RED, country = 0, units = {
        { name = "ri-1", type = "Infantry AK Ins", x = 10, z = 10 }, { name = "ri-2", type = "Infantry AK Ins", x = 12, z = 10 } } })
    w.addGroup({ name = "Red APC grp", side = RED, units = { { name = "Red APC", type = "BTR-80", x = 15, z = 10, heading = 0 } } })
    local ok, why = simpleTransport.load("Red APC", "Red Mission Inf")
    check("red mission-file group loads", ok, why)
    local d = simpleTransport.loaded["Red APC"]
    check("mission task kept", d.groupData.task == "Ground Nothing")
    check("mission unit data kept (skill)", d.groupData.units[1].skill == "Random")
    check("mission route kept", #d.groupData.route.points == 2)
    w.countrySide = { [d.country] = RED }
    ok, why = simpleTransport.unload("Red APC")
    check("mission group unloads", ok, why)
    local spawn = w.spawns[#w.spawns]
    check("first waypoint moved to the spawn position", near(spawn.data.route.points[1].x, 15 + 20) and spawn.data.route.points[1].alt == 0)
    check("stored definition not modified by the spawn", d.groupData.route.points[1].x == 1 and d.groupData.units[1].x == 1)
end

do -- a killed unit is not carried along
    local w = newWorld()
    local g = infantry(w, "Inf 1", 5, 0)
    g.units[2].life = 0
    apc(w, "APC 1", 0, 0)
    assert(simpleTransport.load("APC 1", "Inf 1"))
    local d = simpleTransport.loaded["APC 1"]
    check("dead unit excluded", #d.groupData.units == 2)
    check("dead unit excluded from the weight", d.weight == 90 + 210, d.weight)
end

-- ===============================================================================================
-- 5. Weights
-- ===============================================================================================
do
    local w = newWorld()
    local g = w.addGroup({ name = "G", side = BLUE, units = {
        { name = "known", type = "Soldier RPG", x = 0, z = 0 }, { name = "unknown", type = "Some New Unit", x = 0, z = 0 },
        { name = "mortar", type = "2B11 mortar", x = 0, z = 0 }, { name = "bmp", type = "BMP-2", x = 0, z = 0 } } })
    local gw = simpleTransport._internal.getWeight
    check("weight from the table (infantry)", gw(w.units["known"]) == 95)
    check("weight from the table (mortar)", gw(w.units["mortar"]) == 210)
    check("weight from the table (vehicle)", gw(w.units["bmp"]) == 14300)
    check("unknown type defaults to 200 kg", gw(w.units["unknown"]) == 200)
end

-- ===============================================================================================
-- 6. F10 menu: discovery, shared state, no duplicates
-- ===============================================================================================
do
    local w = newWorld()
    infantry(w, "Inf 1", 5, 0)
    -- a human helicopter, a human tank, and an AI APC
    local heli = w.addGroup({ name = "Hook", side = BLUE, category = 1, units = { { name = "Hook-1", type = "UH-1H", x = 0, z = 0, player = "Joe" } } })
    local tank = w.addGroup({ name = "Armor", side = BLUE, units = { { name = "Armor-1", type = "M-1 Abrams", x = 300, z = 0, player = "Sam" } } })
    apc(w, "AI APC", 400, 0)

    simpleTransport._internal.poll()
    local hm = menusFor(w, heli.id)
    check("menu created for a human helicopter (submenu + 3 commands)", #hm == 4, #hm)
    check("no menu for a human-driven tank", #menusFor(w, tank.id) == 0)
    check("no menu for AI vehicles", #menusFor(w, w.groups["AI APC group"].id) == 0)

    simpleTransport._internal.poll()
    simpleTransport._internal.poll()
    check("no duplicate menus on later polls", #menusFor(w, heli.id) == 4)

    -- F10 load, then API unload (shared state)
    check("F10 Load group works", pressMenu(w, heli.id, "Load group"))
    check("F10 load message reaches the player", contains(lastText(w), "Picked up Inf 1"), lastText(w))
    check("API sees the group loaded through F10", simpleTransport.getLoadedGroupName("Hook-1") == "Inf 1")
    pressMenu(w, heli.id, "Check load status")
    check("F10 status message", contains(lastText(w), "Inf 1 is onboard"), lastText(w))
    local ok, why = simpleTransport.unload("Hook-1")
    check("API unload of an F10-loaded group", ok, why)

    -- API load, then F10 unload
    w.groups["Inf 1"].exists = true   -- (respawned by the unload above)
    local ok2, why2 = simpleTransport.load("Hook-1", "Inf 1")
    check("API load", ok2, why2)
    check("F10 Unload group works", pressMenu(w, heli.id, "Unload group"))
    check("F10 unload message", contains(lastText(w), "Group Inf 1 deployed"), lastText(w))
    check("state empty after F10 unload", simpleTransport.getLoadedGroupName("Hook-1") == nil)

    pressMenu(w, heli.id, "Unload group")
    check("F10 refusal message", contains(lastText(w), "Not transporting any group"), lastText(w))
end

do -- slot respawn: the menu is re-added once, not duplicated
    local w = newWorld()
    local heli = w.addGroup({ name = "Hook", side = BLUE, category = 1, units = { { name = "Hook-1", type = "UH-1H", x = 0, z = 0, player = "Joe" } } })
    simpleTransport._internal.poll()
    check("initial menu", #menusFor(w, heli.id) == 4)
    w.units["Hook-1"].exists = false          -- player leaves / aircraft destroyed
    simpleTransport._internal.poll()
    check("menu kept while the slot is empty", simpleTransport.menus["Hook-1"].gone == true)
    w.units["Hook-1"].exists = true           -- player comes back
    simpleTransport._internal.poll()
    check("menu re-added once after a respawn", #menusFor(w, heli.id) == 4, #menusFor(w, heli.id))
    check("old menu removed", #w.removed == 1)
end

do -- two human slots in one group get separate submenus
    local w = newWorld()
    local g = w.addGroup({ name = "Jolly", side = BLUE, category = 1, units = {
        { name = "Jolly-1", type = "CH-47D", x = 0, z = 0, player = "A" }, { name = "Jolly-2", type = "CH-47D", x = 5, z = 0, player = "B" } } })
    simpleTransport._internal.poll()
    local titles = {}
    for _, m in ipairs(menusFor(w, g.id)) do if m.kind == "sub" then table.insert(titles, m.name) end end
    check("two submenus for two human slots", #titles == 2 and contains(titles[1] .. titles[2], "Jolly-1") and contains(titles[1] .. titles[2], "Jolly-2"),
          table.concat(titles, ";"))
end

do -- Combined Arms vehicle slots: found in the mission file, not through getPlayers
    local mission = { coalition = { blue = { country = { { name = "USA", vehicle = { group = {
        { name = "BMP Slot grp", units = { { name = "BMP Slot", type = "BMP-2", skill = "Client" } } },
        { name = "Tank Slot grp", units = { { name = "Tank Slot", type = "M-1 Abrams", skill = "Player" } } },
        { name = "AI grp", units = { { name = "AI APC", type = "BMP-2", skill = "High" } } } } } } } } } }
    local w = newWorld({ mission = mission })
    local bmp = w.addGroup({ name = "BMP Slot grp", side = BLUE, units = { { name = "BMP Slot", type = "BMP-2", x = 0, z = 0 } } })
    local tank = w.addGroup({ name = "Tank Slot grp", side = BLUE, units = { { name = "Tank Slot", type = "M-1 Abrams", x = 50, z = 0 } } })
    local ai = w.addGroup({ name = "AI grp", side = BLUE, units = { { name = "AI APC", type = "BMP-2", x = 100, z = 0 } } })
    infantry(w, "Inf 1", 5, 0)
    simpleTransport._internal.poll()
    check("vehicle client slot gets a menu", #menusFor(w, bmp.id) == 4, #menusFor(w, bmp.id))
    check("tank client slot gets no menu", #menusFor(w, tank.id) == 0)
    check("AI vehicle gets no menu", #menusFor(w, ai.id) == 0)
    simpleTransport._internal.poll()
    check("no duplicate vehicle menus", #menusFor(w, bmp.id) == 4)
    check("F10 load from a vehicle slot", pressMenu(w, bmp.id, "Load group") and simpleTransport.getLoadedGroupName("BMP Slot") == "Inf 1", lastText(w))
    w.units["BMP Slot"].speed = 4   -- getPlayerName() is nil for these, but the slot counts as player-controlled
    local ok, why = simpleTransport.unload("BMP Slot")
    check("moving vehicle slot cannot unload", ok == false and contains(why, "stop on the ground"), why)
    w.units["BMP Slot"].speed = 0
    ok, why = simpleTransport.unload("BMP Slot")
    check("stopped vehicle slot unloads", ok, why)
end

do -- a destroyed transport loses its cargo
    local w = newWorld()
    infantry(w, "Inf 1", 5, 0)
    apc(w, "APC 1", 0, 0)
    assert(simpleTransport.load("APC 1", "Inf 1"))
    w.units["APC 1"].life = 0
    simpleTransport._internal.poll()
    check("cargo dropped when the transport is destroyed", simpleTransport.getLoadedGroupName("APC 1") == nil)
end

do -- the poll timer reschedules itself, and survives an error
    local w = newWorld()
    local t = w.timers[1]
    local nextTime = t.fn(nil, 10)
    check("poll handler returns the next run time", nextTime == 11, nextTime)
    coalition.getPlayers = function() error("boom") end
    nextTime = t.fn(nil, 20)
    check("poll handler survives an error", nextTime == 21)
end

do -- works without MIST
    local w = newWorld({ mist = false })
    infantry(w, "Inf 1", 5, 0)
    apc(w, "APC 1", 0, 0)
    local ok, why = simpleTransport.load("APC 1", "Inf 1")
    check("load works without mist", ok, why)
    ok, why = simpleTransport.unload("APC 1")
    check("unload works without mist", ok, why)
end

-- ===============================================================================================
-- 7. Generated allowlists
-- ===============================================================================================
do
    newWorld()
    local t, p = simpleTransport.transportTypes, simpleTransport.passengerTypes
    check("tank is not a transport", t["M-1 Abrams"] == nil and t["T-72B"] == nil)
    check("infantry is not a transport", t["Soldier AK"] == nil)
    check("APC is a ground transport", t["BMP-2"] == "ground")
    check("helicopter is an air transport", t["UH-1H"] == "air")
    check("transport aircraft is an air transport", t["C-130"] == "air")
    check("mortar is a passenger", p["2B11 mortar"] == true)
    check("infantry is a passenger", p["Soldier AK"] == true)
    check("vehicles are not passengers", p["BMP-2"] == nil)
    check("allowlists are marked provisional", simpleTransport.allowlistsProvisional == true)
end

do
    undefinedReads["mist"] = nil   -- the script deliberately probes for MIST
    local names = {}
    for k in pairs(undefinedReads) do table.insert(names, k) end
    check("script never reads an undefined global", #names == 0, table.concat(names, ","))
end

print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
