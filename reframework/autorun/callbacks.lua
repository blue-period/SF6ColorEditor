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
			for _, child_xform in ipairs((player_object and player_object.children) or {}) do
				local child = get_anim_object(context, child_xform)
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
		context.runtime.imgui.text(child.name or "Object")
	end
end

local function draw_materials(_, _, context)
	local child = context.active_sf6_material_child
	local runtime = context.runtime
	if child and child.materials and runtime.imgui.tree_node_ptr_id(child.mesh, "Materials") then
		runtime.EMV.show_imgui_mats(child)
		runtime.imgui.tree_pop()
	end
end

return {
	draw_sf6_color_editor = draw_sf6_color_editor,
	draw_player_one = draw_player_one,
	draw_player_two = draw_player_two,
	draw_character_name = draw_character_name,
	draw_materials = draw_materials,
}
