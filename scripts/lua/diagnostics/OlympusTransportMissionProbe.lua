-- TEMPORARY DIAGNOSTIC hook, version 4. Copy this file to
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

-- Runs inside the mission scripting environment
local MISSION_SIDE = [[
env.info('PROBE-MISSIONSIDE start: simpleTransport is ' .. type(simpleTransport) .. ', api version ' .. tostring(simpleTransport and simpleTransport.apiVersion))
local api = { hello = function(name) return 'hello ' .. tostring(name) .. ' from the mission, simpleTransport is ' .. type(simpleTransport) end }
local handler = { onEvent = function(self, event) end, probeApi = api }
world.addEventHandler(handler)
env.info('PROBE-MISSIONSIDE handler registered')
]]

-- Runs in the server state (where Olympus's Lua runs)
local SERVER_SIDE = [[
local out = {}
local handlers = world.eventHandlers
out[#out + 1] = 'world.eventHandlers is a ' .. type(handlers)
local count, found = 0, nil
if type(handlers) == 'table' then
	for key, value in pairs(handlers) do
		count = count + 1
		if count <= 3 then out[#out + 1] = 'entry ' .. count .. ': key ' .. type(key) .. ', value ' .. type(value) end
		local candidates = { key, value }
		for _, candidate in ipairs(candidates) do
			if type(candidate) == 'table' and candidate.probeApi ~= nil then found = candidate end
		end
	end
end
out[#out + 1] = 'handlers counted: ' .. count
if found then
	out[#out + 1] = 'FOUND the probe handler'
	local ok, result = pcall(found.probeApi.hello, 'Olympus')
	out[#out + 1] = 'call worked: ' .. tostring(ok) .. ', returned: ' .. tostring(result)
else
	out[#out + 1] = 'probe handler NOT found'
end
return table.concat(out, ' | ')
]]

local callbacks = {}

function callbacks.onSimulationStart()
	probe.runs = 0
	probe.active = true
	probe.nextTime = DCS.getRealTime() + 60 -- the mission script needs a while to load
	say("probe v4: mission started")
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
say("probe v4 file loaded")
