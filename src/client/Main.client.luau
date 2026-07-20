local UI = script.Parent.UI
local HUDController = require(UI.HUDController)
local PurchasePromptUI = require(UI.PurchasePromptUI)
local LotteryUI = require(UI.LotteryUI)
local CameraShakeController = require(script.Parent.CameraShakeController)

HUDController.Init()
PurchasePromptUI.Init()
LotteryUI.Init()
CameraShakeController.Init()

print("[PlanetHustle] Client initialized")
