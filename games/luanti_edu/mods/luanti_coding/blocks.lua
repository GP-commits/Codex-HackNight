-- Luanti Edu: Programming Blocks
-- Each block represents a programming concept. Players physically place and
-- connect these blocks in the world to create programs.
--
-- Block connection direction: Each block has an OUTPUT face (right/+X)
-- and an INPUT face (left/-X). Chain them left to right to write code.

local COLORS = {
    start   = "#00cc44",  -- Green
    move    = "#2277ff",  -- Blue
    turn    = "#aa44ff",  -- Purple
    loop    = "#ff8800",  -- Orange
    if_cond = "#ffcc00",  -- Yellow
    stop    = "#ff2244",  -- Red
    place   = "#44dddd",  -- Cyan
    dig     = "#bb6600",  -- Brown
}

----------------------------------------------------------------------
-- START Block
-- The entry point of every program. Players right-click to RUN.
----------------------------------------------------------------------
minetest.register_node("luanti_coding:start", {
    description = "START Block\nRight-click to run your program!",
    tiles = {
        "coding_block_top.png^[colorize:" .. COLORS.start .. ":160",
        "coding_block_top.png^[colorize:" .. COLORS.start .. ":160",
        "coding_block_side_output.png^[colorize:" .. COLORS.start .. ":160",
        "coding_block_side_input.png^[colorize:" .. COLORS.start .. ":160",
        "coding_block_front_start.png",
        "coding_block_back.png",
    },
    use_texture_alpha = "clip",
    groups = { cracky = 1, coding_block = 1, coding_start = 1 },
    is_ground_content = false,
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        local pname = clicker:get_player_name()
        minetest.chat_send_player(pname, "[Luanti Edu] Running your program...")
        luanti_coding.run_program(pos, clicker)
        return itemstack
    end,
})

----------------------------------------------------------------------
-- MOVE FORWARD Block
----------------------------------------------------------------------
minetest.register_node("luanti_coding:move_forward", {
    description = "MOVE FORWARD Block\nMakes the robot move 1 step forward.",
    tiles = {
        "coding_block_top.png^[colorize:" .. COLORS.move .. ":160",
        "coding_block_top.png^[colorize:" .. COLORS.move .. ":160",
        "coding_block_side_output.png^[colorize:" .. COLORS.move .. ":160",
        "coding_block_side_input.png^[colorize:" .. COLORS.move .. ":160",
        "coding_block_front_move.png",
        "coding_block_back.png",
    },
    groups = { cracky = 1, coding_block = 1 },
    is_ground_content = false,
    _coding_action = "move_forward",
})

----------------------------------------------------------------------
-- TURN LEFT Block
----------------------------------------------------------------------
minetest.register_node("luanti_coding:turn_left", {
    description = "TURN LEFT Block\nMakes the robot turn 90° left.",
    tiles = {
        "coding_block_top.png^[colorize:" .. COLORS.turn .. ":160",
        "coding_block_top.png^[colorize:" .. COLORS.turn .. ":160",
        "coding_block_side_output.png^[colorize:" .. COLORS.turn .. ":160",
        "coding_block_side_input.png^[colorize:" .. COLORS.turn .. ":160",
        "coding_block_front_turn_left.png",
        "coding_block_back.png",
    },
    groups = { cracky = 1, coding_block = 1 },
    is_ground_content = false,
    _coding_action = "turn_left",
})

----------------------------------------------------------------------
-- TURN RIGHT Block
----------------------------------------------------------------------
minetest.register_node("luanti_coding:turn_right", {
    description = "TURN RIGHT Block\nMakes the robot turn 90° right.",
    tiles = {
        "coding_block_top.png^[colorize:" .. COLORS.turn .. ":160",
        "coding_block_top.png^[colorize:" .. COLORS.turn .. ":160",
        "coding_block_side_output.png^[colorize:" .. COLORS.turn .. ":160",
        "coding_block_side_input.png^[colorize:" .. COLORS.turn .. ":160",
        "coding_block_front_turn_right.png",
        "coding_block_back.png",
    },
    groups = { cracky = 1, coding_block = 1 },
    is_ground_content = false,
    _coding_action = "turn_right",
})

----------------------------------------------------------------------
-- LOOP Block (repeat N times)
-- Metadata "loop_count" sets how many times to repeat the next chain.
----------------------------------------------------------------------
minetest.register_node("luanti_coding:loop", {
    description = "LOOP Block\nRight-click to set how many times to repeat.",
    tiles = {
        "coding_block_top.png^[colorize:" .. COLORS.loop .. ":160",
        "coding_block_top.png^[colorize:" .. COLORS.loop .. ":160",
        "coding_block_side_output.png^[colorize:" .. COLORS.loop .. ":160",
        "coding_block_side_input.png^[colorize:" .. COLORS.loop .. ":160",
        "coding_block_front_loop.png",
        "coding_block_back.png",
    },
    groups = { cracky = 1, coding_block = 1, coding_loop = 1 },
    is_ground_content = false,
    _coding_action = "loop",
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        local pname = clicker:get_player_name()
        local meta = minetest.get_meta(pos)
        local current = meta:get_int("loop_count")
        if current == 0 then current = 3 end
        -- Show a simple formspec to set loop count
        minetest.show_formspec(pname, "luanti_coding:loop_set_" .. minetest.pos_to_string(pos),
            "formspec_version[4]" ..
            "size[6,3]" ..
            "label[0.5,0.5;Set LOOP repeat count:]" ..
            "field[0.5,1.2;5,0.8;count;Times to repeat:;" .. current .. "]" ..
            "button_exit[1.5,2;3,0.8;set;Set Loop Count]"
        )
        return itemstack
    end,
})

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if not formname:find("luanti_coding:loop_set_") then return end
    local posstr = formname:gsub("luanti_coding:loop_set_", "")
    local pos = minetest.string_to_pos(posstr)
    if not pos then return end
    if fields.set and fields.count then
        local count = tonumber(fields.count) or 3
        count = math.max(1, math.min(count, 99))
        local meta = minetest.get_meta(pos)
        meta:set_int("loop_count", count)
        minetest.chat_send_player(player:get_player_name(),
            "[Luanti Edu] Loop set to repeat " .. count .. " times.")
    end
end)

----------------------------------------------------------------------
-- IF Block (if block ahead is air -> continue, else skip)
----------------------------------------------------------------------
minetest.register_node("luanti_coding:if_clear", {
    description = "IF CLEAR Block\nContinues if path is clear, skips next block if blocked.",
    tiles = {
        "coding_block_top.png^[colorize:" .. COLORS.if_cond .. ":160",
        "coding_block_top.png^[colorize:" .. COLORS.if_cond .. ":160",
        "coding_block_side_output.png^[colorize:" .. COLORS.if_cond .. ":160",
        "coding_block_side_input.png^[colorize:" .. COLORS.if_cond .. ":160",
        "coding_block_front_if.png",
        "coding_block_back.png",
    },
    groups = { cracky = 1, coding_block = 1, coding_if = 1 },
    is_ground_content = false,
    _coding_action = "if_clear",
})

----------------------------------------------------------------------
-- PLACE BLOCK action
----------------------------------------------------------------------
minetest.register_node("luanti_coding:place_block", {
    description = "PLACE BLOCK\nRobot places a stone block in front of itself.",
    tiles = {
        "coding_block_top.png^[colorize:" .. COLORS.place .. ":160",
        "coding_block_top.png^[colorize:" .. COLORS.place .. ":160",
        "coding_block_side_output.png^[colorize:" .. COLORS.place .. ":160",
        "coding_block_side_input.png^[colorize:" .. COLORS.place .. ":160",
        "coding_block_front_place.png",
        "coding_block_back.png",
    },
    groups = { cracky = 1, coding_block = 1 },
    is_ground_content = false,
    _coding_action = "place_block",
})

----------------------------------------------------------------------
-- DIG Block action
----------------------------------------------------------------------
minetest.register_node("luanti_coding:dig_block", {
    description = "DIG BLOCK\nRobot digs the block in front of itself.",
    tiles = {
        "coding_block_top.png^[colorize:" .. COLORS.dig .. ":160",
        "coding_block_top.png^[colorize:" .. COLORS.dig .. ":160",
        "coding_block_side_output.png^[colorize:" .. COLORS.dig .. ":160",
        "coding_block_side_input.png^[colorize:" .. COLORS.dig .. ":160",
        "coding_block_front_dig.png",
        "coding_block_back.png",
    },
    groups = { cracky = 1, coding_block = 1 },
    is_ground_content = false,
    _coding_action = "dig_block",
})

----------------------------------------------------------------------
-- STOP Block
----------------------------------------------------------------------
minetest.register_node("luanti_coding:stop", {
    description = "STOP Block\nEnds the program here.",
    tiles = {
        "coding_block_top.png^[colorize:" .. COLORS.stop .. ":160",
        "coding_block_top.png^[colorize:" .. COLORS.stop .. ":160",
        "coding_block_side_output.png^[colorize:" .. COLORS.stop .. ":160",
        "coding_block_side_input.png^[colorize:" .. COLORS.stop .. ":160",
        "coding_block_front_stop.png",
        "coding_block_back.png",
    },
    groups = { cracky = 1, coding_block = 1, coding_stop = 1 },
    is_ground_content = false,
    _coding_action = "stop",
})

----------------------------------------------------------------------
-- Craft Recipes - simple recipes using stone, sticks, coal, and mese
-- (No dye required - students get blocks for free in creative mode anyway)
----------------------------------------------------------------------

-- START: mese crystal centre surrounded by stone
minetest.register_craft({
    output = "luanti_coding:start",
    recipe = {
        {"default:stone", "default:mese_crystal", "default:stone"},
        {"default:mese_crystal", "default:stone", "default:mese_crystal"},
        {"default:stone", "default:mese_crystal", "default:stone"},
    },
})
-- MOVE FORWARD: stone + sticks (arrow shape)
minetest.register_craft({
    output = "luanti_coding:move_forward 3",
    recipe = {
        {"", "default:stick", ""},
        {"default:stick", "default:stone", "default:stick"},
        {"", "default:stick", ""},
    },
})
-- TURN LEFT: sticks curving left
minetest.register_craft({
    output = "luanti_coding:turn_left 3",
    recipe = {
        {"default:stick", "default:stone", ""},
        {"default:stick", "default:stone", ""},
        {"", "", ""},
    },
})
-- TURN RIGHT: sticks curving right
minetest.register_craft({
    output = "luanti_coding:turn_right 3",
    recipe = {
        {"", "default:stone", "default:stick"},
        {"", "default:stone", "default:stick"},
        {"", "", ""},
    },
})
-- LOOP: coal in corners (cycle pattern)
minetest.register_craft({
    output = "luanti_coding:loop 2",
    recipe = {
        {"default:coal_lump", "default:stone", "default:coal_lump"},
        {"default:stone", "default:coal_lump", "default:stone"},
        {"default:coal_lump", "default:stone", "default:coal_lump"},
    },
})
-- IF CLEAR: question mark shape with sticks
minetest.register_craft({
    output = "luanti_coding:if_clear 2",
    recipe = {
        {"default:stick", "default:stone", "default:stick"},
        {"default:stone", "default:stone", "default:stone"},
        {"", "default:stick", ""},
    },
})
-- PLACE BLOCK: plus sign with stone
minetest.register_craft({
    output = "luanti_coding:place_block 3",
    recipe = {
        {"", "default:stone", ""},
        {"default:stone", "default:mese_crystal", "default:stone"},
        {"", "default:stone", ""},
    },
})
-- DIG BLOCK: pick shape
minetest.register_craft({
    output = "luanti_coding:dig_block 3",
    recipe = {
        {"default:stone", "default:stone", "default:stone"},
        {"", "default:stick", ""},
        {"", "default:stick", ""},
    },
})
-- STOP: X pattern with coal
minetest.register_craft({
    output = "luanti_coding:stop",
    recipe = {
        {"default:coal_lump", "", "default:coal_lump"},
        {"", "default:stone", ""},
        {"default:coal_lump", "", "default:coal_lump"},
    },
})
