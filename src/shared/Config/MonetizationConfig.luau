--!strict
--[[
	MonetizationConfig — gamepass and developer product definitions.

	=========================================================================
	MANUAL STEP REQUIRED
	Every Id below is 0. Gamepasses and developer products cannot be created
	from code — you must create them on the Creator Dashboard for this
	experience, then paste their ids here.

	Until an id is filled in, that product is INACTIVE: the shop hides it and
	the server refuses to grant its benefit. Nothing errors, nothing is
	awarded for free.
	=========================================================================
]]

export type Gamepass = {
	Id: number,
	Name: string,
	Description: string,
	-- Applied by the relevant service when the player owns the pass.
	Benefits: { [string]: any },
	Order: number,
}

export type Product = {
	Id: number,
	Name: string,
	Description: string,
	Grant: { [string]: any },
	Order: number,
}

local MonetizationConfig = {}

MonetizationConfig.Gamepasses = {
	VIP = {
		Id = 0,
		Name = "VIP",
		Description = "Chat tag, +25% coins, +10% luck, and an exclusive aura.",
		Benefits = {
			CoinMultiplier = 1.25,
			LuckBonus = 0.10,
			ChatTag = "VIP",
			Cosmetic = "AuraVIP",
		},
		Order = 1,
	},

	AutoRoll = {
		Id = 0,
		Name = "Auto Roll",
		Description = "Unlocks hands-free rolling with a rarity stop condition.",
		Benefits = {
			UnlockAutoRoll = true,
		},
		Order = 2,
	},

	FastRolls = {
		Id = 0,
		Name = "Fast Rolls",
		Description = "Cuts the roll cooldown in half.",
		Benefits = {
			CooldownMultiplier = 0.5,
		},
		Order = 3,
	},

	ExtraInventory = {
		Id = 0,
		Name = "Extra Inventory",
		Description = "+300 inventory slots.",
		Benefits = {
			InventoryBonus = 300,
		},
		Order = 4,
	},

	ExtraEquipmentSlot = {
		Id = 0,
		Name = "Extra Accessory Slot",
		Description = "A second accessory slot.",
		Benefits = {
			ExtraAccessorySlots = 1,
		},
		Order = 5,
	},
} :: { [string]: Gamepass }

MonetizationConfig.Products = {
	LuckBoost1H = {
		Id = 0,
		Name = "2x Luck (1 Hour)",
		Description = "Doubles your luck for one hour.",
		Grant = { Boost = "Luck2x", Duration = 3600 },
		Order = 1,
	},

	CoinPackSmall = {
		Id = 0,
		Name = "Small Coin Pack",
		Description = "10,000 coins.",
		Grant = { Coins = 10_000 },
		Order = 2,
	},

	CoinPackLarge = {
		Id = 0,
		Name = "Large Coin Pack",
		Description = "100,000 coins.",
		Grant = { Coins = 100_000 },
		Order = 3,
	},

	XPBoost1H = {
		Id = 0,
		Name = "2x XP (1 Hour)",
		Description = "Doubles XP gain for one hour.",
		Grant = { Boost = "XP2x", Duration = 3600 },
		Order = 4,
	},
} :: { [string]: Product }

--[[ True when an id has actually been filled in. ]]
function MonetizationConfig.IsConfigured(entry: { Id: number }): boolean
	return type(entry.Id) == "number" and entry.Id > 0
end

--[[ Reverse lookup for ProcessReceipt, which only gets a numeric product id. ]]
function MonetizationConfig.GetProductById(productId: number): (string?, Product?)
	for key, product in pairs(MonetizationConfig.Products) do
		if product.Id == productId and product.Id > 0 then
			return key, product
		end
	end
	return nil, nil
end

function MonetizationConfig.GetGamepassById(passId: number): (string?, Gamepass?)
	for key, pass in pairs(MonetizationConfig.Gamepasses) do
		if pass.Id == passId and pass.Id > 0 then
			return key, pass
		end
	end
	return nil, nil
end

--[[ Human-readable list of everything still needing a dashboard id. ]]
function MonetizationConfig.GetUnconfigured(): { string }
	local missing = {}

	for key, pass in pairs(MonetizationConfig.Gamepasses) do
		if not MonetizationConfig.IsConfigured(pass) then
			table.insert(missing, string.format("Gamepass.%s (%s)", key, pass.Name))
		end
	end

	for key, product in pairs(MonetizationConfig.Products) do
		if not MonetizationConfig.IsConfigured(product) then
			table.insert(missing, string.format("Product.%s (%s)", key, product.Name))
		end
	end

	table.sort(missing)
	return missing
end

return MonetizationConfig
