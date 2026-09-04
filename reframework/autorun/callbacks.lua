local function install_callbacks(callbacks, context)
	callbacks["Enable FreeCam"] = function()
		context.draw_enable_freecam()
	end

	callbacks["Hide UI"] = function()
		context.draw_hide_ui()
	end

	callbacks["2x Quality"] = function()
		context.draw_quality_toggle()
	end

	callbacks["Freeze Time & Scene"] = function()
		context.draw_freeze_time_and_scene()
	end

	callbacks["Orthographic Cam"] = function()
		context.draw_orthographic_cam()
	end

	callbacks["Enable Cam Light"] = function()
		context.draw_enable_cam_light()
	end

	callbacks["SF6 Tools"] = function()
		context.draw_sf6_tools()
	end

	callbacks["Lua FreeCam v1.9.0"] = function(node, draw_children)
		context.draw_lua_freecam_root(node, draw_children)
	end
end

return install_callbacks
