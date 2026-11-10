-- TEMPORARY DIAGNOSTIC hook, version 7. Copy this file to
--   <Saved Games>\DCS.openbeta_server\Scripts\Hooks\OlympusTransportMissionProbe.lua
-- (replacing the previous version) and restart DCS. It writes "TRANSPORT-PROBE" lines to dcs.log; code that runs
-- inside the mission also writes "PROBE-MISSIONSIDE" lines.
--
-- Probe v6 showed that a user flag and a neutral map mark written in the mission can be read from the server state
-- (where Olympus's Lua runs). This version tests the opposite direction, which would let Olympus send commands to the
-- mission script without any change to the Olympus DLL:
--   1. The hook starts a small poller inside the mission (with a_do_script). It looks for a flag and a map mark.
--   2. The server state writes that flag and a mark with a command text.
--   3. The poller reports what it saw, removes the mark and answers with another flag, which the server state reads.
-- A mark "OLYPROBECMD|load|APC 1|Infantry 1" may exist on the map for a few seconds.

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

-- Runs inside the mission scripting environment: installs the poller
local MISSION_SIDE = [=[
local polls = 0
local function poll(_, time)
	polls = polls + 1
	local seen = {}
	local flag = trigger.misc.getUserFlag('OLYPROBE_CMD')
	local ok, marks = pcall(function() return world.getMarkPanels() end)
	if ok and type(marks) == 'table' then
		for _, m in pairs(marks) do
			if type(m.text) == 'string' and string.sub(m.text, 1, 12) == 'OLYPROBECMD|' then
				seen[#seen + 1] = 'mark ' .. tostring(m.idx) .. ' "' .. m.text .. '"'
				trigger.action.removeMark(m.idx)
			end
		end
	else
		env.info('PROBE-MISSIONSIDE getMarkPanels failed: ' .. tostring(marks))
	end
	if flag ~= 0 or #seen > 0 then
		env.info('PROBE-MISSIONSIDE poll ' .. polls .. ': flag=' .. tostring(flag) .. ', ' .. (#seen > 0 and table.concat(seen, '; ') or 'no mark'))
		trigger.action.setUserFlag('OLYPROBE_CMD', 0)
		trigger.action.setUserFlag('OLYPROBE_ACK', 99)
	end
	if polls >= 60 then return nil end
	return time + 2
end
timer.scheduleFunction(poll, nil, timer.getTime() + 2)
env.info('PROBE-MISSIONSIDE poller installed; simpleTransport is ' .. type(simpleTransport))
]=]

-- Runs in the server state: sends the command
local SERVER_SEND = [=[
trigger.action.setUserFlag('OLYPROBE_CMD', 5)
local ok, err = pcall(trigger.action.markToCoalition, 98770, 'OLYPROBECMD|load|APC 1|Infantry 1', {x = 0, y = 0, z = 0}, 0, true)
return 'command written, markToCoalition ok=' .. tostring(ok) .. ' ' .. tostring(err)
]=]

-- Runs in the server state: reads the answer
local SERVER_READ = [=[
local count = 0
local ok, marks = pcall(function() return world.getMarkPanels() end)
if ok and type(marks) == 'table' then
	for _, m in pairs(marks) do
		if m.idx == 98770 then count = count + 1 end
	end
end
return 'ack flag=' .. tostring(trigger.misc.getUserFlag('OLYPROBE_ACK')) .. ', command flag=' .. tostring(trigger.misc.getUserFlag('OLYPROBE_CMD')) .. ', command mark still present: ' .. tostring(count > 0)
]=]

local CLEANUP = "trigger.action.removeMark(98770) trigger.action.setUserFlag('OLYPROBE_CMD', 0) trigger.action.setUserFlag('OLYPROBE_ACK', 0)"

local callbacks = {}

function callbacks.onSimulationStart()
	probe.runs = 0
	probe.active = true
	probe.nextTime = DCS.getRealTime() + 60
	say("probe v7: mission started")
end

function callbacks.onSimulationStop()
	probe.active = false
end

function callbacks.onSimulationFrame()
	if not probe.active or probe.runs >= 5 then
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
	elseif probe.runs == 2 then
		ask("server", SERVER_SEND)
	else
		ask("server", SERVER_READ)
	end
	if probe.runs == 5 then
		ask("mission", "a_do_script(" .. string.format("%q", CLEANUP) .. ")")
		say("--- done")
	end
end

DCS.setUserCallbacks(callbacks)
say("probe v7 file loaded")
