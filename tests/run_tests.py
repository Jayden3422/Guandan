"""Run the mod's scripts against stand-ins for the Tabletop Simulator API.

The scripts in ../src run in MoonSharp, the Lua interpreter the game itself uses, with stubs.lua
playing the part of the game. This checks the scripts' logic; it does not replace trying the mod
in the game, where physics, hand zones and the UI are real.

Needs Tabletop Simulator installed (the interpreter and the Vector class are taken from it)
and the .NET SDK, version 6 or later.

Usage:  python run_tests.py [-v] [game folder]

-v lists every check instead of only the failed ones.
The game folder defaults to the TTS_DIR environment variable, or else to the folder two levels
above this repository, which is right when the repository sits in <game folder>/Modding/.
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "src")

VERBOSE = "-v" in sys.argv[1:]
ARGUMENTS = [argument for argument in sys.argv[1:] if argument != "-v"]


def game_folder():
    if ARGUMENTS:
        return ARGUMENTS[0]
    return os.environ.get("TTS_DIR") or os.path.normpath(os.path.join(ROOT, "..", ".."))


def main():
    managed = os.path.join(game_folder(), "Tabletop Simulator_Data", "Managed")
    if not os.path.exists(os.path.join(managed, "MoonSharp.Interpreter.dll")):
        sys.exit("Tabletop Simulator was not found in %s: pass the game folder as an argument." % game_folder())

    work = tempfile.mkdtemp(prefix="guandan-tests-")
    try:
        # Build outside the repository, so no build output ends up in it.
        project = os.path.join(work, "harness")
        shutil.copytree(os.path.join(HERE, "harness"), project)
        built = subprocess.run(
            ["dotnet", "build", project, "-c", "Release", "-o", os.path.join(work, "out"),
             "-p:TtsManaged=" + managed, "-nologo", "-v", "quiet"],
            capture_output=True, text=True)
        if built.returncode != 0:
            sys.exit(built.stdout + built.stderr)

        # Each script is followed by its tests. They share one environment, so the order matters.
        files = [
            os.path.join(HERE, "stubs.lua"),
            os.path.join(SRC, "global.lua"), os.path.join(HERE, "test_global.lua"),
            os.path.join(SRC, "collect_tool.lua"), os.path.join(HERE, "test_collect.lua"),
            os.path.join(SRC, "deck_selector.lua"), os.path.join(HERE, "test_selector.lua"),
        ]
        run = subprocess.run(["dotnet", os.path.join(work, "out", "harness.dll"), managed] + files,
                             capture_output=True, text=True, encoding="utf-8", errors="replace")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    lines = run.stdout.splitlines()
    passed = sum(1 for line in lines if line.startswith("ok "))
    for line in lines:
        if VERBOSE or not line.startswith("ok "):
            print(line)
    print("%d checks passed" % passed)
    if run.returncode != 0:
        sys.exit(run.stderr or 1)


if __name__ == "__main__":
    main()
