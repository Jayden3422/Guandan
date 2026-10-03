-- Tests for the hooked Sort Hand Tool LR script (run after everything else and the built sort tool script).

failures = 0
objects = {}
waits = {}
frames = {}

-- The sort tool redefined sortLogic; the Global functions need their own back while they run.
local toolSortLogic = sortLogic
local function asGlobal(f)
	return function(params)
		sortLogic = globalSortLogic
		local result = f(params)
		sortLogic = toolSortLogic
		return result
	end
end
globalFunctions.unstackHand = asGlobal(unstackHand)
local stack = asGlobal(stackHand)

self.getDescription = function() return "" end
self.getRotation = function() return Vector(0, 180, 180) end

local function hand(guid, name, suit, x)
	return newCard(guid, name, suit, {x, 2.97, -18})
end
local king, two, ace = hand("k", "King", "Spade", -1), hand("t", "Two", "Heart", 0), hand("a", "Ace", "Club", 1)
local function x(card) return card.getPosition().x end

-- Not stacked: sorts right away, as before.
sortHand(self, "White")
check(x(two) < x(king) and x(king) < x(ace) and #waits == 0, "a hand that is not stacked is sorted right away")

-- Stacked: unstacks first, then sorts once the hand zone has the cards back.
stack({color = "White"})
check(king.locked, "(the hand is stacked)")
sortHand(self, "White")
check(not king.locked and #waits > 0, "sorting a stacked hand first puts it back in the hand zone")
sortLogic = toolSortLogic
settle()
check(not king.locked and x(two) < x(king) and x(king) < x(ace), "and then sorts it")

print(failures == 0 and "SORT TOOL: ALL PASSED" or ("SORT TOOL: " .. failures .. " FAILED"))
if failures > 0 then error("test failures") end
