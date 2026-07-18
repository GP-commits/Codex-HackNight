-- Luanti Edu: Block Coding System
-- Registers all visual programming blocks

local modpath = minetest.get_modpath("luanti_coding")

dofile(modpath .. "/blocks.lua")
dofile(modpath .. "/executor.lua")
dofile(modpath .. "/wires.lua")

minetest.log("action", "[luanti_coding] Loaded!")
