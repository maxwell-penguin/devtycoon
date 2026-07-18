-- Formats numbers for display: under 1000 as-is, above that abbreviated
-- with K/M/B/T suffixes (e.g. 1.2K, 3.4M).
local NumberFormatter = {}

local SUFFIXES = { "", "K", "M", "B", "T" }

function NumberFormatter.Format(n: number): string
	local sign = n < 0 and "-" or ""
	n = math.abs(n)

	local magnitude = 1
	while magnitude < #SUFFIXES and n >= 1000 ^ magnitude do
		magnitude += 1
	end
	magnitude -= 1

	if magnitude <= 0 then
		return sign .. tostring(math.floor(n))
	end

	local scaled = n / (1000 ^ magnitude)
	-- "%.1f" rounding can push e.g. 999,950 -> "1000.0K"; bump a suffix instead.
	if math.floor(scaled * 10 + 0.5) >= 10000 and magnitude < #SUFFIXES - 1 then
		magnitude += 1
		scaled = n / (1000 ^ magnitude)
	end

	-- ponytail: caps at T (matches Planet Hustle's <1e15 numbers); add
	-- Quadrillion+ suffixes here if a later planet needs bigger numbers.
	return sign .. string.format("%.1f%s", scaled, SUFFIXES[magnitude + 1])
end

-- Full integer with thousands separators — for the HUD cash counter where
-- the design brief calls for "$1,234,567" style, not K/M/B abbreviation.
function NumberFormatter.WithCommas(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	while true do
		local next, count = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
		s = next
		if count == 0 then
			break
		end
	end
	return (n < 0 and "-" or "") .. s
end

return NumberFormatter
