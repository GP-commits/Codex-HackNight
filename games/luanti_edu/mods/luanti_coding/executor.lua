-- Luanti Edu: Program Executor
-- Reads the chain of programming blocks starting from a START block,
-- builds a list of instructions, and executes them step-by-step on
-- the nearest luanti_robot entity.

luanti_coding = luanti_coding or {}

-- Maximum chain length (prevents infinite loops from bugs)
local MAX_INSTRUCTIONS = 256

-- Execution delay between steps in seconds
local STEP_DELAY = 0.5

-- Directions as vectors (facedir 0 = facing +Z)
local DIRS = {
    [0] = vector.new( 0, 0,  1),  -- North (+Z)
    [1] = vector.new(-1, 0,  0),  -- West  (-X)
    [2] = vector.new( 0, 0, -1),  -- South (-Z)
    [3] = vector.new( 1, 0,  0),  -- East  (+X)
}

-- Turn left: 0->1->2->3->0
local function turn_left(dir)
    return (dir + 1) % 4
end

-- Turn right: 0->3->2->1->0
local function turn_right(dir)
    return (dir - 1 + 4) % 4
end

----------------------------------------------------------------------
-- parse_program: Walk the block chain starting at START pos,
-- returning a table of {action, param} instructions.
----------------------------------------------------------------------
local function parse_program(start_pos)
    local instructions = {}
    local pos = vector.new(start_pos.x, start_pos.y, start_pos.z)
    local visited = {}

    for _ = 1, MAX_INSTRUCTIONS do
        local key = minetest.pos_to_string(pos)
        if visited[key] then break end  -- cycle detected
        visited[key] = true

        local node = minetest.get_node(pos)
        local def = minetest.registered_nodes[node.name]

        if not def then break end

        local action = def._coding_action

        if action == "stop" then
            table.insert(instructions, {action = "stop"})
            break
        elseif action == "loop" then
            local meta = minetest.get_meta(pos)
            local count = meta:get_int("loop_count")
            if count == 0 then count = 3 end
            table.insert(instructions, {action = "loop_start", count = count})
        elseif action then
            table.insert(instructions, {action = action})
        end

        -- Follow the chain: next block is always at +X (right output face)
        -- respecting node's own facedir rotation
        local next_pos = vector.add(pos, vector.new(1, 0, 0))

        -- Check if next pos has a wire or a coding block
        local next_node = minetest.get_node(next_pos)
        if next_node.name == "luanti_coding:wire" then
            -- Skip over wire(s) until we hit a coding block
            local wire_pos = vector.new(next_pos.x, next_pos.y, next_pos.z)
            for _ = 1, 32 do
                wire_pos = vector.add(wire_pos, vector.new(1, 0, 0))
                local wn = minetest.get_node(wire_pos)
                if wn.name ~= "luanti_coding:wire" then
                    next_pos = wire_pos
                    break
                end
            end
        end

        local next_def = minetest.registered_nodes[minetest.get_node(next_pos).name]
        if not next_def or not (next_def._coding_action or next_def.groups.coding_stop) then
            break  -- chain ends
        end

        pos = next_pos
    end

    return instructions
end

----------------------------------------------------------------------
-- find_robot: Find the nearest luanti_robot entity to the player.
----------------------------------------------------------------------
local function find_robot(player)
    local player_pos = player:get_pos()
    local objects = minetest.get_objects_inside_radius(player_pos, 32)
    local closest = nil
    local closest_dist = math.huge
    for _, obj in ipairs(objects) do
        local ent = obj:get_luaentity()
        if ent and ent.name == "luanti_robot:robot" then
            local d = vector.distance(player_pos, obj:get_pos())
            if d < closest_dist then
                closest = obj
                closest_dist = d
            end
        end
    end
    return closest
end

----------------------------------------------------------------------
-- execute_program: Runs instructions on the robot with step delay.
----------------------------------------------------------------------
local function execute_step(robot, instructions, index, player_name)
    if index > #instructions then
        minetest.chat_send_player(player_name, "[Luanti Edu] ✓ Program finished!")
        return
    end

    local inst = instructions[index]
    local ent = robot:get_luaentity()
    if not ent then
        minetest.chat_send_player(player_name, "[Luanti Edu] ✗ Robot not found!")
        return
    end

    local action = inst.action

    if action == "move_forward" then
        ent:move_forward()
        minetest.chat_send_player(player_name, "[Luanti Edu] Step " .. index .. ": Move Forward")

    elseif action == "turn_left" then
        ent:turn_left()
        minetest.chat_send_player(player_name, "[Luanti Edu] Step " .. index .. ": Turn Left")

    elseif action == "turn_right" then
        ent:turn_right()
        minetest.chat_send_player(player_name, "[Luanti Edu] Step " .. index .. ": Turn Right")

    elseif action == "place_block" then
        ent:place_block()
        minetest.chat_send_player(player_name, "[Luanti Edu] Step " .. index .. ": Place Block")

    elseif action == "dig_block" then
        ent:dig_block()
        minetest.chat_send_player(player_name, "[Luanti Edu] Step " .. index .. ": Dig Block")

    elseif action == "if_clear" then
        local is_clear = ent:is_forward_clear()
        minetest.chat_send_player(player_name,
            "[Luanti Edu] Step " .. index .. ": IF Clear → " .. (is_clear and "YES (continue)" or "NO (skip next)"))
        if not is_clear then
            -- Skip the next instruction
            index = index + 1
        end

    elseif action == "loop_start" then
        -- Expand the loop inline: duplicate next instruction 'count' times
        minetest.chat_send_player(player_name,
            "[Luanti Edu] Step " .. index .. ": LOOP x" .. inst.count)
        local next_inst = instructions[index + 1]
        if next_inst then
            local expanded = {}
            for i = 1, #instructions do
                table.insert(expanded, instructions[i])
                if i == index then
                    -- inject (count-1) more copies of next_inst after it
                    for _ = 2, inst.count do
                        table.insert(expanded, next_inst)
                    end
                end
            end
            -- Restart execution with expanded instruction list, skip this index
            minetest.after(STEP_DELAY, function()
                execute_step(robot, expanded, index + 1, player_name)
            end)
            return
        end

    elseif action == "stop" then
        minetest.chat_send_player(player_name, "[Luanti Edu] ■ Program stopped.")
        return
    end

    -- Schedule the next step
    minetest.after(STEP_DELAY, function()
        execute_step(robot, instructions, index + 1, player_name)
    end)
end

----------------------------------------------------------------------
-- Public API: luanti_coding.run_program(start_pos, player)
----------------------------------------------------------------------
function luanti_coding.run_program(start_pos, player)
    local player_name = player:get_player_name()
    local robot = find_robot(player)

    if not robot then
        minetest.chat_send_player(player_name,
            "[Luanti Edu] No robot found nearby! Place a Robot Spawner and right-click it first.")
        return
    end

    local instructions = parse_program(start_pos)

    if #instructions == 0 then
        minetest.chat_send_player(player_name,
            "[Luanti Edu] No instructions found! Connect some blocks to the right of the START block.")
        return
    end

    minetest.chat_send_player(player_name,
        "[Luanti Edu] Starting program with " .. #instructions .. " instruction(s)...")

    execute_step(robot, instructions, 1, player_name)
end
