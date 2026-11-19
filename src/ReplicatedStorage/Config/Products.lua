-- id = 0: товар еще не создан в Creator Dashboard.
-- В Studio такой товар выдается сразу без покупки, в живой игре кнопка ничего не делает.
local Products = {
	{
		key = "x2cash", kind = "pass", id = 0, price = 99,
		name = "x2 Cash", icon = "money", desc = "Double cash from every animal, forever",
	},
	{
		key = "x2power", kind = "pass", id = 0, price = 149,
		name = "x2 Training", icon = "strength", desc = "Double power from every pull-up, forever",
	},
	{
		key = "luck15", kind = "product", id = 0, price = 49,
		name = "Server Luck x2", icon = "luck", desc = "15 minutes of double luck for the whole server",
		luckSeconds = 15 * 60,
	},
}

Products.ByKey = {}
for _, item in ipairs(Products) do
	Products.ByKey[item.key] = item
end

return Products
