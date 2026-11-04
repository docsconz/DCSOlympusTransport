# Mission scripts

`simpleTransport.lua` lets players and scripts load ground groups (infantry and mortars) into transports and unload them again. It runs inside a DCS mission and does not need Olympus. This folder is not loaded by Olympus (only `scripts/lua/backend` is).

## Add it to a mission

1. In the mission editor, add a trigger: type "Mission start", action "DO SCRIPT FILE", and pick `simpleTransport.lua`.
2. If the mission also uses MIST, load MIST first. The script works without it; MIST is only used to read a unit's skill.
3. Human players in an eligible transport (see `simpleTransport_review.md`) get an F10 menu "Transport" with Load group, Unload group and Check load status.

## Functions other scripts can call

All return `ok, message` (a true/false and a short sentence).

- `simpleTransport.canLoad(transportUnitName, groupName)`
- `simpleTransport.load(transportUnitName, groupName)` (a nil group name loads the nearest loadable group)
- `simpleTransport.unload(transportUnitName)`
- `simpleTransport.getLoadedGroupName(transportUnitName)` returns the group name or nil
- `simpleTransport.apiVersion` is 1

## Changing which unit types are transports

The type lists inside `simpleTransport.lua` are generated. Do not edit them by hand.

1. Add lines like `yes Mi-24P` or `no Trolley bus` to `simpleTransport_overrides.txt`.
2. Run `python3 scripts/lua/missionscripts/simpleTransport_generate_lists.py` from anywhere in the repository. It rewrites the generated section and `simpleTransport_review.md`.
3. When the review table is final, run it once with `--confirmed` to remove the PROVISIONAL mark.

## Tests

`simpleTransport_test.lua` runs the script against a fake DCS world. It needs a Lua 5.1 interpreter:

    lua5.1 scripts/lua/missionscripts/simpleTransport_test.lua

Passing these tests does not prove the script works in DCS.
