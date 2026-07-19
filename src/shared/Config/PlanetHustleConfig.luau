-- Planet Hustle balancing config. Placeholder numbers per build prompt #1 — tune later.
local PlanetHustleConfig = {}

PlanetHustleConfig.DoorDash = {
	-- No longer the always-free starter (Dog Walking took that role) - a
	-- cheap one-time unlock inside the shared per-plot neighborhood instead.
	unlockCost = 100,

	minReward = 1,
	maxReward = 3,
	cooldown = 3, -- seconds per house, tier 0 (no Speed upgrade)
	startingHouseCount = 4,
	maxHouseCount = 8,

	-- Phase 2: Value track. Cash-gated, no Manager required. Each tier
	-- REPLACES the previous one (not stacked) - tier N's multiplier applies
	-- directly to the base min/maxReward roll.
	valueTiers = {
		{ name = "Insulated Bags", cost = 50, multiplier = 1.5 },
		{ name = "Premium Packaging", cost = 250, multiplier = 2 },
		{ name = "Priority Orders", cost = 1000, multiplier = 3 },
	},

	-- Phase 2: Speed track. Cash-gated. Each tier replaces the previous
	-- per-house cooldown (seconds).
	speedTiers = {
		{ name = "E-Bike", cost = 75, cooldown = 2 },
		{ name = "Scooter Upgrade", cost = 300, cooldown = 1 },
		{ name = "Drone Delivery", cost = 1200, cooldown = 0.5 },
	},

	-- Phase 3: "Hire a Dispatcher" - one-time purchase, flips DoorDash from
	-- manual-only to auto-triggering (manual E-press still works, just
	-- resets that house's own timer rather than stacking).
	managerCost = 4000,

	-- Phase 4: Scale. Requires Manager owned first. Extra houses beyond
	-- startingHouseCount, up to maxHouseCount, priced individually and
	-- escalating (index 1 = house 5's cost, etc).
	extraHouseCosts = { 1500, 2500, 4000, 6000 },

	-- Phase 4: Scale tiers reskin the whole neighborhood and multiply the
	-- BASE reward roll (applied before the Value track multiplier). Tier 0
	-- ("Houses") is the starting look, implicit multiplier 1.
	scaleTiers = {
		{ name = "Neighborhood Upgrade", cost = 15000, baseMultiplier = 2 },
		{ name = "Office Building", cost = 50000, baseMultiplier = 5 },
	},
}

PlanetHustleConfig.Rideshare = {
	unlockCost = 150,
	rewardPerLoop = 5,
	cooldown = 5,
}

PlanetHustleConfig.Lottery = {
	unlockCost = 500,
	ticketPrice = 20,
	cooldown = 3, -- seconds between pulls per player per booth
	-- Weighted outcomes, weights sum to 1. Multiplier rolled uniformly in
	-- [minMultiplier, maxMultiplier] once outcome is picked. Theoretical
	-- expected multiplier ≈ 0.9475 (~5% house edge on the $20 ticket).
	outcomes = {
		{ name = "smallLoss", weight = 0.75, minMultiplier = 0, maxMultiplier = 0.4 },
		{ name = "modestWin", weight = 0.20, minMultiplier = 1.5, maxMultiplier = 2.5 },
		{ name = "bigWin", weight = 0.045, minMultiplier = 4, maxMultiplier = 7 },
		{ name = "jackpot", weight = 0.005, minMultiplier = 20, maxMultiplier = 40 },
	},
}

PlanetHustleConfig.DogWalking = {
	-- Now the always-free starter (swapped roles with DoorDash) - no
	-- unlockCost, available the moment a player's plot exists.
	rewardPerLoop = 15,
	cooldown = 10,
}

PlanetHustleConfig.FreelanceGigHub = {
	unlockCost = 4_000,
	incomePerSecond = 50,
}

return PlanetHustleConfig
