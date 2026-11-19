local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local Game = require(Config:WaitForChild("Game"))
local Zones = require(Config:WaitForChild("Zones"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Mutations = require(Config:WaitForChild("Mutations"))
local Animals = require(Config:WaitForChild("Animals"))

-- формулы, которые нужны и серверу, и клиенту
local Formula = {}

local fieldLength = 0
for _, zone in ipairs(Zones) do
	zone.start = fieldLength
	fieldLength += zone.length
end
Formula.FIELD_LENGTH = fieldLength

-- вертикальная шкала броска: бегунок p от 0 (низ) до 1 (верх), чем выше, тем сильнее.
-- Сегменты сверху вниз, color - цвет сегмента на шкале
Formula.TIMING = {
	{ from = 0.8, mult = 1.2, label = "PERFECT!", color = Color3.fromRGB(80, 230, 90) },
	{ from = 0.6, mult = 1, label = "Great!", color = Color3.fromRGB(170, 230, 70) },
	{ from = 0.4, mult = 0.85, label = "Good", color = Color3.fromRGB(245, 215, 60) },
	{ from = 0.2, mult = 0.65, label = "Okay", color = Color3.fromRGB(250, 150, 60) },
	{ from = 0, mult = 0.5, label = "Weak", color = Color3.fromRGB(235, 75, 70) },
}

function Formula.Timing(p)
	for _, timing in ipairs(Formula.TIMING) do
		if p >= timing.from then
			return timing
		end
	end
	return Formula.TIMING[#Formula.TIMING]
end

-- опыт для следующего уровня тренировки; на каждом уровне сила растет на столько же
function Formula.XPNeed(level)
	return math.floor(10 * 1.1 ^ (level - 1))
end

-- дальность от начала поля и номер зоны.
-- Внутри зоны сила интерполируется по логарифму: каждая зона требует в ~8 раз больше силы
function Formula.Distance(power)
	power = math.max(power, 1)
	for i = #Zones, 1, -1 do
		local zone = Zones[i]
		if power >= zone.power then
			local nextPower = Zones[i + 1] and Zones[i + 1].power or zone.power * 8
			local t = math.log(power / zone.power) / math.log(nextPower / zone.power)
			local distance = zone.start + math.clamp(t, 0, 1) * zone.length
			return math.clamp(distance, 12, fieldLength - 8), i
		end
	end
	return 12, 1
end

-- самая дальняя зона, куда можно докинуть с идеальным броском
function Formula.ReachZone(power)
	local best = Formula.TIMING[1].mult
	for i = #Zones, 1, -1 do
		if power * best >= Zones[i].power then
			return i
		end
	end
	return 1
end

function Formula.FlightTime(distance)
	return math.min(1.1 + distance / 450, 4.5)
end

-- сторона вольера при таком числе мест: с каждым купленным местом вольер чуть больше
function Formula.PenSize(slots)
	local extra = math.clamp(slots, Game.START_SLOTS, Game.MAX_SLOTS) - Game.START_SLOTS
	return Game.PEN_SIZE + extra * Game.PEN_GROW
end

function Formula.IsOnThrowPad(position)
	local pad = Game.THROW_PAD
	return math.abs(position.X - pad.x) <= pad.halfX + 1.5
		and math.abs(position.Z) <= pad.halfZ + 1.5
		and position.Y < 15
end

function Formula.RarityWeights(luck)
	local weights, total = {}, 0
	for i, rarity in ipairs(Rarities) do
		local weight = rarity.weight * luck ^ rarity.luck
		weights[i] = weight
		total += weight
	end
	return weights, total
end

function Formula.RollRarity(luck, rng)
	local weights, total = Formula.RarityWeights(luck)
	local roll = rng:NextNumber() * total
	for i, weight in ipairs(weights) do
		roll -= weight
		if roll <= 0 then
			return i
		end
	end
	return 1
end

function Formula.RollMutation(rng)
	local color
	if rng:NextNumber() < Mutations.Rainbow.chance then
		color = "Rainbow"
	elseif rng:NextNumber() < Mutations.Gold.chance then
		color = "Gold"
	end
	return color, rng:NextNumber() < Mutations.Giant.chance
end

-- animal = { id = "zebra", m = "Gold" | "Rainbow" | nil, g = true | nil }
function Formula.Income(animal)
	local species = Animals.ById[animal.id]
	if not species then
		return 0
	end
	local value = Zones[species.zone].base * Rarities[species.rarity].mult
	if animal.m and Mutations[animal.m] then
		value *= Mutations[animal.m].mult
	end
	if animal.g then
		value *= Mutations.Giant.mult
	end
	return value
end

-- чем дальше улетела еда, тем выше удача (растет прямо в полете)
function Formula.DistanceLuck(distance)
	return 1 + math.max(distance, 0) / 120
end

-- шанс "1 из N" выбить именно такое животное без бонусов удачи, для таблицы самых удачных
function Formula.CatchOdds(animal)
	local species = Animals.ById[animal.id]
	if not species then
		return 1
	end
	local weights, total = Formula.RarityWeights(1)
	local chance = weights[species.rarity] / total
	if animal.m == "Rainbow" then
		chance *= Mutations.Rainbow.chance
	elseif animal.m == "Gold" then
		chance *= Mutations.Gold.chance
	end
	if animal.g then
		chance *= Mutations.Giant.chance
	end
	return math.floor(1 / chance)
end

function Formula.SellPrice(animal)
	return Formula.Income(animal) * Game.SELL_SECONDS
end

function Formula.SlotPrice(slots)
	return Game.SLOT_BASE_PRICE * Game.SLOT_PRICE_GROWTH ^ (slots - Game.START_SLOTS)
end

-- "Giant Gold Zebra"
function Formula.AnimalName(animal)
	local species = Animals.ById[animal.id]
	local name = species and species.name or animal.id
	if animal.m then
		name = animal.m .. " " .. name
	end
	if animal.g then
		name = "Giant " .. name
	end
	return name
end

return Formula
