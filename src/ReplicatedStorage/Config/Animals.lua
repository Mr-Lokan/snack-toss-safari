-- по 7 животных на зону, по одному на редкость (1 = Common ... 7 = Secret)
-- model - параметры для AnimalModel, модели собираются из блоков.
-- mesh = имя мульт-модели в ReplicatedStorage.ToonAnimals (из Blender, со скелетом), height - её рост
-- в studs, outline - цвет контура (по умолчанию почти черный);
-- если такой модели в плейсе нет, животное собирается из блоков по остальным параметрам
local rgb = Color3.fromRGB

local Animals = {
	-- Forest Edge
	{ id = "bunny", name = "Bunny", emoji = "🐰", zone = 1, rarity = 1, model = {
		mesh = "Bunny", height = 2.1,
		kind = "quad", size = 0.9, color = rgb(235, 235, 235), color2 = rgb(255, 190, 200),
		body = Vector3.new(1, 0.9, 1.3), legs = 0.35, ears = "long", tail = "fluffy",
	} },
	{ id = "squirrel", name = "Squirrel", emoji = "🐿️", zone = 1, rarity = 2, model = {
		mesh = "Squirrel", height = 2.2,
		kind = "quad", size = 0.8, color = rgb(175, 100, 50), color2 = rgb(240, 210, 170),
		body = Vector3.new(0.9, 0.9, 1.2), legs = 0.35, ears = "pointy", tail = "fluffy", tailSize = 1.6,
	} },
	{ id = "hedgehog", name = "Hedgehog", emoji = "🦔", zone = 1, rarity = 3, model = {
		mesh = "Hedgehog", height = 1.7,
		kind = "quad", size = 0.9, color = rgb(110, 80, 60), color2 = rgb(225, 195, 160),
		body = Vector3.new(1.2, 0.8, 1.4), legs = 0.25, ears = "round", snout = 0.4, spots = rgb(70, 50, 40),
	} },
	{ id = "fox", name = "Fox", emoji = "🦊", zone = 1, rarity = 4, model = {
		mesh = "Fox", height = 2.6,
		kind = "quad", size = 1.1, color = rgb(235, 120, 40), color2 = rgb(250, 245, 235),
		legs = 0.7, ears = "pointy", tail = "fluffy", snout = 0.5,
	} },
	{ id = "deer", name = "Deer", emoji = "🦌", zone = 1, rarity = 5, model = {
		mesh = "Deer", height = 3.0,
		kind = "quad", size = 1.5, color = rgb(165, 110, 65), color2 = rgb(240, 225, 200),
		legs = 1.2, neck = 0.5, ears = "pointy", horns = "antlers", tail = "short", spots = rgb(245, 235, 220),
	} },
	{ id = "owl", name = "Owl", emoji = "🦉", zone = 1, rarity = 6, model = {
		mesh = "Owl", height = 2.7,
		kind = "bird", size = 1.2, color = rgb(130, 95, 60), color2 = rgb(230, 200, 150),
		body = Vector3.new(1, 1.3, 0.9), ears = "pointy",
	} },
	{ id = "spiritstag", name = "Spirit Stag", emoji = "✨", zone = 1, rarity = 7, model = {
		mesh = "SpiritStag", height = 3.6, outline = rgb(50, 80, 210),
		kind = "quad", size = 1.8, color = rgb(215, 240, 255), color2 = rgb(150, 220, 255),
		legs = 1.3, neck = 0.6, ears = "pointy", horns = "antlers", tail = "short", glow = true,
	} },

	-- Savanna
	{ id = "warthog", name = "Warthog", emoji = "🐗", zone = 2, rarity = 1, model = {
		kind = "quad", size = 1.1, color = rgb(125, 95, 80), legs = 0.5, ears = "pointy",
		snout = 0.5, tusks = true, mane = rgb(80, 60, 50), tail = "thin",
	} },
	{ id = "zebra", name = "Zebra", emoji = "🦓", zone = 2, rarity = 2, model = {
		kind = "quad", size = 1.4, color = rgb(245, 245, 245), stripes = rgb(30, 30, 30),
		legs = 1, neck = 0.4, ears = "pointy", tail = "thin", snout = 0.3,
	} },
	{ id = "rhino", name = "Rhino", emoji = "🦏", zone = 2, rarity = 3, model = {
		kind = "quad", size = 2, color = rgb(150, 150, 150), body = Vector3.new(1.4, 1.1, 2),
		legs = 0.6, ears = "pointy", snout = 0.5, horns = "horn", tail = "thin",
	} },
	{ id = "giraffe", name = "Giraffe", emoji = "🦒", zone = 2, rarity = 4, model = {
		kind = "quad", size = 1.6, color = rgb(240, 190, 90), spots = rgb(150, 90, 40),
		legs = 1.4, neck = 2.2, ears = "pointy", horns = "horns", tail = "thin", snout = 0.3,
	} },
	{ id = "elephant", name = "Elephant", emoji = "🐘", zone = 2, rarity = 5, model = {
		kind = "quad", size = 2.6, color = rgb(150, 150, 160), body = Vector3.new(1.4, 1.2, 1.8),
		legs = 0.8, head = 1, ears = "big", trunk = true, tusks = true, tail = "thin",
	} },
	{ id = "lion", name = "Lion", emoji = "🦁", zone = 2, rarity = 6, model = {
		kind = "quad", size = 1.8, color = rgb(225, 170, 80), mane = rgb(150, 80, 30),
		legs = 0.8, ears = "round", tail = "long", snout = 0.3,
	} },
	{ id = "sunking", name = "Sun King", emoji = "👑", zone = 2, rarity = 7, model = {
		kind = "quad", size = 2.2, color = rgb(255, 215, 90), mane = rgb(255, 120, 30),
		legs = 0.9, ears = "round", tail = "long", snout = 0.3, glow = true,
	} },

	-- Desert
	{ id = "lizard", name = "Lizard", emoji = "🦎", zone = 3, rarity = 1, model = {
		kind = "quad", size = 0.9, color = rgb(150, 170, 80), body = Vector3.new(0.8, 0.5, 1.8),
		legs = 0.25, tail = "long", snout = 0.3,
	} },
	{ id = "jackal", name = "Jackal", emoji = "🐺", zone = 3, rarity = 2, model = {
		kind = "quad", size = 1.1, color = rgb(200, 160, 100), color2 = rgb(240, 220, 190),
		legs = 0.8, ears = "pointy", tail = "fluffy", snout = 0.5,
	} },
	{ id = "sandcat", name = "Sand Cat", emoji = "🐈", zone = 3, rarity = 3, model = {
		kind = "quad", size = 1, color = rgb(220, 190, 140), stripes = rgb(180, 140, 90),
		legs = 0.6, ears = "pointy", tail = "long",
	} },
	{ id = "camel", name = "Camel", emoji = "🐪", zone = 3, rarity = 4, model = {
		kind = "quad", size = 2, color = rgb(205, 160, 95), legs = 1.4, neck = 0.9,
		ears = "round", tail = "thin", snout = 0.4, hump = 1,
	} },
	{ id = "vulture", name = "Vulture", emoji = "🦅", zone = 3, rarity = 5, model = {
		kind = "bird", size = 1.4, color = rgb(90, 70, 60), color2 = rgb(60, 45, 40),
		headColor = rgb(230, 170, 160), neck = 0.4,
	} },
	{ id = "scorpionking", name = "Scorpion King", emoji = "🦂", zone = 3, rarity = 6, model = {
		kind = "crab", size = 1.6, color = rgb(60, 40, 40), tail = "stinger",
	} },
	{ id = "miragecamel", name = "Mirage Camel", emoji = "🐫", zone = 3, rarity = 7, model = {
		kind = "quad", size = 2.2, color = rgb(150, 220, 255), legs = 1.4, neck = 0.9,
		ears = "round", tail = "thin", snout = 0.4, hump = 2, glow = true, ghost = true,
	} },

	-- Jungle
	{ id = "frog", name = "Frog", emoji = "🐸", zone = 4, rarity = 1, model = {
		kind = "quad", size = 0.9, color = rgb(90, 190, 70), color2 = rgb(220, 240, 170),
		body = Vector3.new(1.2, 0.7, 1.1), legs = 0.25, head = 0.8,
	} },
	{ id = "parrot", name = "Parrot", emoji = "🦜", zone = 4, rarity = 2, model = {
		kind = "bird", size = 1, color = rgb(230, 40, 40), color2 = rgb(40, 120, 230),
		beakColor = rgb(255, 220, 60),
	} },
	{ id = "monkey", name = "Monkey", emoji = "🐒", zone = 4, rarity = 3, model = {
		kind = "quad", size = 1.1, color = rgb(130, 85, 50), color2 = rgb(230, 190, 150),
		legs = 0.8, ears = "round", tail = "long",
	} },
	{ id = "python", name = "Python", emoji = "🐍", zone = 4, rarity = 4, model = {
		kind = "snake", size = 1.3, color = rgb(120, 160, 60), color2 = rgb(80, 110, 40),
	} },
	{ id = "tiger", name = "Tiger", emoji = "🐅", zone = 4, rarity = 5, model = {
		kind = "quad", size = 1.8, color = rgb(240, 130, 40), stripes = rgb(30, 25, 25),
		color2 = rgb(250, 245, 235), legs = 0.8, ears = "round", tail = "long", snout = 0.3,
	} },
	{ id = "gorilla", name = "Gorilla", emoji = "🦍", zone = 4, rarity = 6, model = {
		kind = "quad", size = 2.2, color = rgb(60, 60, 65), color2 = rgb(110, 110, 115),
		body = Vector3.new(1.5, 1.4, 1.3), legs = 1, ears = "round",
	} },
	{ id = "jadejaguar", name = "Jade Jaguar", emoji = "🐆", zone = 4, rarity = 7, model = {
		kind = "quad", size = 2, color = rgb(60, 200, 140), spots = rgb(20, 100, 70),
		legs = 0.8, ears = "round", tail = "long", snout = 0.3, glow = true,
	} },

	-- Swamp
	{ id = "duck", name = "Duck", emoji = "🦆", zone = 5, rarity = 1, model = {
		kind = "bird", size = 0.9, color = rgb(235, 235, 235), color2 = rgb(200, 200, 200),
		headColor = rgb(40, 130, 70),
	} },
	{ id = "otter", name = "Otter", emoji = "🦦", zone = 5, rarity = 2, model = {
		kind = "quad", size = 1, color = rgb(110, 75, 50), color2 = rgb(200, 170, 140),
		body = Vector3.new(0.9, 0.7, 1.8), legs = 0.3, ears = "round", tail = "long", snout = 0.3,
	} },
	{ id = "turtle", name = "Turtle", emoji = "🐢", zone = 5, rarity = 3, model = {
		kind = "quad", size = 1.2, color = rgb(120, 170, 90), shell = rgb(80, 110, 50),
		body = Vector3.new(1.2, 0.6, 1.4), legs = 0.3, tail = "short",
	} },
	{ id = "flamingo", name = "Flamingo", emoji = "🦩", zone = 5, rarity = 4, model = {
		kind = "bird", size = 1.2, color = rgb(255, 130, 170), color2 = rgb(240, 100, 140),
		legs = 2, neck = 1.2, beakColor = rgb(40, 40, 40),
	} },
	{ id = "hippo", name = "Hippo", emoji = "🦛", zone = 5, rarity = 5, model = {
		kind = "quad", size = 2.4, color = rgb(140, 120, 150), color2 = rgb(220, 160, 170),
		body = Vector3.new(1.6, 1.1, 2), legs = 0.5, ears = "round", snout = 0.8,
	} },
	{ id = "croc", name = "Crocodile", emoji = "🐊", zone = 5, rarity = 6, model = {
		kind = "quad", size = 2, color = rgb(70, 110, 60), spots = rgb(50, 80, 45),
		body = Vector3.new(1, 0.6, 2.4), legs = 0.35, snout = 1.4, tail = "long",
	} },
	{ id = "swampdragon", name = "Swamp Dragon", emoji = "🐉", zone = 5, rarity = 7, model = {
		kind = "quad", size = 2.4, color = rgb(60, 140, 90), color2 = rgb(160, 220, 120),
		legs = 0.9, neck = 0.6, horns = "horns", tail = "long", wings = true, snout = 0.4, glow = true,
	} },

	-- Coast
	{ id = "crab", name = "Crab", emoji = "🦀", zone = 6, rarity = 1, model = {
		kind = "crab", size = 1, color = rgb(230, 70, 50),
	} },
	{ id = "seagull", name = "Seagull", emoji = "🕊️", zone = 6, rarity = 2, model = {
		kind = "bird", size = 0.9, color = rgb(245, 245, 245), color2 = rgb(160, 160, 170),
		beakColor = rgb(255, 200, 40),
	} },
	{ id = "penguin", name = "Penguin", emoji = "🐧", zone = 6, rarity = 3, model = {
		kind = "bird", size = 1, color = rgb(35, 35, 45), color2 = rgb(245, 245, 245),
		body = Vector3.new(1, 1.4, 0.9), legs = 0.2,
	} },
	{ id = "lobster", name = "Lobster", emoji = "🦞", zone = 6, rarity = 4, model = {
		kind = "crab", size = 1.3, color = rgb(200, 40, 40), long = true,
	} },
	{ id = "shark", name = "Shark", emoji = "🦈", zone = 6, rarity = 5, model = {
		kind = "fin", size = 2, color = rgb(110, 130, 150), color2 = rgb(235, 235, 240), fin = "shark",
	} },
	{ id = "octopus", name = "Giant Octopus", emoji = "🐙", zone = 6, rarity = 6, model = {
		kind = "blob", size = 1.8, color = rgb(200, 80, 160),
	} },
	{ id = "whale", name = "Moby Whale", emoji = "🐳", zone = 6, rarity = 7, model = {
		kind = "fin", size = 3, color = rgb(60, 110, 200), color2 = rgb(200, 220, 240), fin = "whale", glow = true,
	} },
}

Animals.ById = {}
Animals.ByZone = {}
for _, animal in ipairs(Animals) do
	Animals.ById[animal.id] = animal
	Animals.ByZone[animal.zone] = Animals.ByZone[animal.zone] or {}
	Animals.ByZone[animal.zone][animal.rarity] = animal
end

return Animals
