-- Collect Cards / Deal Cards tool
-- One side collects every card that is not in a hand, each deck into its own pile.  The other side deals one deck.
-- The pile of each deck is configured in the Global script (deckPilePositions).
-- The deck that gets dealt is chosen with the Deck Selector tool.

-- The Deck Selector tool.  Without it, any complete deck is dealt.
deckSelectorGuid = "9a7e05"

-- Number of cards in a complete deck, and how many each player is dealt.
deckSize = 108
dealCount = 27

-- How long to wait for the collected cards to form complete decks before giving up.
collectTimeout = 10

-- True while a collection is waiting for the cards to arrive.
local collecting = false


function onLoad()

	local button = {}
	button.label = "" button.height = 600 button.width = 600 button.font_size = 500 button.position = {0, 0.15, 0} button.rotation = {0, 0, 0} button.click_function = 'dealCards' button.function_owner = self self.createButton(button)
	button.label = "" button.height = 600 button.width = 600 button.font_size = 500 button.position = {0, 0.10, 0} button.rotation = {0, 0, 180} button.click_function = 'collectCards' button.function_owner = self self.createButton(button)

end


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


-- Send a card or a deck, face down, to the pile of the deck it belongs to.
function sendToPile(object)

	-- A deck must not be caught by the hand zones it passes through.
	if object.name == "Deck" then
		object.use_hands = false
	end

	object.setRotationSmooth(Vector(0, 0, 180), false, true)
	object.setPositionSmooth(Global.call("getPilePosition", {object = object}), false, true)

end


-- A deck object that mixes cards of several decks is taken apart into loose cards, stacked above where it lies.
function splitDeck(deck)

	local position = deck.getPosition()

	-- Taking the second to last card turns the deck into its last card.
	for i = 1, deck.getQuantity() - 1 do
		deck.takeObject({position = {position.x, position.y + 1 + 0.2 * i, position.z}, smooth = false})
	end

end


-- Gather everything that is not in a hand into one deck object per deck, and send those to their piles.
-- The cards are grouped where they lie instead of travelling one by one:
-- a loose card gliding across the table is caught by any play area it passes through.
function gatherDecks()

	-- The cards and deck objects of each deck, by deck ID.
	local groups = {}

	for i, object in pairs(getObjects()) do
		if (object.type == "Card" or object.name == "Deck") and not isInHand(object) then  --only do this on cards, and leave the cards held in a player's Hand alone
			local deckId = Global.call("getDeckId", {object = object})
			if deckId ~= nil then
				groups[deckId] = groups[deckId] or {}
				table.insert(groups[deckId], object)
			end
		end
	end

	for deckId, objects in pairs(groups) do

		-- Gather around a deck object if there is one, else around the first card.
		local anchor = objects[1]
		for _, object in ipairs(objects) do
			if object.name == "Deck" then
				anchor = object
				break
			end
		end

		-- Put the loose cards right above it, so they only have a short way to go when grouped.
		local position = anchor.getPosition()
		for i, object in ipairs(objects) do
			if object.type == "Card" and object.guid ~= anchor.guid then
				object.setPosition({position.x, position.y + 1 + 0.02 * i, position.z})
			end
		end

		local pile = anchor
		if #objects > 1 then
			pile = group(objects)[1]
		end

		if pile ~= nil then
			sendToPile(pile)
		end

	end

end


-- True once everything that is not in a hand has ended up in complete decks.
function allCollected()

	local decks = 0

	for i, object in pairs(getObjects()) do
		if not isInHand(object) then
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
	end

	return decks > 0

end


function collectCards()

	if collecting then
		return
	end

	-- Take apart the deck objects that mix several decks, and give their cards a moment to appear.
	local split = false

	for i, object in pairs(getObjects()) do
		if object.name == "Deck" and not isInHand(object) and Global.call("getDeckId", {object = object}) == nil then
			splitDeck(object)
			split = true
		end
	end

	if split then
		Wait.time(gatherDecks, 1)
	else
		gatherDecks()
	end

	collecting = true

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
			broadcastToAll("牌还没收齐（可能还有牌在玩家手里），收齐后再点一次", {1,1,1})
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
