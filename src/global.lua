--[[ 掼蛋 Guandan - Global script ]]

--  ======================================================================
--						Configuration
--  ======================================================================

-- The scripting hotkeys (i.e. Numpad #).
-- sortHotKey:  sorts the hand in a row, the other way round each time (same as the "正序" / "倒序" button).
-- playHotKey:  starts picking cards, then plays the cards in the play area (same as the "选牌" / "出牌" button).
-- returnHotKey:  takes the cards in the play area back in hand (same as the "收回" button).
-- stackHotKey:  stacks the hand in columns, one per card number (same as the "竖摞" button).
-- groupHotKey:  turns the cards in the play area into a group (same as the "理牌" button).
sortHotKey = 1
playHotKey = 2
returnHotKey = 3
stackHotKey = 4
groupHotKey = 5

-- Groups:  columns of cards the player put together, to the left of the hand zone.
-- The gap between the hand zone and the first group, and between one group and the next.
groupGap = 0.6
groupSpacing = 0.3

-- The stacked hand:  one column per card number, laid out where the hand is.
-- How far each card of a column is shifted towards the player, leaving the top of the card above it visible.
stackRowStep = 0.62
-- Columns are spaced a full card apart, and squeezed together to fit the width of the hand zone.
stackColumnPitchMax = 2.3
cardWidth = 2.2
-- How much higher each column and each card of a column floats, so that overlapping cards never share a height.
stackColumnLift = 0.013
stackRowLift = 0.03
-- Size of the invisible button put on each stacked card, which cannot be picked up but can be clicked.
stackButtonWidth = 1050
stackButtonHeight = 1500

-- Each player owns two hand zones: 1 is the hand, 2 is the play area in front of it.
playAreaHandIndex = 2

-- Height of the outline drawn on the table under each play area.
playAreaOutlineHeight = 1.0

-- How far from the hand zone (towards the table center) played cards are laid out.
playDistance = 10.5

-- Height the played cards are dropped from.
playHeight = 1.6

-- A row of played cards holds at most this many; more cards are split over several rows, so that a big play
-- stays in front of its player instead of reaching the neighbours' hand zones and play areas.
playRowSize = 10
-- How far apart the rows are.  NOTE:  Cards right above one another stick together below 1.5.
playRowStep = 1.6

-- Played cards are spaced a full card apart, and squeezed together once the row gets wider than this.
playRowWidth = 12
cardPitchMax = 2.3
-- NOTE:  Cards closer than ~1.13 stick together (and merge into a deck below 0.5), so don't go lower than this.
cardPitchMin = 1.25

-- Where the cards of each deck are collected, by deck ID (the card IDs without their last two digits).
-- Used by the Collect Cards tool, and for a player's previous play once it is no longer on top.
deckPilePositions = {
	[123] = {-11.54, 2, -11.77},
	[125] = {-8.6, 2, -11.77},
}
-- Cards of any other deck go here.
defaultPilePosition = {-11.54, 2, -11.77}

-- Order of played cards from left to right.  Values are labeled in the card Name, suits in the card Description.
refCardOrder = {"Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King", "Ace", "Joker", }
refSuitOrder = {"Heart", "Club", "Diamond", "Spade", "BW", "Color", }

--  ======================================================================
--						End Configuration
--  ======================================================================

local refCardOrderIndex = {}
for k, v in pairs(refCardOrder) do
	refCardOrderIndex[v] = k
end

local refSuitOrderIndex = {}
for k, v in pairs(refSuitOrder) do
	refSuitOrderIndex[v] = k
end

-- Table of all valid player colors.
playerColorList = {'White', 'Brown', 'Red', 'Orange', 'Yellow', 'Green', 'Teal', 'Blue', 'Purple', 'Pink', }

-- Every color that can see the on-screen buttons.
local uiColorList = {'Grey', 'Black', }
for _, player_color in ipairs(playerColorList) do
	table.insert(uiColorList, player_color)
end

-- The cards each player currently has on the table, by player color:  {guids = {...}, x = , z = , radius = }
local lastPlay = {}

-- The players who are picking cards, by player color.  While picking, clicking a card moves it between hand and play area.
local picking = {}

-- The hand zone each clicked card is on its way to, by card GUID.
local destinations = {}

-- The players whose next sort is from high to low, by player color.  Sorting goes the other way round each time.
local sortDescending = {}

-- The players whose hand is stacked in columns, by player color:  {guids = {[guid] = true, ...}}
-- Stacked cards are locked in place by the script instead of being held by the hand zone.
local stacks = {}

-- The groups each player put together, by player color:  a list of {guids = {guid, ...}}, nearest the hand first.
-- Their cards are locked in place like stacked cards.
local groups = {}


function onLoad(saved_data)

	if saved_data ~= nil and saved_data ~= "" then
		local data = JSON.decode(saved_data)
		if data ~= nil and data.lastPlay ~= nil then
			lastPlay = data.lastPlay
		end
		if data ~= nil and data.stacks ~= nil then
			stacks = data.stacks
		end
		if data ~= nil and data.groups ~= nil then
			groups = data.groups
		end
	end

	drawPlayAreaOutlines()

	-- Buttons and hiding are not part of a save: put them back on the stacked and grouped cards.
	local function restore(player_color, guid, click_function)
		local card = getObjectFromGUID(guid)
		if card ~= nil then
			card.clearButtons()
			stackCard(player_color, card, click_function)
		end
	end

	for player_color, stack in pairs(stacks) do
		for guid in pairs(stack.guids) do
			restore(player_color, guid)
		end
		layoutStack(player_color)
	end

	for player_color, playerGroups in pairs(groups) do
		for _, group in ipairs(playerGroups) do
			for _, guid in ipairs(group.guids) do
				restore(player_color, guid, "onGroupCardClick")
			end
		end
		layoutGroups(player_color)
	end

end


function onSave()

	return JSON.encode({lastPlay = lastPlay, stacks = stacks, groups = groups})

end


-- Hand zones are invisible, so outline every play area on the table in its player's color.
function drawPlayAreaOutlines()

	local lines = {}

	for _, player_color in ipairs(playerColorList) do

		local player = Player[player_color]

		if player.getHandCount() >= playAreaHandIndex then

			local area = player.getHandTransform(playAreaHandIndex)
			local center = Vector(area.position.x, playAreaOutlineHeight, area.position.z)
			local halfWidth = Vector(area.right.x, 0, area.right.z):normalized() * (area.scale.x / 2)
			local halfDepth = Vector(area.forward.x, 0, area.forward.z):normalized() * (area.scale.z / 2)

			table.insert(lines, {
				points = {
					center - halfWidth - halfDepth,
					center + halfWidth - halfDepth,
					center + halfWidth + halfDepth,
					center - halfWidth + halfDepth,
				},
				color = stringColorToRGB(player_color),
				thickness = 0.08,
				loop = true,
			})

		end

	end

	Global.setVectorLines(lines)

end


-- Support scripting hotkeys NumPad 2 and 3.
function onScriptingButtonDown(index, player_color)

	if index == sortHotKey then
		sortHand(player_color)
	elseif index == playHotKey then
		if picking[player_color] then
			playFromPlayArea(player_color)
		else
			startPicking(player_color)
		end
	elseif index == returnHotKey then
		stopPicking(player_color)
		returnPlayAreaToHand(player_color)
	elseif index == stackHotKey then
		stackHand(player_color)
	elseif index == groupHotKey then
		groupPlayArea(player_color)
	end

end


-- The on-screen "选牌" button, shown to the players who are not picking cards.
function onPickButtonClick(player)

	startPicking(player.color)

end


-- The on-screen "出牌" button, shown to the players who are picking cards.
function onPlayButtonClick(player)

	playFromPlayArea(player.color)

end


-- The on-screen "收回" button.
function onReturnButtonClick(player)

	stopPicking(player.color)
	returnPlayAreaToHand(player.color)

end


-- The on-screen "正序" and "倒序" buttons:  the one a player sees says which way their hand is sorted next.
function onSortButtonClick(player)

	sortHand(player.color)

end


-- The on-screen "竖摞" button.
function onStackButtonClick(player)

	stackHand(player.color)

end


-- The on-screen "理牌" button.
function onGroupButtonClick(player)

	groupPlayArea(player.color)

end


function startPicking(player_color, quiet)

	-- Spectators have no hand zones.
	if getPlayAreaCards(player_color) == nil then
		return
	end

	picking[player_color] = true
	updateButtons()

	if not quiet then
		broadcastToColor("选牌中：点手牌放进出牌区，点出牌区里的牌放回手牌", player_color, {1,1,1})
	end

end


function stopPicking(player_color)

	if picking[player_color] then
		picking[player_color] = nil
		updateButtons()
	end

end


-- Show "出牌" to the players who are picking cards, and "选牌" to everyone else.
function updateButtons()

	-- Two buttons share one spot:  the second one is shown to the players listed in switched, the first one to everyone else.
	local function showPair(firstButton, secondButton, switched)

		local switchedColors = {}
		local otherColors = {}

		for _, player_color in ipairs(uiColorList) do
			if switched[player_color] then
				table.insert(switchedColors, player_color)
			else
				table.insert(otherColors, player_color)
			end
		end

		UI.setAttributes(secondButton, {active = #switchedColors > 0 and "true" or "false", visibility = table.concat(switchedColors, "|")})
		UI.setAttributes(firstButton, {visibility = #switchedColors > 0 and table.concat(otherColors, "|") or ""})

	end

	-- "出牌" for the players who are picking cards, "选牌" for the others.
	showPair("guandanPickButton", "guandanPlayButton", picking)

	-- "倒序" for the players whose next sort is descending, "正序" for the others.
	showPair("guandanSortButton", "guandanSortDescendingButton", sortDescending)

end


-- While a player is picking cards, picking up one of their own cards moves it to the other zone instead:
-- from the hand to the play area, or from the play area back to the hand.
function onPlayerAction(player, action, targets)

	if action ~= Player.Action.PickUp or not picking[player.color] then
		return true
	end

	local player_color = player.color
	local moves = {}

	for _, object in ipairs(targets) do
		if object.type == "Card" then
			local handIndex = getHandIndexOf(player_color, object)
			if handIndex == 1 then
				table.insert(moves, {guid = object.guid, handIndex = playAreaHandIndex})
			elseif handIndex == playAreaHandIndex then
				table.insert(moves, {guid = object.guid, handIndex = 1})
			end
		end
	end

	if #moves == 0 then
		return true
	end

	-- Move the cards once the game is done handling the click.
	Wait.frames(function()
		for _, move in ipairs(moves) do
			sendToHandZone(player_color, move.guid, move.handIndex, 3)
		end
		sortPlayAreasSoon()
	end, 1)

	-- Keep the cards from being picked up.
	return false

end


-- Which of the player's hand zones holds the object:  1 for the hand, 2 for the play area, nil for neither.
function getHandIndexOf(player_color, object)

	local player = Player[player_color]

	for handIndex = 1, player.getHandCount() do
		for _, handObject in ipairs(player.getHandObjects(handIndex)) do
			if handObject.guid == object.guid then
				return handIndex
			end
		end
	end

	return nil

end


-- Teleport a card to the right end of one of the player's hand zones.
-- The zone it leaves may pull it back before it is gone, so check a moment later and send it again.
function sendToHandZone(player_color, guid, handIndex, attempts)

	local card = getObjectFromGUID(guid)

	if card == nil then
		return
	end

	local zone = Player[player_color].getHandTransform(handIndex)
	local right = Vector(zone.right.x, 0, zone.right.z):normalized()

	card.setPosition(Vector(zone.position.x, zone.position.y, zone.position.z) + right * (zone.scale.x / 2 - 0.3))
	destinations[guid] = handIndex

	if attempts <= 1 then
		return
	end

	Wait.time(function()

		local card = getObjectFromGUID(guid)

		-- Leave the card alone if it was sent somewhere else in the meantime, or has joined the stacked hand.
		if card ~= nil and destinations[guid] == handIndex and card.held_by_color == nil and not card.getLock() and getHandIndexOf(player_color, card) ~= handIndex then
			sendToHandZone(player_color, guid, handIndex, attempts - 1)
		end

	end, 0.5)

end


-- Cards dropped in a play area are put in order.
function onObjectDrop(player_color, object)

	if object.type == "Card" then
		sortPlayAreasSoon()
	end

end


-- Cards that arrive in the hand of a player whose hand is stacked join the stack.
function onObjectEnterZone(zone, object)

	if zone.type == "Hand" and object.type == "Card" and next(stacks) ~= nil then
		absorbHandsSoon()
	end

end


--  ======================================================================
--						Stacked hand
--  ======================================================================


-- Where a player sits:  the middle of their hand zone, the directions towards the table center and to
-- their right, the width of the hand zone, and the rotation that makes a card read upright for them.
function getSeat(player_color)

	local hand = Player[player_color].getHandTransform()

	local forward = Vector(hand.forward.x, 0, hand.forward.z):normalized()
	if forward:dot(Vector(-hand.position.x, 0, -hand.position.z)) < 0 then
		forward = forward * -1
	end

	return {
		position = Vector(hand.position.x, hand.position.y, hand.position.z),
		forward = forward,
		right = Vector(forward.z, 0, -forward.x),
		width = hand.scale.x,
		rotation = Vector(0, math.deg(math.atan2(forward.x, forward.z)) + 180, 0),
	}

end


-- Stack the player's hand in columns, and keep it stacked:  cards that reach the hand later join the stack.
function stackHand(player_color)

	local player = Player[player_color]

	-- Spectators have no hand.
	if player == nil or player.getHandCount() == 0 then
		return
	end

	if stacks[player_color] == nil then
		stacks[player_color] = {guids = {}}
		broadcastToColor("竖摞：点牌放进出牌区；点“正序 / 倒序”恢复成一排", player_color, {1,1,1})
	end

	absorbHand(player_color)
	layoutStack(player_color)

end


-- Sort the player's hand in a row:  from low to high the first time, the other way round the next time, and so on.
-- A stacked hand goes back in the hand zone as a row.  Groups are left alone.
function sortHand(player_color)

	local player = Player[player_color]

	-- Spectators have no hand.
	if player == nil or player.getHandCount() == 0 then
		return
	end

	local cards = {}
	local positions = {}

	-- The hand zone lists its cards from left to right.
	for _, object in ipairs(player.getHandObjects()) do
		if object.type == "Card" and object.held_by_color == nil then
			table.insert(cards, object)
			table.insert(positions, object.getPosition())
		end
	end

	local stack = stacks[player_color]
	stacks[player_color] = nil

	if stack ~= nil then

		for _, card in ipairs(getStackCards(stack)) do
			table.insert(cards, card)
		end

		-- The stacked cards have no place in the row yet. The hand zone arranges its cards by where they are
		-- from left to right, so lining all the cards up in order is enough.
		local seat = getSeat(player_color)
		for i = 1, #cards do
			positions[i] = seat.position + seat.right * ((i - (#cards + 1) / 2) * 0.3)
		end

	end

	if sortDescending[player_color] then
		table.sort(cards, sortLogicDescending)
	else
		table.sort(cards, sortLogic)
	end

	-- In a hand that was a row already, the cards trade places.
	for i, card in ipairs(cards) do
		card.setPosition(positions[i])
		if card.getLock() then
			unstackCard(card)
		end
	end

	sortDescending[player_color] = not sortDescending[player_color] or nil
	updateButtons()

end


-- The cards of a stack, in order.  Cards that are gone or were unlocked by hand are dropped from the stack.
function getStackCards(stack)

	local cards = {}

	for guid in pairs(stack.guids) do
		local card = getObjectFromGUID(guid)
		if card ~= nil and card.getLock() then
			table.insert(cards, card)
		else
			stack.guids[guid] = nil
		end
	end

	table.sort(cards, sortLogic)

	return cards

end


-- The player whose stack holds this card.
function getStackOwner(guid)

	for player_color, stack in pairs(stacks) do
		if stack.guids[guid] then
			return player_color
		end
	end

	return nil

end


-- Take a card over from the hand zone:  locked, it stays where the script puts it and the hand zone lets go of it.
-- click_function is called when the card is clicked; it defaults to the one for stacked cards.
function stackCard(player_color, card, click_function)

	-- The hand zone no longer hides it, so hide it from everyone else the same way.
	local others = {}
	for _, color in ipairs(uiColorList) do
		if color ~= player_color and color ~= 'Black' then
			table.insert(others, color)
		end
	end
	card.setHiddenFrom(others)

	card.setLock(true)

	-- A locked card cannot be picked up, so it gets an invisible button to click instead.
	card.createButton({
		click_function = click_function or "onStackCardClick",
		function_owner = Global,
		label = "",
		position = {0, 0.3, 0},
		width = stackButtonWidth,
		height = stackButtonHeight,
		color = {1, 1, 1, 0},
		hover_color = {1, 1, 1, 0.15},
		press_color = {1, 1, 1, 0.3},
	})

end


-- Hand a card back to the hand zones:  unlocked, whichever hand zone it is in takes it.
function unstackCard(card)

	card.clearButtons()
	card.setLock(false)

	-- Stop hiding it once the hand zone has had time to take over, unless the script took it again by then.
	local guid = card.guid
	Wait.time(function()
		local card = getObjectFromGUID(guid)
		if card ~= nil and getStackOwner(guid) == nil and getGroupOf(guid) == nil then
			card.setHiddenFrom({})
		end
	end, 0.5)

end


-- Add the cards in the player's hand zone to their stack.  Returns how many were added.
function absorbHand(player_color)

	local stack = stacks[player_color]
	local count = 0

	for _, object in ipairs(Player[player_color].getHandObjects()) do
		if object.type == "Card" and object.held_by_color == nil then
			stackCard(player_color, object)
			stack.guids[object.guid] = true
			count = count + 1
		end
	end

	return count

end


-- Check the stacked players' hands a moment from now, once the arriving cards have settled in.
local absorbPending = false

function absorbHandsSoon()

	if absorbPending then
		return
	end

	absorbPending = true

	Wait.time(function()
		absorbPending = false
		for player_color in pairs(stacks) do
			-- Only rearrange when something was added, so the columns stay put while cards are being picked.
			if absorbHand(player_color) > 0 then
				layoutStack(player_color)
			end
		end
	end, 0.3)

end


-- Arrange a player's stack:  one column per card number from left to right, where the hand is.
-- Each card of a column lies a step closer to the player than the one before, on top of it.
function layoutStack(player_color)

	local stack = stacks[player_color]

	if stack == nil then
		return
	end

	local cards = getStackCards(stack)

	local columns = {}
	for _, card in ipairs(cards) do
		local column = columns[#columns]
		if column ~= nil and column[1].getName() == card.getName() then
			table.insert(column, card)
		else
			table.insert(columns, {card})
		end
	end

	local seat = getSeat(player_color)

	local pitch = 0
	if #columns > 1 then
		pitch = math.min(stackColumnPitchMax, (seat.width - cardWidth) / (#columns - 1))
	end

	for c, column in ipairs(columns) do
		for r, card in ipairs(column) do

			local position = seat.position + seat.right * ((c - (#columns + 1) / 2) * pitch) - seat.forward * ((r - 1) * stackRowStep)
			-- Columns further right and cards further down a column float higher, so each card shows its top left corner.
			position.y = seat.position.y + stackColumnLift * (c - 1) + stackRowLift * (r - 1)

			card.setPosition(position)
			card.setRotation(seat.rotation)

		end
	end

end


-- Clicking a stacked card sends it to the play area, like clicking a hand card while picking cards.
-- Only a left click counts: a right click is what a player does to turn the camera.
function onStackCardClick(card, player_color, alt_click)

	local owner = getStackOwner(card.guid)

	if alt_click or owner == nil or owner ~= player_color then
		return
	end

	stacks[owner].guids[card.guid] = nil

	if not picking[owner] then
		startPicking(owner, true)
	end

	sendToHandZone(owner, card.guid, playAreaHandIndex, 3)
	unstackCard(card)
	sortPlayAreasSoon()

end


--  ======================================================================
--						Groups
--  ======================================================================


-- Turn the cards in the player's play area into a group:  a column of its own to the left of the hand,
-- which sorting and stacking leave alone.  Clicking any of its cards sends the whole group back to the play area.
function groupPlayArea(player_color)

	local cards = getPlayAreaCards(player_color)

	-- Spectators have no hand zones.
	if cards == nil then
		return
	end

	if #cards < 2 then
		broadcastToColor("理牌：先把至少两张牌放进出牌区", player_color, {1,1,1})
		return
	end

	local guids = {}
	for _, card in ipairs(cards) do
		stackCard(player_color, card, "onGroupCardClick")
		table.insert(guids, card.guid)
	end

	groups[player_color] = groups[player_color] or {}
	table.insert(groups[player_color], {guids = guids})

	stopPicking(player_color)
	layoutGroups(player_color)

	-- A stacked hand closes the gaps the grouped cards left.
	layoutStack(player_color)

end


-- The group holding this card:  the player's color and the group's place in their list of groups.
function getGroupOf(guid)

	for player_color, playerGroups in pairs(groups) do
		for index, group in ipairs(playerGroups) do
			for _, groupGuid in ipairs(group.guids) do
				if groupGuid == guid then
					return player_color, index
				end
			end
		end
	end

	return nil

end


-- Arrange a player's groups:  one column each, starting next to the left edge of the hand zone and going left.
-- Like a column of a stacked hand, each card lies a step closer to the player than the one before.
function layoutGroups(player_color)

	local playerGroups = groups[player_color]

	if playerGroups == nil then
		return
	end

	local seat = getSeat(player_color)
	local column = 0

	for index = #playerGroups, 1, -1 do
		-- Cards that are gone or were unlocked by hand have left their group.
		local cards = {}
		for _, guid in ipairs(playerGroups[index].guids) do
			local card = getObjectFromGUID(guid)
			if card ~= nil and card.getLock() then
				table.insert(cards, card)
			end
		end
		if #cards == 0 then
			table.remove(playerGroups, index)
		else
			table.sort(cards, sortLogic)
			playerGroups[index].guids = {}
			for i, card in ipairs(cards) do
				playerGroups[index].guids[i] = card.guid
			end
		end
	end

	for _, group in ipairs(playerGroups) do

		local across = seat.width / 2 + groupGap + cardWidth / 2 + column * (cardWidth + groupSpacing)

		for r, guid in ipairs(group.guids) do

			local card = getObjectFromGUID(guid)
			local position = seat.position - seat.right * across - seat.forward * ((r - 1) * stackRowStep)
			position.y = seat.position.y + stackRowLift * (r - 1)

			card.setPosition(position)
			card.setRotation(seat.rotation)

		end

		column = column + 1

	end

end


-- Clicking a card of a group sends the whole group to the play area, where it is a group no longer:
-- its cards can be played, taken back in hand, or grouped again.
-- Only a left click counts: a right click is what a player does to turn the camera.
function onGroupCardClick(card, player_color, alt_click)

	local owner, index = getGroupOf(card.guid)

	if alt_click or owner == nil or owner ~= player_color then
		return
	end

	local group = table.remove(groups[owner], index)

	if not picking[owner] then
		startPicking(owner, true)
	end

	for _, guid in ipairs(group.guids) do
		local groupCard = getObjectFromGUID(guid)
		if groupCard ~= nil then
			sendToHandZone(owner, guid, playAreaHandIndex, 3)
			unstackCard(groupCard)
		end
	end

	sortPlayAreasSoon()

	-- The groups further left move up.
	layoutGroups(owner)

end


--  ======================================================================
--						Playing cards
--  ======================================================================


-- Called by the Pass tiles: a player who passes no longer has the top play, so their cards leave the table.
function onGuandanPass(params)

	clearLastPlay(params.color)

end


-- Called by the Collect Cards tool before it takes every card:  let go of the stacked hands (which stay
-- switched on for the next deal) and of the groups, end card picking, and forget the plays on the table.
function onCollectCards()

	local function letGo(guid)
		local card = getObjectFromGUID(guid)
		if card ~= nil then
			card.clearButtons()
			card.setHiddenFrom({})
		end
	end

	for player_color, stack in pairs(stacks) do
		for guid in pairs(stack.guids) do
			letGo(guid)
		end
		stack.guids = {}
	end

	for player_color, playerGroups in pairs(groups) do
		for _, group in ipairs(playerGroups) do
			for _, guid in ipairs(group.guids) do
				letGo(guid)
			end
		end
	end
	groups = {}

	picking = {}
	updateButtons()

	lastPlay = {}
	destinations = {}

end


-- The cards lying in a player's play area, from left to right.  Cards still being held are left out.
-- Returns nil for spectators, who have no hand zones.
function getPlayAreaCards(player_color)

	local player = Player[player_color]

	if player == nil or player.getHandCount() < playAreaHandIndex then
		return nil
	end

	local area = player.getHandTransform(playAreaHandIndex)
	local cards = {}
	local offsets = {}

	for _, object in ipairs(player.getHandObjects(playAreaHandIndex)) do
		if object.type == "Card" and object.held_by_color == nil then
			local position = object.getPosition()
			offsets[object.guid] = (position.x - area.position.x) * area.right.x + (position.z - area.position.z) * area.right.z
			table.insert(cards, object)
		end
	end

	table.sort(cards, function(card1, card2)
		if offsets[card1.guid] ~= offsets[card2.guid] then
			return offsets[card1.guid] < offsets[card2.guid]
		end
		return card1.guid < card2.guid
	end)

	return cards

end


-- Sort every play area a moment from now, once the dropped cards have settled in.
local sortPending = false

function sortPlayAreasSoon()

	if sortPending then
		return
	end

	sortPending = true

	Wait.time(function()
		sortPending = false
		for _, player_color in ipairs(playerColorList) do
			sortPlayArea(player_color)
		end
	end, 0.2)

end


-- Put the cards of a play area in order.  The hand zone arranges its cards by where they are from
-- left to right, so the cards only need to be lined up in the right order.
function sortPlayArea(player_color)

	local cards = getPlayAreaCards(player_color)

	if cards == nil or #cards < 2 then
		return
	end

	local sorted = {}
	local inOrder = true
	for i, card in ipairs(cards) do
		sorted[i] = card
	end
	table.sort(sorted, sortLogic)
	for i, card in ipairs(cards) do
		if sorted[i].guid ~= card.guid then
			inOrder = false
		end
	end

	if inOrder then
		return
	end

	local area = Player[player_color].getHandTransform(playAreaHandIndex)
	local center = Vector(area.position.x, area.position.y, area.position.z)
	local right = Vector(area.right.x, 0, area.right.z):normalized()

	for i, card in ipairs(sorted) do
		card.setPosition(center + right * ((i - (#sorted + 1) / 2) * 0.3))
	end

end


-- Take every card of the player's play area back in hand, at the right end of the hand.
function returnPlayAreaToHand(player_color, attempts)

	local cards = getPlayAreaCards(player_color)

	if cards == nil or #cards == 0 then
		return
	end

	local hand = Player[player_color].getHandTransform()
	local center = Vector(hand.position.x, hand.position.y, hand.position.z)
	local right = Vector(hand.right.x, 0, hand.right.z):normalized()
	-- Just inside the right edge of the hand zone, to the right of every card already in hand.
	local edge = hand.scale.x / 2 - 0.3

	for i, card in ipairs(cards) do
		card.setPosition(center + right * (edge - 0.02 * (#cards - i)))
	end

	-- The play area may pull a card back before it has left; send those again.
	attempts = attempts or 3
	if attempts > 1 then
		Wait.time(function() returnPlayAreaToHand(player_color, attempts - 1) end, 0.5)
	end

end


-- Play every card the player has put in their play area.
function playFromPlayArea(player_color)

	local cards = getPlayAreaCards(player_color)

	if cards == nil then
		return
	end

	if #cards == 0 then
		broadcastToColor("出牌区里没有牌：先点手牌，把要出的牌放进出牌区", player_color, {1,1,1})
		return
	end

	stopPicking(player_color)
	playCards(player_color, cards)

	-- A stacked hand closes the gaps the played cards left.
	layoutStack(player_color)

end


-- Lay the cards out face up in front of the player, sorted from left to right.
function playCards(player_color, cards)

	clearLastPlay(player_color)

	table.sort(cards, sortLogic)

	local seat = getSeat(player_color)
	local right = seat.right
	local rotation = seat.rotation
	local center = Vector(seat.position.x, 0, seat.position.z) + seat.forward * playDistance

	-- Rows of equal length, read like text:  the first row is the furthest from the player, the last one
	-- lies where a single row would, on top of the lower part of the row before it.
	local rows = math.ceil(#cards / playRowSize)
	local rowSize = math.ceil(#cards / rows)

	local placements = {}
	local guids = {}
	local reach = 0

	for i, card in ipairs(cards) do

		local row = math.ceil(i / rowSize)
		local column = i - (row - 1) * rowSize
		local columns = math.min(rowSize, #cards - (row - 1) * rowSize)

		local pitch = 0
		if columns > 1 then
			pitch = math.max(cardPitchMin, math.min(cardPitchMax, playRowWidth / (columns - 1)))
		end

		local across = (column - (columns + 1) / 2) * pitch
		local ahead = (rows - row) * playRowStep

		local position = center + right * across + seat.forward * ahead
		-- Each card starts a little higher than the one before it, so overlapping cards land in order.
		position.y = playHeight + 0.06 * i

		table.insert(placements, {guid = card.guid, position = position, rotation = rotation})
		table.insert(guids, card.guid)

		reach = math.max(reach, math.sqrt(across * across + ahead * ahead))

	end

	lastPlay[player_color] = {guids = guids, x = center.x, z = center.z, radius = reach + 3}

	placeCards(placements, 3)

end


-- Teleport the cards out of the hand.  (A smooth move would be overridden by the hand zone, which keeps pulling its cards back.)
-- Any card that did not end up where it should gets teleported again.
function placeCards(placements, attempts)

	for _, placement in ipairs(placements) do
		local card = getObjectFromGUID(placement.guid)
		if card ~= nil then
			card.setPosition(placement.position)
			card.setRotation(placement.rotation)
		end
	end

	if attempts <= 1 then
		return
	end

	Wait.time(function()

		local misplaced = {}

		for _, placement in ipairs(placements) do

			local card = getObjectFromGUID(placement.guid)

			-- A locked card has been taken by something else since (collecting, a stacked hand).
			if card ~= nil and card.held_by_color == nil and not card.getLock() then
				local position = card.getPosition()
				local dx = position.x - placement.position.x
				local dz = position.z - placement.position.z
				if isInHand(card) or dx * dx + dz * dz > 1 then
					table.insert(misplaced, placement)
				end
			end

		end

		if #misplaced > 0 then
			placeCards(misplaced, attempts - 1)
		end

	end, 0.5)

end


-- Move a player's previous play to its deck's pile.  Cards that were picked up, taken back in hand or moved away are left alone.
function clearLastPlay(player_color)

	local play = lastPlay[player_color]
	lastPlay[player_color] = nil

	if play == nil then
		return
	end

	-- Number of cards sent to the piles so far: each one is dropped a little higher than the last.
	local discarded = 0

	for _, guid in ipairs(play.guids) do

		local card = getObjectFromGUID(guid)

		if card ~= nil and card.type == "Card" and card.held_by_color == nil and not isInHand(card) then

			local position = card.getPosition()
			local dx = position.x - play.x
			local dz = position.z - play.z

			if dx * dx + dz * dz <= play.radius * play.radius then
				-- Teleport: a card gliding across the table would be caught by any play area it passes through.
				discarded = discarded + 1
				local pile = getPilePosition({object = card})
				pile.y = pile.y + 0.15 * discarded
				card.setRotation(Vector(0, 0, 180))
				card.setPosition(pile)
			end

		end

	end

end


-- The deck a card belongs to, or the one deck every card of a deck object belongs to.
-- Returns nil for a deck object that mixes cards of several decks.
-- Takes a table so other scripts can use it:  Global.call("getDeckId", {object = card})
function getDeckId(params)

	local data = params.object.getData()

	if data.CardID ~= nil then
		return math.floor(data.CardID / 100)
	end

	local deckId = nil

	for _, cardId in ipairs(data.DeckIDs or {}) do
		local id = math.floor(cardId / 100)
		if deckId ~= nil and deckId ~= id then
			return nil
		end
		deckId = id
	end

	return deckId

end


-- Where a card (or a deck object) is collected:  Global.call("getPilePosition", {object = card})
function getPilePosition(params)

	return Vector(deckPilePositions[getDeckId(params)] or defaultPilePosition)

end


function isInHand(object)

	for _, zone in pairs(object.getZones()) do
		if zone.type == "Hand" then
			return true
		end
	end

	return false

end


-- Comparison function used by table.sort():  by card number, then by suit.
function sortLogic(card1, card2)

	local card1NumberIndex = refCardOrderIndex[card1.getName()] or 99
	local card2NumberIndex = refCardOrderIndex[card2.getName()] or 99

	if card1NumberIndex ~= card2NumberIndex then
		return card1NumberIndex < card2NumberIndex
	end

	local card1SuitIndex = refSuitOrderIndex[card1.getDescription()] or 99
	local card2SuitIndex = refSuitOrderIndex[card2.getDescription()] or 99

	if card1SuitIndex ~= card2SuitIndex then
		return card1SuitIndex < card2SuitIndex
	end

	return card1.guid < card2.guid

end


-- Comparison function used by table.sort():  by card number from high to low.
-- Cards of the same number keep the order of their suits, except the Jokers, where the bigger one comes first.
function sortLogicDescending(card1, card2)

	local card1NumberIndex = refCardOrderIndex[card1.getName()] or 99
	local card2NumberIndex = refCardOrderIndex[card2.getName()] or 99

	if card1NumberIndex ~= card2NumberIndex then
		return card1NumberIndex > card2NumberIndex
	end

	if card1.getName() == "Joker" and card1.getDescription() ~= card2.getDescription() then
		return sortLogic(card2, card1)
	end

	return sortLogic(card1, card2)

end
