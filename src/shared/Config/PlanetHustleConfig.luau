-- Planet Hustle balancing config. Placeholder numbers per build prompt #1 — tune later.
local PlanetHustleConfig = {}

PlanetHustleConfig.DoorDash = {
	-- No longer the always-free starter (Dog Walking took that role) - a
	-- cheap one-time unlock inside the shared per-plot neighborhood instead.
	unlockCost = 100,

	minReward = 1,
	maxReward = 3,
	cooldown = 3, -- seconds per house, tier 0 (no Speed upgrade)
	maxHouseCount = 8,

	-- Phase 4 (purchase-pad branch): the neighborhood now starts genuinely
	-- empty - these 4 original row houses used to be bundled free with
	-- unlockCost, now each is its own pad purchase. Deliberately cheap/fast
	-- (Sell Lemons-style early economy - big numbers come later from a
	-- future prestige/rebirth system, not from Planet Hustle itself).
	startingHouseCosts = { 50, 150, 350, 750 },

	-- 2 more pads beyond Cargo Plane's existing auto-granted 5th/6th house
	-- (unchanged - see vehicleTiers below), reaching maxHouseCount=8.
	-- Deliberately steep: a late-game chase for players already deep in,
	-- not part of the fast early loop.
	extraHousePadCosts = { 50000, 150000 },

	-- Phase 2: Value track. Cash-gated, no Manager required. Each tier
	-- REPLACES the previous one (not stacked) - tier N's multiplier applies
	-- directly to the base min/maxReward roll.
	valueTiers = {
		{ name = "Insulated Bags", cost = 50, multiplier = 1.5 },
		{ name = "Premium Packaging", cost = 250, multiplier = 2 },
		{ name = "Priority Orders", cost = 1000, multiplier = 3 },
	},

	-- Phase 2: Speed track. Cash-gated. Each tier replaces the previous
	-- per-house cooldown (seconds). Deliberately gentler than Dog Walking's
	-- floor (1.5s vs 1.5s... but DoorDash has 4-6 SIMULTANEOUS houses once
	-- Manager is hired, so its aggregate $/s multiplies by house count - a
	-- 0.5s floor here (an earlier dormant draft's number) would have blown
	-- way past the target ceiling once combined with Vehicle tiers below.
	speedTiers = {
		{ name = "Tuned Engine", cost = 75, cooldown = 2.5 },
		{ name = "Bigger Fuel Tank", cost = 300, cooldown = 2 },
		{ name = "Racing Slicks", cost = 1200, cooldown = 1.5 },
	},

	-- Phase 3: "Hire a Dispatcher" - one-time purchase, flips DoorDash from
	-- manual-only to auto-triggering (manual E-press still works, just
	-- resets that house's own timer rather than stacking).
	managerCost = 4000,

	-- Phase 4: Vehicle tier escalation - DoorDash's OWN scale identity,
	-- distinct from Dog Walking's neighborhood-growth scale. Each tier
	-- REPLACES the previous (not stacked): valueMultiplier stacks
	-- multiplicatively with the Value track, cooldownMultiplier applies to
	-- whatever the Speed track achieved. Deliberately modest per-tier bumps -
	-- Cargo Plane's headline feature is +2 houses (extraHouses), not a huge
	-- number, since 4-6 simultaneous houses already does most of the
	-- heavy lifting on the aggregate $/s ceiling.
	-- Full-investment math: 2(avgBase) * 3(Value) * 1.33(CargoPlane) *
	-- 2(Neighborhood) / (1.5s * 0.8) * 6 houses ≈ $80/s - ~1.33x Dog
	-- Walking's $60/s ceiling, ~1.6x Freelance's $50/s, both within the
	-- requested 1.2-1.8x band.
	vehicleTiers = {
		{ name = "Delivery Van", cost = 5000, valueMultiplier = 1.1, cooldownMultiplier = 0.95 },
		{ name = "Drone Fleet", cost = 12000, valueMultiplier = 1.18, cooldownMultiplier = 0.9 },
		{ name = "Helicopter", cost = 30000, valueMultiplier = 1.25, cooldownMultiplier = 0.85 },
		{ name = "Cargo Plane", cost = 75000, valueMultiplier = 1.33, cooldownMultiplier = 0.8, extraHouses = 2 },
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
	-- Deliberately snappy base for the on-screen Walk button - a 10s
	-- cooldown felt slow on the click UX and left no headroom above
	-- Comfortable Shoes' old 6s. Every tier below strictly reduces from
	-- this base.
	cooldown = 2,

	-- Value track. Each tier REPLACES the previous (not stacked) - tier N's
	-- multiplier applies directly to rewardPerLoop. Ceiling dropped from 3x
	-- to 2x during the balance retune - the old 3x combined with Neighborhood
	-- (2x) and 3 parallel stations at Speed 3 pushed aggregate to $540/s,
	-- ~9x Freelance's $50/s baseline.
	valueTiers = {
		{ name = "Better Leashes", cost = 20, multiplier = 1.25 },
		{ name = "Treats & Toys", cost = 150, multiplier = 1.5 },
		{ name = "Premium Grooming Add-on", cost = 600, multiplier = 2 },
	},

	-- Speed track. Each tier replaces the previous cooldown (seconds).
	-- Retuned floor from 0.5s to 1.5s alongside the Value ceiling drop above -
	-- max aggregate now lands at $120/s (15 base × 2 Value × 2 Neighborhood /
	-- 1.5s × 3 stations), within the $80-120/s ceiling target.
	speedTiers = {
		{ name = "Comfortable Shoes", cost = 30, cooldown = 1.75 },
		{ name = "Golf Cart", cost = 200, cooldown = 1.6 },
		{ name = "E-Bike Delivery Route", cost = 800, cooldown = 1.5 },
	},

	-- "Hire a Dog Walker" - one-time purchase, flips Dog Walking from
	-- manual-only to auto-triggering (manual E-press still works, just
	-- resets the station's own timer rather than stacking).
	managerCost = 2000,

	-- Phase 4 (purchase-pad branch): 2 more stations beyond the original
	-- free one, each a full LeashPost+dogs prop with its own ClickDetector
	-- and Manager auto-collect loop.
	stationCosts = { 300, 1500 },
}

-- Neighborhood Upgrade: the one Scale tier this pass builds (DoorDash's own
-- Office Building tier is a separate future pass). One shared purchase that
-- multiplies the BASE reward for BOTH Dog Walking and DoorDash, since they
-- share one neighborhood plot - lives at the top level rather than nested
-- under either hustle's config. At max Dog Walking Value+Speed+this:
-- 15 * 3 * 2 / 1.5 = $60/s, ~1.2x Freelance Gig Hub's $50/s passive ceiling.
PlanetHustleConfig.Neighborhood = {
	upgradeCost = 10000,
	upgradeMultiplier = 2,
}

PlanetHustleConfig.FreelanceGigHub = {
	unlockCost = 4_000,
	incomePerSecond = 50,
}

return PlanetHustleConfig
