function printTableR(tbl, indent, recurse)
    indent = indent or 0
    recurse = recurse or 0

    local spacing = string.rep("  ", indent)
    local result = ""

    for key, value in pairs(tbl) do
        if type(value) == "table" and recurse > 0 then
            result = result .. spacing .. tostring(key) .. " = {\n"
            result = result .. printTableR(value, indent + 1, recurse - 1)
            result = result .. spacing .. "}\n"
        else
            result = result .. spacing .. tostring(key) .. " = " .. tostring(value) .. "\n"
        end
    end

    return result
end

function printTable(tbl)
    local result = ""

    for key, value in pairs(tbl) do
        result = result .. tostring(key) .. " = " .. tostring(value) .. "\n"
    end

    return result
end

-- Return a readable, read-only description of a REFramework managed userdata
-- object and also write it to the REFramework log. This intentionally lists
-- method signatures instead of calling getters: getters may have side effects.
local function print_managed_userdata(runtime, value)
    local lines = {}
    if type(value) ~= "userdata" or not runtime.sdk.is_managed_object(value) then
        local message = "Expected managed userdata, got " .. type(value) .. ": " .. tostring(value)
        log.info(message)
        return message
    end

    local ok, err = pcall(function()
        local typedef = value:get_type_definition()
        lines[#lines + 1] = "Managed userdata: " .. typedef:get_full_name()
        lines[#lines + 1] = "Address: " .. tostring(value:get_address())
        lines[#lines + 1] = "Fields:"

        for _, field in ipairs(typedef:get_fields()) do
            local field_ok, field_line = pcall(function()
                local field_value = field:get_data(value)
                return string.format("  %s %s = %s", field:get_type():get_full_name(), field:get_name(), runtime.EMV.logv(field_value, nil, 0))
            end)
            lines[#lines + 1] = field_ok and field_line or ("  " .. field:get_name() .. " = <unreadable: " .. tostring(field_line) .. ">")
        end

        lines[#lines + 1] = "Methods:"
        for _, method in ipairs(typedef:get_methods()) do
            local method_ok, method_line = pcall(function()
                local return_type = method:get_return_type()
                local parameter_types = {}
                for _, parameter_type in ipairs(method:get_param_types()) do
                    parameter_types[#parameter_types + 1] = parameter_type:get_full_name()
                end
                return string.format(
                    "  %s %s(%s)",
                    return_type and return_type:get_full_name() or "void",
                    method:get_name(),
                    table.concat(parameter_types, ", ")
                )
            end)
            lines[#lines + 1] = method_ok and method_line or ("  " .. method:get_name() .. "(<unreadable signature>)")
        end
    end)

    if not ok then
        lines[#lines + 1] = "Inspection failed: " .. tostring(err)
    end

    local output = table.concat(lines, "\n")
    log.info(output)
    return output
end

local function get_anim_object(context, xform)
	local game = context.game
	local object = game.held_transforms[xform] or context.runtime.EMV.GameObject:new_AnimObject{xform=xform}
	if object then
		game.held_transforms[xform] = object
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
	local file = UserFile:new{filepath=real_path}
	local saved = false
	for _, child in ipairs(children) do
		if child.materials and child.materials.is_cmd then
			saved = file:save(real_path, false, false, true, child.materials) or saved
			child.materials.UserFile = file
		end
	end
	if saved then context.runtime.re.msg("Saved CMD changes for all objects to:\n" .. real_path) end
end

local function draw_player_material_controls(children, context, player_name)
	local runtime = context.runtime
	local imgui = runtime.imgui
	local key = player_name
	context.sf6_material_ui = context.sf6_material_ui or {}
	local state = context.sf6_material_ui[key] or {}
	local first = children[1]
	local owner = first and (first.name_w_parent or first.name)
	if state.owner ~= owner then state = {owner=owner} end
	context.sf6_material_ui[key] = state
	local target_name = first and first.name or key

	if SettingsCache and SettingsCache.remember_materials and imgui.button("Save New Defaults##" .. key) then
		save_new_defaults(children, context)
	end

	if RN and RN.mesh_resource_names and RN.mdf2_resource_names then
		state.mesh_idx = state.mesh_idx or (first and first.mpaths and runtime.EMV.find_index(RN.mesh_resource_names, first.mpaths.mesh_path)) or 1
		local changed
		changed, state.mesh_idx = imgui.combo("Change Mesh " .. target_name .. "##" .. key, state.mesh_idx, RN.mesh_resource_names)
		if changed then set_mesh_for_children(children, RN.mesh_resource_names[state.mesh_idx], context) end

		state.mdf_idx = state.mdf_idx or (first and first.mpaths and runtime.EMV.find_index(RN.mdf2_resource_names, first.mpaths.mdf2_path)) or 1
		changed, state.mdf_idx = imgui.combo("Change Materials " .. target_name .. "##" .. key, state.mdf_idx, RN.mdf2_resource_names)
		if changed then set_materials_for_children(children, RN.mdf2_resource_names[state.mdf_idx], context) end
	end

	if _G.RE_Resource and BitStream and first and first.materials then
		state.mdf_path = state.mdf_path or default_mdf_path(first, context)
		local mdf_exists = state.mdf_path ~= "" and BitStream.checkFileExists(state.mdf_path:gsub("^reframework/data/", ""))
		if mdf_exists then
			if imgui.button("Save MDF##" .. key) then save_mdf_for_children(children, state.mdf_path, context) end
			imgui.same_line()
		end
		local changed
		changed, state.mdf_path = imgui.input_text("Modify MDF File" .. (mdf_exists and "" or " (Does Not Exist)") .. "##" .. key, state.mdf_path)

		state.cmd_path = state.cmd_path or default_cmd_path(first, context)
		local cmd_exists = state.cmd_path ~= "" and BitStream.checkFileExists(state.cmd_path:gsub("^reframework/data/", ""))
		if cmd_exists then
			if imgui.button("Save CMD##" .. key) then save_cmd_for_children(children, state.cmd_path, context) end
			imgui.same_line()
		end
		changed, state.cmd_path = imgui.input_text("Modify CMD File" .. (cmd_exists and "" or " (Does Not Exist)") .. "##" .. key, state.cmd_path)
	end
end

local function draw_sf6_color_editor(node, draw_children, context)
	local state = context.state
	local game = context.game
	local runtime = context.runtime

	state.is_drawing_freecam_ui = true
	state.graphics_settings_mgr = game.isSF6 and runtime.sdk.get_managed_singleton("app.GraphicsSettingsManager")

	if game.isSF6 and context.sf6.players[2] then
		if runtime.imgui.tree_node(node.name) then
			runtime.imgui.begin_rect()
			draw_children()
			runtime.imgui.end_rect(2)
			runtime.imgui.tree_pop()
		end
	else
		runtime.imgui.text()
		runtime.imgui.spacing()
	end

	if state.was_changed then
		runtime.hk.update_hotkey_table(context.settings.freecam_settings.hotkeys)
		context.functions.dump_settings()
	end
end

local function draw_player(node, draw_children, context, player_index)
	local player = context.sf6.players[player_index]
	if not player then return end

	local runtime = context.runtime
	runtime.imgui.push_id(node.name)
	if runtime.imgui.tree_node(node.name) then
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
			draw_player_material_controls(children, context, node.name)
			for _, child in ipairs(children) do
				if child then
					context.active_sf6_material_child = child
					draw_children()
				end
			end
			context.active_sf6_material_child = nil
		end
		runtime.imgui.end_rect(2)
		runtime.imgui.tree_pop()
	end
	runtime.imgui.pop_id()
end

local function draw_player_one(node, draw_children, context)
	draw_player(node, draw_children, context, 2)
end

local function draw_player_two(node, draw_children, context)
	draw_player(node, draw_children, context, 1)
end

local function draw_character_name(_, _, context)
	local child = context.active_sf6_material_child
	if child then
		local imgui = context.runtime.imgui
		context.sf6_material_node_open = imgui.tree_node_ptr_id(child.mesh or child.xform, child.name or "Object")
	end
end

local function draw_materials(_, _, context)
	local child = context.active_sf6_material_child
	local runtime = context.runtime
	if child and child.materials and context.sf6_material_node_open then
		for _, material in ipairs(child.materials) do
			material:draw_imgui_mat()
		end
		runtime.imgui.tree_pop()
	end
	context.sf6_material_node_open = nil
end

return {
	draw_sf6_color_editor = draw_sf6_color_editor,
	draw_player_one = draw_player_one,
	draw_player_two = draw_player_two,
	draw_character_name = draw_character_name,
	draw_materials = draw_materials,
}
