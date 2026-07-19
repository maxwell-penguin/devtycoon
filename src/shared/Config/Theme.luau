-- Planet Hustle brand palette. Single source of truth so every zone/HUD/
-- effect references the same colors instead of re-picking hex values.
local Theme = {}

Theme.Brand = Color3.fromRGB(255, 107, 53) -- #FF6B35 Hustle Orange
Theme.Secondary = Color3.fromRGB(123, 47, 247) -- #7B2FF7 Electric Violet
Theme.CashPositive = Color3.fromRGB(51, 255, 136) -- #33FF88
Theme.Warning = Color3.fromRGB(255, 59, 71) -- #FF3B47
Theme.Locked = Color3.fromRGB(58, 74, 94) -- #3A4A5E
Theme.AffordablePulse = Color3.fromRGB(0, 217, 255) -- #00D9FF
Theme.OutlineStroke = Color3.fromRGB(10, 10, 20) -- #0A0A14
Theme.Gold = Color3.fromRGB(255, 220, 90)

return Theme
