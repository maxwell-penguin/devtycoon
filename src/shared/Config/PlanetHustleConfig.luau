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
}

PlanetHustleConfig.Lottery = {
	unlockCost = 500,
	ticketPrice = 20,
	-- Weighted outcomes, must sum to 1. payoutMultiplier is applied to ticketPrice.
	-- For smallLoss, payoutMultiplier is rolled between min/max at resolve time.
	outcomes = {
		{ name = "smallLoss", weight = 0.60, minMultiplier = 0, maxMultiplier = 0.5 },
		{ name = "modestWin", weight = 0.30, minMultiplier = 2, maxMultiplier = 3 },
		{ name = "bigWin", weight = 0.09, minMultiplier = 5, maxMultiplier = 10 },
		{ name = "jackpot", weight = 0.01, minMultiplier = 50, maxMultiplier = 100 },
	},
}

PlanetHustleConfig.DogWalking = {
	unlockCost = 800,
	rewardPerLoop = 15,
}

PlanetHustleConfig.FreelanceGigHub = {
	unlockCost = 4_000,
	incomePerSecond = 50,
}

return PlanetHustleConfig
