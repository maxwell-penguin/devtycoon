local UI = script.Parent.UI
local HUDController = require(UI.HUDController)
local PurchasePromptUI = require(UI.PurchasePromptUI)
local LotteryUI = require(UI.LotteryUI)
local DogWalkingButton = require(UI.DogWalkingButton)
local OnboardingPointer = require(UI.OnboardingPointer)
local CameraShakeController = require(script.Parent.CameraShakeController)

HUDController.Init()
PurchasePromptUI.Init()
LotteryUI.Init()
DogWalkingButton.Init()
OnboardingPointer.Init()
CameraShakeController.Init()

print("[PlanetHustle] Client initialized")
