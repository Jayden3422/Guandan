"""List where everything sits on the table in the built mod, to check the layout by eye.

Usage:  python show_layout.py
"""
import io
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
BUILT = os.path.join(HERE, "..", "workshop", "3138177412.json")

with io.open(BUILT, encoding="utf-8") as f:
    save = json.load(f)

print("%-12s %-22s %-7s %8s %8s %7s" % ("type", "name", "guid", "x", "z", "turn"))
for obj in save["ObjectStates"]:
    transform = obj["Transform"]
    name = obj.get("Nickname") or obj.get("FogColor") or ""
    if obj["Name"] == "Deck":
        name = "deck %s" % ", ".join(obj["CustomDeck"])
    print("%-12s %-22s %-7s %8.2f %8.2f %7.1f" % (
        obj["Name"], name, obj["GUID"], transform["posX"], transform["posZ"], transform["rotY"]))
