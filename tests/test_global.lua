-- Tests for global.lua (run after stubs.lua and global.lua).

failures = 0

function check(condition, what)
	if condition then
		print("ok    " .. what)
	else
		failures = failures + 1
		print("FAIL  " .. what)
	end
end

function near(a, b) return math.abs(a - b) < 0.01 end

local nextGuid = 0

-- Put cards in a player's hand (zone 1) or play area (zone 2).
local function deal(color, list, zoneIndex)
	local cards = {}
	local zone = seats[color][zoneIndex or 1]
	for i, entry in ipairs(list) do
		nextGuid = nextGuid + 1
		table.insert(cards, newCard(string.format("c%04d", nextGuid), entry[1], entry[2], {zone.position.x, 4, zone.position.z}, entry[3]))
	end
	return cards
end

local function stage(color, cards)
	local zone = seats[color][2]
	for _, card in ipairs(cards) do card.setPosition({zone.position.x, 4, zone.position.z}) end
end

local function zoneOf(card) return select(2, inHandZone(card.getPosition())) end
local function x(card) return card.getPosition().x end

-- Whether a card lies face down on the first (x = -11.54) or second (x = -8.6) pile.
local function atPile(card, pileX)
	local position = card.getPosition()
	return near(position.x, pileX) and near(position.z, -11.77) and near(card.getRotation().z, 180)
end

local function countAtPiles(cards)
	local count = 0
	for _, card in ipairs(cards) do
		if atPile(card, -11.54) or atPile(card, -8.6) then count = count + 1 end
	end
	return count
end

-- Play whatever is in the player's play area: the hotkey starts picking, the second press plays.
local function play(color)
	onScriptingButtonDown(2, color)
	onScriptingButtonDown(2, color)
end

onLoad("")

-- 0. Play area outlines.
check(#vectorLines == 4, "one outline per play area")
local whiteOutline
for _, line in ipairs(vectorLines) do if line.color.name == "White" then whiteOutline = line end end
local xs, zs = {}, {}
for _, point in ipairs(whiteOutline.points) do table.insert(xs, point.x) table.insert(zs, point.z) end
table.sort(xs) table.sort(zs)
check(near(xs[1], -5.97) and near(xs[4], 6.03) and near(zs[1], -14.5) and near(zs[4], -11.5) and whiteOutline.loop, "White's outline matches the play area footprint")

-- 1. Spectators cannot pick; an empty play area cannot be played.
onPickButtonClick({color = "Grey"})
check(#messages == 0 and uiAttributes.guandanPlayButton == nil, "spectator: nothing happens")
local white = deal("White", {{"King", "Spade"}, {"Three", "Heart"}, {"Joker", "Color"}, {"Three", "Club"}, {"Joker", "BW"}, {"Ace", "Diamond"}})
onScriptingButtonDown(9, "White")
check(uiAttributes.guandanPlayButton == nil, "other hotkeys are ignored")

-- 2. Picking: the buttons swap for the picking player only.
onScriptingButtonDown(2, "White")
check(uiAttributes.guandanPlayButton.active == "true" and uiAttributes.guandanPlayButton.visibility == "White", "while picking, White sees the play button")
check(not string.find(uiAttributes.guandanPickButton.visibility, "White") and string.find(uiAttributes.guandanPickButton.visibility, "Green") ~= nil, "and the others keep the pick button")
onScriptingButtonDown(2, "White")
check(#messages == 2 and zoneOf(white[1]) == 1 and uiAttributes.guandanPlayButton.active == "true", "playing an empty play area only shows a message and keeps picking")

-- 3. Clicking cards while picking moves them between hand and play area.
local whitePlayer = {color = "White"}
check(onPlayerAction(whitePlayer, Player.Action.PickUp, {white[1], white[2]}) == false, "picking up own hand cards is intercepted")
check(zoneOf(white[1]) == 1, "the cards move once the click has been handled")
settle()
check(zoneOf(white[1]) == 2 and zoneOf(white[2]) == 2 and zoneOf(white[3]) == 1, "clicked hand cards go to the play area")
check(x(white[2]) < x(white[1]), "and the play area is put in order")
check(onPlayerAction(whitePlayer, Player.Action.PickUp, {white[1]}) == false, "picking up a play area card is intercepted too")
settle()
check(zoneOf(white[1]) == 1 and zoneOf(white[2]) == 2, "a clicked play area card goes back to the hand")
check(onPlayerAction(whitePlayer, Player.Action.Select, {white[3]}) == true, "other actions are not intercepted")
local tableCard = newCard("t1", "Two", "Heart", {0, 1, 0})
check(onPlayerAction(whitePlayer, Player.Action.PickUp, {tableCard}) == true, "cards on the table can still be picked up")
check(onPlayerAction({color = "Green"}, Player.Action.PickUp, {white[3]}) == true, "players who are not picking are not intercepted")
objects["t1"] = nil

-- 4. A clicked card pulled back by the zone it leaves is sent again; one sent elsewhere meanwhile is not.
onPlayerAction(whitePlayer, Player.Action.PickUp, {white[3]})
runFrames()
white[3].setPosition({0.03, 4, -18})
runWaits()
check(zoneOf(white[3]) == 2, "a card pulled back into the hand is sent to the play area again")
settle()
onPlayerAction(whitePlayer, Player.Action.PickUp, {white[3]})
runFrames()
onPlayerAction(whitePlayer, Player.Action.PickUp, {white[3]})
runFrames()
check(zoneOf(white[3]) == 2, "clicking twice sends the card to the hand and back to the play area")
settle()
check(zoneOf(white[3]) == 2, "and the first move is not repeated afterwards")

-- 5. Playing: sorted left to right, face up, in front of White; picking ends.
for _, card in ipairs({white[1], white[3], white[4], white[5]}) do
	if zoneOf(card) == 1 then onPlayerAction(whitePlayer, Player.Action.PickUp, {card}) end
end
settle()
onPlayButtonClick(whitePlayer)
local order = {}
for i = 1, 5 do order[i] = x(white[i]) end
-- expected order: Three Heart, Three Club, King, Joker BW, Joker Color
check(order[2] < order[4] and order[4] < order[1] and order[1] < order[5] and order[5] < order[3], "White's cards are sorted left to right")
check(near(white[2].getPosition().z, -7.5), "White's cards land at z = -7.5")
check(near(x(white[4]) - x(white[2]), 2.3), "five cards are a full card apart")
check(near(white[1].getRotation().y, 180) and near(white[1].getRotation().z, 0), "White's cards are face up and upright for White")
check(white[2].getPosition().y < white[4].getPosition().y, "cards further right start higher")
check(zoneOf(white[6]) == 1, "the card left in hand stays in hand")
check(uiAttributes.guandanPlayButton.active == "false" and uiAttributes.guandanPickButton.visibility == "", "playing ends picking: everyone sees the pick button again")
check(onPlayerAction(whitePlayer, Player.Action.PickUp, {white[6]}) == true, "and cards can be picked up normally again")
settle()

-- 6. A played card that got pulled back into the play area is placed again.
stage("White", {white[1]})
play("White")
stage("White", {white[1]})
runWaits()
check(near(white[1].getPosition().z, -7.5), "card pulled back by the hand zone is teleported again")
settle()

-- 7. Other seats: layout direction and rotation.
local green = deal("Green", {{"Four", "Spade"}, {"Five", "Spade"}}, 2)
play("Green")
check(near(green[1].getPosition().z, 7.5) and x(green[1]) > x(green[2]), "Green's row is mirrored (their left is +x)")
check(near(green[1].getRotation().y % 360, 0), "Green's cards are upright for Green")

local purple = deal("Purple", {{"Four", "Heart", 12503}, {"Five", "Heart", 12504}}, 2)
play("Purple")
check(near(x(purple[1]), 7.73) and purple[1].getPosition().z < purple[2].getPosition().z, "Purple's row runs along z, low card at -z")
check(near(purple[1].getRotation().y % 360, 90), "Purple's cards are upright for Purple")

local orange = deal("Orange", {{"Four", "Club"}, {"Five", "Club"}}, 2)
play("Orange")
check(near(x(orange[1]), -7.67) and orange[1].getPosition().z > orange[2].getPosition().z, "Orange's row runs along z, low card at +z")
check(near(orange[1].getRotation().y % 360, 270), "Orange's cards are upright for Orange")
settle()

-- 8. Up to ten cards share one row; more are split over equal rows that stay in front of the player.
local ten = {}
for i = 1, 10 do ten[i] = {"Six", "Heart"} end
local row = deal("White", ten, 2)
play("White")
xs = {}
for i = 1, 10 do xs[i] = x(row[i]) end
table.sort(xs)
check(near(xs[2] - xs[1], 12 / 9) and near(row[1].getPosition().z, -7.5) and near(row[10].getPosition().z, -7.5), "ten cards are squeezed into one row")
settle()

local many = {}
for i = 1, 12 do many[i] = {"Six", "Heart"} end
local big = deal("Green", many, 2)
play("Green")
local far, nearRow = {}, {}
for i = 1, 12 do
	if near(big[i].getPosition().z, 7.5) then table.insert(nearRow, big[i]) elseif near(big[i].getPosition().z, 5.9) then table.insert(far, big[i]) end
end
check(#far == 6 and #nearRow == 6, "twelve cards are split into two rows of six, the extra row towards the table center")
xs = {}
for i = 1, 6 do xs[i] = x(nearRow[i]) end
table.sort(xs)
check(near(xs[2] - xs[1], 2.3) and near(xs[1], 0.03 - 5.75), "each row is laid out like a single row")
check(far[1].getPosition().y < nearRow[1].getPosition().y, "the row nearest the player lies on top")
local widest = 0
local hand27 = {}
for i = 1, 27 do hand27[i] = {"Seven", "Club"} end
local huge = deal("Purple", hand27, 2)
play("Purple")
for i = 1, 27 do widest = math.max(widest, math.abs(huge[i].getPosition().z - 0.14)) end
check(widest < 6.1, "a whole hand played at once still stays clear of the neighbours' zones")
settle()
for i = 1, 27 do objects[huge[i].guid] = nil end
check(atPile(green[1], -11.54) and atPile(green[2], -11.54), "Green's earlier play went to its deck's pile, face down")
check(green[1].getPosition().y ~= green[2].getPosition().y, "discards are dropped one above the other")
settle()

-- 9. Playing again discards the previous play without gliding; cards taken back or moved away are left alone.
smoothMoves = {}
big[1].setPosition({0.03, 4, 18})      -- taken back in hand
big[2].setPosition({-9, 1, -3})        -- moved elsewhere on the table
big[3].held_by_color = "Green"         -- being held
deal("Green", {{"Seven", "Heart"}}, 2)
play("Green")
check(countAtPiles(big) == 9, "previous play goes to the pile, except taken / moved / held cards")
check(#smoothMoves == 0, "discards are teleported, so they cannot be caught by a play area on the way")
check(near(x(big[2]), -9) and inHandZone(big[1].getPosition()) == "Green", "taken / moved cards stay where they are")
settle()

-- 10. Passing discards the passer's play, and only theirs; each deck has its own pile.
onGuandanPass({color = "Purple"})
check(atPile(purple[1], -8.6) and atPile(purple[2], -8.6), "cards of the second deck go to the second pile")
check(near(x(orange[1]), -7.67), "passing clears the passer's cards only")
purple[1].setPosition({0, 1, 0})
onGuandanPass({color = "Purple"})
check(near(x(purple[1]), 0), "passing twice does nothing more")

-- 11. Deck IDs.
check(getDeckId({object = newDeck({12300, 12353, 12301}, {0, 1, 0})}) == 123, "a deck of one deck's cards has that deck's ID")
check(getDeckId({object = newDeck({12300, 12553}, {0, 1, 0})}) == nil, "a deck mixing two decks has no ID")
check(near(getPilePosition({object = newCard("x1", "Two", "Heart", {0, 1, 0}, 99901)}).x, -11.54), "unknown decks use the default pile")

-- 12. Save and load round trip.
local saved = onSave()
onLoad(saved)
onGuandanPass({color = "Orange"})
check(countAtPiles(orange) == 2, "table state survives save / load")

-- 13. Cards dropped in a play area are put in order; held cards and sorted areas are left alone.
objects = {}
local function staged(name, suit, atX)
	nextGuid = nextGuid + 1
	return newCard(string.format("c%04d", nextGuid), name, suit, {atX, 4, -13})
end
local king, three, ace, two = staged("King", "Spade", -2), staged("Three", "Heart", -1), staged("Ace", "Club", 0), staged("Two", "Club", 1)
local joker = staged("Joker", "BW", -3)
joker.held_by_color = "White"
onObjectDrop("White", two)
onObjectDrop("White", ace)
check(runWaits() == 1, "several drops trigger one sort")
check(x(two) < x(three) and x(three) < x(king) and x(king) < x(ace), "the play area is sorted from low to high")
check(zoneOf(two) == 2 and zoneOf(ace) == 2, "sorted cards stay in the play area")
check(near(x(joker), -3), "a card still being held is not moved")
local before = x(two)
two.setPosition({before - 0.05, 4, -13})
onObjectDrop("White", two)
runWaits()
check(near(x(two), before - 0.05), "an area already in order is left alone")
onObjectDrop("White", {type = "Dice"})
check(runWaits() == 0, "dropping something else does not sort")

-- 14. Taking the play area back in hand, which also ends picking.
joker.held_by_color = nil
local inHand = newCard("hand1", "Nine", "Heart", {8.9, 4, -18})
onPickButtonClick(whitePlayer)
onScriptingButtonDown(3, "White")
local allBack = true
for _, card in ipairs({joker, two, three, king, ace}) do
	if zoneOf(card) ~= 1 or x(card) <= x(inHand) then allBack = false end
end
check(allBack, "returned cards are in the hand, to the right of the cards already there")
check(x(joker) < x(two) and x(two) < x(three) and x(three) < x(king) and x(king) < x(ace), "returned cards keep their order")
check(uiAttributes.guandanPlayButton.active == "false", "taking the cards back ends picking")
settle()
onReturnButtonClick({color = "Grey"})
onReturnButtonClick(whitePlayer)
check(runWaits() == 0, "returning with an empty play area does nothing")

-- 15. Stacking the hand in columns.
objects = {}
messages = {}
local function hand(color, name, suit)
	nextGuid = nextGuid + 1
	local zone = seats[color][1]
	return newCard(string.format("c%04d", nextGuid), name, suit, {zone.position.x, zone.position.y, zone.position.z})
end
local function z(card) return card.getPosition().z end
local function y(card) return card.getPosition().y end
local function hiddenFrom(card, color)
	for _, hidden in ipairs(card.hiddenFrom) do if hidden == color then return true end end
	return false
end

stackHand("Grey")
check(#messages == 0, "spectators cannot stack")
local aceS, twoC, kingS, aceH, twoH, aceD = hand("White", "Ace", "Spade"), hand("White", "Two", "Club"), hand("White", "King", "Spade"), hand("White", "Ace", "Heart"), hand("White", "Two", "Heart"), hand("White", "Ace", "Diamond")
local jokerC, jokerB = hand("White", "Joker", "Color"), hand("White", "Joker", "BW")
local stacked = {aceS, twoC, kingS, aceH, twoH, aceD, jokerC, jokerB}
onScriptingButtonDown(4, "White")
local allTaken = true
for _, card in ipairs(stacked) do
	if not card.locked or #card.buttons ~= 1 or hiddenFrom(card, "White") or hiddenFrom(card, "Black") or not hiddenFrom(card, "Green") or not hiddenFrom(card, "Grey") then allTaken = false end
end
check(allTaken, "stacked cards are locked, clickable, and hidden from everyone but their owner")
check(#Player["White"].getHandObjects() == 0, "the hand zone no longer holds them")
check(near(x(twoH), -3.42) and near(x(kingS), -1.12) and near(x(aceH), 1.18) and near(x(jokerB), 3.48), "four columns a full card apart, from Two to Joker")
check(near(x(twoH), x(twoC)) and near(x(aceH), x(aceD)) and near(x(aceD), x(aceS)), "cards of the same number share a column")
check(near(z(twoH), -18) and near(z(twoC), -18.62) and near(z(aceH), -18) and near(z(aceD), -18.62) and near(z(aceS), -19.24), "each card of a column is a step closer to the player, in suit order")
check(y(twoC) > y(twoH) and y(kingS) > y(twoH) and y(aceS) > y(aceD) and y(aceD) > y(aceH), "later cards and columns float higher")
check(near(aceS.getRotation().y, 180) and near(aceS.getRotation().z, 0), "stacked cards are face up and upright for their owner")

-- 16. Clicking a stacked card sends it to the play area; the other cards stay put.
local before = {x(aceS), z(aceS)}
onStackCardClick(aceD, "Green")
check(aceD.locked, "another player's click does nothing")
onStackCardClick(aceD, "White", true)
check(aceD.locked, "nor does the owner's right click")
onStackCardClick(aceD, "White")
settle()
check(not aceD.locked and #aceD.buttons == 0 and zoneOf(aceD) == 2 and #aceD.hiddenFrom == 0, "the owner's click sends the card to the play area as a normal card")
check(uiAttributes.guandanPlayButton.visibility == "White", "and starts picking, so the play button shows")
check(near(x(aceS), before[1]) and near(z(aceS), before[2]), "the columns stay put while picking")

-- 17. A card coming back to the hand joins the stack again.
onPlayerAction(whitePlayer, Player.Action.PickUp, {aceD})
runFrames()
check(zoneOf(aceD) == 1 and not aceD.locked, "a clicked play area card first goes back to the hand zone")
onObjectEnterZone({type = "Hand"}, aceD)
settle()
check(aceD.locked and #aceD.buttons == 1 and hiddenFrom(aceD, "Green") and near(z(aceD), -18.62), "and is then stacked in its column again")
check(near(x(aceD), x(aceH)), "without being sent back to the hand zone afterwards")

-- 18. Playing from a stacked hand closes the gaps.
onStackCardClick(kingS, "White")
settle()
onPlayButtonClick(whitePlayer)
check(near(z(kingS), -7.5) and near(x(twoH), -2.27) and near(x(aceH), 0.03) and near(x(jokerB), 2.33), "after playing, the remaining columns close up")
settle()

-- 19. Cards dealt to a stacked hand join it; many columns are squeezed to the width of the hand.
local names = {"Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King"}
local dealt = {}
for i, name in ipairs(names) do dealt[i] = hand("White", name, "Heart") end
onObjectEnterZone({type = "Hand"}, dealt[1])
onObjectEnterZone({type = "Hand"}, dealt[2])
check(runWaits() == 1, "several arriving cards trigger one check")
check(dealt[1].locked and dealt[11].locked, "dealt cards are stacked")
check(near(x(dealt[1]) - x(twoH), 17.8 / 13) and near(x(jokerB) - x(twoH), 17.8), "fourteen columns span the hand zone")

-- 20. Other seats stack towards their own player.
local purpleA, purpleB = hand("Purple", "Nine", "Heart"), hand("Purple", "Nine", "Club")
stackHand("Purple")
check(near(x(purpleA), 18.23) and near(x(purpleB), 18.85) and near(z(purpleA), z(purpleB)), "Purple's column runs towards Purple")
check(near(purpleA.getRotation().y % 360, 90), "Purple's stacked cards are upright for Purple")

-- 21. Save and load: the stacks come back with their buttons and hiding.
saved = onSave()
for _, card in ipairs({twoH, purpleA}) do card.buttons = {} card.hiddenFrom = {} end
onLoad(saved)
check(#twoH.buttons == 1 and hiddenFrom(twoH, "Green") and #purpleA.buttons == 1 and hiddenFrom(purpleA, "White"), "stacks survive save / load")
onStackCardClick(purpleA, "Purple")
settle()
check(zoneOf(purpleA) == 2, "and stay clickable")

-- 22. Sorting puts a stacked hand back in the hand zone as a row, from low to high the first time.
sortHand("Grey")
check(uiAttributes.guandanSortDescendingButton == nil or uiAttributes.guandanSortDescendingButton.active == "false", "spectators cannot sort")
onSortButtonClick(whitePlayer)
local allFree = true
for _, card in ipairs({twoH, twoC, aceH, aceD, aceS, jokerB, jokerC, dealt[1], dealt[11]}) do
	if card.locked or #card.buttons ~= 0 or zoneOf(card) ~= 1 then allFree = false end
end
check(allFree, "the stacked cards are unlocked and back in the hand zone")
check(x(twoH) < x(twoC) and x(twoC) < x(dealt[1]) and x(dealt[11]) < x(aceH) and x(aceS) < x(jokerB) and x(jokerB) < x(jokerC), "lined up from low to high")
check(hiddenFrom(twoH, "Green"), "still hidden until the hand zone has taken over")
settle()
check(#twoH.hiddenFrom == 0, "then no longer hidden by the script")
onObjectEnterZone({type = "Hand"}, twoH)
settle()
check(not twoH.locked, "cards arriving in a hand that is no longer stacked are left alone")
check(uiAttributes.guandanSortDescendingButton.visibility == "White" and not string.find(uiAttributes.guandanSortButton.visibility, "White") and string.find(uiAttributes.guandanSortButton.visibility, "Green") ~= nil, "the sort button now offers the other order, to that player only")

-- 22b. The next sort is from high to low, the cards of the row trading places; then from low to high again.
local leftmost, rightmost = x(twoH), x(jokerC)
onScriptingButtonDown(1, "White")
check(x(jokerC) < x(jokerB) and x(jokerB) < x(aceH) and x(aceH) < x(aceD) and x(aceD) < x(aceS) and x(aceS) < x(dealt[11]) and x(dealt[1]) < x(twoH) and x(twoH) < x(twoC), "the second sort is from high to low, the bigger Joker first")
check(near(x(jokerC), leftmost) and near(x(twoC), rightmost) and zoneOf(aceD) == 1, "the cards trade places within the row")
check(uiAttributes.guandanSortDescendingButton.active == "false" and uiAttributes.guandanSortButton.visibility == "", "and the button is back to the first order")
onSortButtonClick(whitePlayer)
check(near(x(twoH), leftmost) and near(x(jokerC), rightmost), "the third sort is from low to high again")
onSortButtonClick(whitePlayer)
onSortButtonClick(whitePlayer)

-- 23. Groups: the cards in the play area become a column of their own, to the left of the hand.
settle()
objects = {}
messages = {}
local three, four, five = hand("White", "Three", "Heart"), hand("White", "Four", "Heart"), hand("White", "Five", "Heart")
local nineC, nineS, kingH = hand("White", "Nine", "Club"), hand("White", "Nine", "Spade"), hand("White", "King", "Heart")
onGroupButtonClick({color = "Grey"})
onGroupButtonClick(whitePlayer)
check(#messages == 1 and not three.locked, "grouping needs at least two cards in the play area")
stage("White", {five, three, four})
onPickButtonClick(whitePlayer)
onScriptingButtonDown(5, "White")
check(three.locked and #three.buttons == 1 and three.buttons[1].click_function == "onGroupCardClick" and hiddenFrom(three, "Green") and not hiddenFrom(three, "White"), "grouped cards are locked, clickable and hidden from the others")
check(near(x(three), 0.03 - 11.7) and near(x(four), x(three)) and near(x(five), x(three)), "a group is a column left of the hand zone, with a gap")
check(near(z(three), -18) and near(z(four), -18.62) and near(z(five), -19.24) and y(five) > y(three), "in order, each card a step closer to the player")
check(not string.find(uiAttributes.guandanPlayButton.visibility, "White"), "grouping ends picking")
check(not nineC.locked and zoneOf(nineC) == 1, "the rest of the hand is left alone")

-- 24. Several groups line up to the left; sorting and stacking leave them alone.
stage("White", {nineS, nineC})
onGroupButtonClick(whitePlayer)
check(near(x(nineC), 0.03 - 11.7 - 2.5) and near(x(nineS), x(nineC)) and near(x(three), 0.03 - 11.7), "a second group goes further left")
onStackButtonClick(whitePlayer)
check(kingH.locked and near(x(kingH), 0.03) and near(x(three), 0.03 - 11.7) and near(z(five), -19.24) and three.buttons[1].click_function == "onGroupCardClick", "stacking the hand does not touch the groups")
onSortButtonClick(whitePlayer)
settle()
check(not kingH.locked and three.locked and near(x(three), 0.03 - 11.7), "nor does sorting it back into a row")
onSortButtonClick(whitePlayer)

-- 25. A left click on any card of a group sends the whole group to the play area, and the group is gone.
onGroupCardClick(four, "White", true)
onGroupCardClick(four, "Green", false)
check(four.locked and three.locked, "a right click or another player's click does nothing")
onGroupCardClick(four, "White", false)
check(string.find(uiAttributes.guandanPlayButton.visibility, "White") ~= nil, "the owner's left click starts picking")
check(near(x(nineC), 0.03 - 11.7), "the remaining group moves up next to the hand")
settle()
local allInArea = true
for _, card in ipairs({three, four, five}) do
	if card.locked or #card.buttons ~= 0 or zoneOf(card) ~= 2 or #card.hiddenFrom ~= 0 then allInArea = false end
end
check(allInArea, "and its cards are ordinary cards in the play area")
onGroupCardClick(three, "White", false)
check(zoneOf(three) == 2, "which no longer act as a group")

-- 26. Taking them back makes them ordinary hand cards; grouping again makes a new group.
onReturnButtonClick(whitePlayer)
settle()
check(zoneOf(three) == 1 and zoneOf(five) == 1 and not three.locked, "taken back, they are ordinary hand cards")
stage("White", {three, four})
onGroupCardClick(nineS, "White", false)
settle()
onGroupButtonClick(whitePlayer)
check(near(x(three), 0.03 - 11.7) and near(x(nineS), x(three)) and near(z(three), -18) and near(z(four), -18.62) and near(z(nineC), -19.24) and near(z(nineS), -19.86), "a group and more cards put in the play area become one new group")
check(zoneOf(five) == 1 and not five.locked, "cards left in hand stay there")

-- 27. Save and load, and collecting.
saved = onSave()
three.buttons = {}
three.hiddenFrom = {}
onLoad(saved)
check(#three.buttons == 1 and three.buttons[1].click_function == "onGroupCardClick" and hiddenFrom(three, "Green"), "groups survive save / load")
onCollectCards()
check(#three.buttons == 0 and #three.hiddenFrom == 0, "collecting lets go of the groups")
onGroupCardClick(three, "White", false)
settle()
check(three.locked, "and forgets them")

print(failures == 0 and "GLOBAL: ALL PASSED" or ("GLOBAL: " .. failures .. " FAILED"))
if failures > 0 then error("test failures") end

-- Hand the Global functions to the tool scripts loaded next.
globalFunctions.getDeckId = getDeckId
globalFunctions.getPilePosition = getPilePosition
globalFunctions.onGuandanPass = onGuandanPass
globalFunctions.onCollectCards = onCollectCards
