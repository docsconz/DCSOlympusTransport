-- TEMPORARY DIAGNOSTIC hook, version 3. Copy this file to
--   <Saved Games>\DCS.openbeta_server\Scripts\Hooks\OlympusTransportMissionProbe.lua
-- (replacing the previous version) and restart DCS. It only reads and writes "TRANSPORT-PROBE" lines to dcs.log.
--
-- Results so far: Olympus's Lua ("server" state) and net.dostring_in("mission") can not see the simpleTransport global,
-- and trigger.action.doScript does not exist in the server state. This version lists what each state does offer
-- (global names, trigger functions, file access), so that a way to pass messages between Olympus and the mission script
-- can be chosen from facts. It changes nothing in the mission.

local probe = { runs = 0, nextTime = nil, active = false }

local function say(text)
	log.write("TRANSPORT-PROBE", log.INFO, tostring(text))
end

-- Writes long text as several log lines
local function sayLong(prefix, text)
	local size = 1500
	local i, part = 1, 1
	while i <= #text do
		say(prefix .. " [" .. part .. "] " .. string.sub(text, i, i + size - 1))
		i = i + size
		part = part + 1
	end
end

local INSPECT = [[
local function keys(t)
	local r = {}
	if type(t) == 'table' then
		for k in pairs(t) do r[#r + 1] = tostring(k) end
		table.sort(r)
	end
	return table.concat(r, ',')
end
local out = {}
out[#out + 1] = 'simpleTransport=' .. type(simpleTransport) .. ' mist=' .. type(mist) .. ' Olympus=' .. type(Olympus)
out[#out + 1] = 'io=' .. type(io) .. ' lfs=' .. type(lfs) .. ' os=' .. type(os) .. ' package=' .. type(package) .. ' dofile=' .. type(dofile) .. ' loadfile=' .. type(loadfile) .. ' loadstring=' .. type(loadstring) .. ' require=' .. type(require) .. ' net=' .. type(net)
out[#out + 1] = 'trigger.action: ' .. keys(trigger and trigger.action)
out[#out + 1] = 'trigger.misc: ' .. keys(trigger and trigger.misc)
out[#out + 1] = 'world: ' .. keys(world)
out[#out + 1] = 'globals: ' .. keys(_G)
return table.concat(out, '\n')
]]

local function inspect(stateName)
	local results = { pcall(net.dostring_in, stateName, INSPECT) }
	say("=== state " .. stateName .. ": pcall=" .. tostring(results[1]) .. " flag=" .. tostring(results[3]))
	local text = tostring(results[2])
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		sayLong(stateName, line)
	end
end

local callbacks = {}

function callbacks.onSimulationStart()
	probe.runs = 0
	probe.active = true
	probe.nextTime = DCS.getRealTime() + 45 -- the mission script needs a while to load
	say("probe v3: mission started")
end

function callbacks.onSimulationStop()
	probe.active = false
end

function callbacks.onSimulationFrame()
	if not probe.active or probe.runs >= 1 then
		return
	end
	if DCS.getRealTime() < probe.nextTime then
		return
	end
	probe.runs = probe.runs + 1
	say("--- inspection")
	inspect("mission")
	inspect("server")
	say("--- done")
end

DCS.setUserCallbacks(callbacks)
say("probe v3 file loaded")
