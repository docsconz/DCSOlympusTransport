-- TEMPORARY DIAGNOSTIC hook, version 6. Copy this file to
--   <Saved Games>\DCS.openbeta_server\Scripts\Hooks\OlympusTransportMissionProbe.lua
-- (replacing the previous version) and restart DCS. It writes "TRANSPORT-PROBE" lines to dcs.log; code that runs
-- inside the mission also writes "PROBE-MISSIONSIDE" lines.
--
-- What the previous probes showed: the hook can run code inside the mission with a_do_script, but the mission and
-- Olympus's Lua share no objects at all (not even the string or math tables), so Olympus can not call the mission
-- script directly. What is left is passing messages through things the DCS engine itself holds for both sides.
-- This version tests two of those, with results going from the mission to Olympus's Lua ("server" state):
--   - a user flag with a text name (carries a number)
--   - a map mark (carries a text), created for coalition 0 (neutral), which no player should be on, so that players
--     are unlikely to see it. A mark with the text "OLYPROBE|unit|group" may exist on the map during the test.

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
local MISSION_SIDE = [=[
env.info('PROBE-MISSIONSIDE start: simpleTransport is ' .. type(simpleTransport) .. ', api version ' .. tostring(simpleTransport and simpleTransport.apiVersion))
trigger.action.setUserFlag('OLYPROBE_RESULT_abc123', 42)
env.info('PROBE-MISSIONSIDE flag set')
local ok, err = pcall(trigger.action.markToCoalition, 98765, 'OLYPROBE|unit|group', {x = 0, y = 0, z = 0}, 0, true)
env.info('PROBE-MISSIONSIDE markToCoalition(neutral) ok=' .. tostring(ok) .. ' ' .. tostring(err))
]=]

-- Runs in the server state (where Olympus's Lua runs)
local SERVER_SIDE = [=[
local out = {}
out[#out + 1] = 'flag=' .. tostring(trigger.misc.getUserFlag('OLYPROBE_RESULT_abc123'))
local okm, marks = pcall(function() return world.getMarkPanels() end)
if okm and type(marks) == 'table' then
	local count = 0
	for _, m in pairs(marks) do
		count = count + 1
		if m.idx == 98765 then
			local fields = {}
			for k, v in pairs(m) do
				if type(v) ~= 'table' then fields[#fields + 1] = tostring(k) .. '=' .. tostring(v) end
			end
			table.sort(fields)
			out[#out + 1] = 'MARK FOUND: ' .. table.concat(fields, ', ')
		end
	end
	out[#out + 1] = 'markCount=' .. count
else
	out[#out + 1] = 'getMarkPanels failed: ' .. tostring(marks)
end
return table.concat(out, ' | ')
]=]

local CLEANUP = "trigger.action.removeMark(98765) trigger.action.setUserFlag('OLYPROBE_RESULT_abc123', 0)"

local callbacks = {}

function callbacks.onSimulationStart()
	probe.runs = 0
	probe.active = true
	probe.nextTime = DCS.getRealTime() + 60
	say("probe v6: mission started")
end

function callbacks.onSimulationStop()
	probe.active = false
end

function callbacks.onSimulationFrame()
	if not probe.active or probe.runs >= 4 then
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
	if probe.runs == 4 then
		ask("mission", "a_do_script(" .. string.format("%q", CLEANUP) .. ")")
		say("--- done")
	end
end

DCS.setUserCallbacks(callbacks)
say("probe v6 file loaded")
