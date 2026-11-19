local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Formula = require(Shared:WaitForChild("Formula"))
local Bars = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Bars"))
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)

local trainStart = Net.Event("TrainStart")
local trainState = Net.Event("TrainState")
local trainRep = Net.Event("TrainRep")
local trainStop = Net.Event("TrainStop")
local barUpgrade = Net.Event("BarUpgrade")
local trainBonus = Net.Event("TrainBonus")

local PAD_RADIUS = 3.6
local RETRY_DELAY = 1.5

-- Турник: встал в пунктирный круг у своего турника - сразу на нем, подтягивания идут сами.
-- Здесь только вход/выход, шкала опыта, кружок x2 и платформа улучшения
local TrainingController = {}

local stopSent = false
local nextStartAt = 0
local shownUpgrade -- что сейчас на панели улучшения, чтобы не перерисовывать каждый кадр

local function stop()
	if State.training and not stopSent then
		stopSent = true
		trainStop:FireServer()
	end
end

local function myPlot()
	local index = player:GetAttribute("Plot")
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	return index and plots and plots:FindFirstChild("Plot" .. index)
end

local function flatDistance(a, b)
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- зашел в круг у своего турника - просим сервер посадить на турник
local function checkBarRing(plot, root)
	if State.training or State.data.Carry or os.clock() < nextStartAt then
		return
	end
	local spot, ring = plot:GetAttribute("BarSpot"), plot:GetAttribute("BarRing")
	if spot and ring and flatDistance(root.Position, spot) < ring then
		nextStartAt = os.clock() + RETRY_DELAY
		trainStart:FireServer()
	end
end

-- панель улучшения видна, только пока стоишь на круглой платформе у своего турника
local function checkUpgradePad(plot, root)
	local data = State.data
	local pad = plot and plot:GetAttribute("UpgradePad")
	local onPad = pad and root and State.Ready() and not State.training and not data.Carry
		and flatDistance(root.Position, pad) < PAD_RADIUS and root.Position.Y - pad.Y < 8
	if not onPad then
		if shownUpgrade then
			shownUpgrade = nil
			UI.SetUpgradePad(nil)
		end
		return
	end
	local level = data.BarLevel or 1
	local nextBar = Bars[level + 1]
	local canBuy = nextBar ~= nil and data.Cash >= nextBar.price
	local key = level .. ":" .. tostring(canBuy)
	if key ~= shownUpgrade then
		shownUpgrade = key
		UI.SetUpgradePad({ current = Bars[level], next = nextBar, canBuy = canBuy })
	end
end

function TrainingController.Init()
	trainState.OnClientEvent:Connect(function(active)
		State.training = active or nil
		stopSent = false
		if not active then
			nextStartAt = os.clock() + RETRY_DELAY
		end
		UI.SetTrainingMode(active)
		local data = State.data
		if active and data.TrainLevel then
			UI.SetXP(data.TrainLevel, data.TrainXP, Formula.XPNeed(data.TrainLevel))
		end
	end)

	trainRep.OnClientEvent:Connect(function(gain, boosted, newLevel, power)
		UI.ShowGain(gain, boosted)
		if newLevel then
			UI.ShowLevelUp(player.Character, power)
		end
	end)

	-- сервер выдает кружок с бонусом и подтверждает, что успели нажать
	trainBonus.OnClientEvent:Connect(function(kind, a, b)
		if kind == "offer" and State.training then
			UI.ShowBonusCircle(b, function()
				trainBonus:FireServer(a)
			end)
		elseif kind == "active" then
			UI.ShowBonusActive(a)
		end
	end)

	UI.Controls().stop.Activated:Connect(stop)
	UserInputService.JumpRequest:Connect(stop)
	UI.UpgradeButton().Activated:Connect(function()
		barUpgrade:FireServer()
	end)

	RunService.Heartbeat:Connect(function()
		local plot = myPlot()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if plot and root and State.Ready() then
			checkBarRing(plot, root)
		end
		checkUpgradePad(plot, root)
	end)
end

return TrainingController
