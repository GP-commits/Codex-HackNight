-- Luanti Edu: Robot Entity
-- A friendly programmable robot that students control via coding blocks.

local modpath = minetest.get_modpath("luanti_robot")
local ROBOT_GRAVITY = -9.81
local ROBOT_MAX_FALL_SPEED = -20

local function is_walkable(pos)
    local node = minetest.get_node_or_nil(pos)
    if not node then
        return false
    end

    local node_def = minetest.registered_nodes[node.name]
    return node_def and node_def.walkable
end

local function snap_to_block_center(pos)
    return vector.new(math.floor(pos.x + 0.5), pos.y, math.floor(pos.z + 0.5))
end

----------------------------------------------------------------------
-- Robot Entity Definition
----------------------------------------------------------------------
minetest.register_entity("luanti_robot:robot", {
    initial_properties = {
        physical = true,
        collide_with_objects = false,
        collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
        visual = "mesh",
        mesh = "character.b3d",
        textures = {"robot.png"},
        visual_size = {x = 1, y = 1},
        makes_footstep_sound = true,
        static_save = true,
    },

    -- Robot's facing direction (0=North, 1=West, 2=South, 3=East)
    _dir = 0,

    -- Direction offset vectors
    _dir_vecs = {
        [0] = vector.new( 0, 0,  1),
        [1] = vector.new(-1, 0,  0),
        [2] = vector.new( 0, 0, -1),
        [3] = vector.new( 1, 0,  0),
    },

    on_activate = function(self, staticdata, dtime_s)
        self.object:set_armor_groups({immortal = 1})
        self.object:set_acceleration(vector.new(0, ROBOT_GRAVITY, 0))
        -- Restore direction from staticdata
        if staticdata and staticdata ~= "" then
            local data = minetest.deserialize(staticdata)
            if data then self._dir = data.dir or 0 end
        end
        self:_update_yaw()
    end,

    get_staticdata = function(self)
        return minetest.serialize({dir = self._dir})
    end,

    on_rightclick = function(self, clicker)
        local pname = clicker:get_player_name()
        minetest.chat_send_player(pname,
            "[Luanti Edu] Robot is ready! Place START block and coding blocks, then right-click START to run.")
    end,

    on_step = function(self, dtime)
        local vel = self.object:get_velocity()
        if not vel then
            return
        end

        local pos = self.object:get_pos()
        local standing_on = vector.offset(pos, 0, -0.1, 0)
        if is_walkable(standing_on) and vel.y <= 0 then
            self.object:set_velocity(vector.new(0, 0, 0))
            self.object:set_acceleration(vector.new(0, 0, 0))
        else
            self.object:set_acceleration(vector.new(0, ROBOT_GRAVITY, 0))
            if vel.y < ROBOT_MAX_FALL_SPEED then
                self.object:set_velocity(vector.new(0, ROBOT_MAX_FALL_SPEED, 0))
            else
                self.object:set_velocity(vector.new(0, vel.y, 0))
            end
        end
    end,

    --------------------------------------------------------------------
    -- Robot Actions (called by the executor)
    --------------------------------------------------------------------

    _update_yaw = function(self)
        -- Convert direction index to yaw
        local yaw_map = {[0] = 0, [1] = math.pi/2, [2] = math.pi, [3] = -math.pi/2}
        self.object:set_yaw(yaw_map[self._dir] or 0)
    end,

    move_forward = function(self)
        local pos = snap_to_block_center(self.object:get_pos())
        local dir_vec = self._dir_vecs[self._dir]
        local new_pos = vector.add(pos, dir_vec)

        -- Check if destination is walkable
        if is_walkable(new_pos) then
            -- Try to step up one block
            local up_pos = vector.add(new_pos, vector.new(0, 1, 0))
            if not is_walkable(up_pos) then
                new_pos = up_pos
            else
                return  -- blocked, can't move
            end
        else
            -- Check if we'd fall (drop down)
            local below = vector.add(new_pos, vector.new(0, -1, 0))
            if not is_walkable(below) then
                new_pos = below  -- step down
            end
        end

        self.object:set_pos(snap_to_block_center(new_pos))
        self.object:set_velocity(vector.new(0, 0, 0))
        self.object:set_acceleration(vector.new(0, ROBOT_GRAVITY, 0))
        -- Play movement animation/sound
        minetest.sound_play("robot_move", {object = self.object, gain = 0.5}, true)
    end,

    turn_left = function(self)
        self._dir = (self._dir + 1) % 4
        self:_update_yaw()
        minetest.sound_play("robot_turn", {object = self.object, gain = 0.3}, true)
    end,

    turn_right = function(self)
        self._dir = (self._dir - 1 + 4) % 4
        self:_update_yaw()
        minetest.sound_play("robot_turn", {object = self.object, gain = 0.3}, true)
    end,

    is_forward_clear = function(self)
        local pos = self.object:get_pos()
        local dir_vec = self._dir_vecs[self._dir]
        local check_pos = vector.add(pos, dir_vec)
        local node = minetest.get_node(check_pos)
        local node_def = minetest.registered_nodes[node.name]
        return node_def and not node_def.walkable
    end,

    place_block = function(self)
        local pos = self.object:get_pos()
        local dir_vec = self._dir_vecs[self._dir]
        local target = vector.add(pos, dir_vec)
        local node = minetest.get_node(target)
        local node_def = minetest.registered_nodes[node.name]
        if node_def and not node_def.walkable then
            minetest.set_node(target, {name = "default:stone"})
            minetest.sound_play("default_place_node_hard", {pos = target, gain = 0.5}, true)
        end
    end,

    dig_block = function(self)
        local pos = self.object:get_pos()
        local dir_vec = self._dir_vecs[self._dir]
        local target = vector.add(pos, dir_vec)
        local node = minetest.get_node(target)
        local node_def = minetest.registered_nodes[node.name]
        if node_def and node_def.walkable and node.name ~= "air" then
            minetest.remove_node(target)
            minetest.sound_play("default_dig_hard", {pos = target, gain = 0.5}, true)
        end
    end,
})

----------------------------------------------------------------------
-- Robot Spawner Node
-- Players right-click this to spawn a robot at that location.
----------------------------------------------------------------------
minetest.register_node("luanti_robot:spawner", {
    description = "Robot Spawner\nRight-click to place a programmable robot here!",
    tiles = {"robot_spawner.png"},
    groups = {cracky = 1},
    is_ground_content = false,
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        local pname = clicker:get_player_name()
        local spawn_pos = vector.add(snap_to_block_center(pos), vector.new(0, 1, 0))
        -- Check if there is already a robot nearby
        local objs = minetest.get_objects_inside_radius(spawn_pos, 2)
        for _, obj in ipairs(objs) do
            local ent = obj:get_luaentity()
            if ent and ent.name == "luanti_robot:robot" then
                minetest.chat_send_player(pname,
                    "[Luanti Edu] A robot already exists here!")
                return itemstack
            end
        end
        minetest.add_entity(spawn_pos, "luanti_robot:robot")
        minetest.chat_send_player(pname,
            "[Luanti Edu] Robot spawned! Now build your program with coding blocks and right-click the START block.")
        return itemstack
    end,
})

minetest.register_craft({
    output = "luanti_robot:spawner",
    recipe = {
        {"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
        {"default:steel_ingot", "default:mese_crystal",  "default:steel_ingot"},
        {"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
    },
})

minetest.log("action", "[luanti_robot] Loaded!")
