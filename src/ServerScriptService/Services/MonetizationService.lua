local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = ReplicatedStorage:WaitForChild("Config")
local Net = require(Shared:WaitForChild("Net"))
local Products = require(Config:WaitForChild("Products"))

local purchaseRemote = Net.Event("Purchase")
local notify = Net.Event("Notify")

local MonetizationService = {}

local owned = {} -- [player] = { x2cash = true }
local passCallbacks = {}

local function setPass(player, key)
	owned[player] = owned[player] or {}
	if owned[player][key] then
		return
	end
	owned[player][key] = true
	player:SetAttribute("Pass_" .. key, true)
	for _, callback in passCallbacks do
		task.spawn(callback, player, key)
	end
end

local function grant(player, item)
	if item.kind == "pass" then
		setPass(player, item.key)
		notify:FireClient(player, "Thanks! " .. item.name .. " is active", "good")
	elseif item.luckSeconds then
		local now = workspace:GetServerTimeNow()
		local current = workspace:GetAttribute("LuckUntil") or 0
		workspace:SetAttribute("LuckUntil", math.max(current, now) + item.luckSeconds)
		notify:FireAllClients(player.DisplayName .. " activated Server Luck x2!", "luck", "luck")
	end
end

function MonetizationService.HasPass(player, key)
	return owned[player] ~= nil and owned[player][key] == true
end

function MonetizationService.CashMultiplier(player)
	return MonetizationService.HasPass(player, "x2cash") and 2 or 1
end

function MonetizationService.PowerMultiplier(player)
	return MonetizationService.HasPass(player, "x2power") and 2 or 1
end

function MonetizationService.LuckMultiplier()
	local luckUntil = workspace:GetAttribute("LuckUntil") or 0
	return workspace:GetServerTimeNow() < luckUntil and 2 or 1
end

function MonetizationService.OnPassChanged(callback)
	table.insert(passCallbacks, callback)
end

local function checkPasses(player)
	for _, item in ipairs(Products) do
		if item.kind == "pass" and item.id ~= 0 then
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, item.id)
			if ok and has then
				setPass(player, item.key)
			end
		end
	end
end

function MonetizationService.Init()
	Players.PlayerAdded:Connect(checkPasses)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)

	purchaseRemote.OnServerEvent:Connect(function(player, key)
		local item = type(key) == "string" and Products.ByKey[key]
		if not item then
			return
		end
		if item.kind == "pass" and MonetizationService.HasPass(player, key) then
			return
		end
		if item.id == 0 then
			-- товар не заведен: в Studio выдаем для теста
			if RunService:IsStudio() then
				grant(player, item)
			else
				notify:FireClient(player, "This item is not available yet", "bad")
			end
			return
		end
		if item.kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(player, item.id)
		else
			MarketplaceService:PromptProductPurchase(player, item.id)
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, item in ipairs(Products) do
			if item.kind == "pass" and item.id == passId then
				grant(player, item)
			end
		end
	end)

	-- сейчас все developer products - временные бусты, сохранять их не нужно
	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		for _, item in ipairs(Products) do
			if item.kind == "product" and item.id == receipt.ProductId then
				grant(player, item)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

return MonetizationService
