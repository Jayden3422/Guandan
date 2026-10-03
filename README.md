<p align="center">
  <img src="workshop/3138177412.png" alt="Guandan icon" width="160">
</p>

<h1 align="center">Guandan (掼蛋) for Tabletop Simulator</h1>

<p align="center">
  <b>English</b> | <a href="README.zh-CN.md">简体中文</a>
</p>

A scripted [Tabletop Simulator](https://store.steampowered.com/app/286160/Tabletop_Simulator/) table for Guandan, the four-player card game played with two decks. It adds one-click dealing and collecting, a private play area, click-to-pick card play, and a hand that can be stacked in columns like in the mobile Guandan apps.

The mod does not enforce the rules of Guandan. It handles the cards; the players judge the plays.

## Based on

This mod is built on the Workshop mod **[Guandan](https://steamcommunity.com/sharedfiles/filedetails/?id=3138177412)**. The table, the cards, the seats and the original tools come from it, and everything here is a continuation of that work.

**To the author of the original mod:** I am sorry that I had not managed to reach you by the time I published this on the Workshop. Thank you for sharing your work. If you have any concerns, please contact me at any time through the [issues of this repository](https://github.com/Jayden3422/Guandan/issues), and I will rework the parts that come from your mod as soon as possible.

## Installing

1. Download [`workshop/3138177412.json`](workshop/3138177412.json) and [`workshop/3138177412.png`](workshop/3138177412.png).
2. Put both files in the Saves folder of Tabletop Simulator: `Documents/My Games/Tabletop Simulator/Saves`.
3. In the game, start a table, open **Games → Save & Load**, and load **Guandan 掼蛋（出牌区）**.

Only the host needs the files. Tested with Tabletop Simulator v14.2.2.

## Playing a round

The table has four seats: White, Green, Purple and Orange.

1. **Choose a deck.** The table has two decks, one with white card faces and one with black ones. The Deck Selector tile in the middle of the table shows the back of the deck that will be dealt. Click it to switch.
2. **Deal.** Click the **Deal** tile in the middle of the table. Every seated player gets 27 cards, and the tile flips to **Collect Cards**.
3. **Play.** See the buttons below.
4. **Collect.** Click **Collect Cards**. Every card goes back to its deck's pile in the corner of the table, the decks are shuffled, and the tile flips back to **Deal**. If any player still holds cards, a first click only warns; click again within 5 seconds to collect.

Each seat also has a **Pass** tile. The die and the two counters are there for keeping score by hand.

## The buttons

Five buttons sit in the lower right corner of the screen. Their labels are in Chinese. Each has a scripting hotkey, which is a numpad key unless you changed it in **Options → Game Keys**.

| Button | Meaning | Hotkey | What it does |
|---|---|---|---|
| 正序 / 倒序 | Sort ascending / descending | Numpad 1 | Sorts your hand in a row. The button shows the order the next click gives, and alternates. |
| 竖摞 | Stack | Numpad 4 | Stacks your hand in columns, one per card number. |
| 选牌 / 出牌 | Pick / Play | Numpad 2 | Starts picking cards, then plays the cards in your play area. |
| 收回 | Take back | Numpad 3 | Takes the cards in your play area back into your hand. |
| 理牌 | Group | Numpad 5 | Turns the cards in your play area into a group. |

### Playing cards

- **The play area** is the outlined rectangle on the table in front of your hand. Like your hand, only you can see the cards in it. They are kept sorted.
- **Picking.** Click **选牌**. Now a click on a card in your hand moves it to the play area, and a click on a card in the play area moves it back. You can also drag cards into the play area without picking.
- **Playing.** While you are picking, the button reads **出牌**. Click it to play every card in the play area: the cards are laid out face up in front of you, sorted from low to high. More than 10 cards are split over several rows.
- **Taking back.** **收回** returns the play area to your hand and ends picking.
- While you are picking, your own hand cards cannot be dragged, because a click moves them. Click **收回** first.
- When you play again, or click your **Pass** tile, your previous play is moved to its deck's pile.

### A stacked hand

**竖摞** arranges your hand like the mobile Guandan apps do: cards of the same number in one column, the columns from 2 up to the Jokers, each card showing its top edge.

- The hand stays stacked. Cards that reach your hand later, dealt or taken back, join the stack.
- Stacked cards are held in place by the script, so they cannot be dragged. **Left-click** a card to send it to the play area.
- Click **正序 / 倒序** to go back to a row.

### Groups

A group keeps cards together that you plan to play together, such as a straight.

- Put two or more cards in the play area and click **理牌**. They become a column of their own to the left of your hand.
- **Left-click** any card of a group to send the whole group to the play area. There it is a group no longer: play the cards, take them back, or group them again.
- Sorting and stacking leave groups alone. To change a group, send it to the play area, add or remove cards, and click **理牌** again.
- You can have several groups.

## For developers

```
workshop/   the mod itself, as loaded by the game
src/        the scripts, the original Workshop file they are applied to, and the build script
tests/      tests for the scripts
```

The mod file is generated. `src/build.py` takes the unmodified Workshop file in `src/original/`, injects the scripts in `src/`, adds the play areas and the Deck Selector, removes the original sort tiles and arranges the table. Only the lines that change are rewritten, so the result diffs cleanly against the original.

**Build** (Python 3):

```
python src/build.py
```

This writes `workshop/3138177412.json`. To try a build in the game, give a file in your Saves folder as an extra output. The icon is copied next to it:

```
python src/build.py "<Documents>/My Games/Tabletop Simulator/Saves/TS_Save_1.json"
```

**Test** (Tabletop Simulator installed, and the .NET SDK 6 or later):

```
python tests/run_tests.py
```

The tests run the scripts in MoonSharp, the Lua interpreter the game uses, against `tests/stubs.lua`, which stands in for the game's API. They check the scripts' logic. They do not replace trying a change in the game, where physics, hand zones and the UI are real.

**Where things are:**

| File | What it holds |
|---|---|
| `src/global.lua` | Playing, picking, sorting, the stacked hand and groups. Settings are at the top. |
| `src/global.xml` | The on-screen buttons. |
| `src/collect_tool.lua` | The Deal / Collect Cards tile. |
| `src/deck_selector.lua` | The Deck Selector tile. |
| `src/pass_tile.lua` | The Pass tiles. |
| `src/build.py` | The build, and where everything sits on the table. |
| `tests/show_layout.py` | Lists where everything sits in the built mod. |
