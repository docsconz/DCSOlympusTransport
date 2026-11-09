-- TEMPORARY DIAGNOSTIC hook, version 2. Copy this file to
--   <Saved Games>\DCS.openbeta_server\Scripts\Hooks\OlympusTransportMissionProbe.lua
-- (replacing version 1) and restart DCS. It writes "TRANSPORT-PROBE" and "PROBE-MISSIONSIDE" lines to dcs.log.
--
-- Version 1 showed that neither the "server" state (where Olympus runs) nor net.dostring_in("mission") can see the
-- simpleTransport global. This version tests another way in: trigger.action.doScript, run from the server state like
-- Olympus can. It checks (1) does code run that way see simpleTransport, and (2) can it hand back a number (user flag)
-- and a text (a temporary map mark, removed again) that the server state can read.
-- A short-lived map mark "OLY|hello world 123" may flash on the F10 map during the test.

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

-- Code that doScript runs inside the mission
local MISSION_SIDE = [[
local ok, value = pcall(function() return simpleTransport.getLoadedGroupName('none') end)
env.info('PROBE-MISSIONSIDE type=' .. type(simpleTransport) .. ' api=' .. tostring(simpleTransport and simpleTransport.apiVersion) .. ' call=' .. tostring(ok) .. ',' .. tostring(value))
trigger.action.setUserFlag('OLY_PROBE', 7)
trigger.action.markToAll(98765, 'OLY|hello world 123', {x = 0, y = 0, z = 0}, true)
]]

-- Code that runs in the server state and reports what the mission side left behind
local SERVER_READ = [[
local out = {}
out[#out + 1] = 'flag=' .. tostring(trigger.misc.getUserFlag('OLY_PROBE'))
local okm, marks = pcall(function() return world.getMarkPanels() end)
if okm and type(marks) == 'table' then
	local count = 0
	for _, m in pairs(marks) do
		count = count + 1
		if m.idx == 98765 then out[#out + 1] = 'mark=' .. tostring(m.text) end
	end
	out[#out + 1] = 'markCount=' .. count
else
	out[#out + 1] = 'getMarkPanels failed: ' .. tostring(marks)
end
return table.concat(out, ' ')
]]

local REMOVE = "trigger.action.removeMark(98765) trigger.action.setUserFlag('OLY_PROBE', 0)"

local function doScriptFromServer(code)
	ask("server", "trigger.action.doScript(" .. string.format("%q", code) .. ") return 'doScript called'")
end

local callbacks = {}

function callbacks.onSimulationStart()
	probe.runs = 0
	probe.active = true
	probe.nextTime = DCS.getRealTime() + 60 -- the mission script needs a while to load
	say("probe v2: mission started")
end

function callbacks.onSimulationStop()
	probe.active = false
end

function callbacks.onSimulationFrame()
	if not probe.active or probe.runs >= 5 then
		return
	end
	local now = DCS.getRealTime()
	if now < probe.nextTime then
		return
	end
	probe.runs = probe.runs + 1
	probe.nextTime = now + 20
	say("--- run " .. probe.runs)

	ask("mission", "return tostring(type(simpleTransport))")
	if probe.runs == 1 then
		doScriptFromServer(MISSION_SIDE)
	else
		ask("server", SERVER_READ)
	end
	if probe.runs == 5 then
		doScriptFromServer(REMOVE)
		say("--- done")
	end
end

DCS.setUserCallbacks(callbacks)
say("probe v2 file loaded")
