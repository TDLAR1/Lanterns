--!strict
--[[
	Shared types used by both server and client.

	Keep this file dependency-free (types only) so any module can require it
	without creating require cycles.
]]

-- Every district of the playable world. Ids are stable: they are saved in player
-- data and used as Workspace folder names, so never rename an existing id.
export type DistrictId = "Downtown" | "Farmstead" | "NorthFields" | "Residential" | "SouthFields" | "RailYard" | "OuterRing"

export type DistrictInfo = {
	Id: DistrictId,
	DisplayName: string,
	Subtitle: string,
}

-- Saved player data (ProfileStore profile.Data). Only JSON-compatible values:
-- no Instances, Vector3s, functions, or arrays with holes.
-- New fields are filled in automatically from Config.Data.Template (Profile:Reconcile).
export type PlayerData = {
	SchemaVersion: number,
	-- Set of discovered district ids (id -> true). A set, not an array, so the
	-- same district can never be counted twice.
	DiscoveredDistricts: { [string]: boolean },
}

-- What the client is allowed to know about its own saved data on join.
export type ProfileSummary = {
	SessionCount: number,
	DiscoveredDistricts: { string },
	TotalDistricts: number,
	-- False when the DataStore is unavailable (e.g. Studio without API access):
	-- progress still works for this session but will not be saved.
	SavingEnabled: boolean,
}

export type NotifyKind = "Info" | "Success" | "Warning"

export type InputDevice = "KeyboardMouse" | "Gamepad" | "Touch"

export type ActionPhase = "Begin" | "End"

-- On-screen button for an action on touch devices.
export type TouchButtonConfig = {
	Label: string,
	-- Anchor point is (0.5, 0.5); position is relative to the TouchControls ScreenGui.
	Position: UDim2,
	-- Diameter in pixels before UI scaling.
	Size: number,
}

export type InputActionConfig = {
	Keyboard: { Enum.KeyCode },
	Gamepad: { Enum.KeyCode },
	Touch: TouchButtonConfig?,
}

return nil
