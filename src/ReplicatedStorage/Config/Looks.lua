-- Варианты цветокора: солнце, цвет картинки и воздух. Какой включен - Game.LOOK.
-- В Studio можно переключать на лету: workspace:SetAttribute("Look", "golden") в режиме Server
local rgb = Color3.fromRGB

return {
	-- яркое дневное солнце, насыщенно и контрастно, чистый голубой воздух
	juicy = {
		name = "Сочный", clock = 14, brightness = 3, shadowSoftness = 0.3,
		ambient = rgb(120, 120, 135), outdoor = rgb(175, 175, 190),
		saturation = 0.28, contrast = 0.12, exposure = 0.02, tint = rgb(255, 252, 245),
		bloom = { intensity = 0.5, size = 24, threshold = 1.6 }, rays = 0.06,
		air = { density = 0.18, haze = 0.3, glare = 0, color = rgb(190, 225, 255), decay = rgb(120, 170, 220) },
	},
	-- как в мультике: очень яркие цвета, почти без теней, светло
	cartoon = {
		name = "Мультяшный", clock = 13, brightness = 3.2, shadowSoftness = 0.6,
		ambient = rgb(150, 150, 165), outdoor = rgb(200, 200, 215),
		saturation = 0.45, contrast = 0.04, exposure = 0.06, tint = rgb(255, 255, 255),
		bloom = { intensity = 0.35, size = 20, threshold = 1.8 }, rays = 0.03,
		air = { density = 0.1, haze = 0, glare = 0, color = rgb(200, 230, 255), decay = rgb(150, 190, 230) },
	},
	-- вечернее солнце: теплые оттенки, длинные тени. Матовое: без бликов неба, мягкое солнце
	-- и светлые тени, слабое свечение - иначе круглые мульт-модельки блестят, как в масле
	golden = {
		name = "Золотой час", clock = 17.4, brightness = 1.8, shadowSoftness = 0.25,
		ambient = rgb(150, 135, 125), outdoor = rgb(205, 185, 170), specular = 0, diffuse = 0.8,
		saturation = 0.25, contrast = 0.08, exposure = 0, tint = rgb(255, 236, 212),
		bloom = { intensity = 0.25, size = 22, threshold = 2.2 }, rays = 0.12,
		air = { density = 0.3, haze = 1.2, glare = 0.4, color = rgb(255, 215, 170), decay = rgb(255, 160, 110) },
	},
	-- утро: прохладный свет, легкая голубая дымка
	morning = {
		name = "Свежее утро", clock = 9.2, brightness = 2.8, shadowSoftness = 0.35,
		ambient = rgb(120, 130, 150), outdoor = rgb(170, 185, 210),
		saturation = 0.2, contrast = 0.1, exposure = 0.03, tint = rgb(235, 245, 255),
		bloom = { intensity = 0.4, size = 24, threshold = 1.7 }, rays = 0.08,
		air = { density = 0.24, haze = 0.8, glare = 0, color = rgb(210, 235, 255), decay = rgb(140, 180, 230) },
	},
	-- мягкие светлые тона, как на открытке
	pastel = {
		name = "Пастельный", clock = 14, brightness = 2.4, shadowSoftness = 0.5,
		ambient = rgb(170, 165, 175), outdoor = rgb(210, 205, 215),
		saturation = -0.05, contrast = -0.08, exposure = 0.07, tint = rgb(255, 245, 250),
		bloom = { intensity = 0.25, size = 16, threshold = 2 }, rays = 0,
		air = { density = 0.3, haze = 1.6, glare = 0, color = rgb(240, 225, 240), decay = rgb(200, 190, 220) },
	},
}
