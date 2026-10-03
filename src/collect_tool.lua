-- Collect Cards / Deal Cards tool
-- One side collects every card, each deck into its own pile.  The other side deals one deck.
-- The pile of each deck is configured in the Global script (deckPilePositions).
-- The deck that gets dealt is chosen with the Deck Selector tool.

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

-- True while a collection is under way.
local collecting = false

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
-- and clear of a deck object lying on the pile.  counts keeps how many were placed so far, by deck ID.
function nextPilePosition(card, counts)

	local deckId = Global.call("getDeckId", {object = card}) or 0
	local position = Global.call("getPilePosition", {object = card})

	counts[deckId] = (counts[deckId] or 0) + 1
	position.y = position.y + 1.5 + 0.02 * counts[deckId]

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

	local counts = {}

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
				object.setPosition(nextPilePosition(object, counts))

			end

		end
	end

end


-- Second step of collecting:  group the cards and deck objects of each deck into one deck object on its pile.
function gatherDecks()

	-- The cards and deck objects of each deck, by deck ID.
	local groups = {}
	local counts = {}

	for i, object in pairs(getObjects()) do
		if (object.type == "Card" or object.name == "Deck") and object.held_by_color == nil then
			local deckId = Global.call("getDeckId", {object = object})
			if deckId ~= nil then

				-- Everything is brought to the pile first, so that grouping only moves cards a short way, away from any hand zone.
				if object.type == "Card" then
					object.setRotation(Vector(0, 0, 180))
					object.setPosition(nextPilePosition(object, counts))
					-- The cards go into the deck as they are now: unlocked and able to be held in a hand, ready to be dealt.
					object.setLock(false)
				else
					-- A deck must not be caught by a hand zone.
					object.use_hands = false
					object.setRotation(Vector(0, 0, 180))
					object.setPosition(Global.call("getPilePosition", {object = object}))
				end

				groups[deckId] = groups[deckId] or {}
				table.insert(groups[deckId], object)

			end
		end
	end

	for deckId, objects in pairs(groups) do

		local pile = objects[1]
		if #objects > 1 then
			pile = group(objects)[1]
		end

		-- A deck object newly made of loose cards appears where they were: put it on the pile as well.
		if pile ~= nil and pile.name == "Deck" then
			pile.use_hands = false
			pile.setRotation(Vector(0, 0, 180))
			pile.setPosition(Global.call("getPilePosition", {object = pile}))
		end

	end

end


-- True once every card has ended up in a complete deck.
function allCollected()

	local decks = 0

	for i, object in pairs(getObjects()) do
		if object.type == "Card" then
			return false
		end
		if object.name == "Deck" then
			if object.getQuantity() ~= deckSize then
				return false
			end
			decks = decks + 1
		end
	end

	return decks > 0

end


function collectCards()

	if collecting then
		return
	end

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
		broadcastToAll("还有玩家手里有牌：" .. confirmTimeout .. " 秒内再点一次，连手里的牌一起收走", {1,1,1})
		return
	end

	confirmUntil = nil
	collecting = true

	releaseCards()
	Wait.time(gatherDecks, releaseTime)

	-- Once the cards have formed complete decks: shuffle them and turn the tool to its deal side.
	Wait.condition(
		function()
			collecting = false
			for i, object in pairs(getObjects()) do
				if object.name == "Deck" and object.getQuantity() == deckSize then
					object.shuffle()
				end
			end
			self.flip()
		end,
		allCollected,
		collectTimeout,
		function()
			collecting = false
			broadcastToAll("牌没有收齐成整副（可能有牌被拿着或缺牌），处理后再点一次", {1,1,1})
		end
	)

end


function dealCards()

	-- The deck chosen with the Deck Selector tool:  {id = , name = }
	local selected = nil
	local selector = getObjectFromGUID(deckSelectorGuid)
	if selector ~= nil then
		selected = selector.call("getSelectedDeck")
	end

	-- Find that deck, complete.
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
		broadcastToAll((selected and selected.name or "牌") .. "还没有收齐成一整副，先收牌", {1,1,1})
		return
	end

	deck.shuffle()
	for _,playerColor in ipairs(getSeatedPlayers()) do
		deck.deal(dealCount, playerColor)
	end

	self.flip()

end
