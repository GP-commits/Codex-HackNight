-- Luanti
-- Copyright (C) 2014 sapier
-- SPDX-License-Identifier: LGPL-2.1-or-later


local current_game
local local_server_choices = {}
local local_server_last_sync = 0
local LOCAL_SERVER_SYNC_INTERVAL = 10
local valid_disabled_settings = {
	["enable_damage"]=true,
	["creative_mode"]=true,
	["enable_server"]=true,
}

-- Name and port stored to persist when updating the formspec
local current_name = core.settings:get("name") or ""
local current_port = core.settings:get("port") or core.settings:get("remote_port") or "30000"
local current_address = core.settings:get("address") or ""

local function is_private_address(address)
	if not address or address == "" then
		return false
	end
	return address == "localhost" or address == "127.0.0.1" or
		address:match("^10%.") or address:match("^192%.168%.") or
		address:match("^172%.1[6-9]%.") or address:match("^172%.2[0-9]%.") or
		address:match("^172%.3[0-1]%.")
end

local function get_local_server_choices()
	local choices = {}
	local seen = {}
	if serverlistmgr then
		local online = {}
		for _, server in ipairs(serverlistmgr.servers or {}) do
			if server.address and server.port then
				local port = tonumber(server.port) or 30000
				online[server.address:lower() .. ":" .. port] = server
				if is_private_address(server.address) then
					local key = server.address .. ":" .. port
					if not seen[key] then
						choices[#choices + 1] = {
							name = server.name or server.address,
							address = server.address,
							port = port,
						}
						seen[key] = true
					end
				end
			end
		end

		for _, fav in ipairs(serverlistmgr.get_favorites()) do
			if fav.address then
				local port = tonumber(fav.port) or 30000
				local online_server = online[fav.address:lower() .. ":" .. port]
				if is_private_address(fav.address) or online_server then
					local key = fav.address .. ":" .. port
					if not seen[key] then
						local source = online_server or fav
						choices[#choices + 1] = {
							name = source.name or fav.name or fav.address,
							address = fav.address,
							port = port,
						}
						seen[key] = true
					end
				end
			end
		end
	end
	return choices
end

local function render_local_serverlist()
	local rows = {}
	for _, server in ipairs(local_server_choices) do
		rows[#rows + 1] = core.formspec_escape(server.name .. "  " .. server.address .. ":" .. server.port)
	end
	if #rows == 0 then
		return core.formspec_escape(fgettext("No online local servers found"))
	end
	return table.concat(rows, ",")
end

-- Currently chosen game in gamebar for theming and filtering
function current_game()
	local gameid = core.settings:get("menu_last_game")
	local game = gameid and pkgmgr.find_by_gameid(gameid)
	-- Fall back to first game installed if one exists.
	if not game and #pkgmgr.games > 0 then

		-- If devtest is the first game in the list and there is another
		-- game available, pick the other game instead.
		local picked_game
		if pkgmgr.games[1].id == "devtest" and #pkgmgr.games > 1 then
			picked_game = 2
		else
			picked_game = 1
		end

		game = pkgmgr.games[picked_game]
		gameid = game.id
		core.settings:set("menu_last_game", gameid)
	end

	return game
end

-- Apply menu changes from given game
function apply_game(game)
	core.settings:set("menu_last_game", game.id)
	menudata.worldlist:set_filtercriteria(game.id)

	mm_game_theme.set_game(game)

	local index = filterlist.get_current_index(menudata.worldlist,
		tonumber(core.settings:get("mainmenu_last_selected_world")))
	if not index or index < 1 then
		local selected = core.get_textlist_index("sp_worlds")
		if selected ~= nil and selected < #menudata.worldlist:get_list() then
			index = selected
		else
			index = #menudata.worldlist:get_list()
		end
	end
	menu_worldmt_legacy(index)
end


local function get_disabled_settings(game)
	if not game then
		return {}
	end

	local gameconfig = Settings(game.path .. "/game.conf")
	local disabled_settings = {}
	if gameconfig then
		local disabled_settings_str = (gameconfig:get("disabled_settings") or ""):split()
		for _, value in pairs(disabled_settings_str) do
			local state = false
			value = value:trim()
			if string.sub(value, 1, 1) == "!" then
				state = true
				value = string.sub(value, 2)
			end
			if valid_disabled_settings[value] then
				disabled_settings[value] = state
			else
				core.log("error", "Invalid disabled setting in game.conf: "..tostring(value))
			end
		end
	end
	return disabled_settings
end

local function get_formspec(tabview, name, tabdata)
	tabdata.view = tabdata.view or "servers"
	if serverlistmgr and os.time() - local_server_last_sync >= LOCAL_SERVER_SYNC_INTERVAL then
		local_server_last_sync = os.time()
		serverlistmgr.sync()
	end
	local_server_choices = get_local_server_choices()

	-- Point the player to ContentDB when no games are found
	if #pkgmgr.games == 0 then
		local W = tabview.width
		local H = tabview.height

		local hypertext = "<global valign=middle halign=center size=18>" ..
				fgettext_ne("Luanti is a game-creation platform that allows you to play many different games.") .. "\n" ..
				fgettext_ne("Luanti doesn't come with a game by default.") .. " " ..
				fgettext_ne("You need to install a game before you can create a world.")

		local button_y = H * 2/3 - 0.6
		return table.concat({
			"hypertext[0.375,0;", W - 2*0.375, ",", button_y, ";ht;", core.formspec_escape(hypertext), "]",
			"button[5.25,", button_y, ";5,1.2;game_open_cdb;", fgettext("Install a game"), "]"})
	end

	local index = core.get_textlist_index("sp_worlds") or filterlist.get_current_index(menudata.worldlist,
				tonumber(core.settings:get("mainmenu_last_selected_world"))) or 0

	local list = menudata.worldlist:get_list()
	local world = list and list[math.min(index, #list)]
	local game

	if world then
		game = pkgmgr.find_by_gameid(world.gameid)
	else
		game = current_game()
	end
	local disabled_settings = get_disabled_settings(game)

	local educator, damage, host = "", "", ""
	local y = 1.45
	local yo = 0.95

	if world then
		if disabled_settings["creative_mode"] == nil then
			educator = "checkbox[0.35," .. y .. ";cb_educator_mode;" .. fgettext("Educator") .. ";" ..
				dump(core.settings:get_bool("educator_mode")) .. "]"
			y = y + yo
		end
		if disabled_settings["enable_damage"] == nil then
			damage = "checkbox[0.35,"..y..";cb_enable_damage;".. fgettext("Enable Damage") .. ";" ..
				dump(core.settings:get_bool("enable_damage")) .. "]"
			y = y + yo
		end
		if disabled_settings["enable_server"] == nil then
			host = "checkbox[0.35,"..y..";cb_server;".. fgettext("Host Server") ..";" ..
				dump(core.settings:get_bool("enable_server")) .. "]"
			y = y + yo
		end
	end

	-- Styling elements to match mockup
	local styles = "style_type[button,checkbox,textlist;border=true;content_offset=0;textcolor=#ffffff]" ..
		"style_type[label;textcolor=#ffffff]" ..
		"style_type[button;bgcolor=#3d3d3d;textcolor=#ffffff]" ..
		"style_type[button:hovered;bgcolor=#555555;textcolor=#ffffff]" ..
		"style_type[button:pressed;bgcolor=#222222;textcolor=#ffffff]" ..
		"style[play,join_local;bgcolor=#79d986;textcolor=#102416;font=bold;font_size=16]" ..
		"style[world_create;bgcolor=#79d986;textcolor=#102416;font=bold]" ..
		"style[world_delete;bgcolor=#b85b63;textcolor=#ffffff;font=bold]" ..
		"style[world_configure;bgcolor=#d8d8dc;textcolor=#30343a;font=bold]" ..
		"style[sp_worlds,local_servers;bgcolor=#141414dd;textcolor=#ffffff;border=false]" ..
		"style[mode_singleplayer,mode_local_servers;bgcolor=#ffffff18;textcolor=#ffffff]" ..
		"style[" .. (tabdata.view == "servers" and "mode_local_servers" or "mode_singleplayer") ..
		";bgcolor=#79d98666;textcolor=#ffffff]"

	local retval = styles ..
			"box[0.25,0.02;15.1,7.05;#0b0d10ee]" ..
			"box[0.4,0.17;14.8,6.75;#2f3338e8]" ..
			"box[0.55,0.32;14.5,6.45;#ffffff1f]" ..
			"button[5.0,0.65;2.7,0.65;mode_singleplayer;" .. fgettext("Singleplayer") .. "]" ..
			"button[7.9,0.65;2.9,0.65;mode_local_servers;" .. fgettext("Local Servers") .. "]"

	if tabdata.view == "servers" then
		local local_index = core.get_textlist_index("local_servers") or 1
		local chosen = local_server_choices[math.min(local_index, #local_server_choices)] or local_server_choices[1]
		local address = current_address ~= "" and current_address or (chosen and chosen.address) or "localhost"
		local port = current_port or tostring((chosen and chosen.port) or 30000)
		retval = retval ..
			"container[2.05,1.55]" ..
			"label[0,0;" .. fgettext("Local Servers") .. "]" ..
			"button[3.95,-0.15;1.95,0.55;refresh_local_servers;" .. fgettext("Refresh") .. "]" ..
			"textlist[0,0.35;5.9,3.35;local_servers;" ..
			render_local_serverlist() .. ";" .. local_index .. "]" ..
			"label[6.55,0;" .. fgettext("Name") .. "]" ..
			"field[6.55,0.25;4.15,0.75;te_playername;;" .. core.formspec_escape(current_name) .. "]" ..
			"label[6.55,1.15;" .. fgettext("Address") .. "]" ..
			"field[6.55,1.4;2.9,0.75;te_local_address;;" .. core.formspec_escape(address) .. "]" ..
			"label[9.65,1.15;" .. fgettext("Port") .. "]" ..
			"field[9.65,1.4;1.05,0.75;te_local_port;;" .. core.formspec_escape(port) .. "]" ..
			"label[6.55,2.3;" .. fgettext("Password") .. "]" ..
			"pwdfield[6.55,2.55;4.15,0.75;te_passwd;]" ..
			"button[7.2,4.2;3.5,0.8;join_local;> " .. fgettext("JOIN SERVER") .. "]" ..
			"container_end[]"
	else
		retval = retval ..
			"container[2.05,1.35]" ..
			educator ..
			damage ..
			host ..
			"container_end[]" ..
			"container[5.45,1.35]" ..
			"label[0,0;" .. fgettext("Worlds") .. "]" ..
			"textlist[0,0.35;6.3,3.35;sp_worlds;" ..
			menu_render_worldlist() ..
			";" .. index .. "]" ..
			"container_end[]" ..
			"box[1.65,5.0;12.45,0.03;#ffffff33]" ..
			"container[3.2,5.25]"

		if world then
			retval = retval ..
					"button[0,0;1.65,0.6;world_delete;".. fgettext("Delete") .. "]" ..
					"button[2.0,0;2.55,0.6;world_configure;".. fgettext("Configure Mods") .. "]"
		end

		retval = retval ..
				"button[4.9,0;2.25,0.6;world_create;+ " .. fgettext("New World") .. "]" ..
				"container_end[]"

		if core.settings:get_bool("enable_server") and disabled_settings["enable_server"] == nil then
			retval = retval ..
					"container[11.95,1.35]" ..
					"checkbox[0,0;cb_server_announce;" .. fgettext("Announce Server") .. ";" ..
					dump(core.settings:get_bool("server_announce")) .. "]"

			y = 0.6
			retval = retval .. "field[0," .. y .. ";2.4,0.7;te_playername;" .. fgettext("Name") .. ";" ..
					core.formspec_escape(current_name) .. "]"

			y = y + 1.0
			retval = retval .. "pwdfield[0," .. y .. ";2.4,0.7;te_passwd;" .. fgettext("Password") .. "]"

			y = y + 1.0
			local bind_addr = core.settings:get("bind_address")
			if bind_addr ~= nil and bind_addr ~= "" then
				retval = retval ..
					"field[0," .. y .. ";1.55,0.7;te_serveraddr;" .. fgettext("Bind Address") .. ";" ..
					core.formspec_escape(core.settings:get("bind_address")) .. "]" ..
					"field[1.7," .. y .. ";0.7,0.7;te_serverport;" .. fgettext("Port") .. ";" ..
					core.formspec_escape(current_port) .. "]"
			else
				retval = retval ..
					"field[0," .. y .. ";2.4,0.7;te_serverport;" .. fgettext("Server Port") .. ";" ..
					core.formspec_escape(current_port) .. "]"
			end
			retval = retval ..
				"button[0,3.35;2.4,0.75;play;> " .. fgettext("HOST GAME") .. "]" ..
				"container_end[]"
		elseif world then
			retval = retval ..
					"button[6.05,6.1;3.6,0.75;play;> " .. fgettext("PLAY GAME") .. "]"
		end
	end

	return retval
end

local function main_button_handler(this, fields, name, tabdata)

	assert(name == "local")

	if fields.game_open_cdb then
		local maintab = ui.find_by_name("maintab")
		local dlg = create_contentdb_dlg("game")
		dlg:set_parent(maintab)
		maintab:hide()
		dlg:show()
		return true
	end

	if this.dlg_create_world_closed_at == nil then
		this.dlg_create_world_closed_at = 0
	end

	local world_doubleclick = false

	if fields["te_playername"] then
		current_name = fields["te_playername"]
		core.settings:set("name", current_name)
	end

	if fields["te_serverport"] then
		current_port = fields["te_serverport"]
	end

	if fields["te_local_port"] then
		current_port = fields["te_local_port"]
	end

	if fields["te_local_address"] then
		current_address = fields["te_local_address"]
	end

	if fields["mode_singleplayer"] then
		tabdata.view = "singleplayer"
		return true
	end

	if fields["mode_local_servers"] then
		tabdata.view = "servers"
		return true
	end

	if fields["refresh_local_servers"] then
		if serverlistmgr then
			local_server_last_sync = os.time()
			serverlistmgr.sync()
		end
		return true
	end

	if fields["local_servers"] ~= nil then
		local event = core.explode_textlist_event(fields["local_servers"])
		local selected = core.get_textlist_index("local_servers") or 1
		local server = local_server_choices[selected]
		if server then
			current_address = server.address
			current_port = tostring(server.port)
			core.settings:set("address", current_address)
			core.settings:set("remote_port", current_port)
			if event.type == "DCL" then
				gamedata.mode = "join"
				gamedata.address = current_address
				gamedata.port = tonumber(current_port) or 30000
				gamedata.playername = current_name
				gamedata.password = fields["te_passwd"]
				gamedata.selected_world = 0
				core.start()
			end
			return true
		end
	end

	if fields["join_local"] then
		local port = tonumber(current_port) or 30000
		if current_address and current_address ~= "" then
			gamedata.mode = "join"
			gamedata.address = current_address
			gamedata.port = port
			gamedata.playername = current_name
			gamedata.password = fields["te_passwd"]
			gamedata.selected_world = 0
			core.settings:set("address", current_address)
			core.settings:set("remote_port", tostring(port))
			core.start()
		end
		return true
	end

	if fields["sp_worlds"] ~= nil then
		local event = core.explode_textlist_event(fields["sp_worlds"])
		local selected = core.get_textlist_index("sp_worlds")

		menu_worldmt_legacy(selected)

		if event.type == "DCL" then
			world_doubleclick = true
		end

		if event.type == "CHG" and selected ~= nil then
			core.settings:set("mainmenu_last_selected_world",
				menudata.worldlist:get_raw_index(selected))
			return true
		end
	end

	if menu_handle_key_up_down(fields,"sp_worlds","mainmenu_last_selected_world") then
		return true
	end

	if fields["cb_creative_mode"] then
		core.settings:set("creative_mode", fields["cb_creative_mode"])
		local selected = core.get_textlist_index("sp_worlds")
		menu_worldmt(selected, "creative_mode", fields["cb_creative_mode"])

		return true
	end

	if fields["cb_enable_damage"] then
		core.settings:set("enable_damage", fields["cb_enable_damage"])
		local selected = core.get_textlist_index("sp_worlds")
		menu_worldmt(selected, "enable_damage", fields["cb_enable_damage"])

		return true
	end

	if fields["cb_server"] then
		core.settings:set("enable_server", fields["cb_server"])

		return true
	end

	if fields["cb_server_announce"] then
		core.settings:set("server_announce", fields["cb_server_announce"])
		local selected = core.get_textlist_index("srv_worlds")
		menu_worldmt(selected, "server_announce", fields["cb_server_announce"])
		return true
	end

	if fields["cb_educator_mode"] then
		core.settings:set_bool("educator_mode", fields["cb_educator_mode"] == "true")
		return true
	end

	if fields["play"] ~= nil or world_doubleclick or fields["key_enter"] then
		local enter_key_duration = core.get_us_time() - this.dlg_create_world_closed_at
		if world_doubleclick and enter_key_duration <= 200000 then -- 200 ms
			this.dlg_create_world_closed_at = 0
			return true
		end

		local selected = core.get_textlist_index("sp_worlds")
		gamedata.selected_world = menudata.worldlist:get_raw_index(selected)

		if selected == nil or gamedata.selected_world == 0 then
			return true
		end

		-- Update last game
		local world = menudata.worldlist:get_raw_element(gamedata.selected_world)
		local game_obj
		if world then
			game_obj = pkgmgr.find_by_gameid(world.gameid)
			core.settings:set("menu_last_game", game_obj.id)
		end

		local disabled_settings = get_disabled_settings(game_obj)
		for k, _ in pairs(valid_disabled_settings) do
			local v = disabled_settings[k]
			if v ~= nil then
				if k == "enable_server" and v == true then
					error("Setting 'enable_server' cannot be force-enabled! The game.conf needs to be fixed.")
				end
				core.settings:set_bool(k, disabled_settings[k])
			end
		end

		if core.settings:get_bool("enable_server") then
			gamedata.mode       = "host"
			gamedata.playername = fields["te_playername"]
			gamedata.password   = fields["te_passwd"]
			gamedata.port       = fields["te_serverport"]
			gamedata.address    = ""

			core.settings:set("port",gamedata.port)
			if fields["te_serveraddr"] ~= nil then
				core.settings:set("bind_address",fields["te_serveraddr"])
			end

			-- Educator mode: grant the hosting player full admin privileges
			if core.settings:get_bool("educator_mode") then
				local pname = fields["te_playername"] or ""
				if pname ~= "" then
					core.settings:set("name", pname)
					core.settings:set("default_privs", "interact, shout")
					core.settings:set("initial_privs", "interact, shout")
					-- Server admin gets all privs
					core.settings:set("server_dedicated", "false")
				end
			end
		else
			gamedata.mode = "singleplayer"
		end

		core.start()
		return true
	end

	if fields["world_create"] ~= nil then
		this.dlg_create_world_closed_at = 0
		local create_world_dlg = create_create_world_dlg()
		create_world_dlg:set_parent(this)
		this:hide()
		create_world_dlg:show()
		return true
	end

	if fields["world_delete"] ~= nil then
		local selected = core.get_textlist_index("sp_worlds")
		if selected ~= nil and
			selected <= menudata.worldlist:size() then
			local world = menudata.worldlist:get_list()[selected]
			if world ~= nil and
				world.name ~= nil and
				world.name ~= "" then
				local index = menudata.worldlist:get_raw_index(selected)
				local delete_world_dlg = create_delete_world_dlg(world.name,index)
				delete_world_dlg:set_parent(this)
				this:hide()
				delete_world_dlg:show()
			end
		end

		return true
	end

	if fields["world_configure"] ~= nil then
		local selected = core.get_textlist_index("sp_worlds")
		if selected ~= nil then
			local configdialog =
				create_configure_world_dlg(
						menudata.worldlist:get_raw_index(selected))

			if (configdialog ~= nil) then
				configdialog:set_parent(this)
				this:hide()
				configdialog:show()
			end
		end

		return true
	end
end

local function on_change(type)
	if type == "ENTER" then
		local game = current_game()
		if game then
			apply_game(game)
		else
			mm_game_theme.set_engine()
		end
	elseif type == "LEAVE" then
		menudata.worldlist:set_filtercriteria(nil)
	end
end

--------------------------------------------------------------------------------
return {
	name = "local",
	caption = fgettext("Start Game"),
	cbf_formspec = get_formspec,
	cbf_button_handler = main_button_handler,
	on_change = on_change
}
