-- Tests for collect_tool.lua (run after stubs.lua, global.lua, test.lua and collect_tool.lua).

failures = 0
objects = {}
messages = {}
smoothMoves = {}
conditions = {}
waits = {}
frames = {}

local function ids(deckId, count, first)
	local list = {}
	for i = 1, count do list[i] = deckId * 100 + ((i + (first or 0)) % 54) end
	return list
end

-- Whether an object lies face down on the first (white, x = -11.54) or second (black, x = -8.6) pile.
local function atPile(object, x)
	local position = object.getPosition()
	return near(position.x, x) and near(position.z, -11.77) and near(object.getRotation().z, 180)
end

-- Whether a card waits, locked and face down, above a pile.
local function waitsAbovePile(card, x)
	return atPile(card, x) and card.locked and card.getPosition().y > 3.5
end

-- The Deck Selector tool.
local selected = {id = 123, name = "白牌"}
local selector = {call = function(name) return selected end}

onLoad()

-- 1. Dealing: only the selected deck, 27 cards to each seated player.
local deckA = newDeck(ids(123, 108), {-6.2, 1.5, -3.4})
local deckB = newDeck(ids(125, 108), {-3.2, 1.5, 1.9})
objects["9a7e05"] = selector
dealCards()
check(deckA.dealt.White == 27 and deckA.dealt.Orange == 27 and next(deckB.dealt) == nil, "white selected: only the white deck is dealt, 27 cards each")
check(deckA.shuffled == 1 and self.flips == 1, "the dealt deck is shuffled and the tool flips")
deckA.dealt = {}
dealCards()
check(deckA.dealt.Green == 27 and next(deckB.dealt) == nil, "the white deck is dealt again the next time")
selected = {id = 125, name = "黑牌"}
deckA.dealt = {}
dealCards()
check(deckB.dealt.Green == 27 and next(deckA.dealt) == nil, "black selected: only the black deck is dealt")

-- 2. Dealing when the selected deck is not complete, and without a Deck Selector.
objects = {}
objects["9a7e05"] = selector
newDeck(ids(125, 81), {0, 1, 0})
local other = newDeck(ids(123, 108), {3, 1, 0})
self.flips = 0
dealCards()
check(self.flips == 0 and #messages == 1 and next(other.dealt) == nil, "selected deck incomplete: nothing is dealt, a message is shown")
objects["9a7e05"] = nil
dealCards()
check(other.dealt.White == 27, "without a Deck Selector any complete deck is dealt")

-- 3. Nobody holds cards: one click collects, each deck to its own pile.
objects = {}
messages = {}
self.flips = 0
groupTravel = 0
groupedBadState = false
local partA = newDeck(ids(123, 106), {3, 1, 3})
local looseA1 = newCard("a1", "Two", "Heart", {5, 1, 5}, 12301)
local looseA2 = newCard("a2", "Two", "Heart", {6, 1, -7.5}, 12302)
local idleB = newDeck(ids(125, 108), {-3.2, 1.5, 1.9})
collectCards()
check(#messages == 0, "no confirmation is asked when nobody holds cards")
check(waitsAbovePile(looseA1, -11.54) and waitsAbovePile(looseA2, -11.54), "loose cards are first put above their pile, locked and face down")
check(looseA1.getPosition().y ~= looseA2.getPosition().y, "one above the other")
check(near(partA.getPosition().x, 3), "deck objects stay where they are for now")
collectCards()
check(#waits == 1, "clicking again while collecting does nothing")
runWaits()
check(partA.getQuantity() == 108 and objects["a1"] == nil and objects["a2"] == nil, "then everything of a deck is grouped into one deck object")
check(groupTravel < 0.01 and not groupedBadState, "on the pile, as ordinary cards: nothing glides across the table")
check(atPile(partA, -11.54) and partA.use_hands == false and atPile(idleB, -8.6) and idleB.use_hands == false, "each deck ends up on its own pile, face down")
check(#smoothMoves == 0, "nothing is moved smoothly")
runConditions(false)
check(partA.shuffled == 1 and idleB.shuffled == 1 and self.flips == 1 and #conditions == 0, "complete decks are shuffled and the tool flips once")

-- 4. Players still hold cards: a second click within five seconds is needed.
objects = {}
messages = {}
self.flips = 0
groupedBadState = false
local tableDeck = newDeck(ids(123, 104), {3, 1, 3})
local inHand = newCard("h1", "Two", "Heart", {0.03, 4, -18}, 12301)       -- in White's hand
local inArea = newCard("h2", "Two", "Heart", {0.03, 4, -13}, 12302)       -- in White's play area
local onTable = newCard("h3", "Two", "Heart", {6, 1, -7.5}, 12303)
globalFunctions.stackHand({color = "Green"})
local stacked = newCard("h4", "Two", "Heart", {0.03, 2.97, 18}, 12304)    -- in Green's hand, then stacked
globalFunctions.stackHand({color = "Green"})
check(stacked.locked and #stacked.buttons == 1, "(Green's hand is stacked)")
messages = {}
Time.time = 100
collectCards()
check(#messages == 1 and near(inHand.getPosition().z, -18) and near(onTable.getPosition().x, 6) and #waits == 0, "first click: a warning, nothing is collected")
Time.time = 106
collectCards()
check(#messages == 2 and near(inHand.getPosition().z, -18), "a second click after more than five seconds only warns again")
Time.time = 109
collectCards()
check(#messages == 2, "a second click within five seconds collects")
check(waitsAbovePile(inHand, -11.54) and waitsAbovePile(inArea, -11.54) and waitsAbovePile(onTable, -11.54) and waitsAbovePile(stacked, -11.54), "cards in hands, play areas and stacked hands are taken too")
check(#stacked.buttons == 0 and #stacked.hiddenFrom == 0, "stacked cards lose their button and hiding")
runWaits()
check(tableDeck.getQuantity() == 108 and not groupedBadState and atPile(tableDeck, -11.54), "and all end up in the deck as ordinary cards")
runConditions(false)
check(tableDeck.shuffled == 1 and self.flips == 1, "the deck is shuffled and the tool flips")
local dealt = newCard("h5", "Two", "Heart", {0.03, 2.97, 18}, 12305)
onObjectEnterZone({type = "Hand"}, dealt)
settle()
check(dealt.locked, "Green's hand stays switched to stacked for the next deal")
globalFunctions.unstackHand({color = "Green"})
settle()

-- 5. Not complete in time: a message, no flip, and the tool can be used again.
objects = {}
messages = {}
self.flips = 0
local short = newDeck(ids(123, 100), {3, 1, 3})
collectCards()
runWaits()
runConditions(true)
check(self.flips == 0 and short.shuffled == 0 and #messages == 1, "incomplete collection: message, no shuffle, no flip")
collectCards()
check(#waits == 1, "and collecting can be tried again")
runWaits()
runConditions(true)

-- 6. A deck mixing both decks is taken apart, and its cards grouped into one deck per pile.
objects = {}
groupedBadState = false
local mixed = newDeck({12301, 12501, 12302, 12502, 12303}, {2, 1, 2})
collectCards()
check(objects[mixed.guid] == nil and #getObjects() == 5, "a mixed deck is first taken apart into loose cards")
runWaits()
local first, second, others = 0, 0, 0
for _, object in pairs(objects) do
	if object.name == "Deck" and object.use_hands == false and atPile(object, -11.54) and getDeckId({object = object}) == 123 then
		first = object.getQuantity()
	elseif object.name == "Deck" and object.use_hands == false and atPile(object, -8.6) and getDeckId({object = object}) == 125 then
		second = object.getQuantity()
	else
		others = others + 1
	end
end
check(first == 3 and second == 2 and others == 0 and not groupedBadState, "and its cards are then grouped into one deck per pile")
runConditions(true)

-- 7. A card a player is holding with the pointer is left alone.
objects = {}
local grabbed = newCard("g1", "Two", "Heart", {4, 3, 4}, 12507)
grabbed.held_by_color = "White"
collectCards()
runWaits()
check(near(grabbed.getPosition().x, 4) and not grabbed.locked, "a card being held with the pointer is not taken")
runConditions(true)

print(failures == 0 and "COLLECT: ALL PASSED" or ("COLLECT: " .. failures .. " FAILED"))
if failures > 0 then error("test failures") end
