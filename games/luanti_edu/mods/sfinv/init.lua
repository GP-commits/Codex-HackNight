-- sfinv/init.lua

dofile(minetest.get_modpath("sfinv") .. "/api.lua")

-- Load support for MT game translation.
local S = minetest.get_translator("sfinv")

sfinv.register_page("sfinv:inventory", {
	title = S("Inventory"),
	get = function(self, player, context)
		return sfinv.make_formspec(player, context, "", true)
	end
})
