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

-- Draw only the player's immediate EMV children and their material controls.
-- This keeps the SF6 Tools tree focused on color/material editing without the
-- transform and hierarchy nodes from the full EMV viewer.
local function draw_player_material_children(runtime, game, player_xform)
	local player = game.held_transforms[player_xform] or runtime.EMV.GameObject:new_AnimObject{xform=player_xform}
	if not player then return end
	game.held_transforms[player_xform] = player

	for _, child_xform in ipairs(player.children or {}) do
		local child = game.held_transforms[child_xform] or runtime.EMV.GameObject:new_AnimObject{xform=child_xform}
		if child then
			game.held_transforms[child_xform] = child
			local child_name = child.name or "Object"
			runtime.imgui.text(child_name)
			if child.materials and runtime.imgui.tree_node_ptr_id(child.mesh, "Materials") then
				runtime.EMV.show_imgui_mats(child)
				runtime.imgui.tree_pop()
			end
		end
	end
end



local function install_callbacks(callbacks, context)

	local state = context.state
	local camera = context.camera
	local lighting = context.lighting
	local sf6 = context.sf6
	local settings = context.settings
	local ui = context.ui
	local game = context.game
	local runtime = context.runtime
	local fn = context.functions
	local function mark_changed()
		state.was_changed = state.was_changed or state.changed
	end

	local function draw_named_node(name)
		local callback = callbacks[name]
		if callback then
			callback({ name = name, children = {} }, function() end)
		end
	end

	local function draw_enable_freecam()
		state.freecam_changed, state.freecam_on = runtime.imgui.checkbox("Enable FreeCam        ", state.freecam_on)
		if state.freecam_changed then
			camera.last_mouse_pos = fn.get_mouse_pos()
		end
	end

	local function draw_hide_ui()
		runtime.imgui.same_line()
		state.changed, state.hud_disabled = runtime.imgui.checkbox("Hide UI", state.hud_disabled)
	end

	local function draw_quality_toggle()
		runtime.imgui.same_line()
		state.changed, state.hi_quality = runtime.imgui.checkbox("2x Quality", state.hi_quality)
		fn.tooltip("Renders the game at double your resolution, then scales it down")
		if state.changed then
			fn.change_quality()
		end
	end

	local function draw_freeze_time_and_scene()
		state.changed, state.frozen_scene = runtime.imgui.checkbox("Freeze Time & Scene", state.frozen_scene)
		if state.changed then
			runtime.sdk.call_native_func(runtime.sdk.get_native_singleton("via.Application"), runtime.sdk.find_type_definition("via.Application"), "set_GlobalSpeed", (state.frozen_scene and 0.00001) or 1.0)
			if game.battleflow then game.battleflow:call("set_Enabled", not state.frozen_scene) end
		end
	end

	local function draw_orthographic_cam()
		if camera.cam and not runtime.imgui.same_line() then
			state.changed, state.use_orthographic = runtime.imgui.checkbox("Orthographic Cam", (camera.cam:call("get_ProjectionType") == 1))
			if state.changed then
				camera.cam:call("set_ProjectionType", state.use_orthographic and 1 or 0)
			end
		end
	end

	local function draw_enable_cam_light()
		if not camera.cam then return end
		state.changed, state.freecam_light_enabled = runtime.imgui.checkbox("Enable Cam Light", state.freecam_light_enabled)
		fn.tooltip("Attaches a configurable light to the camera")

		if state.changed then
			local had_light = camera.cam_light
			fn.create_or_toggle_cam_light()
			camera.cam_light.light:call("set_Enabled", state.freecam_light_enabled)
			if not had_light then camera.cam_light.attached = true end
		end
	end


	local function draw_sf6_tools()
		if game.isSF6 and sf6.players[2] then
			if runtime.imgui.tree_node("SF6 Color Editor") then
				runtime.imgui.begin_rect()
				for i = 2, 1, -1 do
					local player = sf6.players[i]
					local name = "P" .. (i == 2 and 1 or 2)
					if player then
						runtime.imgui.push_id(name)
						if runtime.imgui.tree_node(name) then
							runtime.imgui.begin_rect()
							if runtime.EMV then
								local player_xform = player:get_GameObject():get_Transform()
								draw_player_material_children(runtime, game, player_xform)
							end
							runtime.imgui.end_rect(2)
							runtime.imgui.tree_pop()
						end
						runtime.imgui.pop_id()
					end
				end
				runtime.imgui.end_rect(2)
				runtime.imgui.tree_pop()
			end
		else
			runtime.imgui.text()
			runtime.imgui.spacing()
		end
	end

	local function draw_lua_freecam_root()
		state.is_drawing_freecam_ui = true
		state.graphics_settings_mgr = game.isSF6 and runtime.sdk.get_managed_singleton("app.GraphicsSettingsManager")
		draw_sf6_tools()
		if state.was_changed then
			runtime.hk.update_hotkey_table(settings.freecam_settings.hotkeys)
			fn.dump_settings()
		end
	end

	callbacks["Enable FreeCam"] = draw_enable_freecam
	callbacks["Hide UI"] = draw_hide_ui
	callbacks["2x Quality"] = draw_quality_toggle
	callbacks["Freeze Time & Scene"] = draw_freeze_time_and_scene
	callbacks["Orthographic Cam"] = draw_orthographic_cam
	callbacks["Enable Cam Light"] = draw_enable_cam_light
	callbacks["SF6 Tools"] = draw_sf6_tools
	callbacks["Lua FreeCam v1.9.0"] = draw_lua_freecam_root
end

return install_callbacks
