/* Rules and helpers for loading ground groups into transports with the simpleTransport mission script.
 * The mission script has the final say: these checks only decide what the map offers and give quick feedback. */
import type { Unit } from "./unit";
import { getApp } from "../olympusapp";
import { TRANSPORT_PASSENGER_TYPES, TRANSPORT_TRANSPORT_TYPES } from "./transportlists";

/* Must match MAX_PICKUP_DISTANCE in simpleTransport.lua (meters, from the transport to the nearest unit of the group) */
export const TRANSPORT_LOAD_RANGE = 50;

/* A transport that is faster than this (m/s) can not unload. Same value the built-in disembark action uses */
const TRANSPORT_UNLOAD_MAX_SPEED = 2;

/* Does the unit type appear in the list of transports? */
export function isTransportType(unit: Unit) {
  return TRANSPORT_TRANSPORT_TYPES[unit.getName()] !== undefined;
}

/* Living members of the group of a unit, including the unit itself */
export function getGroupUnits(unit: Unit): Unit[] {
  const group = unit.getGroup();
  if (group === null) return unit.getAlive() ? [unit] : [];
  return group.getMembers().filter((member: Unit) => member.getAlive());
}

/* The group that the current selection would load, or null when the selection is not exactly one group of passengers.
 * Selecting units of more than one group disables loading. */
export function getSelectedPassengerGroup(selectedUnits: Unit[]): Unit[] | null {
  if (selectedUnits.length === 0) return null;
  const groupName = selectedUnits[0].getGroupName();
  if (groupName === "" || !selectedUnits.every((unit) => unit.getGroupName() === groupName)) return null;

  const groupUnits = getGroupUnits(selectedUnits[0]);
  if (groupUnits.length === 0) return null;
  if (!groupUnits.every((unit) => TRANSPORT_PASSENGER_TYPES[unit.getName()] === true)) return null;
  return groupUnits;
}

/* Why the group can not be loaded into the transport right now, or null if it can. Short text, shown to the user */
export function getLoadRefusal(transport: Unit, groupUnits: Unit[]): string | null {
  if (!isTransportType(transport)) return null; // Not a transport at all: the caller handles it as an ordinary unit
  if (transport.getHuman()) return "The transport is controlled by a player";
  if (groupUnits.some((unit) => unit.getHuman())) return "The group is controlled by a player";
  if (!transport.getAlive()) return "The transport is destroyed";
  if (transport.getLoadedGroupName() !== "") return "The transport is already carrying a group";
  if (transport.getCoalition() !== groupUnits[0].getCoalition()) return "The group and the transport are on different sides";
  if (transport.getAirborne()) return "The transport is in the air";

  const transportPosition = transport.getPosition();
  const distance = Math.min(...groupUnits.map((unit) => unit.getPosition().distanceTo(transportPosition)));
  if (distance > TRANSPORT_LOAD_RANGE) return `Too far: ${Math.round(distance)} m, the limit is ${TRANSPORT_LOAD_RANGE} m`;
  return null;
}

/* Why the transport can not unload right now, or null if it can */
export function getUnloadRefusal(transport: Unit): string | null {
  if (transport.getLoadedGroupName() === "") return "The transport is not carrying a group";
  if (transport.getHuman()) return "The transport is controlled by a player";
  if (transport.getAirborne()) return "The transport is in the air";
  if (transport.getSpeed() > TRANSPORT_UNLOAD_MAX_SPEED) return "The transport is moving";
  return null;
}

/* Shortens a group name so it fits on the unit badge */
export function shortenGroupName(name: string, maxLength: number = 10) {
  return name.length > maxLength ? name.substring(0, maxLength - 1) + "…" : name;
}

/* The bridge answers with a result code. Anything other than "ok" is shown to the user. */
const SCRIPT_PROBLEM_TEXT: { [key: string]: string } = {
  scriptMissing: "The simpleTransport script is not loaded in this mission, so groups can not be loaded or unloaded",
  scriptVersion: "The simpleTransport script in this mission is too old for this version of Olympus",
};

/* Waits for the result of a transport command and tells the user if it did not work.
 * The DCS side stores the result under the command hash; it is read the same way as "command executed". */
export function watchTransportCommand(commandHash: string, onSuccess: () => void = () => {}) {
  if (commandHash === undefined || commandHash === null) return;

  let attempts = 0;
  let executedAttempts = 0;
  const timer = window.setInterval(() => {
    attempts++;
    if (attempts > 20) {
      window.clearInterval(timer);
      getApp().addInfoMessage("No answer from DCS for the transport command");
      return;
    }
    getApp()
      .getServerManager()
      .isCommandExecuted((res: any) => {
        if (!res.commandExecuted) return;

        /* The result may arrive a moment after the command is reported as executed: wait a few more polls for it */
        const result = res.commandResult;
        if (result === undefined || result === null) {
          if (++executedAttempts > 6) window.clearInterval(timer);
          return;
        }

        window.clearInterval(timer);
        if (result.success === true) onSuccess();
        else getApp().addInfoMessage(SCRIPT_PROBLEM_TEXT[result.code] ?? result.message ?? "The transport command failed");
      }, commandHash);
  }, 500);
}
