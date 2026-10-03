"""Build the modified Guandan mod from the original Workshop mod.

Reads original/3138177412.json (the unmodified Workshop file), injects the scripts in this folder
and adds a play area (a second hand zone) in front of every player's hand, the Deck Selector tool
and the Sort Hand Tool Stack.
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

# The Deck Selector tool: a copy of the Collect Cards tile, showing on each side the back of the deck it selects.
DECK_SELECTOR_GUID = "9a7e05"
DECK_SELECTOR_POSITION = (8.4, -5.5)
DECK_SELECTOR_FACE_UP_DECK = "123"
DECK_SELECTOR_FACE_DOWN_DECK = "125"

# The Sort Hand Tool Stack: a copy of the Sort Hand Tool LR tile, square instead of round to tell them apart.
SORT_STACK_TOOL_GUID = "9a7e06"
SORT_STACK_TOOL_POSITION = (1.5, -3.1)
SQUARE_TILE = 0

# Added at the top of the other Sort Hand Tools' sortHand(): a stacked hand goes back in the hand zone first.
SORT_TOOL_HEAD = "function sortHand(obj, player_color)"
SORT_TOOL_HOOK = """
\t-- A stacked hand goes back in the hand zone first, which needs a moment to take the cards.
\tif Global.call("unstackHand", {color = player_color}) then
\t\tWait.time(function() sortHand(obj, player_color) end, 0.6)
\t\treturn
\tend
"""

# A line holding one string property:  <indent>"<key>": "<value>"[,]
STRING_PROPERTY = re.compile(r'^(\s*)"(\w+)": (".*")(,?)$')
# A position line inside an object's Transform.
POSITION_PROPERTY = re.compile(r'^        "(posX|posZ)": (\S+),$')


def read(name):
    with io.open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read()


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
    selector["Transform"].update(posX=DECK_SELECTOR_POSITION[0], posZ=DECK_SELECTOR_POSITION[1],
                                 rotX=0.0, rotY=180.0, rotZ=0.0)
    selector["CustomImage"]["ImageURL"] = backs[DECK_SELECTOR_FACE_UP_DECK]
    selector["CustomImage"]["ImageSecondaryURL"] = backs[DECK_SELECTOR_FACE_DOWN_DECK]
    selector["LuaScript"] = read("deck_selector.lua")
    return selector


def sort_stack_tool(save):
    """The Sort Hand Tool Stack, derived from the Sort Hand Tool LR tile."""
    sort_tools = [o for o in save["ObjectStates"] if o.get("Nickname") == "Sort Hand Tool LR"]
    if len(sort_tools) != 1:
        sys.exit("Expected 1 Sort Hand Tool LR tile, found %d." % len(sort_tools))
    tool = copy.deepcopy(sort_tools[0])
    tool["GUID"] = SORT_STACK_TOOL_GUID
    tool["Nickname"] = "Sort Hand Tool Stack"
    tool["Description"] = "竖摞：同点数的牌摞成一列。用另外两个排序工具恢复成一排。"
    tool["Transform"].update(posX=SORT_STACK_TOOL_POSITION[0], posZ=SORT_STACK_TOOL_POSITION[1])
    tool["CustomImage"]["CustomTile"]["Type"] = SQUARE_TILE
    tool["LuaScript"] = read("sort_stack_tool.lua")
    return tool


def hook_sort_tool(script):
    """Make a Sort Hand Tool unstack the hand before sorting it."""
    newline = "\r\n" if "\r\n" in script else "\n"
    line_end = script.index("\n", script.index(SORT_TOOL_HEAD)) + 1
    return script[:line_end] + SORT_TOOL_HOOK.replace("\n", newline) + script[line_end:]


def move_towards_center(lines, guid, distance):
    """Shift the object with this GUID towards the table center, along the axis it sits on."""
    start = lines.index('      "GUID": "%s",' % guid)
    position = {}
    for i in range(start, start + 8):
        match = POSITION_PROPERTY.match(lines[i])
        if match:
            position[match.group(1)] = (i, float(match.group(2)))
    if len(position) != 2:
        sys.exit("Could not find the position of %s." % guid)
    axis = max(position, key=lambda key: abs(position[key][1]))
    i, value = position[axis]
    value -= math.copysign(distance, value)
    lines[i] = '        "%s": %s,' % (axis, round(value, 4))


def main():
    with io.open(SOURCE, encoding="utf-8-sig", newline="") as f:
        source_text = f.read()
    lines = source_text.split("\r\n")
    save = json.loads(source_text)

    # Top-level properties are indented by one level.
    top_level = {"SaveName": SAVE_NAME, "LuaScript": read("global.lua"), "XmlUI": read("global.xml")}
    # Object scripts, recognized by a snippet of the script they replace:  (snippet, new script or edit, count)
    object_scripts = {
        "pass_tile": ('label = "Pass"', read("pass_tile.lua"), 4),
        "collect_tool": ("function collectCards()", read("collect_tool.lua"), 1),
        "sort_tool": (SORT_TOOL_HEAD, hook_sort_tool, 2),
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
                    new_value = script(old_script) if callable(script) else script
                    replaced[name] += 1
        if new_value is None:
            continue

        lines[i] = '%s"%s": %s%s' % (indent, key, json.dumps(new_value, ensure_ascii=False), comma)

    expected = dict.fromkeys(top_level, 1)
    expected.update({name: count for name, (_, _, count) in object_scripts.items()})
    if replaced != expected:
        sys.exit("Unexpected replacements: %s (expected %s)" % (replaced, expected))

    pass_tile_snippet = object_scripts["pass_tile"][0]
    for obj in save["ObjectStates"]:
        if obj["Name"] == "Mahjong_Tile" and pass_tile_snippet in obj.get("LuaScript", ""):
            move_towards_center(lines, obj["GUID"], PASS_TILE_SHIFT)

    # ObjectStates is the last top-level property: append the new objects after its last object.
    if lines[-3:] != ["    }", "  ]", "}"]:
        sys.exit("Unexpected end of file: %r" % lines[-3:])
    used_guids = set(re.findall(r'"GUID": "(\w+)"', source_text))
    for obj in play_areas(save) + [deck_selector(save), sort_stack_tool(save)]:
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
