# Guide for AI agents

How this repository is worked on. Read it before changing anything.

## Working with the owner

- Propose first, change later. For any new behavior, layout change or "can you…?" question, reply with the plan and the choices to make, then wait for an explicit go-ahead before editing.
- Commit and push only when asked. The owner tries a build in the game first; the tests here do not replace that.
- Keep both READMEs (`README.md`, `README.zh-CN.md`) in step when behavior changes.

## Layout

```
workshop/   the mod the game loads: generated, never edited by hand
src/        the scripts, build.py, and original/ (the unmodified Workshop file: never edit)
tests/      tests for the scripts, run in the game's own Lua interpreter
```

- `src/global.lua`: playing, picking, sorting, stacked hand, groups. Settings at the top.
- `src/global.xml`: the on-screen buttons.
- `src/collect_tool.lua`: Deal / Collect Cards tile. `src/deck_selector.lua`, `src/pass_tile.lua`: the other tiles.
- `src/build.py`: patches `src/original/3138177412.json` line by line, adds the play areas and the Deck Selector, removes the original sort tiles, places the tools. Save name, icon and table layout constants are at its top.

## Build

```
python src/build.py                      # writes workshop/3138177412.json
python src/build.py <Saves>/TS_Save_1.json   # also a copy the game loads, with the icon next to it
```

Rebuild before every commit and commit `src/`, `tests/` and `workshop/` together, so the mod always matches its sources.

## Tests

```
python tests/run_tests.py        # -v lists every check
```

- Needs Tabletop Simulator installed and the .NET SDK 6+. The harness takes MoonSharp and the `Vector` class from the game; `tests/stubs.lua` stands in for the game's API. Extend the stubs when a script starts using a new API.
- Every behavior change gets a test. Scripts are loaded one after another into one environment, so a later script's globals override an earlier one's.
- `python tests/show_layout.py` lists where everything sits in the built mod.

## Verifying without running the game

The game cannot be driven from an agent session. Ground truth for the API is the decompiled game: `Tabletop Simulator_Data/Managed/Assembly-CSharp.dll` with `ilspycmd` (`dotnet tool install ilspycmd --version 8.2.0.7535 --tool-path <dir>`). Most useful: `LuaGlobal.cs`, `LuaObject.cs`, `LuaPlayer.cs`, `HandZone.cs`, `ManagerPhysicsObject.cs`, `NetPhysObject.cs`, `DeckObject.cs`.

## Engine lessons

- A loose card gliding across the table (`setPositionSmooth`) is caught by any hand zone its body touches. Teleport with `setPosition`, or merge cards into a deck first; decks with `use_hands = false` are not caught.
- A hand zone re-targets its cards every physics step: move a card out of a hand with `setPosition`, not a smooth move.
- Locked objects are let go by hand zones and never raise the PickUp action; clicking them needs an invisible `createButton`. Unlocking inside a hand zone hands the card back to it.
- `group()` and card-on-deck merges dispose of merged objects by flying them to the target and destroying them on arrival. An object already within 0.025 of the target is left alive, collision off, with its cards also in the deck: never let two objects that will be merged share a spot (see `collect_tool.lua`).
- Those flights have no reliable end time; count `onObjectDestroy` events instead of waiting a fixed time.
- A deck that fell through the table has collision and gravity off. A short `setPositionSmooth` restores collision when it ends; `use_gravity = true` restores gravity.
- Cards 0.5–1.13 apart stick together as a fan, closer than 0.5 they merge; played rows use a pitch of at least 1.25, rows at least 1.6 apart.

## Conventions

- Player-facing text carries the game's language codes: `{en}English{zh}中文`, resolved on each player's client. On-screen tooltips do not support them and give both languages on one line.
- Stacked and grouped cards react to a left click only (`alt_click` ignored).
- Keep played cards, piles and tools out of the hand zones and play areas (`tests/show_layout.py`, and the geometry notes in `build.py` and `global.lua`).

## Publishing

Steam Workshop item [3812889038](https://steamcommunity.com/sharedfiles/filedetails/?id=3812889038). To update: load the freshly built save in the game, touch nothing, then **Modding → Workshop Upload → Update Workshop** with that id.
