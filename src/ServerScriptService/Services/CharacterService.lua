local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

-- игроки не сталкиваются друг с другом: не толкаются в зоне броска, у турников и у Sell Shop
local CharacterService = {}

local GROUP = "Players"

local function setGroup(object)
	if object:IsA("BasePart") then
		object.CollisionGroup = GROUP
	end
end

local function onCharacter(character)
	for _, object in character:GetDescendants() do
		setGroup(object)
	end
	character.DescendantAdded:Connect(setGroup)
end

local function watch(player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

function CharacterService.Init()
	PhysicsService:RegisterCollisionGroup(GROUP)
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return CharacterService
