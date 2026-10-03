"""Build the modified Guandan mod from the original Workshop mod.

Reads original/3138177412.json (the unmodified Workshop file), injects the scripts in this folder,
adds a play area (a second hand zone) in front of every player's hand and the Deck Selector tool,
removes the Sort Hand Tools (sorting is done with on-screen buttons) and tidies the table.
Only the lines that change are rewritten, so the result diffs cleanly against the original.

Usage:  python build.py [extra output file ...]

The result is written to ../workshop/3138177412.json, and to every extra output file given,
each with a copy of the mod's icon (../workshop/3138177412.png) next to it.
To try it in the game, give a file in the Saves folder (Documents/My Games/Tabletop Simulator/Saves),
for example TS_Save_1.json: it then shows up under Games > Save & Load.
"""
import copy
import io
import json
import math
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORKSHOP_FILE = "3138177412.json"
SOURCE = os.path.join(HERE, "original", WORKSHOP_FILE)
OUTPUT = os.path.join(HERE, "..", "workshop", WORKSHOP_FILE)
SAVE_NAME = "Guandan 掼蛋（出牌区）"

# Play areas: a second hand zone per player, this far in front of the hand (towards the table center).
# They must come after the original hand zones in the save, so each player's hand stays hand zone 1.
PLAY_AREA_OFFSET = 5.0
PLAY_AREA_WIDTH = 12.0
PLAY_AREA_DEPTH = 3.0
PLAY_AREA_GUIDS = {"White": "9a7e01", "Green": "9a7e02", "Purple": "9a7e03", "Orange": "9a7e04"}

# The Pass tiles can be held in a hand, so they must stay out of the play areas:
# they are moved this far towards the table center.
PASS_TILE_SHIFT = 1.1

# The Sort Hand Tools are taken off the table: the Global script sorts hands, with on-screen buttons.
REMOVED_TOOLS = ["Sort Hand Tool LR", "Sort Hand Tool RL"]

# The tools left on the table sit in a row in its middle, the one place an ordinary play does not reach:
# played cards lie 6 or more from the center (4.3 for a second row), the row ends 3.4 from it.
# From left to right as seen by White; tools by Nickname, the die (it has none) by Name.
TOOL_ROW = ["Collect Cards", "Deck Selector", "Die_12"]
TOOL_PITCH = 2.4

# The Deck Selector tool: a copy of the Collect Cards tile, showing on each side the back of the deck it selects.
DECK_SELECTOR_GUID = "9a7e05"
DECK_SELECTOR_FACE_UP_DECK = "123"
DECK_SELECTOR_FACE_DOWN_DECK = "125"

# The piles in global.lua, where the decks also start:  [deck ID] = {x, y, z},
DECK_PILE = re.compile(r'^\t\[(\d+)\] = \{(-?[\d.]+), -?[\d.]+, (-?[\d.]+)\},$', re.MULTILINE)

# A line holding one string property:  <indent>"<key>": "<value>"[,]
STRING_PROPERTY = re.compile(r'^(\s*)"(\w+)": (".*")(,?)$')
# A position or turn line inside an object's Transform.
POSITION_PROPERTY = re.compile(r'^        "(posX|posZ|rotY)": (\S+),$')


def read(name):
    with io.open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read()


def tool_position(name):
    """Where a tool sits in the tool row:  (x, z)"""
    return round((TOOL_ROW.index(name) - (len(TOOL_ROW) - 1) / 2) * TOOL_PITCH, 4), 0.0


def play_areas(save):
    """The play area hand zones, derived from the hand zones already in the save."""
    areas = []
    for obj in save["ObjectStates"]:
        if obj["Name"] != "HandTrigger":
            continue
        area = copy.deepcopy(obj)
        area["GUID"] = PLAY_AREA_GUIDS[obj["FogColor"]]
        transform = area["Transform"]
        yaw = math.radians(transform["rotY"])
        forward = (math.sin(yaw), math.cos(yaw))
        # The hand zones face the table center; make sure the play area ends up on that side.
        if forward[0] * -transform["posX"] + forward[1] * -transform["posZ"] < 0:
            forward = (-forward[0], -forward[1])
        transform["posX"] = round(transform["posX"] + forward[0] * PLAY_AREA_OFFSET, 4)
        transform["posZ"] = round(transform["posZ"] + forward[1] * PLAY_AREA_OFFSET, 4)
        transform["scaleX"] = PLAY_AREA_WIDTH
        transform["scaleZ"] = PLAY_AREA_DEPTH
        areas.append(area)
    if len(areas) != 4:
        sys.exit("Expected 4 hand zones, found %d." % len(areas))
    return areas


def deck_selector(save):
    """The Deck Selector tool, derived from the Collect Cards tile and the two decks in the save."""
    backs = {}
    for obj in save["ObjectStates"]:
        if obj["Name"] == "Deck":
            for deck_id, deck in obj["CustomDeck"].items():
                backs[deck_id] = deck["BackURL"]
    collect_tiles = [o for o in save["ObjectStates"] if o.get("Nickname") == "Collect Cards"]
    if len(collect_tiles) != 1:
        sys.exit("Expected 1 Collect Cards tile, found %d." % len(collect_tiles))
    selector = copy.deepcopy(collect_tiles[0])
    selector["GUID"] = DECK_SELECTOR_GUID
    selector["Nickname"] = "Deck Selector"
    selector["Description"] = "正面朝上发白牌，翻面发黑牌。点击切换。"
    x, z = tool_position(selector["Nickname"])
    selector["Transform"].update(posX=x, posZ=z, rotX=0.0, rotY=180.0, rotZ=0.0)
    selector["CustomImage"]["ImageURL"] = backs[DECK_SELECTOR_FACE_UP_DECK]
    selector["CustomImage"]["ImageSecondaryURL"] = backs[DECK_SELECTOR_FACE_DOWN_DECK]
    selector["LuaScript"] = read("deck_selector.lua")
    return selector


def transform_lines(lines, guid):
    """The position and turn lines of the object with this GUID:  {name: (line number, value)}"""
    start = lines.index('      "GUID": "%s",' % guid)
    found = {}
    for i in range(start, start + 8):
        match = POSITION_PROPERTY.match(lines[i])
        if match:
            found[match.group(1)] = (i, float(match.group(2)))
    if len(found) != 3:
        sys.exit("Could not find the position of %s." % guid)
    return found


def move_towards_center(lines, guid, distance):
    """Shift the object with this GUID towards the table center, along the axis it sits on."""
    position = transform_lines(lines, guid)
    axis = max(("posX", "posZ"), key=lambda key: abs(position[key][1]))
    i, value = position[axis]
    value -= math.copysign(distance, value)
    lines[i] = '        "%s": %s,' % (axis, round(value, 4))


def place(lines, guid, **values):
    """Put the object with this GUID somewhere else:  posX, posZ and rotY as given."""
    found = transform_lines(lines, guid)
    for name, value in values.items():
        lines[found[name][0]] = '        "%s": %s,' % (name, value)


def remove(lines, guid):
    """Take the object with this GUID, which must not be the last one, out of the save."""
    start = lines.index('      "GUID": "%s",' % guid) - 1
    end = lines.index("    },", start)
    if lines[start] != "    {":
        sys.exit("Could not find the start of %s." % guid)
    del lines[start:end + 1]


def main():
    with io.open(SOURCE, encoding="utf-8-sig", newline="") as f:
        source_text = f.read()
    lines = source_text.split("\r\n")
    save = json.loads(source_text)

    # Top-level properties are indented by one level.
    top_level = {"SaveName": SAVE_NAME, "LuaScript": read("global.lua"), "XmlUI": read("global.xml")}
    # Object scripts, recognized by a snippet of the script they replace:  (snippet, new script, count)
    object_scripts = {
        "pass_tile": ('label = "Pass"', read("pass_tile.lua"), 4),
        "collect_tool": ("function collectCards()", read("collect_tool.lua"), 1),
    }
    replaced = dict.fromkeys(list(top_level) + list(object_scripts), 0)

    for i, line in enumerate(lines):
        match = STRING_PROPERTY.match(line)
        if match is None:
            continue
        indent, key, value, comma = match.groups()

        new_value = None
        if indent == "  " and key in top_level:
            new_value = top_level[key]
            replaced[key] += 1
        elif key == "LuaScript":
            old_script = json.loads(value)
            for name, (snippet, script, _) in object_scripts.items():
                if snippet in old_script:
                    new_value = script
                    replaced[name] += 1
        if new_value is None:
            continue

        lines[i] = '%s"%s": %s%s' % (indent, key, json.dumps(new_value, ensure_ascii=False), comma)

    expected = dict.fromkeys(top_level, 1)
    expected.update({name: count for name, (_, _, count) in object_scripts.items()})
    if replaced != expected:
        sys.exit("Unexpected replacements: %s (expected %s)" % (replaced, expected))

    pass_tile_snippet = object_scripts["pass_tile"][0]
    piles = {deck_id: (float(x), float(z)) for deck_id, x, z in DECK_PILE.findall(top_level["LuaScript"])}
    done = dict.fromkeys(["removed", "placed", "decks"], 0)

    for obj in save["ObjectStates"]:
        name = obj.get("Nickname") or obj["Name"]
        if obj["Name"] == "Mahjong_Tile" and pass_tile_snippet in obj.get("LuaScript", ""):
            move_towards_center(lines, obj["GUID"], PASS_TILE_SHIFT)
        elif name in REMOVED_TOOLS:
            remove(lines, obj["GUID"])
            done["removed"] += 1
        elif name in TOOL_ROW:
            x, z = tool_position(name)
            place(lines, obj["GUID"], posX=x, posZ=z)
            if obj["Name"] == "Custom_Tile":
                # Readable from White's side, like the rest of the table.
                place(lines, obj["GUID"], rotY=180.0)
            done["placed"] += 1
        elif obj["Name"] == "Deck":
            # The decks start face down on the piles they are collected to.
            (deck_id,) = obj["CustomDeck"]
            place(lines, obj["GUID"], posX=piles[deck_id][0], posZ=piles[deck_id][1], rotY=0.0)
            done["decks"] += 1

    # The Deck Selector, added below, completes the tool row.
    if done != {"removed": len(REMOVED_TOOLS), "placed": len(TOOL_ROW) - 1, "decks": 2}:
        sys.exit("Unexpected changes to the table: %s" % done)

    # ObjectStates is the last top-level property: append the new objects after its last object.
    if lines[-3:] != ["    }", "  ]", "}"]:
        sys.exit("Unexpected end of file: %r" % lines[-3:])
    used_guids = set(re.findall(r'"GUID": "(\w+)"', source_text))
    for obj in play_areas(save) + [deck_selector(save)]:
        if obj["GUID"] in used_guids:
            sys.exit("GUID %s is already in use." % obj["GUID"])
        obj_lines = json.dumps(obj, ensure_ascii=False, indent=2).split("\n")
        lines[-3] += ","
        lines[-2:-2] = ["    " + obj_line for obj_line in obj_lines]

    text = "\r\n".join(lines)
    json.loads(text)

    # The game shows the image with the same name next to a save as its icon.
    icon = os.path.splitext(os.path.normpath(OUTPUT))[0] + ".png"

    for output in [os.path.normpath(OUTPUT)] + sys.argv[1:]:
        with io.open(output, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        output_icon = os.path.splitext(output)[0] + ".png"
        if os.path.normcase(os.path.abspath(output_icon)) != os.path.normcase(icon):
            shutil.copyfile(icon, output_icon)
        print("Wrote %s" % output)


if __name__ == "__main__":
    main()
