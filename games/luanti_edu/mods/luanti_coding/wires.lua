-- Luanti Edu: Wire / Connector blocks
-- Players use these to connect programming blocks together.
-- Wires carry the execution signal between non-adjacent blocks.

minetest.register_node("luanti_coding:wire", {
    description = "Code Wire\nConnect programming blocks together.",
    drawtype = "nodebox",
    tiles = {"coding_wire.png"},
    node_box = {
        type = "fixed",
        fixed = {
            {-0.5, -0.2, -0.1,  0.5, 0.2, 0.1},  -- horizontal beam
        },
    },
    paramtype = "light",
    paramtype2 = "facedir",
    groups = { cracky = 3, coding_wire = 1 },
    is_ground_content = false,
})

minetest.register_craft({
    output = "luanti_coding:wire 8",
    recipe = {
        {"default:stone", "default:stone", "default:stone"},
        {"", "", ""},
        {"", "", ""},
    },
})
