-- TEMPORARY DIAGNOSTIC hook. Copy this file to
--   <Saved Games>\DCS.openbeta_server\Scripts\Hooks\OlympusTransportMissionProbe.lua
-- (the same folder as OlympusHook.lua) and restart DCS. It changes nothing; it only writes "TRANSPORT-PROBE" lines to dcs.log.
--
-- Question it answers: from DCS's hook environment, can code be run in the "mission" Lua state (where the simpleTransport
-- mission script lives), and can it see simpleTransport there? It also asks the "server" state, which is where Olympus runs.

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

local CHECK = "return tostring(type(simpleTransport)) .. ' api=' .. tostring(simpleTransport and simpleTransport.apiVersion)"
	.. " .. ' loadedGroupName(none)=' .. tostring(simpleTransport and simpleTransport.getLoadedGroupName and simpleTransport.getLoadedGroupName('none'))"

local callbacks = {}

function callbacks.onSimulationStart()
	probe.runs = 0
	probe.active = true
	probe.nextTime = DCS.getRealTime() + 20
	say("probe loaded and mission started")
end

function callbacks.onSimulationStop()
	probe.active = false
end

function callbacks.onSimulationFrame()
	if not probe.active or probe.runs >= 6 then
		return
	end
	local now = DCS.getRealTime()
	if now < probe.nextTime then
		return
	end
	probe.runs = probe.runs + 1
	probe.nextTime = now + 20
	say("--- run " .. probe.runs)
	for _, stateName in ipairs({ "mission", "server" }) do
		ask(stateName, CHECK)
	end
end

DCS.setUserCallbacks(callbacks)
say("probe file loaded")
