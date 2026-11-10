-- TEMPORARY DIAGNOSTIC hook, version 5. Copy this file to
--   <Saved Games>\DCS.openbeta_server\Scripts\Hooks\OlympusTransportMissionProbe.lua
-- (replacing the previous version) and restart DCS. It writes "TRANSPORT-PROBE" lines to dcs.log; code that runs
-- inside the mission also writes "PROBE-MISSIONSIDE" lines. It registers one harmless do-nothing event handler.
--
-- What the previous probes showed: the "mission" state of net.dostring_in is the trigger-action state (it has
-- a_do_script, a_set_flag and so on), not the place where mission scripts keep their variables.
-- The idea tested here:
--   1. Run code inside the mission with a_do_script (what a "DO SCRIPT" trigger does), from the hook.
--   2. That code registers an event handler that carries a small API table.
--   3. Olympus's Lua (the "server" state) looks through world.eventHandlers, finds the handler, and calls the API.
-- If step 3 works, Olympus can call functions that live in the mission, and get their return values, with no mailbox.

local probe = { runs = 0, nextTime = nil, active = false }

local function say(text)
	log.write("TRANSPORT-PROBE", log.INFO, tostring(text))
end

local function ask(stateName, code)
	local results = { pcall(net.dostring_in, stateName, code) }
	local parts = {}
	for i = 1, #results do
		parts[i] = tostring(results[i])
	end
	say("net.dostring_in(" .. stateName .. ") returned: " .. table.concat(parts, " | "))
end

-- Shared objects that the mission side will try to leave an API table on. If the same object is visible from both
-- environments, the server state can read it.
local OBJECTS = [[{ env = env, world = world, trigger = trigger, ['trigger.misc'] = trigger and trigger.misc, ['trigger.action'] = trigger and trigger.action, coalition = coalition, timer = timer, string = string, math = math, table = table, Unit = Unit, Group = Group, land = land, missionCommands = missionCommands, Airbase = Airbase, StaticObject = StaticObject }]]

-- Runs inside the mission scripting environment
local MISSION_SIDE = [=[
env.info('PROBE-MISSIONSIDE start: simpleTransport is ' .. type(simpleTransport) .. ', api version ' .. tostring(simpleTransport and simpleTransport.apiVersion))
local api = { hello = function(name) return 'hello ' .. tostring(name) .. ' from the mission, simpleTransport is ' .. type(simpleTransport) .. ', api ' .. tostring(simpleTransport and simpleTransport.apiVersion) end }
local handler = { onEvent = function(self, event) end, probeApi = api }
world.addEventHandler(handler)
local placed = {}
for name, target in pairs(]=] .. OBJECTS .. [=[) do
	if type(target) == 'table' then
		target.__oly_probe = api
		placed[#placed + 1] = name
	end
end
table.sort(placed)
env.info('PROBE-MISSIONSIDE handler registered; api left on: ' .. table.concat(placed, ','))
]=]

-- Runs in the server state (where Olympus's Lua runs)
local SERVER_SIDE = [=[
local out = {}
local function fields(t)
	local r = {}
	for k, v in pairs(t) do
		if #r < 12 then r[#r + 1] = tostring(k) .. ':' .. type(v) end
	end
	table.sort(r)
	return table.concat(r, ',')
end
local handlers = world.eventHandlers
local count = 0
if type(handlers) == 'table' then
	for key, value in pairs(handlers) do
		count = count + 1
		out[#out + 1] = 'entry ' .. count .. ' key{' .. (type(key) == 'table' and fields(key) or type(key)) .. '} value{' .. (type(value) == 'table' and fields(value) or type(value)) .. '}'
	end
end
local found = {}
for name, target in pairs(]=] .. OBJECTS .. [=[) do
	if type(target) == 'table' and target.__oly_probe ~= nil then
		local callOk, result = pcall(target.__oly_probe.hello, 'Olympus')
		found[#found + 1] = name .. ' -> ' .. tostring(callOk) .. ': ' .. tostring(result)
	end
end
out[#out + 1] = 'rendezvous objects carrying the api: ' .. (#found > 0 and table.concat(found, ' ; ') or 'NONE')
return table.concat(out, ' | ')
]=]

local callbacks = {}

function callbacks.onSimulationStart()
	probe.runs = 0
	probe.active = true
	probe.nextTime = DCS.getRealTime() + 60 -- the mission script needs a while to load
	say("probe v5: mission started")
end

function callbacks.onSimulationStop()
	probe.active = false
end

function callbacks.onSimulationFrame()
	if not probe.active or probe.runs >= 3 then
		return
	end
	if DCS.getRealTime() < probe.nextTime then
		return
	end
	probe.runs = probe.runs + 1
	probe.nextTime = DCS.getRealTime() + 20
	say("--- run " .. probe.runs)
	if probe.runs == 1 then
		ask("mission", "a_do_script(" .. string.format("%q", MISSION_SIDE) .. ")")
	else
		ask("server", SERVER_SIDE)
	end
	if probe.runs == 3 then
		say("--- done")
	end
end

DCS.setUserCallbacks(callbacks)
say("probe v5 file loaded")
