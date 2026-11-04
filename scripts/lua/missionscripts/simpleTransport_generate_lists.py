#!/usr/bin/env python3
"""
Generates the type-name allowlists used by simpleTransport.lua, and an owner review table.

Reads (relative to the repository root):
  databases/units/groundunitdatabase.json
  databases/units/helicopterdatabase.json
  databases/units/aircraftdatabase.json
and optionally an overrides file (default: simpleTransport_overrides.txt next to this script).

Writes:
  - the section of simpleTransport.lua between the GENERATED markers (rewritten in place)
  - simpleTransport_review.md (the review table for the owner)

Usage (from anywhere):
  python3 simpleTransport_generate_lists.py            # allowlists stay marked PROVISIONAL
  python3 simpleTransport_generate_lists.py --confirmed  # owner has reviewed: clear the PROVISIONAL mark

Overrides file format: one entry per line, "yes <DCS type name>" or "no <DCS type name>".
Blank lines and lines starting with # are ignored. An override always wins over the guesses below.

Rules (decisions recorded by the owner):
  - Passengers: every database entry of type "Infantry", plus the "2B11 mortar".
  - Ground transports: database types APC, Armoured Car, Tactical Vehicle and Unarmed, subject to the
    per-entry guesses below. Tanks, infantry and mortars are never transports.
  - Air transports: aircraft and helicopters that Olympus flags as transports. Olympus (see
    backend/core/src/helicopter.cpp and aircraft.cpp) flags a unit when ANY of its database loadouts has the
    role "Transport"; this script uses the same rule, minus the entries in AIR_GUESS_NO.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
LUA_FILE = os.path.join(HERE, "simpleTransport.lua")
REVIEW_FILE = os.path.join(HERE, "simpleTransport_review.md")
DEFAULT_OVERRIDES = os.path.join(HERE, "simpleTransport_overrides.txt")

BEGIN = "-- BEGIN GENERATED"
END = "-- END GENERATED"

PASSENGER_EXTRA = ["2B11 mortar"]

# ---------------------------------------------------------------------------------------------
# Best-guess decisions. True = can carry a ground group. These are GUESSES for the owner to confirm.
# ---------------------------------------------------------------------------------------------

# Every database entry of type "Unarmed" must have a line here (the script fails if one is missing,
# so new database entries are noticed).
UNARMED = {
    "ATMZ-5": (False, "Refueler truck; tank body, no troop space"),
    "ATZ-10": (False, "Refueler truck; tank body"),
    "ATZ-5": (False, "Refueler truck; tank body"),
    "ural_atz5_civil": (False, "Civilian refueler; tank body"),
    "GAZ-3307": (True, "Truck with cargo bay"),
    "GAZ-3308": (True, "Military truck, canvas-covered cargo bay"),
    "GAZ-66": (True, "Military truck, open cargo bay"),
    "gaz-66_civil": (True, "Civilian GAZ-66 truck"),
    "HEMTT TFFT": (False, "Fire truck"),
    "IKARUS Bus": (True, "Bus; carries people"),
    "LAZ Bus": (True, "Bus; carries people"),
    "LiAZ Bus": (True, "Bus; carries people"),
    "Trolley bus": (True, "Bus-type road vehicle; carries people (odd choice, easy to turn off)"),
    "KAMAZ Truck": (True, "Military cargo truck"),
    "kamaz_tent_civil": (True, "Civilian KAMAZ with tent cargo bay"),
    "M 818": (True, "Heavy utility cargo truck"),
    "M978 HEMTT Tanker": (False, "Fuel tanker"),
    "MAZ-6303": (True, "Military cargo truck"),
    "Predator GCS": (False, "Ground control station, not a transport"),
    "Predator TrojanSpirit": (False, "Satellite/data link equipment"),
    "SKP-11": (False, "Repair/comms vehicle with enclosed equipment body"),
    "Suidae": (False, "Joke unit (a pig); cannot carry anything"),
    "Tigr_233036": (True, "Light utility vehicle with seats"),
    "UAZ-469": (True, "Light utility vehicle with seats"),
    "Ural ATsP-6": (False, "Fire truck"),
    "Ural-375 PBU": (False, "Command vehicle with enclosed body"),
    "Ural-375": (True, "Military cargo truck"),
    "Ural-4320 APA-5D": (False, "Airfield ground-power unit on a Ural chassis; equipment body"),
    "Ural-4320-31": (True, "Military cargo truck"),
    "Ural-4320T": (True, "Military cargo truck"),
    "ural_4230_civil_b": (True, "Civilian Ural-4320 truck"),
    "ural_4230_civil_t": (True, "Civilian Ural-4320T truck"),
    "VAZ Car": (True, "Civilian car; carries a few people"),
    "ZIL-131 KUNG": (False, "KUNG shelter body (repair/comms), not a troop bay"),
    "ZIL-4331": (True, "Military truck"),
    "ZiL-131 APA-80": (False, "Airfield ground-power unit; equipment body"),
    "zil-131_civil": (True, "Civilian ZiL-131 truck"),
    "KrAZ6322": (True, "Military cargo truck"),
    "tacr2a": (False, "Fire and rescue vehicle"),
    "LARC-V": (True, "Amphibious cargo vehicle"),
    "generator_5i57": (False, "Diesel power station (equipment)"),
    "AA8": (False, "Fire truck"),
    "TZ-22_KrAZ": (False, "Refueler tractor, cab only, no troop space"),
    "ATZ-60_Maz": (False, "Refueler tractor, cab only, no troop space"),
    "S_75_ZIL": (False, "Missile tractor, cab only, no troop space"),
    "ZIL-135": (False, "Heavy 8x8 chassis (missile carrier); no description in database, unsure"),
    "Bedford_MWD": (True, "WWII military cargo truck"),
    "Land_Rover_101_FC": (True, "Light utility truck"),
    "Land_Rover_109_S3": (True, "Light utility vehicle"),
    "Blitz_36-6700A": (True, "WWII military cargo truck"),
    "Kubelwagen_82": (True, "WWII light utility vehicle"),
    "Sd_Kfz_2": (True, "Kettenrad light tracked utility vehicle; carries a small crew/passengers"),
    "Sd_Kfz_7": (True, "Half-track artillery tractor with a crew seating area"),
    "Horch_901_typ_40_kfz_21": (True, "WWII staff car; carries personnel"),
    "Allies_Director": (False, "Rangefinder equipment"),
    "CCKW_353": (True, "WWII 2.5-ton cargo truck"),
    "Willys_MB": (True, "WWII jeep"),
    "M30_CC": (True, "Tracked cargo carrier; doubtful (built for ammo), easy to turn off"),
    "M4_Tractor": (False, "Artillery tractor, mainly a tow vehicle; doubtful"),
    "TugHarlan_drivable": (False, "Airfield tug"),
    "B600_drivable": (False, "Airfield support vehicle"),
    "MJ-1_drivable": (False, "Airfield support vehicle"),
    "P20_drivable": (False, "Airfield support vehicle"),
    "r11_volvo_drivable": (False, "Airfield refueler"),
    "Type_94_Truck": (True, "Military cargo truck"),
    "Type_98_So_Da": (True, "Tracked armoured transport (labelled APC in the database label)"),
    "GD-20": (False, "Airfield lift truck"),
    "CHAP_M1083": (True, "M1083 medium tactical truck with cargo bay"),
    "GPS_Spoofer_Blue": (False, "Electronic warfare equipment"),
    "GPS_Spoofer_Red": (False, "Electronic warfare equipment"),
    "rsbn_beacon": (False, "Navigation beacon vehicle"),
    "prmg_gp_beacon": (False, "Navigation beacon vehicle"),
    "prmg_loc_beacon": (False, "Navigation beacon vehicle"),
}

# Entries of type APC / Armoured Car / Tactical Vehicle that are NOT a clear "yes". All other entries of
# those types default to yes (they are personnel carriers or utility vehicles).
DOUBTFUL = {
    # APC
    "CHAP_BMPT": (False, "Tank-support fighting vehicle with a crew only; no troop compartment"),
    # Armoured Car (all four have a crew only)
    "Sd_Kfz_234_2_Puma": (False, "Armoured car with a crew only; no passenger space"),
    "Daimler_AC": (False, "Armoured car with a crew only; no passenger space"),
    "M8_Greyhound": (False, "Armoured car with a crew only; no passenger space"),
    "Tetrarch": (False, "Light tank, crew only"),
    # Tactical Vehicle
    "M1128 Stryker MGS": (False, "Gun system with a crew only; no troop compartment"),
    "CHAP_FV107": (False, "Scimitar reconnaissance vehicle, crew only"),
    "VAB_Mephisto": (True, "VAB-based ATGM carrier; the VAB carries troops, but this variant mainly carries missiles"),
    "HL_DSHK": (True, "Technical (pickup with gun); carries a few people in the bed"),
    "HL_KORD": (True, "Technical (pickup with gun); carries a few people in the bed"),
    "tt_DSHK": (True, "Pickup with gun; carries a few people in the bed"),
    "tt_KORD": (True, "Pickup with gun; carries a few people in the bed"),
    "BRDM-2": (True, "Scout car with a few passenger seats"),
    "Cobra": (True, "Otokar Cobra; carries a squad"),
    "M1045 HMMWV TOW": (True, "HMMWV with TOW launcher; seats a few people"),
    "M1043 HMMWV Armament": (True, "HMMWV with a mounted gun; seats a few people"),
}

# Aircraft/helicopters that Olympus flags as transport (role "Transport" in a loadout) but that cannot
# realistically carry a ground group.
AIR_GUESS_NO = {
    "OH58D": (False, "Two-seat scout helicopter; the database flags it as Transport only through armed-scout loadouts"),
    "MB-339A": (False, "Two-seat jet trainer; flagged through ferry loadouts"),
    "Christen Eagle II": (False, "Two-seat aerobatic aircraft"),
}

# Air entries the owner's earlier list named, but that the database does not flag as Transport.
AIR_NOT_FLAGGED_NOTE = {
    "Mi-24P": "Named in the owner's earlier list, but no Mi-24P loadout has the role Transport in the database, "
              "so Olympus does not flag it. Excluded; add 'yes Mi-24P' to the overrides file to include it.",
}

GROUND_TYPES = ["APC", "Armoured Car", "Tactical Vehicle", "Unarmed"]


def load(name):
    with open(os.path.join(REPO, "databases", "units", name), encoding="utf-8") as f:
        return json.load(f)


def read_overrides(path):
    result = {}
    if not os.path.exists(path):
        return result
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            match = re.match(r"^(yes|no)\s+(.+)$", line, re.IGNORECASE)
            if not match:
                sys.exit("overrides line %d is not 'yes <name>' or 'no <name>': %r" % (number, line))
            result[match.group(2).strip()] = match.group(1).lower() == "yes"
    return result


def lua_str(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--overrides", default=DEFAULT_OVERRIDES)
    parser.add_argument("--confirmed", action="store_true",
                        help="the owner has reviewed the table: write allowlistsProvisional = false")
    args = parser.parse_args()

    ground = load("groundunitdatabase.json")
    helis = load("helicopterdatabase.json")
    planes = load("aircraftdatabase.json")
    overrides = read_overrides(args.overrides)

    # ---- passengers
    passengers = sorted(n for n, v in ground.items() if v.get("type") == "Infantry")
    for extra in PASSENGER_EXTRA:
        if extra not in ground:
            sys.exit("passenger %r not found in the ground database" % extra)
        passengers.append(extra)
    passengers = sorted(set(passengers))

    # ---- ground transports
    missing = [n for n, v in ground.items() if v.get("type") == "Unarmed" and n not in UNARMED]
    if missing:
        sys.exit("Unarmed entries without a guess in UNARMED (add them): %s" % ", ".join(missing))
    stale = [n for n in list(UNARMED) + list(DOUBTFUL) if n not in ground]
    if stale:
        sys.exit("Guesses refer to names not in the ground database: %s" % ", ".join(stale))

    rows = []  # (name, label, db type, decision, reason, source)
    transports = {}  # name -> "ground"/"air"

    for name, entry in sorted(ground.items()):
        dbtype = entry.get("type")
        if dbtype not in GROUND_TYPES:
            continue
        if name in UNARMED:
            decision, reason = UNARMED[name]
            listed = True
        elif name in DOUBTFUL:
            decision, reason = DOUBTFUL[name]
            listed = True
        else:
            decision, reason, listed = True, "database type %s" % dbtype, False
        if name in overrides:
            decision = overrides[name]
            reason = "OVERRIDE from overrides file (guess was: %s)" % reason
            listed = True
        if decision:
            transports[name] = "ground"
        if listed:
            rows.append((name, entry.get("label", ""), dbtype, decision, reason, "ground"))

    # ---- air transports
    for dbname, db in (("helicopter", helis), ("aircraft", planes)):
        for name, entry in sorted(db.items()):
            flagged = any("Transport" in loadout.get("roles", []) for loadout in entry.get("loadouts", []))
            if not flagged and name not in AIR_NOT_FLAGGED_NOTE and name not in overrides:
                continue
            if flagged:
                decision, reason = AIR_GUESS_NO.get(name, (True, "Flagged as Transport by Olympus"))
            else:
                decision, reason = False, AIR_NOT_FLAGGED_NOTE.get(name, "Not flagged as Transport by Olympus")
            if name in overrides:
                decision = overrides[name]
                reason = "OVERRIDE from overrides file (guess was: %s)" % reason
            if decision:
                transports[name] = "air"
            rows.append((name, entry.get("label", ""), dbname, decision, reason, "air"))

    for name in overrides:
        if name not in ground and name not in helis and name not in planes:
            print("warning: override %r is not in any database; ignored" % name, file=sys.stderr)

    collisions = set(ground) & (set(helis) | set(planes))
    if collisions:
        sys.exit("type names exist in more than one database: %s" % sorted(collisions))

    # ---- Lua section
    lines = [BEGIN + " (do not edit by hand; regenerate with scripts/lua/missionscripts/simpleTransport_generate_lists.py) --",
             "-- Source: databases/units/*.json. Overrides file: simpleTransport_overrides.txt.",
             "-- While true, the lists below are the generator's best guesses and still need the owner's confirmation.",
             "simpleTransport.allowlistsProvisional = %s" % ("false" if args.confirmed else "true"),
             "",
             "-- Groups made only of these unit types can be loaded (infantry plus the 2B11 mortar).",
             "simpleTransport.passengerTypes = {"]
    lines += ["    [%s] = true," % lua_str(n) for n in passengers]
    lines += ["}", "",
              "-- Units of these types can act as transports. \"ground\" = ground vehicle, \"air\" = aircraft/helicopter.",
              "simpleTransport.transportTypes = {"]
    lines += ["    [%s] = %s," % (lua_str(n), lua_str(k)) for n, k in sorted(transports.items())]
    lines += ["}", END + " --"]
    generated = "\n".join(lines)

    with open(LUA_FILE, encoding="utf-8") as f:
        text = f.read()
    pattern = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END) + r" --", re.DOTALL)
    if not pattern.search(text):
        sys.exit("markers %r / %r not found in %s" % (BEGIN, END, LUA_FILE))
    text = pattern.sub(lambda _m: generated, text, count=1)
    with open(LUA_FILE, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

    # ---- review table
    yes_unarmed = sum(1 for r in rows if r[2] == "Unarmed" and r[3])
    no_unarmed = sum(1 for r in rows if r[2] == "Unarmed" and not r[3])
    out = ["# simpleTransport: allowlist review table", "",
           "Generated by `simpleTransport_generate_lists.py`. Every decision below is a best guess"
           + (" (confirmed by the owner)" if args.confirmed else " and PROVISIONAL until you confirm it") + ".",
           "To change a decision, add `yes <name>` or `no <name>` to `simpleTransport_overrides.txt` and rerun the generator.",
           "",
           "Unarmed entries: %d yes, %d no (total %d)." % (yes_unarmed, no_unarmed, yes_unarmed + no_unarmed),
           "Total transport types in the generated list: %d ground, %d air." % (
               sum(1 for k in transports.values() if k == "ground"), sum(1 for k in transports.values() if k == "air")),
           "Passenger types: %d." % len(passengers), ""]

    def table(title, selection):
        out.extend(["## " + title, "", "| Name (DCS type) | Label | Database type | Transport? | Reason |",
                    "|---|---|---|---|---|"])
        for name, label, dbtype, decision, reason, _kind in selection:
            out.append("| %s | %s | %s | %s | %s |" % (name, label, dbtype, "yes" if decision else "no", reason.replace("|", "/")))
        out.append("")

    table("Unarmed ground vehicles (all %d database entries)" % len(UNARMED),
          [r for r in rows if r[2] == "Unarmed"])
    table("Doubtful APC / Armoured Car / Tactical Vehicle entries (all other entries of these types are yes)",
          [r for r in rows if r[5] == "ground" and r[2] != "Unarmed"])
    table("Aircraft and helicopters (Olympus-flagged, plus mismatches with the owner's earlier list)",
          [r for r in rows if r[5] == "air"])
    out.extend(["## Passenger types", "", ", ".join(passengers), ""])
    with open(REVIEW_FILE, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))

    print("wrote %s and %s" % (os.path.relpath(LUA_FILE, REPO), os.path.relpath(REVIEW_FILE, REPO)))
    print("Unarmed: %d yes, %d no; transports: %d; passengers: %d" % (yes_unarmed, no_unarmed, len(transports), len(passengers)))


if __name__ == "__main__":
    main()
