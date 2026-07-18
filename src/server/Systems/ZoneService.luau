-- Zone-walk-to-buy: locked zones show price, touch triggers a buy prompt on the
-- client, confirm is validated server-side, then plays the build animation.
-- Implemented in Step 5 (pattern) and Step 6 (remaining zones).
local ZoneService = {}

function ZoneService.Init() end

function ZoneService.IsOwned(player: Player, zoneId: string): boolean
	return false
end

return ZoneService
