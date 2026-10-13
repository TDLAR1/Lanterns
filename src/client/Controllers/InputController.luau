--!strict
--[[
	InputController: devices and actions, for keyboard/mouse, gamepad and touch.

	Gameplay code never listens to keys itself. It binds an ACTION by name (an
	entry of Config.Input.Actions) and gets "Begin" when the action is pressed and
	"End" when it is released, whatever the device:

	  * Keyboard and gamepad: the keys listed in the action's config. Input the
	    game already used (typing in chat, the Roblox menu, a focused text box,
	    gamepad UI navigation) is ignored, so chatting never triggers actions.
	  * Mouse: the buttons in the action's optional Mouse list. A click the game
	    already used (on a GUI button, say) is ignored the same way, so clicking
	    UI never fires the beam; releases always count. Ignored while the player
	    is on touch, where Roblox also reports taps as mouse clicks.
	  * Touch: a round on-screen button built from the action's Touch config, in
	    the "TouchControls" ScreenGui, shown only while the player is on touch.
	    Buttons react to touch input only: they are hidden whenever the mouse is
	    the preferred input, and ignoring the mouse events Roblox emulates for a
	    tap means one tap can never trigger an action twice.

	An action counts as held while ANY of its keys or its button is down: Begin
	fires on the first press and End when the last one is released (hold-style
	powers rely on this). Holds are also released when the window loses focus or
	the touch buttons hide, because the matching release would never arrive.

	While a panel is open (Config.Input.TouchWhileMenuOpen.MenuAction is bound)
	only the TouchWhileMenuOpen.Keep actions show their touch buttons, so power
	buttons never sit on top of the panel and catch taps meant for it, and a key
	of the menu action goes to the menu alone (gamepad B closes the panel without
	also diving while flying).

	The current device comes from UserInputService.PreferredInput, which Roblox
	updates as the player switches between mouse/keyboard, gamepad and touch.

	API:
	  InputController:GetDevice(): InputDevice
	  InputController.DeviceChanged  Signal(device)
	  InputController:BindAction(actionName, handler(phase))   (one handler per action)
	  InputController:UnbindAction(actionName)
	  InputController:IsHeld(actionName): boolean
	  InputController:SetTouchLabel(actionName, label)   (relabels a bound action's
	    touch button until it is unbound; binding again starts from the config label)
	  InputController:IsMenuOpen(): boolean   (a panel has bound the menu action)
	  InputController:SetTouchHidden(reason, hidden)   (hides every touch button while
	    any reason is set, e.g. a cutscene; held buttons are released)
	  InputController:GetTouchInput(actionName): InputObject?
	    The touch currently holding the action's button (its Position follows the
	    finger), e.g. so dragging the Beam button can aim the camera.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local InputConfig = require(Shared.Config.Input)
local Signal = require(Shared.Util.Signal)
local Theme = require(Shared.Config.Theme)
local Types = require(Shared.Types)
local UIConfig = require(Shared.Config.UI)

local Create = require(script.Parent.Parent.UI.Create)
local HudController = require(script.Parent.HudController)

type ActionHandler = (phase: Types.ActionPhase) -> ()

-- Something holding an action down: the KeyCode of a keyboard/gamepad key, the
-- UserInputType of a mouse button, or the InputObject of the finger on its touch
-- button (one object per touch).
type Holder = Enum.KeyCode | Enum.UserInputType | InputObject

type TouchButton = {
	button: TextButton,
	stroke: UIStroke,
	-- The touch currently pressing the button, if any.
	input: InputObject?,
}

type Binding = {
	name: string,
	config: Types.InputActionConfig,
	handler: ActionHandler,
	holders: { [Holder]: boolean },
	touch: TouchButton?,
}

local GAMEPAD_INPUT_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
	[Enum.UserInputType.Gamepad5] = true,
	[Enum.UserInputType.Gamepad6] = true,
	[Enum.UserInputType.Gamepad7] = true,
	[Enum.UserInputType.Gamepad8] = true,
}

local MOUSE_BUTTONS: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
}

local menuConfig = InputConfig.TouchWhileMenuOpen

local bindings: { [string]: Binding } = {}
local touchGui: ScreenGui? = nil
-- Reasons currently hiding every touch button (SetTouchHidden).
local touchHiddenReasons: { [string]: boolean } = {}

local function readDevice(): Types.InputDevice
	local preferred = UserInputService.PreferredInput
	if preferred == Enum.PreferredInput.Touch then
		return "Touch"
	elseif preferred == Enum.PreferredInput.Gamepad or preferred == Enum.PreferredInput.MicroGamepad then
		return "Gamepad"
	end
	return "KeyboardMouse"
end

local device: Types.InputDevice = readDevice()

local InputController = {
	-- The player's preferred input device changed. (device)
	DeviceChanged = Signal.new() :: Signal.Signal<Types.InputDevice>,
}

local function isHeld(binding: Binding): boolean
	return next(binding.holders) ~= nil
end

local function press(binding: Binding, holder: Holder)
	if binding.holders[holder] then
		return
	end
	local wasHeld = isHeld(binding)
	binding.holders[holder] = true
	if not wasHeld then
		-- Own thread: an erroring or yielding handler never breaks input handling.
		task.spawn(binding.handler, "Begin" :: Types.ActionPhase)
	end
end

local function release(binding: Binding, holder: Holder)
	if not binding.holders[holder] then
		return
	end
	binding.holders[holder] = nil
	if not isHeld(binding) then
		task.spawn(binding.handler, "End" :: Types.ActionPhase)
	end
end

local function setTouchPressed(touch: TouchButton, pressed: boolean)
	local config = UIConfig.TouchButton
	touch.button.BackgroundColor3 = if pressed then Theme.RingGreenDim else Theme.PanelColor
	touch.button.BackgroundTransparency = if pressed then config.PressedTransparency else Theme.PanelTransparency
	touch.stroke.Color = if pressed then Theme.TextPrimary else Theme.RingGreen
end

local function releaseTouch(binding: Binding)
	local touch = binding.touch
	if touch == nil then
		return
	end
	local input = touch.input
	if input == nil then
		return
	end
	touch.input = nil
	setTouchPressed(touch, false)
	release(binding, input)
end

-- Handlers run immediately and may bind or unbind actions themselves (opening a
-- panel binds CloseMenu), so loops walk a copy and skip bindings removed meanwhile.
local function forEachBinding(callback: (binding: Binding) -> ())
	for actionName, binding in table.clone(bindings) do
		if bindings[actionName] == binding then
			callback(binding)
		end
	end
end

local function releaseBinding(binding: Binding)
	releaseTouch(binding)
	for holder in table.clone(binding.holders) do
		release(binding, holder)
	end
end

local function releaseAll()
	forEachBinding(releaseBinding)
end

-- The keys of `binding` for the device that produced `input` (nil: not a key device).
local function keysFor(binding: Binding, inputType: Enum.UserInputType): { Enum.KeyCode }?
	if inputType == Enum.UserInputType.Keyboard then
		return binding.config.Keyboard
	elseif GAMEPAD_INPUT_TYPES[inputType] then
		return binding.config.Gamepad
	end
	return nil
end

local function hasMouseButton(binding: Binding, inputType: Enum.UserInputType): boolean
	local buttons = binding.config.Mouse
	return buttons ~= nil and table.find(buttons, inputType) ~= nil
end

-- True if `binding` lists the key of `input` for the device that produced it.
local function hasKey(binding: Binding, inputType: Enum.UserInputType, keyCode: Enum.KeyCode): boolean
	local keys = keysFor(binding, inputType)
	return keys ~= nil and table.find(keys, keyCode) ~= nil
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	local inputType = input.UserInputType
	-- While a panel is open its menu key belongs to the panel alone: the same
	-- button may mean something else in play (gamepad B also dives in flight).
	local menuBinding = bindings[menuConfig.MenuAction]
	if menuBinding ~= nil and hasKey(menuBinding, inputType, input.KeyCode) then
		press(menuBinding, input.KeyCode)
		return
	end
	if MOUSE_BUTTONS[inputType] then
		-- On touch a tap also arrives as a mouse click; touch has its own buttons.
		if device == "Touch" then
			return
		end
		forEachBinding(function(binding: Binding)
			if hasMouseButton(binding, inputType) then
				press(binding, inputType)
			end
		end)
		return
	end
	forEachBinding(function(binding: Binding)
		if hasKey(binding, inputType, input.KeyCode) then
			press(binding, input.KeyCode)
		end
	end)
end

-- Releases are handled even when the game processed them: a key pressed in
-- gameplay and released while chat has focus must still end the hold.
local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	local inputType = input.UserInputType
	forEachBinding(function(binding: Binding)
		local touch = binding.touch
		if touch ~= nil and touch.input == input then
			releaseTouch(binding)
		elseif MOUSE_BUTTONS[inputType] then
			release(binding, inputType)
		elseif keysFor(binding, inputType) ~= nil then
			release(binding, input.KeyCode)
		end
	end)
end

-- Shows every bound touch button, or only the Keep ones while a panel is open.
-- A button that hides releases its touch: its release would never arrive.
local function refreshTouchVisibility()
	local menuOpen = bindings[menuConfig.MenuAction] ~= nil
	forEachBinding(function(binding: Binding)
		local touch = binding.touch
		if touch == nil then
			return
		end
		local visible = not menuOpen or table.find(menuConfig.Keep, binding.name) ~= nil
		if touch.button.Visible ~= visible then
			touch.button.Visible = visible
			if not visible then
				releaseTouch(binding)
			end
		end
	end)
end

-- The touch buttons show only on touch, and only while nothing hides them.
local function refreshTouchGui()
	local gui = touchGui
	if gui == nil then
		return
	end
	local show = device == "Touch" and next(touchHiddenReasons) == nil
	if not show then
		-- A hidden button never receives its release.
		forEachBinding(releaseTouch)
	end
	gui.Enabled = show
end

local function buildTouchButton(
	binding: Binding,
	actionName: string,
	config: Types.TouchButtonConfig,
	parent: ScreenGui
)
	local button = Instance.new("TextButton")
	button.Name = actionName
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = config.Position
	button.Size = UDim2.fromOffset(config.Size, config.Size)
	button.BackgroundColor3 = Theme.PanelColor
	button.BackgroundTransparency = Theme.PanelTransparency
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	-- Touch-only: gamepad UI navigation must never land on it.
	button.Selectable = false
	button.Text = config.Label
	button.FontFace = Theme.FontBold
	button.TextSize = UIConfig.TouchButton.TextSize
	button.TextColor3 = Theme.TextPrimary
	button.TextWrapped = true
	Create.corner(button, UDim.new(0.5, 0))
	local stroke = Create.stroke(button, Theme.RingGreen, UIConfig.TouchButton.StrokeThickness)

	local touch: TouchButton = { button = button, stroke = stroke, input = nil }
	binding.touch = touch

	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch or touch.input ~= nil then
			return
		end
		touch.input = input
		setTouchPressed(touch, true)
		press(binding, input)
	end)
	-- Normally the release arrives through UserInputService.InputEnded (even when
	-- the finger slid off the button); this covers it ending over the button too.
	-- releaseTouch only acts once per touch.
	button.InputEnded:Connect(function(input: InputObject)
		if touch.input == input then
			releaseTouch(binding)
		end
	end)

	button.Parent = parent
end

function InputController.GetDevice(_self: InputController): Types.InputDevice
	return device
end

-- Calls handler("Begin") when the action is pressed and handler("End") when it
-- is released. Only valid after InputController:Init.
function InputController.BindAction(_self: InputController, actionName: string, handler: ActionHandler)
	local config = InputConfig.Actions[actionName]
	assert(config ~= nil, `Unknown action "{actionName}" (not in Config.Input.Actions)`)
	assert(bindings[actionName] == nil, `Action "{actionName}" is already bound`)
	local gui = touchGui
	assert(gui ~= nil, "InputController:BindAction() called before InputController:Init()")

	local binding: Binding = { name = actionName, config = config, handler = handler, holders = {}, touch = nil }
	bindings[actionName] = binding
	if config.Touch ~= nil then
		buildTouchButton(binding, actionName, config.Touch, gui)
	end
	refreshTouchVisibility()
end

-- Removes the action's handler and touch button. A held action gets its "End"
-- first, so a hold can never get stuck.
function InputController.UnbindAction(_self: InputController, actionName: string)
	local binding = bindings[actionName]
	if binding == nil then
		return
	end
	-- Removed first, so the "End" handler may safely bind the action again.
	bindings[actionName] = nil
	local touch = binding.touch
	releaseBinding(binding)
	if touch ~= nil then
		binding.touch = nil
		-- Destroying the button also disconnects its event connections.
		touch.button:Destroy()
	end
	refreshTouchVisibility()
end

function InputController.IsHeld(_self: InputController, actionName: string): boolean
	local binding = bindings[actionName]
	return binding ~= nil and isHeld(binding)
end

-- Changes the text on a bound action's touch button (e.g. "Fly" -> "Land").
-- Does nothing for an action that is not bound or has no touch button.
function InputController.SetTouchLabel(_self: InputController, actionName: string, label: string)
	local binding = bindings[actionName]
	local touch = if binding ~= nil then binding.touch else nil
	if touch ~= nil then
		touch.button.Text = label
	end
end

function InputController.IsMenuOpen(_self: InputController): boolean
	return bindings[menuConfig.MenuAction] ~= nil
end

-- The touch pressing the action's on-screen button right now, or nil.
function InputController.GetTouchInput(_self: InputController, actionName: string): InputObject?
	local binding = bindings[actionName]
	local touch = if binding ~= nil then binding.touch else nil
	return if touch ~= nil then touch.input else nil
end

-- Hides (true) or shows again (false) every touch button for `reason`; they
-- stay hidden while any reason is set. Nothing changes off touch.
function InputController.SetTouchHidden(_self: InputController, reason: string, hidden: boolean)
	if hidden then
		touchHiddenReasons[reason] = true
	else
		touchHiddenReasons[reason] = nil
	end
	refreshTouchGui()
end

function InputController.Init(_self: InputController)
	touchGui = HudController:CreateScreenGui("TouchControls", { DisplayOrder = UIConfig.DisplayOrder.TouchControls })
	refreshTouchGui()

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	UserInputService.WindowFocusReleased:Connect(releaseAll)

	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		local newDevice: Types.InputDevice = readDevice()
		if newDevice == device then
			return
		end
		device = newDevice
		refreshTouchGui()
		InputController.DeviceChanged:Fire(newDevice)
	end)
end

function InputController.Start(_self: InputController) end

export type InputController = typeof(InputController)

return InputController
