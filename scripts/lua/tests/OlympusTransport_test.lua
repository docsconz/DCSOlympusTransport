-- Tests for scripts/lua/backend/OlympusTransport.lua, run outside DCS with stubbed DCS and Olympus globals.
--
-- Run from the repository root with a Lua 5.1 interpreter (DCS uses Lua 5.1):
--   lua5.1 scripts/lua/tests/OlympusTransport_test.lua
-- The stubs are simplified models; passing here does NOT prove the bridge works inside DCS.

local scriptDir = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local BRIDGE = scriptDir .. "/../backend/OlympusTransport.lua"

local failures, checks = 0, 0
local function check(name, condition, detail)
	checks = checks + 1
	if not condition then
		failures = failures + 1
		print("FAIL: " .. name .. (detail and (" -- " .. tostring(detail)) or ""))
	end
end

local function contains(text, part)
	return type(text) == "string" and text:find(part, 1, true) ~= nil
end

local undefinedReads = {}

-- Builds a fresh fake environment and loads the bridge into it
local function newEnv()
	local env = { units = {}, groups = {}, players = {}, logs = {}, calls = {} }

	local function unit(id, name, options)
		options = options or {}
		local u = { id = id, name = name, exists = true, player = options.player }
		function u:getID() return self.id end
		function u:getName() return self.name end
		function u:isExist() return self.exists end
		function u:getPlayerName() return self.player end
		env.units[id] = u
		return u
	end
	env.unit = unit

	function env.group(name, members)
		local g = { name = name, members = members, exists = true }
		function g:isExist() return self.exists end
		function g:getUnits() return self.members end
		env.groups[name] = g
		return g
	end

	Olympus = {
		log = { info = function(_, message) table.insert(env.logs, message) end },
		debug = function() end,
		executionResults = {},
		getUnitByID = function(id) return env.units[id] end,
	}
	-- the log stub is called as Olympus.log:info(message)
	Olympus.log.info = function(_, message) table.insert(env.logs, message) end

	Group = { getByName = function(name) return env.groups[name] end }
	coalition = {
		side = { NEUTRAL = 0, RED = 1, BLUE = 2 },
		getPlayers = function(side)
			local list = {}
			for _, p in ipairs(env.players) do table.insert(list, p) end
			return list
		end,
	}

	-- a stand-in for the mission script
	function env.installScript(options)
		options = options or {}
		simpleTransport = {
			apiVersion = options.apiVersion or 1,
			load = options.load or function(transportName, groupName)
				table.insert(env.calls, { "load", transportName, groupName })
				return true, "picked up " .. tostring(groupName)
			end,
			unload = options.unload or function(transportName)
				table.insert(env.calls, { "unload", transportName })
				return true, "group deployed"
			end,
		}
	end
	simpleTransport = nil

	local chunk, err = loadfile(BRIDGE)
	assert(chunk, err)
	chunk()
	setmetatable(_G, { __index = function(_, key) undefinedReads[key] = true end })
	return env
end

local function result(hash) return Olympus.executionResults[hash] end

-- ---------------------------------------------------------------------------------------------
-- Script presence and version
-- ---------------------------------------------------------------------------------------------
do
	local env = newEnv()
	env.unit(1, "APC 1"); env.group("Inf", { env.unit(2, "Inf-1") })
	Olympus.transportLoad(1, "Inf", "h1")
	check("missing script is reported", result("h1") and result("h1").success == false and result("h1").code == "scriptMissing", result("h1") and result("h1").code)
	check("missing script message is readable", contains(result("h1").message, "not loaded"))
	Olympus.transportUnload(1, "h2")
	check("missing script reported for unload too", result("h2").code == "scriptMissing")
	local status = Olympus.getTransportScriptStatus()
	check("status says not present", status.present == false and status.code == "scriptMissing")
end

do
	local env = newEnv()
	env.installScript({ apiVersion = 0 })
	env.unit(1, "APC 1")
	Olympus.transportUnload(1, "h1")
	check("too old script is reported", result("h1").code == "scriptVersion" and contains(result("h1").message, "too old"), result("h1").message)

	simpleTransport = { apiVersion = "one" }
	check("non-numeric version is rejected", Olympus.getTransportScriptStatus().code == "scriptVersion")
	simpleTransport = { apiVersion = 1 }
	check("script without functions is rejected", Olympus.getTransportScriptStatus().code == "scriptVersion")
	env.installScript()
	local status = Olympus.getTransportScriptStatus()
	check("good script is accepted", status.present == true and status.version == 1 and status.code == "ok")
end

-- ---------------------------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------------------------
do
	local env = newEnv()
	env.installScript()
	env.unit(10, "APC One")
	env.group("Inf Group", { env.unit(20, "Inf-1"), env.unit(21, "Inf-2") })
	Olympus.transportLoad(10, "Inf Group", "h1")
	check("load succeeds", result("h1").success == true and result("h1").code == "ok", result("h1").message)
	check("script gets the transport NAME and the group name", env.calls[1][1] == "load" and env.calls[1][2] == "APC One" and env.calls[1][3] == "Inf Group",
		env.calls[1] and (env.calls[1][2] .. "," .. tostring(env.calls[1][3])))
	check("script message is passed on", contains(result("h1").message, "picked up Inf Group"))
end

do
	local env = newEnv()
	env.installScript({ load = function() return false, "group 'Inf' is 200 m away" end })
	env.unit(10, "APC One"); env.group("Inf", { env.unit(20, "Inf-1") })
	Olympus.transportLoad(10, "Inf", "h1")
	check("refusal is reported with the script's reason", result("h1").success == false and result("h1").code == "refused" and contains(result("h1").message, "200 m"))
end

do
	local env = newEnv()
	env.installScript({ load = function() error("boom") end, unload = function() error("boom") end })
	env.unit(10, "APC One"); env.group("Inf", { env.unit(20, "Inf-1") })
	Olympus.transportLoad(10, "Inf", "h1")
	check("script error is caught on load", result("h1").code == "error" and contains(result("h1").message, "boom"), result("h1").message)
	Olympus.transportUnload(10, "h2")
	check("script error is caught on unload", result("h2").code == "error")
end

do
	local env = newEnv()
	env.installScript()
	env.unit(10, "APC One"); env.group("Inf", { env.unit(20, "Inf-1") })

	Olympus.transportLoad(999, "Inf", "h1")
	check("unknown transport ID", result("h1").code == "unitNotFound")

	env.units[10].exists = false
	Olympus.transportLoad(10, "Inf", "h2")
	check("destroyed transport", result("h2").code == "unitNotFound")
	env.units[10].exists = true

	Olympus.transportLoad(10, "Nope", "h3")
	check("unknown group", result("h3").code == "groupNotFound")

	env.groups["Inf"].exists = false
	Olympus.transportLoad(10, "Inf", "h4")
	check("destroyed group", result("h4").code == "groupNotFound")
	check("script never called for invalid requests", #env.calls == 0)
end

-- ---------------------------------------------------------------------------------------------
-- Human-controlled units
-- ---------------------------------------------------------------------------------------------
do
	local env = newEnv()
	env.installScript()
	env.unit(10, "Heli", { player = "Joe" })
	env.group("Inf", { env.unit(20, "Inf-1") })
	Olympus.transportLoad(10, "Inf", "h1")
	check("player-controlled transport refused (player name)", result("h1").code == "humanControlled" and contains(result("h1").message, "transport"))
	Olympus.transportUnload(10, "h2")
	check("player-controlled transport refused on unload", result("h2").code == "humanControlled")

	local ai = env.unit(11, "AI APC")
	table.insert(env.players, ai)   -- listed by DCS as an occupied player unit, but with no player name
	Olympus.transportLoad(11, "Inf", "h3")
	check("player-controlled transport refused (listed among players)", result("h3").code == "humanControlled")
	env.players = {}

	local tank = env.unit(12, "APC Two")
	env.group("Mixed", { env.unit(30, "m1"), env.unit(31, "m2", { player = "Sam" }) })
	Olympus.transportLoad(12, "Mixed", "h4")
	check("group with a player-controlled member refused", result("h4").code == "humanControlled" and contains(result("h4").message, "group"), result("h4").message)

	env.group("Listed", { env.unit(40, "l1") })
	table.insert(env.players, env.units[40])
	Olympus.transportLoad(12, "Listed", "h5")
	check("group member listed among players refused", result("h5").code == "humanControlled")
	check("script never called for human-controlled units", #env.calls == 0)

	-- a dead player unit must not block anything
	env.players = {}
	env.unit(50, "ghost"); env.units[50].exists = false; table.insert(env.players, env.units[50])
	Olympus.transportLoad(12, "Inf", "h6")
	check("a non-existing player unit is ignored", result("h6").code == "ok", result("h6").code)
end

-- ---------------------------------------------------------------------------------------------
-- Unload and housekeeping
-- ---------------------------------------------------------------------------------------------
do
	local env = newEnv()
	env.installScript()
	env.unit(10, "APC One")
	Olympus.transportUnload(10, "h1")
	check("unload succeeds", result("h1").success == true and env.calls[1][1] == "unload" and env.calls[1][2] == "APC One")

	env.installScript({ unload = function() return false, "you must come to a stop on the ground before unloading" end })
	Olympus.transportUnload(10, "h2")
	check("unload refusal reported", result("h2").code == "refused" and contains(result("h2").message, "stop on the ground"))

	-- results of different requests do not overwrite each other
	check("results kept per request", result("h1").code == "ok" and result("h2").code == "refused")

	-- no request hash: nothing is stored and nothing fails
	local before = 0
	for _ in pairs(Olympus.executionResults) do before = before + 1 end
	Olympus.transportUnload(10, nil)
	local after = 0
	for _ in pairs(Olympus.executionResults) do after = after + 1 end
	check("no hash, no stored result", before == after)

	-- results only contain what the C++ side can convert to JSON (numbers, booleans, strings, tables)
	for _, key in ipairs({ "success", "code", "message" }) do
		local t = type(result("h2")[key])
		check("result field " .. key .. " is JSON friendly", t == "boolean" or t == "string")
	end
end

-- ---------------------------------------------------------------------------------------------
-- Contract with the real mission script: the bridge must accept it and understand its answers
-- ---------------------------------------------------------------------------------------------
do
	local env = newEnv()
	timer = { getTime = function() return 0 end, scheduleFunction = function() end }
	_G.env = { info = function() end, error = function() end, mission = { coalition = {} } }
	Unit = { getByName = function() return nil end }
	Group.Category = { GROUND = 2 }
	local chunk, err = loadfile(scriptDir .. "/../missionscripts/simpleTransport.lua")
	assert(chunk, err)
	chunk()
	local status = Olympus.getTransportScriptStatus()
	check("bridge accepts the real mission script", status.present == true and status.version == simpleTransport.apiVersion, status.message)
	local ok, message = simpleTransport.load("No such unit", "No such group")
	check("real script answers (false, reason) for an unknown unit", ok == false and type(message) == "string")
	ok, message = simpleTransport.unload("No such unit")
	check("real unload answers (false, reason) for an unknown unit", ok == false and type(message) == "string")
	env.unit(1, "Some unit")
	Olympus.transportUnload(1, "contract")
	check("bridge turns a real refusal into a result", result("contract").success == false and result("contract").code == "refused" and type(result("contract").message) == "string",
		result("contract") and result("contract").code)
	undefinedReads["mist"] = nil
end

do
	undefinedReads["simpleTransport"] = nil   -- the bridge reads it with rawget, so this should never be recorded anyway
	local names = {}
	for k in pairs(undefinedReads) do table.insert(names, k) end
	check("bridge never reads an undefined global", #names == 0, table.concat(names, ","))
end

print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
