local function get_anim_object(context, xform)
	local object = context.held_transforms[xform] or context.runtime.EMV.GameObject:new_AnimObject{xform=xform}
	if object then
		context.held_transforms[xform] = object
	end
	return object
end

local function get_upvalue(func, wanted_name)
	if not debug or not debug.getupvalue then return nil end
	for index = 1, 100 do
		local name, value = debug.getupvalue(func, index)
		if not name then break end
		if name == wanted_name then return value end
	end
end

local function save_new_defaults(children, context)
	local saved_names = {}
	for _, child in ipairs(children) do
		for _, material in ipairs(child.materials or {}) do
			material:save_json_material()
		end
		if child.name_w_parent then saved_names[child.name_w_parent] = true end
	end

	local saved_mats = get_upvalue(context.runtime.EMV.show_imgui_mats, "saved_mats")
	if saved_mats then
		for name in pairs(saved_names) do
			if saved_mats[name] then
				context.runtime.json.dump_file(
					"EMV_Engine\\Saved_Materials\\" .. name .. ".json",
					context.runtime.EMV.jsonify_table(saved_mats[name])
				)
			end
		end
	end
end

local function set_mesh_for_children(children, resource_name, context)
	local resource = RSCache and RSCache.mesh_resources and RSCache.mesh_resources[resource_name]
	if not resource then return end

	if type(resource[1]) == "string" then
		context.runtime.EMV.add_resource_to_cache(resource[1], resource[2])
		resource = RSCache.mesh_resources[resource_name]
	end
	for _, child in ipairs(children) do
		if child.mesh then
			local old_parent = child.parent
			child:set_parent(0)
			child.mesh:call("setMesh", resource[1])
			if old_parent then child:set_parent(old_parent) end
			if resource[2] then
				child.mesh:call("set_Material", resource[2])
				child.mpaths = child.mpaths or {}
				child.mpaths.mdf2_path = resource[2]:call("ToString()"):match("^.+%[@?(.+)%]")
			end
			child.mpaths = child.mpaths or {}
			child.mpaths.mesh_path = resource_name
			child:set_materials()
		end
	end
end

local function set_materials_for_children(children, resource_name, context)
	local resource = RSCache and RSCache.mdf2_resources and RSCache.mdf2_resources[resource_name]
	if not resource then return end
	if type(resource) == "string" then
		context.runtime.EMV.add_resource_to_cache(resource)
		resource = RSCache.mdf2_resources[resource_name]
	else
		context.runtime.EMV.add_resource_to_cache(resource)
	end
	for _, child in ipairs(children) do
		if child.mesh then
			child.mesh:call("set_Material", resource)
			child.mpaths = child.mpaths or {}
			child.mpaths.mdf2_path = resource_name
			child:set_materials()
		end
	end
end

local function default_mdf_path(child, context)
	if not child or not child.mpaths or not child.mpaths.mdf2_path then return "" end
	local platform = context and context.runtime.sdk.get_tdb_version() <= 67 and "x64/" or "stm/"
	local extension = MDFFile and MDFFile.extensions and MDFFile.extensions[game_name] or ""
	return "$natives/" .. platform .. child.mpaths.mdf2_path .. extension
end

local function default_cmd_path(child, context)
	local path = ""
	pcall(function()
		child.parent_obj = child.parent_obj or context.runtime.EMV.GameObject:new{xform=child.parent}
		local controller = child.parent_obj.components_named.PlayerColorController
		path = "$natives/stm/" .. controller.ColorData.Datas[controller.ColorNum]:get_Path() .. ".2"
	end)
	return path
end

local function save_mdf_for_children(children, path, context)
	local real_path = path:gsub("^reframework/data/", "")
	local saved = 0
	for _, child in ipairs(children) do
		local mesh = child.mesh or (child.materials and child.materials[1] and child.materials[1].mesh)
		if mesh and MDFFile then
			local file = MDFFile:new{filepath=real_path, mobject=mesh}
			child.materials.mesh = mesh
			if file:save(real_path, false, false, true, child.materials) then saved = saved + 1 end
			child.materials.MDFFile = file
		end
	end
	if saved > 0 then context.runtime.re.msg("Saved MDF changes for " .. saved .. " object(s) to:\n" .. path) end
end

local function save_cmd_for_children(children, path, context)
    local real_path = path:gsub("^reframework/data/", "")

    if not UserFile then return end

    if real_path == "" or not BitStream.checkFileExists(real_path) then
        context.runtime.re.msg("Could not find CMD file:\n" .. path)
        return
    end

    local file = UserFile:new{filepath = real_path}

    if not file.RSZ or not file.RSZ.objects or not file.RSZ.objects[1] then
        context.runtime.re.msg("Could not read CMD file:\n" .. path)
        return
    end

    local saved = false

    for _, child in ipairs(children) do
        if child.materials and child.materials.is_cmd then
            saved = file:save(real_path, false, false, true, child.materials) or saved
            child.materials.UserFile = file
        end
    end

    if saved then
        context.runtime.re.msg("Saved CMD changes to:\n" .. path)
    end
end

local function get_player_material_state(context, player_name, owner)
	context.sf6_material_ui = context.sf6_material_ui or {}
	local state = context.sf6_material_ui[player_name] or {}
	if state.owner ~= owner then
		state = {owner=owner, children={}}
	end
	state.children = state.children or {}
	context.sf6_material_ui[player_name] = state
	return state
end

local function draw_player_material_controls(children, context, player_name, owner)
	local runtime = context.runtime
	local imgui = runtime.imgui
	local state = get_player_material_state(context, player_name, owner)
	local key = player_name
	local first = children[1]

	if SettingsCache and SettingsCache.remember_materials and imgui.button("Save New Defaults##" .. key) then
		save_new_defaults(children, context)
	end

	if _G.RE_Resource and BitStream and first and first.materials then
		state.cmd_path = state.cmd_path or default_cmd_path(first, context)
		local cmd_exists = state.cmd_path ~= "" and BitStream.checkFileExists(state.cmd_path:gsub("^reframework/data/", ""))
		if cmd_exists then
			if imgui.button("Save CMD##" .. key) then save_cmd_for_children(children, state.cmd_path, context) end
			imgui.same_line()
		end
		local changed
		changed, state.cmd_path = imgui.input_text("Modify CMD File" .. (cmd_exists and "" or " (Does Not Exist)") .. "##" .. key, state.cmd_path)
	end
end

local function draw_child_material_controls(child, context, player_name)
	local runtime = context.runtime
	local imgui = runtime.imgui
	local player_state = get_player_material_state(context, player_name, context.active_sf6_player_owner)
	local child_state_key = child.xform or child.mesh or child
	local state = player_state.children[child_state_key] or {}
	player_state.children[child_state_key] = state
	local key = player_name .. "::" .. tostring(child_state_key)
	local target_name = child.name or tostring(child_state_key)

	if RN and RN.mesh_resource_names and RN.mdf2_resource_names then
		state.mesh_idx = state.mesh_idx or (child.mpaths and runtime.EMV.find_index(RN.mesh_resource_names, child.mpaths.mesh_path)) or 1
		local changed
		changed, state.mesh_idx = imgui.combo("Change Mesh " .. target_name .. "##" .. key, state.mesh_idx, RN.mesh_resource_names)
		if changed then
			set_mesh_for_children({child}, RN.mesh_resource_names[state.mesh_idx], context)
			state.mdf_idx = child.mpaths and runtime.EMV.find_index(RN.mdf2_resource_names, child.mpaths.mdf2_path) or state.mdf_idx
			state.mdf_path = default_mdf_path(child, context)
		end

		state.mdf_idx = state.mdf_idx or (child.mpaths and runtime.EMV.find_index(RN.mdf2_resource_names, child.mpaths.mdf2_path)) or 1
		changed, state.mdf_idx = imgui.combo("Change Materials " .. target_name .. "##" .. key, state.mdf_idx, RN.mdf2_resource_names)
		if changed then
			set_materials_for_children({child}, RN.mdf2_resource_names[state.mdf_idx], context)
			state.mdf_path = default_mdf_path(child, context)
		end
	end

	if _G.RE_Resource and BitStream and child.materials then
		state.mdf_path = state.mdf_path or default_mdf_path(child, context)
		local mdf_exists = state.mdf_path ~= "" and BitStream.checkFileExists(state.mdf_path:gsub("^reframework/data/", ""))
		if mdf_exists then
			if imgui.button("Save MDF##" .. key) then save_mdf_for_children({child}, state.mdf_path, context) end
			imgui.same_line()
		end
		local changed
		changed, state.mdf_path = imgui.input_text("Modify MDF File" .. (mdf_exists and "" or " (Does Not Exist)") .. "##" .. key, state.mdf_path)
	end
end

local function draw_sf6_color_editor(context, draw_players)
	local runtime = context.runtime

	if context.is_sf6 and context.players[2] then
		if runtime.imgui.tree_node("SF6 Color Editor") then
			runtime.imgui.begin_rect()
			draw_players()
			runtime.imgui.end_rect(2)
			runtime.imgui.tree_pop()
		end
	else
		runtime.imgui.text()
		runtime.imgui.spacing()
	end
end

local function draw_player(context, player_index, player_name, draw_materials)
	local player = context.players[player_index]
	if not player then return end

	local runtime = context.runtime
	runtime.imgui.push_id(player_name)
	if runtime.imgui.tree_node(player_name) then
		runtime.imgui.begin_rect()
		if runtime.EMV then
			local player_xform = player:get_GameObject():get_Transform()
			local player_object = get_anim_object(context, player_xform)
			local children = {}
			for _, child_xform in ipairs((player_object and player_object.children) or {}) do
				local child = get_anim_object(context, child_xform)
				if child and child.materials then
					children[#children + 1] = child
				end
			end
			draw_player_material_controls(children, context, player_name, player_xform)
			context.active_sf6_player_name = player_name
			context.active_sf6_player_owner = player_xform
			for _, child in ipairs(children) do
				if child then
					context.active_sf6_material_child = child
				draw_materials()
				end
			end
			context.active_sf6_material_child = nil
			context.active_sf6_player_name = nil
			context.active_sf6_player_owner = nil
		end
		runtime.imgui.end_rect(2)
		runtime.imgui.tree_pop()
	end
	runtime.imgui.pop_id()
end

local function draw_player_one(context, draw_materials)
	draw_player(context, 2, "P1", draw_materials)
end

local function draw_player_two(context, draw_materials)
	draw_player(context, 1, "P2", draw_materials)
end

local function draw_materials(context)
	local child = context.active_sf6_material_child
	if not child or not child.materials then return end

	local imgui = context.runtime.imgui
	if imgui.tree_node_ptr_id(child.mesh or child.xform, child.name or "Object") then
		draw_child_material_controls(child, context, context.active_sf6_player_name)
		for _, material in ipairs(child.materials) do
			material:draw_imgui_mat()
		end
		imgui.tree_pop()
	end
end

return {
	draw_sf6_color_editor = draw_sf6_color_editor,
	draw_player_one = draw_player_one,
	draw_player_two = draw_player_two,
	draw_materials = draw_materials,
}
