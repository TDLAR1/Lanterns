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

	Touch layout of the ring powers (centres as offsets from the bottom-right
	corner of the safe area, in units before UI scaling; px = units x scale).
	A 3-column grid left of Roblox's jump button: Beam (84 units, the biggest)
	next to the jump button where the right thumb rests, the rest 54 units with
	11-unit gaps. The flight-only Up / Down / Boost (shown only while flying)
	take the top row's outer slots, Boost nearest the thumb.
	  row 3 (y -202):  Up (x -365)    Swap (-300)     Boost (-235)
	  row 2 (y -137):  Down (-365)    Shield (-300)   Cast (-235)
	  row 1 (y  -57):       Fly (-330)       Beam (-250)          (jump)
	Phones (screen min side <= 500 px) always run at Theme.MinScale 0.85: the
	buttons are 46 px with 9 px gaps, Beam 71 px. Checked at every UI scale
	0.85..1.35 (scale s), on squares around the round buttons:
	  * Each other: horizontally the columns span x -392..-338, -327..-273 and
	    -262..-208 (Fly -357..-303, Beam -292..-208); vertically the rows span
	    y -229..-175, -164..-110 and Beam -99..-15 (Fly -84..-30). Neighbours are
	    at least 11 units (9.35 px) apart in x or y.
	  * Jump button: every right edge is at x <= -208, i.e. <= W - 176.8 px at
	    s >= 0.85, left of the phone jump button (W-95 .. W-25 px) and of the
	    large one (W-170 .. W-50 px), at every scale.
	  * Dynamic thumbstick (left 40 % of the screen): every left edge is at
	    x >= -392, i.e. W - 392s px. Phones: W - 333.2 >= 0.4 W for W >= 556 px
	    (every landscape phone is 568 px or wider). Larger screens:
	    W >= 653s holds for s = 0.85 (W >= 556) and s = H/720 (W >= 0.91 H, any
	    landscape screen) and s = 1.35 (H >= 972 so W >= 972 >= 882).
	  * Map button (x >= W - 84s, see ToggleDistricts) is right of every power
	    button (x <= W - 208s), so they never meet whatever the screen height.
	  * Top bar: the top row reaches 229 units = 194.7 px above the bottom on
	    phones, under the top bar of even a 320 px tall phone (262 px usable
	    below a 58 px top bar); on larger screens 229s < H - 58 always.
	The area the grid leaves free above the jump button is where the right thumb
	drags the camera; while firing, dragging the Beam button aims too
	(Config.Camera.TouchAim).

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
			Touch = { Label = "Fly", Position = UDim2.new(1, -330, 1, -57), Size = 54 },
		},
		-- Climb while flying (bound only while flying, so Space still jumps on foot).
		-- Holding Roblox's own jump button (touch, controller A) climbs too.
		Ascend = {
			Keyboard = { Enum.KeyCode.Space },
			Gamepad = { Enum.KeyCode.ButtonA },
			Touch = { Label = "Up", Position = UDim2.new(1, -365, 1, -202), Size = 54 },
		},
		-- Dive while flying; holding it near the ground lands.
		Descend = {
			Keyboard = { Enum.KeyCode.LeftControl, Enum.KeyCode.C },
			Gamepad = { Enum.KeyCode.ButtonB },
			Touch = { Label = "Down", Position = UDim2.new(1, -365, 1, -137), Size = 54 },
		},
		-- A burst of speed while flying. Held on the keyboard; on controller and
		-- touch one press switches it on and the next off (Config.Flight.BoostToggle).
		Boost = {
			Keyboard = { Enum.KeyCode.LeftShift },
			Gamepad = { Enum.KeyCode.ButtonL3 },
			Touch = { Label = "Boost", Position = UDim2.new(1, -235, 1, -202), Size = 54 },
		},
		-- Hold to fire the energy beam at the crosshair.
		FireBeam = {
			Keyboard = {},
			Mouse = { Enum.UserInputType.MouseButton1 },
			Gamepad = { Enum.KeyCode.ButtonR2 },
			Touch = { Label = "Beam", Position = UDim2.new(1, -250, 1, -57), Size = 84 },
		},
		-- Raise / drop the shield bubble.
		ToggleShield = {
			Keyboard = { Enum.KeyCode.Q },
			Gamepad = { Enum.KeyCode.ButtonL2 },
			Touch = { Label = "Shield", Position = UDim2.new(1, -300, 1, -137), Size = 54 },
		},
		-- Cast the selected construct at the crosshair.
		CastConstruct = {
			Keyboard = { Enum.KeyCode.R },
			Gamepad = { Enum.KeyCode.ButtonX },
			Touch = { Label = "Cast", Position = UDim2.new(1, -235, 1, -137), Size = 54 },
		},
		-- Select the next / previous construct (Config.Powers.ConstructOrder).
		NextConstruct = {
			Keyboard = {},
			Gamepad = { Enum.KeyCode.ButtonR1 },
			Touch = { Label = "Swap", Position = UDim2.new(1, -300, 1, -202), Size = 54 },
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
