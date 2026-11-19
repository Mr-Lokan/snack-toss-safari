local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))

local DataService = require(script.Parent.DataService)

local REFRESH_INTERVAL = 10

-- три доски у вольеров: больше всего животных, больше всего денег, самая редкая поимка.
-- Считаем по игрокам на сервере
local LeaderboardService = {}

local BOARDS = {
	animals = {
		value = function(data)
			local n = #data.Backpack
			for _ in data.Animals do
				n += 1
			end
			return n
		end,
		text = function(value)
			return Format.Number(value)
		end,
	},
	money = {
		value = function(data)
			return data.Cash
		end,
		text = Format.Money,
	},
	luck = {
		value = function(data)
			return data.BestOdds
		end,
		text = function(value)
			return "1 in " .. Format.Number(value)
		end,
	},
}

local function refresh(boards)
	local all = DataService.GetAll()
	for id, rule in BOARDS do
		local rows = boards[id]
		local entries = {}
		for player, data in all do
			local value = rule.value(data)
			if player.Parent and value > 0 then
				table.insert(entries, { name = player.DisplayName, value = value })
			end
		end
		table.sort(entries, function(a, b)
			return a.value > b.value
		end)
		for i, row in rows do
			local entry = entries[i]
			row.name.Text = entry and entry.name or "-"
			row.value.Text = entry and rule.text(entry.value) or ""
		end
	end
end

function LeaderboardService.Init(map)
	refresh(map.boards)
	task.spawn(function()
		while true do
			task.wait(REFRESH_INTERVAL)
			refresh(map.boards)
		end
	end)
	-- новый игрок появляется на досках сразу, не через 10 секунд
	DataService.OnLoaded(function()
		task.wait(1)
		refresh(map.boards)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh, map.boards)
	end)
end

return LeaderboardService
