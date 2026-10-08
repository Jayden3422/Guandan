-- Collect Cards / Deal Cards tool
-- One side collects every card, each deck into its own pile.  The other side deals one deck.
-- The pile of each deck is configured in the Global script (deckPilePositions).
-- The deck that gets dealt is chosen with the Deck Selector tool.

-- Messages hold the text in both languages, marked with the game's language codes:
-- each player sees the part for the language of their own game.

-- The Deck Selector tool.  Without it, any complete deck is dealt.
deckSelectorGuid = "9a7e05"

-- Number of cards in a complete deck, and how many each player is dealt.
deckSize = 108
dealCount = 27

-- While players still hold cards, collecting takes a second click within this many seconds.
confirmTimeout = 5

-- How long the hand zones get to let go of their cards before the cards are grouped into decks.
releaseTime = 0.6

-- How long to wait for the collected cards to form complete decks before giving up.
collectTimeout = 10

-- Merged cards fly into their deck and vanish on arrival.  Once the last one is gone, this much longer is
-- allowed for the deck to settle before it is shuffled and the tool turns over.
settleTime = 0.5

-- After the tool turns over, clicks on it are ignored for this long, so a few quick clicks do not deal as well.
clickCooldown = 1

-- Where the cards wait above their pile before they are grouped:  this far above the pile point, this far apart.
-- NOTE:  An object that is already within 0.025 of the spot it is merged into is not removed by the game,
-- and its cards end up twice.  So nothing waiting to be merged may share a spot with anything else.
cardsHeight = 1.5
cardSpacing = 0.05
-- Deck objects other than the one on the pile wait above the cards, this far apart.
decksHeight = 7.5
deckSpacing = 0.3

-- Objects lower than this are under the table.
tableLevel = 0.5

-- Before a deck is dealt, it is put back on its pile with a short glide, which also restores the physics of a deck
-- that was left with no collision or gravity (a deck that fell through the table, say).  The deal follows this much later.
settleDelay = 1

-- True while a collection is under way.
local collecting = false

-- Until when clicks on the tool are ignored.
local busyUntil = nil

-- How many cards of each deck have been put above its pile during this collection, by deck ID.
local placed = {}

-- How many merged objects are still flying into their deck.  Each one vanishes on arrival.
local mergesPending = 0

-- What to do once the collection is done:  turn the tool over (started from its collect side), deal (started from Deal).
local flipWhenDone = true
local dealWhenDone = false

-- Until when a second click confirms collecting the cards the players still hold.
local confirmUntil = nil


function onLoad()

	local button = {}
	button.label = "" button.height = 600 button.width = 600 button.font_size = 500 button.position = {0, 0.15, 0} button.rotation = {0, 0, 0} button.click_function = 'dealCards' button.function_owner = self self.createButton(button)
	button.label = "" button.height = 600 button.width = 600 button.font_size = 500 button.position = {0, 0.10, 0} button.rotation = {0, 0, 180} button.click_function = 'collectCards' button.function_owner = self self.createButton(button)

end


-- Whether a player holds the card:  in their hand, in their play area, or in their stacked hand.
function isInHand(object)

	-- A stacked hand: its cards are locked in place by the Global script instead of being held by a Hand zone.
	if object.type == "Card" and object.getLock() then
		return true
	end

	for j, zone in pairs(object.getZones()) do  --get every zone that the object is in
		if zone.type == "Hand" then  --and check if it's a Hand type zone, ie held in a player's Hand
			return true
		end
	end

	return false

end


-- Where the next card of a deck waits to be grouped:  above the deck's pile, each one a little higher than the last
-- and clear of a deck object lying on the pile.
function nextPilePosition(card)

	local deckId = Global.call("getDeckId", {object = card}) or 0
	local position = Global.call("getPilePosition", {object = card})

	placed[deckId] = (placed[deckId] or 0) + 1
	position.y = position.y + cardsHeight + cardSpacing * placed[deckId]

	return position

end


-- A deck object that mixes cards of several decks is taken apart into loose cards, stacked above where it lies.
function splitDeck(deck)

	local position = deck.getPosition()

	-- Taking the second to last card turns the deck into its last card.
	for i = 1, deck.getQuantity() - 1 do
		deck.takeObject({position = {position.x, position.y + 1 + 0.2 * i, position.z}, smooth = false})
	end

end


-- First step of collecting:  take every card away from the players and put it above its deck's pile.
-- Cards are teleported instead of gliding across the table, where any hand zone they pass through would catch them.
function releaseCards()

	-- Stacked hands, card picking and the plays on the table all end here.
	Global.call("onCollectCards")

	placed = {}

	for i, object in pairs(getObjects()) do
		if object.held_by_color == nil then

			if object.name == "Deck" then

				if Global.call("getDeckId", {object = object}) == nil then
					splitDeck(object)
				end

			elseif object.type == "Card" then

				-- A locked card is let go by the hand zone holding it, and stays where it is put: it neither falls nor merges.
				object.setLock(true)
				object.setRotation(Vector(0, 0, 180))
				object.setPosition(nextPilePosition(object))

			end

		end
	end

end


-- Second step of collecting:  group the cards and deck objects of each deck into one deck object on its pile.
function gatherDecks()

	-- The cards and deck objects of each deck, by deck ID.
	local groups = {}

	for i, object in pairs(getObjects()) do
		if (object.type == "Card" or object.name == "Deck") and object.held_by_color == nil then
			local deckId = Global.call("getDeckId", {object = object})
			if deckId ~= nil then
				groups[deckId] = groups[deckId] or {}
				table.insert(groups[deckId], object)
			end
		end
	end

	for deckId, objects in pairs(groups) do

		local pilePosition = Global.call("getPilePosition", {object = objects[1]})

		-- The deck object everything else is merged into:  the one lying on the pile, else one lying on the table,
		-- else any.  A deck under the table or in the air is in no state to keep.
		local pile = nil
		local pileScore = -1
		for _, object in ipairs(objects) do
			if object.name == "Deck" then
				local position = object.getPosition()
				local dx = position.x - pilePosition.x
				local dz = position.z - pilePosition.z
				local score = 0
				if position.y > tableLevel then
					score = 1
					if dx * dx + dz * dz < 1 then
						score = 2
					end
				end
				if score > pileScore then
					pile = object
					pileScore = score
				end
			end
		end

		-- Everything is brought above the pile first, so that grouping only moves cards a short way, away from any hand zone.
		-- Each object gets a spot of its own, clear of the one it is merged into (see cardSpacing).
		local ordered = {}
		local decks = 0

		-- The deck kept goes to the pile point: being the one merged into, its old spot does not matter.
		if pile ~= nil then
			pile.use_hands = false
			pile.setRotation(Vector(0, 0, 180))
			pile.setPosition(pilePosition)
			table.insert(ordered, pile)
		end

		for _, object in ipairs(objects) do
			if object.type == "Card" then
				object.setRotation(Vector(0, 0, 180))
				-- The cards taken from the players are above the pile already (locked); the others are put there now.
				if not object.getLock() then
					object.setPosition(nextPilePosition(object))
				end
				-- The cards go into the deck as they are now: unlocked and able to be held in a hand, ready to be dealt.
				object.setLock(false)
				table.insert(ordered, object)
			elseif object.guid ~= pile.guid then
				object.use_hands = false
				object.setRotation(Vector(0, 0, 180))
				object.setPosition(Vector(pilePosition.x, pilePosition.y + decksHeight + deckSpacing * decks, pilePosition.z))
				decks = decks + 1
				table.insert(ordered, object)
			end
		end

		local result = ordered[1]
		if #ordered > 1 then
			-- The first deck object in the list is the one the game keeps; every other object vanishes once it has flown in.
			mergesPending = mergesPending + #ordered - 1
			result = group(ordered)[1]
		end

		-- A deck object newly made of loose cards appears where they were: put it on the pile as well.
		if result ~= nil and result.name == "Deck" then
			result.use_hands = false
			result.setRotation(Vector(0, 0, 180))
			result.setPosition(pilePosition)
		end

	end

end


-- True once every card has ended up in a deck of full size.  A deck with too many cards counts as settled too,
-- so that finishing can report it.
function allCollected()

	local decks = 0

	for i, object in pairs(getObjects()) do
		if object.type == "Card" then
			return false
		end
		if object.name == "Deck" then
			if object.getQuantity() < deckSize then
				return false
			end
			decks = decks + 1
		end
	end

	return decks > 0

end


-- A merged object has flown into its deck and is gone.
function onObjectDestroy(object)

	if collecting and mergesPending > 0 then
		mergesPending = mergesPending - 1
	end

end


-- True once the merged objects have all flown in.
function allMerged()

	return mergesPending == 0 and allCollected()

end


-- Put a deck on its pile with a short glide.  When the glide ends the game switches the deck's collision back on,
-- and gravity is switched on here: this mends a deck that was left without either.
function settleDeck(deck)

	deck.use_hands = false
	deck.use_gravity = true
	deck.setRotationSmooth(Vector(0, 0, 180), false, true)
	deck.setPositionSmooth(Global.call("getPilePosition", {object = deck}), false, true)

end


-- Last step of collecting:  shuffle the complete decks, then turn the tool to its deal side or deal.
function finishCollecting()

	collecting = false
	busyUntil = Time.time + clickCooldown

	for i, object in pairs(getObjects()) do
		if object.name == "Deck" then
			local extra = object.getQuantity() - deckSize
			if extra > 0 then
				broadcastToAll("{en}A deck has " .. extra .. " cards too many (" .. object.getQuantity() .. " in all): please check it{zh}有一堆牌多了 " .. extra .. " 张（共 " .. object.getQuantity() .. " 张），请检查", {1,1,1})
			elseif extra == 0 then
				object.shuffle()
			end
			settleDeck(object)
		end
	end

	if flipWhenDone then
		self.flip()
	end

	if dealWhenDone then
		dealWhenDone = false
		dealSelectedDeck()
	end

end


-- Collect every card.  Called from the tool's collect side, and by dealCards when the deck to deal is not complete.
function collectCards()

	if collecting or (busyUntil ~= nil and Time.time < busyUntil) then
		return
	end

	flipWhenDone = true
	startCollecting()

end


function startCollecting()

	-- Taking the cards the players still hold ends their round: ask for a second click first.
	local held = false
	for i, object in pairs(getObjects()) do
		if object.type == "Card" and isInHand(object) then
			held = true
			break
		end
	end

	if held and (confirmUntil == nil or Time.time > confirmUntil) then
		confirmUntil = Time.time + confirmTimeout
		broadcastToAll("{en}Some players still hold cards: click again within " .. confirmTimeout .. " seconds to collect those too{zh}还有玩家手里有牌：" .. confirmTimeout .. " 秒内再点一次，连手里的牌一起收走", {1,1,1})
		return
	end

	confirmUntil = nil
	collecting = true
	mergesPending = 0
	broadcastToAll("{en}Collecting the cards...{zh}正在收牌…", {1,1,1})

	releaseCards()
	Wait.time(gatherDecks, releaseTime)

	-- Once the cards have formed complete decks and the merged ones have flown in, finish.
	Wait.condition(
		function()
			Wait.time(finishCollecting, settleTime)
		end,
		allMerged,
		collectTimeout,
		function()
			-- The decks are complete but the vanishing of the merged objects was not seen: carry on anyway.
			if allCollected() then
				finishCollecting()
			else
				collecting = false
				dealWhenDone = false
				broadcastToAll("{en}The cards did not form complete decks (a card may be held or missing): sort that out and click again{zh}牌没有收齐成整副（可能有牌被拿着或缺牌），处理后再点一次", {1,1,1})
			end
		end
	)

end


-- Deal the deck chosen with the Deck Selector tool.  If it is not complete, collect the cards first, then deal.
function dealCards()

	if collecting or (busyUntil ~= nil and Time.time < busyUntil) then
		return
	end

	if dealSelectedDeck() then
		return
	end

	local selected = selectedDeck()
	broadcastToAll("{en}" .. (selected and selected.name.en or "The deck") .. " is not complete: collecting the cards first{zh}" .. (selected and selected.name.zh or "牌") .. "不是完整的一副，先收牌再发", {1,1,1})

	-- The tool stays on its deal side; the deal follows the collection.
	flipWhenDone = false
	dealWhenDone = true
	startCollecting()

end


-- The deck chosen with the Deck Selector tool:  {id = , name = {en = , zh = }}, or nil without the tool.
function selectedDeck()

	local selector = getObjectFromGUID(deckSelectorGuid)

	if selector == nil then
		return nil
	end

	return selector.call("getSelectedDeck")

end


-- Deal the chosen deck if it is complete, and turn the tool to its collect side.  Returns whether a deck was found.
-- The deck first settles on its pile; the deal follows a moment later.
function dealSelectedDeck()

	local selected = selectedDeck()
	local deck = nil

	for i, object in pairs(getObjects()) do
		if deck == nil and object.name == "Deck" and object.getQuantity() == deckSize then
			local id = Global.call("getDeckId", {object = object})
			if id ~= nil and (selected == nil or id == selected.id) then
				deck = object
			end
		end
	end

	if deck == nil then
		return false
	end

	settleDeck(deck)
	busyUntil = Time.time + settleDelay + clickCooldown

	Wait.time(function()
		deck.shuffle()
		for _,playerColor in ipairs(getSeatedPlayers()) do
			deck.deal(dealCount, playerColor)
		end
		self.flip()
	end, settleDelay)

	return true

end
