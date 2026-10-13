--!strict
--[[
	SoundController: every ring-power sound on this client.

	Sounds are named by their key in Config.Assets.Sounds, never by asset id, so
	all audio is swapped in one place. An empty id means "no sound yet": every
	call with it quietly does nothing, so the game works before audio exists.

	  * One-shots (Play): at a part or a world position they are 3D (rolling off
	    with distance, Config.Assets.RollOff*); without one they play 2D from
	    SoundService. Each removes itself when it ends, or after
	    Config.Assets.MaxOneShotSeconds at the latest.
	  * Loops (StartLoop / StopLoop) are keyed by an id the caller picks (e.g.
	    "Beam_123"), so starting the same loop twice never doubles it. A loop is
	    forgotten by itself when its parent is destroyed (a character
	    respawning), and fades out briefly when stopped.

	API:
	  SoundController:Play(soundKey, at?: BasePart | Vector3): Sound?
	  SoundController:StartLoop(loopId, soundKey, parent): Sound?   (parent SoundService for 2D)
	  SoundController:GetLoop(loopId): Sound?
	  SoundController:StopLoop(loopId)
	  SoundController:HasSound(soundKey): boolean
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AssetsConfig = require(ReplicatedStorage.Shared.Config.Assets)

type Loop = {
	sound: Sound,
	soundKey: string,
	parent: Instance,
	destroying: RBXScriptConnection,
}

local SOUND_IDS: { [string]: string } = AssetsConfig.Sounds

local loops: { [string]: Loop } = {}

local SoundController = {}

local function soundIdFor(soundKey: string): string?
	local id = SOUND_IDS[soundKey]
	if type(id) ~= "string" or id == "" then
		return nil
	end
	return id
end

local function newSound(soundKey: string, id: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = soundKey
	sound.SoundId = id
	sound.Volume = AssetsConfig.SoundVolume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = AssetsConfig.RollOffMinDistance
	sound.RollOffMaxDistance = AssetsConfig.RollOffMaxDistance
	return sound
end

-- An invisible point in the world to hang a 3D sound on. Attachments in
-- Terrain take world positions directly.
local function anchorAt(position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "SoundAnchor"
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	return attachment
end

function SoundController.HasSound(_self: SoundController, soundKey: string): boolean
	return soundIdFor(soundKey) ~= nil
end

-- Plays a sound once: at `at` (a part, which it follows, or a fixed position)
-- in 3D, or 2D without it. Returns the Sound, or nil when the key has no id.
function SoundController.Play(_self: SoundController, soundKey: string, at: (BasePart | Vector3)?): Sound?
	local id = soundIdFor(soundKey)
	if id == nil then
		return nil
	end
	local sound = newSound(soundKey, id)
	-- What to remove when it ends: the sound, or the anchor it hangs on.
	local holder: Instance = sound
	if typeof(at) == "Vector3" then
		local anchor = anchorAt(at)
		sound.Parent = anchor
		holder = anchor
	elseif typeof(at) == "Instance" then
		if at.Parent == nil then
			-- The part is already gone: nothing sensible to play at.
			sound:Destroy()
			return nil
		end
		sound.Parent = at
	else
		sound.Parent = SoundService
	end
	sound.Ended:Once(function()
		holder:Destroy()
	end)
	-- Backstop: a sound that fails to load never fires Ended.
	Debris:AddItem(holder, AssetsConfig.MaxOneShotSeconds)
	sound:Play()
	return sound
end

local function removeLoop(loopId: string, fade: boolean)
	local loop = loops[loopId]
	if loop == nil then
		return
	end
	loops[loopId] = nil
	loop.destroying:Disconnect()
	local sound = loop.sound
	if not fade or sound.Parent == nil or AssetsConfig.LoopFadeTime <= 0 then
		sound:Destroy()
		return
	end
	local tween = TweenService:Create(sound, TweenInfo.new(AssetsConfig.LoopFadeTime), { Volume = 0 })
	tween.Completed:Once(function()
		sound:Destroy()
	end)
	tween:Play()
end

-- Starts a looped sound under `parent` (a part for 3D, SoundService for 2D),
-- keyed by `loopId`. Already running with the same sound and parent: kept as
-- it is. Returns the Sound, or nil when the key has no id.
function SoundController.StartLoop(_self: SoundController, loopId: string, soundKey: string, parent: Instance): Sound?
	local existing = loops[loopId]
	if existing ~= nil then
		if existing.soundKey == soundKey and existing.parent == parent and existing.sound.Parent == parent then
			return existing.sound
		end
		removeLoop(loopId, false)
	end
	local id = soundIdFor(soundKey)
	-- A parent already removed from the game (a character that just despawned).
	if id == nil or parent.Parent == nil then
		return nil
	end
	local sound = newSound(soundKey, id)
	sound.Looped = true
	sound.Parent = parent
	local loop: Loop
	loop = {
		sound = sound,
		soundKey = soundKey,
		parent = parent,
		-- The parent (e.g. a character) went away and took the sound with it.
		destroying = sound.Destroying:Connect(function()
			if loops[loopId] == loop then
				loops[loopId] = nil
				loop.destroying:Disconnect()
			end
		end),
	}
	loops[loopId] = loop
	sound:Play()
	return sound
end

function SoundController.GetLoop(_self: SoundController, loopId: string): Sound?
	local loop = loops[loopId]
	if loop == nil or loop.sound.Parent == nil then
		return nil
	end
	return loop.sound
end

function SoundController.StopLoop(_self: SoundController, loopId: string)
	removeLoop(loopId, true)
end

function SoundController.Init(_self: SoundController) end

function SoundController.Start(_self: SoundController) end

export type SoundController = typeof(SoundController)

return SoundController
