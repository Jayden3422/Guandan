-- Minimal stand-ins for the Tabletop Simulator API, enough to drive the mod's scripts.

objects = {}        -- guid -> object
waits = {}          -- pending Wait.time callbacks
frames = {}         -- pending Wait.frames callbacks
conditions = {}     -- pending Wait.condition entries
messages = {}
smoothMoves = {}
vectorLines = nil
uiAttributes = {}   -- element id -> attributes set by the script

Time = {time = 0}

JSON = {
	encode = function(t) return t end,
	decode = function(t) return t end,
}

Wait = {
	time = function(f, seconds) table.insert(waits, f) end,
	frames = function(f, count) table.insert(frames, f) end,
	condition = function(f, condition, timeout, onTimeout)
		table.insert(conditions, {f = f, condition = condition, onTimeout = onTimeout})
	end,
}

local function run(queueName)
	local pending = _G[queueName]
	_G[queueName] = {}
	for _, f in ipairs(pending) do f() end
	return #pending
end

function runWaits() return run("waits") end
function runFrames() return run("frames") end

-- Run every pending timer and frame callback, including the ones they schedule.
function settle()
	for i = 1, 10 do
		if runFrames() + runWaits() == 0 then return end
	end
end

-- Resolve pending conditions: run those that hold, time out the others when asked to.
function runConditions(timeOut)
	local pending = conditions
	conditions = {}
	for _, entry in ipairs(pending) do
		if entry.condition() then
			entry.f()
		elseif timeOut then
			entry.onTimeout()
		else
			table.insert(conditions, entry)
		end
	end
end

-- Hand zones per color: index 1 is the hand, index 2 the play area in front of it.
local function seat(x, z, fx, fz)
	local forward = Vector(fx, 0, fz)
	local right = Vector(fz, 0, -fx)
	return {
		{position = Vector(x, 2.97, z), forward = forward, right = right, scale = Vector(20, 6.63, 3.52)},
		{position = Vector(x + fx * 5, 2.97, z + fz * 5), forward = forward, right = right, scale = Vector(12, 6.63, 3)},
	}
end

seats = {
	White  = seat(0.03, -18.0, 0, 1),
	Green  = seat(0.03, 18.0, 0, -1),
	Purple = seat(18.23, 0.14, -1, 0),
	Orange = seat(-18.17, -0.06, 1, 0),
}

-- Which hand zone a position is in:  color, index
function inHandZone(position)
	for color, zones in pairs(seats) do
		for index, zone in ipairs(zones) do
			local delta = Vector(position.x - zone.position.x, 0, position.z - zone.position.z)
			if math.abs(delta:dot(zone.right)) <= zone.scale.x / 2 and math.abs(delta:dot(zone.forward)) <= zone.scale.z / 2 then
				return color, index
			end
		end
	end
	return nil
end

local function newObject(guid, position)
	local object = {guid = guid, held_by_color = nil, use_hands = true}
	local pos = Vector(position)
	local rot = Vector(0, 0, 0)
	object.getPosition = function() return pos:copy() end
	object.getRotation = function() return rot:copy() end
	object.setPosition = function(p) pos = Vector(p) return true end
	object.setRotation = function(r) rot = Vector(r) return true end
	object.setPositionSmooth = function(p) pos = Vector(p) table.insert(smoothMoves, guid) return true end
	object.setRotationSmooth = function(r) rot = Vector(r) return true end
	object.getZones = function()
		if object.use_hands and not object.locked and inHandZone(pos) then return {{type = "Hand"}} end
		return {}
	end
	object.locked = false
	object.getLock = function() return object.locked end
	object.setLock = function(lock) object.locked = lock return true end
	object.hiddenFrom = {}
	object.setHiddenFrom = function(colors) object.hiddenFrom = colors return true end
	object.buttons = {}
	object.createButton = function(parameters) table.insert(object.buttons, parameters) return true end
	object.clearButtons = function() object.buttons = {} return true end
	objects[guid] = object
	return object
end

function newCard(guid, name, description, position, cardId)
	local card = newObject(guid, position)
	card.type = "Card"
	card.name = "Card"
	card.cardId = cardId or 12300
	card.getName = function() return name end
	card.getDescription = function() return description end
	card.getData = function() return {CardID = card.cardId} end
	return card
end

nextDeckGuid = 0

-- A deck object holding the given card IDs (last one on top).
function newDeck(cardIds, position)
	nextDeckGuid = nextDeckGuid + 1
	local deck = newObject("deck" .. nextDeckGuid, position)
	deck.type = "Deck"
	deck.name = "Deck"
	deck.use_hands = false
	deck.cardIds = cardIds
	deck.shuffled = 0
	deck.dealt = {}
	deck.getQuantity = function() return #cardIds end
	deck.getData = function() return {DeckIDs = cardIds} end
	deck.shuffle = function() deck.shuffled = deck.shuffled + 1 end
	deck.deal = function(count, color) deck.dealt[color] = count end
	deck.takeObject = function(params)
		local cardId = table.remove(cardIds)
		local card = newCard(deck.guid .. "-" .. #cardIds, "Two", "Heart", params.position, cardId)
		if #cardIds == 1 then
			deck.remainder = newCard(deck.guid .. "-last", "Two", "Heart", deck.getPosition(), cardIds[1])
			objects[deck.guid] = nil
		end
		if params.callback_function then params.callback_function(card) end
		return card
	end
	return deck
end

-- Like the game's group(): everything ends up in the first deck object, or in a new one where the first card lies.
function group(list)
	local target = nil
	for _, object in ipairs(list) do
		if target == nil and object.name == "Deck" then target = object end
	end
	if target == nil then
		target = newDeck({}, list[1].getPosition())
		target.use_hands = true
	end
	for _, object in ipairs(list) do
		if object ~= target then
			if object.name == "Deck" then
				for _, cardId in ipairs(object.cardIds) do table.insert(target.cardIds, cardId) end
			else
				table.insert(target.cardIds, object.cardId)
				-- The card glides to the deck: note where from, to check it starts right above it.
				local from, to = object.getPosition(), target.getPosition()
				groupTravel = math.max(groupTravel or 0, math.abs(from.x - to.x) + math.abs(from.z - to.z))
				-- The card's state is saved into the deck as it is now: it must be an ordinary card again.
				if object.locked or not object.use_hands then groupedBadState = true end
			end
			objects[object.guid] = nil
		end
	end
	return {target}
end

function getObjectFromGUID(guid) return objects[guid] end

function getObjects()
	local result = {}
	for _, object in pairs(objects) do table.insert(result, object) end
	return result
end

seated = {"White", "Green", "Purple", "Orange"}
function getSeatedPlayers() return seated end

Player = setmetatable({Action = {PickUp = 8, Select = 13}}, {__index = function(_, color)
	local zones = seats[color] or {}
	return {
		color = color,
		getHandCount = function() return #zones end,
		getHandTransform = function(index) return zones[index or 1] end,
		getHandObjects = function(index)
			local result = {}
			for _, object in pairs(objects) do
				if object.type == "Card" and object.use_hands and not object.locked then
					local zoneColor, zoneIndex = inHandZone(object.getPosition())
					if zoneColor == color and zoneIndex == (index or 1) then
						table.insert(result, object)
					end
				end
			end
			-- Like the game, list the hand from left to right.
			local zone = zones[index or 1]
			local function along(object)
				local position = object.getPosition()
				return (position.x - zone.position.x) * zone.right.x + (position.z - zone.position.z) * zone.right.z
			end
			table.sort(result, function(a, b)
				if along(a) ~= along(b) then return along(a) < along(b) end
				return a.guid < b.guid
			end)
			return result
		end,
	}
end})

function stringColorToRGB(color) return {r = 1, g = 1, b = 1, name = color} end

function broadcastToColor(message, color) table.insert(messages, color .. ": " .. message) end
function broadcastToAll(message) table.insert(messages, "all: " .. message) end

UI = {
	setAttributes = function(id, attributes) uiAttributes[id] = attributes return true end,
}

-- The Global object: calls go to the functions global.lua defined (captured before another script redefines them).
globalFunctions = {}
Global = {
	setVectorLines = function(lines) vectorLines = lines return true end,
	call = function(name, params) return globalFunctions[name](params) end,
}

-- The object a tool script runs on.
self = {
	flips = 0,
	createButton = function() end,
	editButton = function() end,
	is_face_down = false,
	flip = function() self.flips = self.flips + 1 self.is_face_down = not self.is_face_down end,
}
