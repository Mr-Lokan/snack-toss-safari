local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

-- копия данных игрока, которую присылает сервер
local State = {
	data = {},
	training = nil, -- id турника, на котором висит игрок
}

local listeners = {}

function State.OnChanged(callback)
	table.insert(listeners, callback)
end

function State.Ready()
	return State.data.Cash ~= nil
end

function State.Init()
	Net.Event("Sync").OnClientEvent:Connect(function(payload)
		for key, value in payload do
			State.data[key] = value
		end
		for _, callback in listeners do
			task.spawn(callback, payload)
		end
	end)
	Net.Event("RequestSync"):FireServer()
end

return State
