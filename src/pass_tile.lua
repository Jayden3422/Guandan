-- Define the button parameters
local buttonParams = {
    click_function = "onClick",
    function_owner = self,
    label = "Pass",
    position = {0, 0.05, 0},
    rotation = {0, 0, 0},
    width = 300,
    height = 100,
    font_size = 80,
}

function onLoad()
    -- Create the button
    self.createButton(buttonParams)
end

function onClick(obj, player_color)
    -- The passing player's previous play leaves the table
    Global.call("onGuandanPass", {color = player_color})

    -- Set the text to "Passed"
    self.editButton({
        index = 0,
        label = "Passed",
        width = 300,
        height = 100,
        font_size = 80,
    })

    -- Wait for 5 seconds
    Wait.time(function()
        -- Change the text back to "Pass" after 5 seconds
        self.editButton({
            index = 0,
            label = "Pass",
            width = 300,
            height = 100,
            font_size = 80,
        })
    end, 5)
end
