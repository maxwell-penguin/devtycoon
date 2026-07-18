local UI = script.Parent.UI
local HUDController = require(UI.HUDController)
local PurchasePromptUI = require(UI.PurchasePromptUI)
local LotteryUI = require(UI.LotteryUI)

HUDController.Init()
PurchasePromptUI.Init()
LotteryUI.Init()

print("[PlanetHustle] Client initialized")
