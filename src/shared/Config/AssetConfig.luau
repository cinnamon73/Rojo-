--!strict
--[[
	AssetConfig — every external asset id in one place.

	IDs are deliberately left as 0 rather than filled with plausible-looking
	numbers. A 0 is an obvious "not configured yet"; a wrong id is a silent
	failure that sounds like a bug in the audio system.

	Helpers below return nil for unconfigured ids so callers can no-op cleanly
	instead of spamming "Unable to load asset" into the console.

	To wire real assets: upload them, then paste the ids here. Nothing else in
	the codebase needs to change.
]]

local AssetConfig = {}

--[[ Sound ids by logical name. ]]
AssetConfig.Sounds = {
	ButtonClick = 0,
	ButtonHover = 0,


	Error = 0,

	AttackSwing = 0,
	AttackHit = 0,
	EnemyDeath = 0,
	BossAttack = 0,
	BossDeath = 0,

	QuestComplete = 0,
	LevelUp = 0,
	GlobalAnnounce = 0,
}

--[[
	Image ids. Chrome only.

	The gear panel artwork and per-slot icons were removed with the inventory
	UI. The uploaded panel asset still exists in the CGS Student Development
	group if it is ever wanted for a class select or shop screen — it is not
	referenced by any code now.
]]
AssetConfig.Images = {
	CoinIcon = 0,
	GemIcon = 0,
	LuckIcon = 0,
	PowerIcon = 0,
}

AssetConfig.Volume = {
	UI = 0.4,
	Reveal = 0.6,
	Combat = 0.5,
	Ambient = 0.25,
}

--[[
	Resolves a sound name to a content string, or nil when unconfigured.
	Callers should treat nil as "play nothing".
]]
function AssetConfig.GetSound(name: string): string?
	local id = AssetConfig.Sounds[name]
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	return "rbxassetid://" .. tostring(id)
end

--[[ Reveal sound for a rarity's SoundTier, or nil. ]]
function AssetConfig.GetRevealSound(tier: number): string?
	return AssetConfig.GetSound("Reveal" .. tostring(math.clamp(tier, 1, 6)))
end

--[[ Resolves an image name to a content string, or nil when unconfigured. ]]
function AssetConfig.GetImage(name: string): string?
	local id = AssetConfig.Images[name]
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	return "rbxassetid://" .. tostring(id)
end

--[[ Names of every asset still left at 0. Printed once at startup. ]]
function AssetConfig.GetUnconfigured(): { string }
	local missing = {}

	for name, id in pairs(AssetConfig.Sounds) do
		if type(id) == "number" and id <= 0 then
			table.insert(missing, "Sounds." .. name)
		end
	end

	for name, id in pairs(AssetConfig.Images) do
		if type(id) == "number" and id <= 0 then
			table.insert(missing, "Images." .. name)
		end
	end

	table.sort(missing)
	return missing
end

return AssetConfig
