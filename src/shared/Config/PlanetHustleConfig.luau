-- Planet Hustle balancing config. Placeholder numbers per build prompt #1 — tune later.
local PlanetHustleConfig = {}

PlanetHustleConfig.DoorDash = {
	minReward = 1,
	maxReward = 3,
	cooldown = 3, -- seconds per house
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
	unlockCost = 800,
	rewardPerLoop = 15,
	cooldown = 10,
}

PlanetHustleConfig.FreelanceGigHub = {
	unlockCost = 4_000,
	incomePerSecond = 50,
}

return PlanetHustleConfig
