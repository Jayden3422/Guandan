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
local selected = {id = 123, name = {en = "The white deck", zh = "白牌"}}
local selector = {call = function(name) return selected end}

onLoad()

-- 1. Dealing: only the selected deck, 27 cards to each seated player.
local deckA = newDeck(ids(123, 108), {-6.2, 1.5, -3.4})
local deckB = newDeck(ids(125, 108), {-3.2, 1.5, 1.9})
objects["9a7e05"] = selector
Time.time = Time.time + 5
dealCards()
runWaits()
check(deckA.dealt.White == 27 and deckA.dealt.Orange == 27 and next(deckB.dealt) == nil, "white selected: only the white deck is dealt, 27 cards each")
check(deckA.shuffled == 1 and self.flips == 1, "the dealt deck is shuffled and the tool flips")
deckA.dealt = {}
Time.time = Time.time + 5
dealCards()
runWaits()
check(deckA.dealt.Green == 27 and next(deckB.dealt) == nil, "the white deck is dealt again the next time")
selected = {id = 125, name = {en = "The black deck", zh = "黑牌"}}
deckA.dealt = {}
Time.time = Time.time + 5
dealCards()
runWaits()
check(deckB.dealt.Green == 27 and next(deckA.dealt) == nil, "black selected: only the black deck is dealt")

-- 2. Dealing when the selected deck is not complete, and without a Deck Selector.
objects = {}
objects["9a7e05"] = selector
newDeck(ids(125, 81), {0, 1, 0})
local other = newDeck(ids(123, 108), {3, 1, 0})
self.flips = 0
Time.time = Time.time + 5
messages = {}
dealCards()
check(self.flips == 0 and #messages == 2 and next(other.dealt) == nil and #waits == 1, "selected deck incomplete: nothing is dealt, the cards are collected first")
runWaits()
runConditions(true)
check(self.flips == 0 and #messages == 3 and next(other.dealt) == nil, "(the black deck cannot be completed: the collection gives up with a message)")
objects["9a7e05"] = nil
Time.time = Time.time + 5
dealCards()
runWaits()
check(other.dealt.White == 27, "without a Deck Selector any complete deck is dealt")

-- 3. Nobody holds cards: one click collects, each deck to its own pile.
objects = {}
messages = {}
smoothMoves = {}
self.flips = 0
groupTravel = 0
Time.time = 50
groupedBadState = false
local partA = newDeck(ids(123, 106), {3, 1, 3})
local looseA1 = newCard("a1", "Two", "Heart", {5, 1, 5}, 12301)
local looseA2 = newCard("a2", "Two", "Heart", {6, 1, -7.5}, 12302)
local idleB = newDeck(ids(125, 108), {-3.2, 1.5, 1.9})
collectCards()
check(#messages == 1, "no confirmation is asked when nobody holds cards, just a notice that collecting started")
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
check(self.flips == 0 and #conditions == 0 and #waits == 1, "complete decks, merged cards gone: a moment to settle")
Time.time = 60
runWaits()
check(partA.shuffled == 1 and idleB.shuffled == 1 and self.flips == 1, "then the decks are shuffled and the tool flips once")
collectCards()
dealCards()
check(#waits == 0 and self.flips == 1 and partA.dealt.White == nil, "right after the flip, clicks on either side are ignored")

-- 4. Players still hold cards: a second click within five seconds is needed.
objects = {}
messages = {}
self.flips = 0
groupedBadState = false
local tableDeck = newDeck(ids(123, 104), {3, 1, 3})
local inHand = newCard("h1", "Two", "Heart", {0.03, 4, -18}, 12301)       -- in White's hand
local inArea = newCard("h2", "Two", "Heart", {0.03, 4, -13}, 12302)       -- in White's play area
local onTable = newCard("h3", "Two", "Heart", {6, 1, -7.5}, 12303)
stackHand("Green")
local stacked = newCard("h4", "Two", "Heart", {0.03, 2.97, 18}, 12304)    -- in Green's hand, then stacked
stackHand("Green")
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
check(#messages == 3, "a second click within five seconds collects")
check(waitsAbovePile(inHand, -11.54) and waitsAbovePile(inArea, -11.54) and waitsAbovePile(onTable, -11.54) and waitsAbovePile(stacked, -11.54), "cards in hands, play areas and stacked hands are taken too")
check(#stacked.buttons == 0 and #stacked.hiddenFrom == 0, "stacked cards lose their button and hiding")
runWaits()
check(tableDeck.getQuantity() == 108 and not groupedBadState and atPile(tableDeck, -11.54), "and all end up in the deck as ordinary cards")
runConditions(false)
runWaits()
check(tableDeck.shuffled == 1 and self.flips == 1, "the deck is shuffled and the tool flips")
local dealt = newCard("h5", "Two", "Heart", {0.03, 2.97, 18}, 12305)
onObjectEnterZone({type = "Hand"}, dealt)
settle()
check(dealt.locked, "Green's hand stays switched to stacked for the next deal")
sortHand("Green")
settle()

-- 5. Not complete in time: a message, no flip, and the tool can be used again.
objects = {}
messages = {}
self.flips = 0
Time.time = 200
local short = newDeck(ids(123, 100), {3, 1, 3})
collectCards()
runWaits()
runConditions(true)
check(self.flips == 0 and short.shuffled == 0 and #messages == 2, "incomplete collection: message, no shuffle, no flip")
collectCards()
check(#waits == 1, "and collecting can be tried again")
runWaits()
runConditions(true)

-- 6. A deck mixing both decks is taken apart, and its cards grouped into one deck per pile.
objects = {}
groupedBadState = false
Time.time = 300
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
Time.time = 400
local grabbed = newCard("g1", "Two", "Heart", {4, 3, 4}, 12507)
grabbed.held_by_color = "White"
collectCards()
runWaits()
check(near(grabbed.getPosition().x, 4) and not grabbed.locked, "a card being held with the pointer is not taken")
runConditions(true)

-- 8. A second deck object of a deck (say, one that fell under the table) is merged into the one on the pile:
--    nothing is copied, the deck on the pile is the one kept.
objects = {}
messages = {}
self.flips = 0
groupedTooClose = false
Time.time = 500
local onPile = newDeck(ids(123, 60), {-11.54, 1.4, -11.77})
local underTable = newDeck(ids(123, 48, 60), {3, -5, 3})
local pileB = newDeck(ids(125, 108), {-8.6, 1.5, -11.77})
collectCards()
runWaits()
check(objects[onPile.guid] == onPile and objects[underTable.guid] == nil, "the deck on the pile is kept, the other merged into it")
check(onPile.getQuantity() == 108 and not groupedTooClose, "with no card copied")
check(near(onPile.getPosition().y, 2) and atPile(onPile, -11.54) and atPile(pileB, -8.6), "the decks sit on their piles")
runConditions(false)
runWaits()
check(onPile.shuffled == 1 and pileB.shuffled == 1 and self.flips == 1, "and get shuffled")

-- 9. Many loose cards and no deck object: the cards wait apart from one another, so none is copied.
objects = {}
groupedTooClose = false
self.flips = 0
Time.time = 600
local loose = {}
for i = 1, 108 do loose[i] = newCard("L" .. i, "Two", "Heart", {i % 7, 1, i % 5}, 12300 + (i % 54)) end
collectCards()
runWaits()
local built = nil
for _, object in pairs(objects) do if object.name == "Deck" then built = object end end
check(built ~= nil and built.getQuantity() == 108 and not groupedTooClose and #getObjects() == 1, "108 loose cards become one deck of 108")
runConditions(false)
runWaits()
check(self.flips == 1, "(and the tool flips)")

-- 10. A deck that somehow has too many cards: a warning instead of a shuffle, and the tool still flips.
objects = {}
messages = {}
self.flips = 0
Time.time = 700
local fat = newDeck(ids(123, 110), {-11.54, 1.4, -11.77})
collectCards()
runWaits()
runConditions(false)
runWaits()
check(fat.shuffled == 0 and self.flips == 1 and #messages == 2 and string.find(messages[2], "多了 2") ~= nil, "a deck with 110 cards is reported, not shuffled")

-- 11. Dealing is ignored while a collection is under way.
objects = {}
self.flips = 0
Time.time = 800
local deckC = newDeck(ids(123, 108), {-11.54, 1.4, -11.77})
objects["9a7e05"] = selector
selected = {id = 123, name = {en = "The white deck", zh = "白牌"}}
collectCards()
dealCards()
check(next(deckC.dealt) == nil, "no deal while collecting")
runWaits()
runConditions(false)
runWaits()
dealCards()
check(next(deckC.dealt) == nil, "nor right after the flip")
Time.time = 802
dealCards()
check(next(deckC.dealt) == nil and #smoothMoves > 0 and deckC.use_gravity, "a second later, dealing works again: the deck first settles on its pile")
runWaits()
check(deckC.dealt.White == 27 and self.flips == 2, "and is dealt a moment later")

-- 12. The tool does not turn over until the merged cards have really vanished; if that is never seen, it carries on
--     once the decks are complete.
objects = {}
self.flips = 0
Time.time = 900
withholdDestroys = true
local keep = newDeck(ids(123, 100), {-11.54, 1.4, -11.77})
for i = 1, 8 do newCard("f" .. i, "Two", "Heart", {2, 1, 2}, 12300 + i) end
collectCards()
runWaits()
check(keep.getQuantity() == 108 and #withheld == 8, "(the deck is complete while eight merged cards are still flying)")
runConditions(false)
check(#conditions == 1 and #waits == 0 and self.flips == 0, "the tool waits for them")
check(releaseDestroys() == 8, "(they arrive)")
runConditions(false)
runWaits()
check(self.flips == 1 and keep.shuffled == 1, "then it finishes")
withholdDestroys = true
objects = {}
self.flips = 0
messages = {}
Time.time = 950
local keep2 = newDeck(ids(123, 100), {-11.54, 1.4, -11.77})
for i = 1, 8 do newCard("g" .. i, "Two", "Heart", {2, 1, 2}, 12300 + i) end
collectCards()
runWaits()
runConditions(true)
check(self.flips == 1 and keep2.shuffled == 1 and #messages == 1, "when the vanishing is never reported but the decks are complete, it finishes on the timeout")
withheld = {}
withholdDestroys = false

-- 13. Deal with the chosen deck not complete: the cards are collected first, then dealt, the tool ending on its collect side.
objects = {}
messages = {}
self.flips = 0
Time.time = 1000
objects["9a7e05"] = selector
selected = {id = 123, name = {en = "The white deck", zh = "白牌"}}
local half = newDeck(ids(123, 60), {-11.54, 1.4, -11.77})
local rest = newDeck(ids(123, 48, 60), {4, 1, 4})
dealCards()
check(#messages == 2 and string.find(messages[1], "先收牌再发") ~= nil and next(half.dealt) == nil, "an incomplete deck is collected first")
runWaits()
runConditions(false)
runWaits()
runWaits()
check(half.getQuantity() == 108 and half.dealt.White == 27 and half.dealt.Orange == 27, "then dealt without another click")
check(self.flips == 1, "and the tool ends on its collect side")

-- 14. Deal while players hold cards: the confirmation applies, and the second click on Deal collects and deals.
objects = {}
messages = {}
self.flips = 0
Time.time = 1100
objects["9a7e05"] = selector
local most = newDeck(ids(123, 107), {-11.54, 1.4, -11.77})
local last = newCard("last", "Two", "Heart", {0.03, 4, -18}, 12353)   -- in White's hand
dealCards()
check(#messages == 2 and most.getQuantity() == 107, "Deal: warned that a player holds cards, nothing collected")
Time.time = 1102
dealCards()
runWaits()
runConditions(false)
runWaits()
runWaits()
check(most.getQuantity() == 108 and most.dealt.Green == 27 and self.flips == 1, "the second click collects the held card too, then deals")

-- 15. A deck under the pile (fallen through the table) is never the one kept, even when it is right below the pile.
objects = {}
self.flips = 0
Time.time = 1200
local sunk = newDeck(ids(123, 60), {-11.54, -6, -11.77})
local good = newDeck(ids(123, 48, 60), {-11.54, 1.4, -11.77})
collectCards()
runWaits()
check(objects[good.guid] == good and objects[sunk.guid] == nil and good.getQuantity() == 108, "the deck on the table is kept, the sunk one merged into it")
runConditions(false)
smoothMoves = {}
runWaits()
check(#smoothMoves == 1 and smoothMoves[1] == good.guid and good.use_gravity, "when done, the deck glides onto its pile, which mends its physics")
objects = {}
Time.time = 1300
local sunkOnly = newDeck(ids(123, 108), {-11.54, -6, -11.77})
collectCards()
runWaits()
runConditions(false)
runWaits()
check(objects[sunkOnly.guid] == sunkOnly and near(sunkOnly.getPosition().y, 2), "a lone deck under the table is brought back up")

print(failures == 0 and "COLLECT: ALL PASSED" or ("COLLECT: " .. failures .. " FAILED"))
if failures > 0 then error("test failures") end
