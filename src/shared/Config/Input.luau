--!strict
--[[
	Input bindings for every player action, per device.

	Keyboard/Gamepad list the keys that trigger the action, Mouse the mouse
	buttons. Touch describes the on-screen button shown on phones/tablets (omit it
	for actions that should not have a touch button). Positions use the
	TouchControls ScreenGui's space (inside the safe area, before UI scaling).

	A touch button only exists while its action is bound, so contextual buttons
	(Up / Down / Boost) appear only while flying. While a panel is open, only the
	TouchWhileMenuOpen.Keep actions show their buttons (see below).

	Touch layout of the ring powers (offsets from the bottom-right corner, before
	UI scaling): a 3-column cluster left of Roblox's jump button, Beam (largest)
	nearest the right thumb, the others 54 px with 11 px gaps (46 px and 9 px on
	phones, which always run at Theme.MinScale).
	  row 3:  Up    Boost   Swap
	  row 2:  Down  Shield  Cast
	  row 1:     Fly     [ Beam ]          (jump)
	It is checked against both of Roblox's jump buttons, at every UI scale:
	  * Every right edge is at x <= -208, i.e. <= -176.8 px at MinScale and further
	    left as the scale grows, so it stays left of the large jump button
	    (screens over 500 px: left edge at W-170 px) and of the phone one (W-95 px).
	  * Every left edge is at x >= -392, i.e. >= -333.2 px on phones, inside the
	    right 60 % of a 568 px wide phone (340.8 px) where the dynamic thumbstick
	    never starts; on tablets (>= 960 x scale px wide) it is far inside.
	  * The top row ends 223 units above the bottom (189.6 px on phones), under
	    the top bar on a 320 px tall phone (262 px below the top bar) and left of
	    the Map button, which sits at the right edge.
	The area the cluster leaves free above the jump button is where the right
	thumb drags the camera.

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
		-- Touch positions: see the layout notes at the top of this file.

		-- Take off / land. The touch button reads "Land" while flying.
		ToggleFlight = {
			Keyboard = { Enum.KeyCode.F },
			Gamepad = { Enum.KeyCode.ButtonY },
			Touch = { Label = "Fly", Position = UDim2.new(1, -330, 1, -51), Size = 54 },
		},
		-- Climb while flying (bound only while flying, so Space still jumps on foot).
		-- Holding Roblox's own jump button (touch, controller A) climbs too.
		Ascend = {
			Keyboard = { Enum.KeyCode.Space },
			Gamepad = { Enum.KeyCode.ButtonA },
			Touch = { Label = "Up", Position = UDim2.new(1, -365, 1, -196), Size = 54 },
		},
		-- Dive while flying; holding it near the ground lands.
		Descend = {
			Keyboard = { Enum.KeyCode.LeftControl, Enum.KeyCode.C },
			Gamepad = { Enum.KeyCode.ButtonB },
			Touch = { Label = "Down", Position = UDim2.new(1, -365, 1, -131), Size = 54 },
		},
		-- A burst of speed while flying. Held on the keyboard; on controller and
		-- touch one press switches it on and the next off (Config.Flight.BoostToggle).
		Boost = {
			Keyboard = { Enum.KeyCode.LeftShift },
			Gamepad = { Enum.KeyCode.ButtonL3 },
			Touch = { Label = "Boost", Position = UDim2.new(1, -300, 1, -196), Size = 54 },
		},
		-- Hold to fire the energy beam at the crosshair.
		FireBeam = {
			Keyboard = {},
			Mouse = { Enum.UserInputType.MouseButton1 },
			Gamepad = { Enum.KeyCode.ButtonR2 },
			Touch = { Label = "Beam", Position = UDim2.new(1, -250, 1, -51), Size = 84 },
		},
		-- Raise / drop the shield bubble.
		ToggleShield = {
			Keyboard = { Enum.KeyCode.Q },
			Gamepad = { Enum.KeyCode.ButtonL2 },
			Touch = { Label = "Shield", Position = UDim2.new(1, -300, 1, -131), Size = 54 },
		},
		-- Cast the selected construct at the crosshair.
		CastConstruct = {
			Keyboard = { Enum.KeyCode.R },
			Gamepad = { Enum.KeyCode.ButtonX },
			Touch = { Label = "Cast", Position = UDim2.new(1, -235, 1, -131), Size = 54 },
		},
		-- Select the next / previous construct (Config.Powers.ConstructOrder).
		NextConstruct = {
			Keyboard = {},
			Gamepad = { Enum.KeyCode.ButtonR1 },
			Touch = { Label = "Swap", Position = UDim2.new(1, -235, 1, -196), Size = 54 },
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

	-- While MenuAction is bound (a panel is open), only the actions in Keep show
	-- their touch buttons. Touch buttons draw above the HUD, so gameplay buttons
	-- would otherwise sit on top of the panel and catch taps meant for it (its
	-- Close button runs along the bottom, right through the power buttons).
	TouchWhileMenuOpen = {
		MenuAction = "CloseMenu",
		Keep = { "ToggleDistricts" },
	},
}

return Input
