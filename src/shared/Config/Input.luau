--!strict
--[[
	Input bindings for every player action, per device.

	Keyboard/Gamepad list the keys that trigger the action. Touch describes the
	on-screen button shown on phones/tablets (omit it for actions that should not
	have a touch button). Positions use the TouchControls ScreenGui's space.
]]

local Types = require(script.Parent.Parent.Types)

local Input = {
	Actions = {
		-- Opens the district / exploration panel.
		ToggleDistricts = {
			Keyboard = { Enum.KeyCode.M },
			Gamepad = { Enum.KeyCode.DPadUp },
			Touch = {
				Label = "Map",
				Position = UDim2.new(1, -56, 0, 96),
				Size = 56,
			},
		},
		-- Closes the open panel. Only bound while a panel is open. No keyboard key
		-- (Escape belongs to the Roblox menu) and no touch button (panels have
		-- their own Close button).
		CloseMenu = {
			Keyboard = {},
			Gamepad = { Enum.KeyCode.ButtonB },
		},
	} :: { [string]: Types.InputActionConfig },
}

return Input
