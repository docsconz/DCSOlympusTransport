-- OlympusTransport.lua
-- Bridge between Olympus and the simpleTransport mission script (scripts/lua/missionscripts/simpleTransport.lua),
-- which loads ground groups into transports and unloads them again.
--
-- The mission script lives in the mission and works without Olympus. This file only calls its API (after checking
-- that the script is there and recent enough) and reports what happened. It is loaded after OlympusCommand.lua,
-- in the same Lua environment, and uses the global "Olympus" table created there.
--
-- Result reporting: every function takes the request hash of the command as its last argument and stores
-- Olympus.executionResults[requestHash] = { success = <boolean>, code = <string>, message = <string> }.
-- Codes: "ok", "refused" (the script said no, message has the reason), "scriptMissing", "scriptVersion",
-- "unitNotFound", "groupNotFound", "humanControlled", "error".
-- Note that a group that is loaded is destroyed and a group that is unloaded is respawned, so its units get new IDs.

-- Lowest simpleTransport.apiVersion this bridge works with
Olympus.transportMinApiVersion = 1

-- Returns the simpleTransport table if the mission has it, otherwise nil
function Olympus.getTransportScript()
	local script = rawget(_G, "simpleTransport")
	if type(script) == "table" then
		return script
	end
	return nil
end

-- Checks that the mission script is present and usable. Returns a table:
-- { present = <boolean>, version = <number or nil>, code = "ok" | "scriptMissing" | "scriptVersion", message = <string> }
function Olympus.getTransportScriptStatus()
	local script = Olympus.getTransportScript()
	if script == nil then
		return { present = false, version = nil, code = "scriptMissing", message = "The simpleTransport script is not loaded in this mission" }
	end

	local version = script.apiVersion
	if type(version) ~= "number" or version < Olympus.transportMinApiVersion or type(script.load) ~= "function" or type(script.unload) ~= "function" then
		return { present = false, version = version, code = "scriptVersion",
			message = "The simpleTransport script in this mission is too old (API version " .. tostring(version) .. ", Olympus needs at least " .. tostring(Olympus.transportMinApiVersion) .. ")" }
	end

	return { present = true, version = version, code = "ok", message = "" }
end

-- Name of the group that the unit with the given DCS name has loaded, or an empty string if it carries none or the
-- mission has no (usable) simpleTransport script. Called for every unit when the units data is collected, so it must be cheap and never fail.
function Olympus.getLoadedGroupName(unitName)
	local script = Olympus.getTransportScript()
	if script == nil or type(script.getLoadedGroupName) ~= "function" then
		return ""
	end

	local called, name = pcall(script.getLoadedGroupName, unitName)
	if called and type(name) == "string" then
		return name
	end
	return ""
end

-- Is this unit controlled by a human? Olympus only loads and unloads AI-controlled units.
-- A unit counts as human if it has a player name (the same test Olympus uses for its isHuman data) or if DCS lists it
-- among the occupied player units. The second test is a safety net for vehicles that a player jumped into.
function Olympus.isHumanControlled(unit)
	if unit:getPlayerName() ~= nil then
		return true
	end

	local ID = unit:getID()
	for _, side in pairs(coalition.side) do
		for _, player in ipairs(coalition.getPlayers(side) or {}) do
			if player:isExist() and player:getID() == ID then
				return true
			end
		end
	end
	return false
end

-- Stores and logs the result of a transport command
function Olympus.reportTransportResult(requestHash, success, code, message)
	Olympus.log:info("Transport command: " .. tostring(code) .. " - " .. tostring(message))
	if requestHash ~= nil then
		Olympus.executionResults[requestHash] = { success = success, code = code, message = message }
	end
end

-- Finds the transport unit and runs the checks that are the same for loading and unloading. Returns the unit, or nil
-- after reporting the problem.
function Olympus.checkTransportUnit(transportID, requestHash)
	local status = Olympus.getTransportScriptStatus()
	if not status.present then
		Olympus.reportTransportResult(requestHash, false, status.code, status.message)
		return nil
	end

	local transport = Olympus.getUnitByID(transportID)
	if transport == nil or not transport:isExist() then
		Olympus.reportTransportResult(requestHash, false, "unitNotFound", "The transport unit does not exist")
		return nil
	end

	if Olympus.isHumanControlled(transport) then
		Olympus.reportTransportResult(requestHash, false, "humanControlled", "The transport is controlled by a player")
		return nil
	end

	return transport
end

-- Loads the group with the given name into the transport with the given Olympus unit ID
function Olympus.transportLoad(transportID, groupName, requestHash)
	Olympus.debug("Olympus.transportLoad " .. tostring(transportID) .. " " .. tostring(groupName), 2)

	local transport = Olympus.checkTransportUnit(transportID, requestHash)
	if transport == nil then
		return
	end

	local group = Group.getByName(groupName)
	if group == nil or not group:isExist() then
		Olympus.reportTransportResult(requestHash, false, "groupNotFound", "The group to load does not exist")
		return
	end

	for _, member in ipairs(group:getUnits() or {}) do
		if member:isExist() and Olympus.isHumanControlled(member) then
			Olympus.reportTransportResult(requestHash, false, "humanControlled", "The group is controlled by a player")
			return
		end
	end

	-- Protected call: a bug in the mission script must not break Olympus
	local called, success, message = pcall(Olympus.getTransportScript().load, transport:getName(), groupName)
	if not called then
		Olympus.reportTransportResult(requestHash, false, "error", "The simpleTransport script failed: " .. tostring(success))
	else
		Olympus.reportTransportResult(requestHash, success == true, success == true and "ok" or "refused", tostring(message))
	end
end

-- Unloads the group carried by the transport with the given Olympus unit ID
function Olympus.transportUnload(transportID, requestHash)
	Olympus.debug("Olympus.transportUnload " .. tostring(transportID), 2)

	local transport = Olympus.checkTransportUnit(transportID, requestHash)
	if transport == nil then
		return
	end

	local called, success, message = pcall(Olympus.getTransportScript().unload, transport:getName())
	if not called then
		Olympus.reportTransportResult(requestHash, false, "error", "The simpleTransport script failed: " .. tostring(success))
	else
		Olympus.reportTransportResult(requestHash, success == true, success == true and "ok" or "refused", tostring(message))
	end
end
