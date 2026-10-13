--!strict
--[[
	Input bindings for every player action, per device.

	Keyboard/Gamepad list the keys that trigger the action, Mouse the mouse
	buttons. Touch describes the on-screen button shown on phones/tablets (omit it
	for actions that should not have a touch button). Positions use the
	TouchControls ScreenGui's space (inside the safe area, before UI scaling).

	A touch button only exists while its action is bound, so contextual buttons
	(Up / Down / Boost) appear only while flying.

	Default layout
	  PC:       F fly · Space up · Ctrl/C down · Shift boost · Left mouse beam (hold)
	            Q shield · 1/2/3 wall/hammer/cage · R cast selected construct
	  Gamepad:  Y fly · A up · B down · L3 boost · R2 beam (hold) · L2 shield
	            X cast selected construct · R1/L1 next/previous construct
	  Touch:    Fly · Beam (hold) · Shield · Cast · Swap construct; Up/Down/Boost while flying
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

		-- Ring powers ------------------------------------------------------------
		-- Touch positions below are the starting layout; the client keeps every
		-- button clear of Roblox's own jump button and thumbstick.

		-- Take off / land.
		ToggleFlight = {
			Keyboard = { Enum.KeyCode.F },
			Gamepad = { Enum.KeyCode.ButtonY },
			Touch = { Label = "Fly", Position = UDim2.new(1, -330, 1, -70), Size = 60 },
		},
		-- Climb while flying (bound only while flying, so Space still jumps on foot).
		Ascend = {
			Keyboard = { Enum.KeyCode.Space },
			Gamepad = { Enum.KeyCode.ButtonA },
			Touch = { Label = "Up", Position = UDim2.new(1, -60, 1, -300), Size = 60 },
		},
		-- Dive while flying; holding it near the ground lands.
		Descend = {
			Keyboard = { Enum.KeyCode.LeftControl, Enum.KeyCode.C },
			Gamepad = { Enum.KeyCode.ButtonB },
			Touch = { Label = "Down", Position = UDim2.new(1, -60, 1, -230), Size = 60 },
		},
		-- Hold for a burst of speed while flying.
		Boost = {
			Keyboard = { Enum.KeyCode.LeftShift },
			Gamepad = { Enum.KeyCode.ButtonL3 },
			Touch = { Label = "Boost", Position = UDim2.new(1, -330, 1, -150), Size = 60 },
		},
		-- Hold to fire the energy beam at the crosshair.
		FireBeam = {
			Keyboard = {},
			Mouse = { Enum.UserInputType.MouseButton1 },
			Gamepad = { Enum.KeyCode.ButtonR2 },
			Touch = { Label = "Beam", Position = UDim2.new(1, -240, 1, -80), Size = 84 },
		},
		-- Raise / drop the shield bubble.
		ToggleShield = {
			Keyboard = { Enum.KeyCode.Q },
			Gamepad = { Enum.KeyCode.ButtonL2 },
			Touch = { Label = "Shield", Position = UDim2.new(1, -150, 1, -240), Size = 60 },
		},
		-- Cast the selected construct at the crosshair.
		CastConstruct = {
			Keyboard = { Enum.KeyCode.R },
			Gamepad = { Enum.KeyCode.ButtonX },
			Touch = { Label = "Cast", Position = UDim2.new(1, -240, 1, -180), Size = 64 },
		},
		-- Select the next / previous construct (Config.Powers.ConstructOrder).
		NextConstruct = {
			Keyboard = {},
			Gamepad = { Enum.KeyCode.ButtonR1 },
			Touch = { Label = "Swap", Position = UDim2.new(1, -320, 1, -230), Size = 52 },
		},
		PreviousConstruct = {
			Keyboard = {},
			Gamepad = { Enum.KeyCode.ButtonL1 },
		},
		-- Cast a specific construct straight away (and select it).
		CastWall = {
			Keyboard = { Enum.KeyCode.One },
			Gamepad = {},
		},
		CastHammer = {
			Keyboard = { Enum.KeyCode.Two },
			Gamepad = {},
		},
		CastCage = {
			Keyboard = { Enum.KeyCode.Three },
			Gamepad = {},
		},
	} :: { [string]: Types.InputActionConfig },
}

return Input
