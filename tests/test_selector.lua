-- Tests for deck_selector.lua (run after the other scripts and deck_selector.lua).

failures = 0
messages = {}
self.flips = 0
self.is_face_down = false

onLoad()
check(getSelectedDeck().id == 123, "face up selects the white deck")
switchDeck()
check(self.flips == 1 and getSelectedDeck().id == 125 and #messages == 1, "clicking flips the tool to the black deck and says so")
switchDeck()
check(getSelectedDeck().id == 123 and #messages == 2, "clicking again goes back to the white deck")
self.is_face_down = true
check(getSelectedDeck().name == "黑牌", "flipping the tool by hand selects the black deck too")

print(failures == 0 and "SELECTOR: ALL PASSED" or ("SELECTOR: " .. failures .. " FAILED"))
if failures > 0 then error("test failures") end
