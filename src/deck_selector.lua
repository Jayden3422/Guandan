-- Deck Selector tool
-- Chooses the deck the Deal tool deals: one side up for the white deck, the other side for the black deck.
-- Click the tool, or flip it like any other object, to switch decks.



--  ======================================================================
--						Configuration
--  ======================================================================



-- The deck dealt for each side of the tool.
-- id:  the deck's ID (its card IDs without their last two digits).  name:  what the players are told, in English and Chinese.
faceUpDeck = {id = 123, name = {en = "The white deck", zh = "白牌"}}
faceDownDeck = {id = 125, name = {en = "The black deck", zh = "黑牌"}}



--  ======================================================================
--						End Configuration
--  ======================================================================



function onLoad()

	local button = {}
	button.label = "" button.height = 600 button.width = 600 button.font_size = 500 button.position = {0, 0.15, 0} button.rotation = {0, 0, 0} button.click_function = 'switchDeck' button.function_owner = self self.createButton(button)
	button.label = "" button.height = 600 button.width = 600 button.font_size = 500 button.position = {0, 0.10, 0} button.rotation = {0, 0, 180} button.click_function = 'switchDeck' button.function_owner = self self.createButton(button)

end


-- The deck of the side that is up:  {id = , name = {en = , zh = }}.  Called by the Collect Cards tool when dealing.
function getSelectedDeck()

	if self.is_face_down then
		return faceDownDeck
	end

	return faceUpDeck

end


function switchDeck()

	-- The flip takes a moment, so announce the deck of the side that is coming up.
	local deck = faceDownDeck
	if self.is_face_down then
		deck = faceUpDeck
	end

	self.flip()

	-- Each player sees the part for the language of their own game.
	broadcastToAll("{en}" .. deck.name.en .. " will be dealt{zh}发牌改用" .. deck.name.zh, {1,1,1})

end
