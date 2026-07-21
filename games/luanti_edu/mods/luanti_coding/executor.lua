-- Luanti Edu: Program Executor
-- Reads the chain of programming blocks starting from a START block,
-- builds a list of instructions, and executes them step-by-step on
-- the nearest luanti_robot entity.

luanti_coding = luanti_coding or {}

local MAX_INSTRUCTIONS = 256
local STEP_DELAY = 0.5
local WAIT_DELAY = 1.0
local WHILE_MAX_REPEAT = 16

local function parse_program(start_pos)
    local instructions = {}
    local pos = vector.new(start_pos.x, start_pos.y, start_pos.z)
    local visited = {}

    for _ = 1, MAX_INSTRUCTIONS do
        local key = minetest.pos_to_string(pos)
        if visited[key] then
            break
        end
        visited[key] = true

        local node = minetest.get_node(pos)
        local def = minetest.registered_nodes[node.name]
        if not def then
            break
        end

        local action = def._coding_action
        if action == "stop" then
            table.insert(instructions, { action = "stop" })
            break
        elseif action == "loop" then
            local meta = minetest.get_meta(pos)
            local count = meta:get_int("loop_count")
            if count == 0 then
                count = 3
            end
            table.insert(instructions, { action = "loop_start", count = count })
        elseif action then
            table.insert(instructions, { action = action })
        end

        local next_pos = vector.add(pos, vector.new(1, 0, 0))
        local next_node = minetest.get_node(next_pos)
        if next_node.name == "luanti_coding:wire" then
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
            break
        end

        pos = next_pos
    end

    return instructions
end

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

local function get_forward_node(ent)
    local pos = ent.object:get_pos()
    local dir_vec = ent._dir_vecs and ent._dir_vecs[ent._dir]
    if not dir_vec then
        return nil
    end
    return minetest.get_node(vector.add(pos, dir_vec))
end

local function execute_step(robot, instructions, index, player_name, state)
    state = state or { variables = {}, while_counts = {} }

    if index > #instructions then
        minetest.chat_send_player(player_name, "[Luanti Edu] Program finished!")
        return
    end

    local inst = instructions[index]
    local ent = robot:get_luaentity()
    if not ent then
        minetest.chat_send_player(player_name, "[Luanti Edu] Robot not found!")
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
            "[Luanti Edu] Step " .. index .. ": IF Clear -> " ..
            (is_clear and "YES (run next)" or "NO (skip next)"))
        if not is_clear then
            index = index + 1
        end

    elseif action == "else_block" then
        minetest.chat_send_player(player_name,
            "[Luanti Edu] Step " .. index .. ": ELSE -> skipping alternate block")
        index = index + 1

    elseif action == "while_clear" then
        local is_clear = ent:is_forward_clear()
        local repeats = state.while_counts[index] or 0
        minetest.chat_send_player(player_name,
            "[Luanti Edu] Step " .. index .. ": WHILE Clear -> " ..
            (is_clear and "YES" or "NO") .. " (" .. repeats .. "/" .. WHILE_MAX_REPEAT .. ")")

        local next_inst = instructions[index + 1]
        if is_clear and next_inst and repeats < WHILE_MAX_REPEAT then
            state.while_counts[index] = repeats + 1
            local expanded = {}
            for i = 1, #instructions do
                table.insert(expanded, instructions[i])
                if i == index then
                    table.insert(expanded, next_inst)
                    table.insert(expanded, { action = "while_jump", target = index })
                end
            end
            minetest.after(STEP_DELAY, function()
                execute_step(robot, expanded, index + 1, player_name, state)
            end)
            return
        else
            state.while_counts[index] = 0
            if next_inst then
                index = index + 1
            end
        end

    elseif action == "while_jump" then
        minetest.after(STEP_DELAY, function()
            execute_step(robot, instructions, inst.target, player_name, state)
        end)
        return

    elseif action == "variable_inc" then
        state.variables.counter = (state.variables.counter or 0) + 1
        minetest.chat_send_player(player_name,
            "[Luanti Edu] Step " .. index .. ": Variable counter = " .. state.variables.counter)

    elseif action == "sensor_clear" then
        local node = get_forward_node(ent)
        local is_clear = ent:is_forward_clear()
        local node_name = node and node.name or "unknown"
        minetest.chat_send_player(player_name,
            "[Luanti Edu] Step " .. index .. ": Sensor sees " .. node_name ..
            " -> " .. (is_clear and "clear" or "blocked"))
        if not is_clear then
            index = index + 1
        end

    elseif action == "wait" then
        minetest.chat_send_player(player_name, "[Luanti Edu] Step " .. index .. ": Wait")
        minetest.after(WAIT_DELAY, function()
            execute_step(robot, instructions, index + 1, player_name, state)
        end)
        return

    elseif action == "loop_start" then
        minetest.chat_send_player(player_name,
            "[Luanti Edu] Step " .. index .. ": LOOP x" .. inst.count)
        local next_inst = instructions[index + 1]
        if next_inst then
            local expanded = {}
            for i = 1, #instructions do
                table.insert(expanded, instructions[i])
                if i == index then
                    for _ = 2, inst.count do
                        table.insert(expanded, next_inst)
                    end
                end
            end
            minetest.after(STEP_DELAY, function()
                execute_step(robot, expanded, index + 1, player_name, state)
            end)
            return
        end

    elseif action == "stop" then
        minetest.chat_send_player(player_name, "[Luanti Edu] Program stopped.")
        return
    end

    minetest.after(STEP_DELAY, function()
        execute_step(robot, instructions, index + 1, player_name, state)
    end)
end

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
