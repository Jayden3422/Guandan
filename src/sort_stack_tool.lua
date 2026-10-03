-- Sort Hand Tool Stack
-- This tool stacks the calling player's hand in columns, one per card number, and keeps it stacked.
-- The other Sort Hand Tools put the hand back in a row.
-- The stacking itself is done by the Global script, which also binds scripting hotkey NumPad 4 to it.


function onLoad()

	local button = {}
	button.label = "" button.height = 600 button.width = 600 button.font_size = 500 button.position = {0, 0.15, 0} button.rotation = {0, 0, 0} button.click_function = 'stackHand' button.function_owner = self self.createButton(button)
	button.label = "" button.height = 600 button.width = 600 button.font_size = 500 button.position = {0, 0.10, 0} button.rotation = {0, 0, 180} button.click_function = 'stackHand' button.function_owner = self self.createButton(button)

end


-- Stack the calling player's hand.
function stackHand(obj, player_color)

	Global.call("stackHand", {color = player_color})

end
