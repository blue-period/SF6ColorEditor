--RE Engine Lua Freecam Script v1.9.0
--by alphaZomega, June 9, 2024
--Special thanks to praydog and Tedder


--Added 'Light Configuration' save/load boxes to recall positions of lights relative to the orbit Gizmo
--Added 'Mount Object Name' and 'Mount Joint Name' text boxes to let you mount the camera to a joint on an object:getSampleRate()
--Added gamepad support for pointing the camera (with invert-Y option)
--Switched to 'ProjectionSpotLight' type camera lights


local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
_G["is" .. reframework.get_game_name():sub(1, 3):upper()] = true

pcall(function()
	--EMV = EMV or require("EMV Engine") --EMV is not required but it allows for many powerful features including camera orbit
	--https://github.com/alphazolam/EMV-Engine
end)

local candela_multi = 12.57

local default_settings = {
	hotkeys = {
		["Activate FreeCam"] = "F5",
		["Hide UI"] = "F8",
		["2x Quality"] = "F7",
		["Toggle FreeCam Light"] = "F6",
		["CModifier"] = "LShift",
		["CModifier2"] = "RShift",
		["CModifier3"] = "LAlt",
		["Cam Forward"] = "NumPad8",
		["Cam Backward"] = "NumPad2",
		["Cam Left"] = "NumPad4",
		["Cam Right"] = "NumPad6",
		["Cam Up"] = "NumPad9",
		["Cam Down"] = "NumPad3",
		["Roll Left"] = "NumPad7",
		["Roll Right"] = "NumPad1",
		["Freeze Camera"] = "Divide",
		["Zoom In"] = "Subtract",
		["Zoom Out"] = "Add",
		["Reset Zoom"] = "NumPadEnter",
		["Freeze Time"] = "NumPad0",
		["Freeze Time & Scene"] = (isSF6 and "Pause") or "NumPad0",
		["Skip Frame"] = "Decimal",
		["Quick Zoom"] = "LStickPush",
		["Create New Light"] = "NumPad5",
		["Attach/Detach Selected Light"] = "OEM_102",
		["Move to Light 0"] = "Alpha1",
		["Move to Light 1"] = "Alpha2",
		["Move to Light 2"] = "Alpha3",
		["Move to Light 3"] = "Alpha4",
		["Move to Light 4"] = "Alpha5",
		["Move to Light 5"] = "Alpha6",
		["Move to Light 6"] = "Alpha7",
		["Move to Light 7"] = "Alpha8",
		["Move to Light 8"] = "Alpha9",
		["Move to Light 9"] = "Alpha0",
	},
	light_settings = {
		_Color = Vector3f.new(1.0, 1.0, 1.0),
		_Intensity = (isRE2 and 800.0*candela_multi) or (isRE3 and 150.0*candela_multi) or (isRE7 and 50.0*candela_multi) or (isMHR and 5.0*candela_multi) or 400.0*candela_multi, --or (isDMC and 15000.0) 
		_Radius = 6.0,
		_Cone = 110.0,
		_Spread = 12.0,
		_Falloff = 1.75,
		_ShadowBias = 0.0000009,
	},
	cached_luts = {},
	img_quality = 1.0,
	use_quick_zoom = false,
	zoom_fov = 35.0,
	zoom_speed = 0.2,
	do_lookat = false,
	change_scale_together = true,
	tps_unlocked = true,
	rot_speed = (isRE7 and 0.6) or 0.2,
	dir_speed = 6,
	do_invert_pad = false,
	control_type = 1,
}

_G.freecam_on = false
local movelights_on = false
local movechars_on = false
local movestage_on = false
local movestage_only_lights = false
local frameskip = false
local cam_frozen = false
local use_orthographic = false
local changed, stage_change, freecam_changed
local cam_joint
local cam_gameobj, cam_xform
local kb, mouse, pad
local via_hid_keyboard = sdk.get_native_singleton("via.hid.Keyboard")
local via_hid_keyboard_typedef = sdk.find_type_definition("via.hid.Keyboard")
local via_hid_mouse = sdk.get_native_singleton("via.hid.Mouse")
local via_hid_mouse_typedef = sdk.find_type_definition("via.hid.Mouse")
local scene_mgr_typedef = sdk.find_type_definition("via.SceneManager")

local cam = sdk.get_primary_camera()
local last_camera_matrix-- = cam and cam:get_WorldMatrix()
local timescale_mult = 1.0
local last_pos_and_rot
local last_euler_rot
local last_mouse_pos = Vector2f.new(0,0) 
local frozenFOV
local battlecam
local players = {}
local frozen_funcs = {}
local twist_radians = 0
local tics = 0
local lights_enabled = true
local dummy, dummy_pos, dummy_rot
local sceneview
local main


local cam_light
local attached_children = {}
local cam_lights = {}
local cam_lights_map = {}
local all_lights = {}

local orig_render_output_id
local can_rt = not not sdk.find_type_definition("via.render.ExperimentalRayTrace")
local freecam_light_enabled = false
local roll_mode = false
local is_drawing_freecam_ui = false
local is_constant = false
local constant_fn
local graphics_settings_mgr
local frozen_scene = false
local dof_on = false
local ssao_on = false
local temporal_ssao = false
local rt_enabled = false
local rt_reflections_enabled = false
local vignette_on = false
local contrast
local softbloom_on = false
local dof_options = {}
local do_force_shadow_bias
local cc_on = false
local cc_factors = {{},{},{},{},{},{},{},{}}
local zoom = {}
local greenscreen_on = false
local gs_color
local ev_value
local defaults = {}
local disable_all_efx = false
local show_cam_lights = false
local disable_all_lights = false
local cam_attached = false
local pos_before_teleport
local filter_on = true
local do_third_person = false
local temp_fns = {}
local cached_lightprobes = {}
local tps_parent_joint_name
local mounting_fn
local mount_obj_name
local mount_obj_jname

local lightconfigs_glob
local lightconfig_names
local imgui_data = {
	lightconfig_text = "",
}

local filter_options = { 
	mdf_names={},
	mdf_exts = {
		re2 = ((sdk.get_tdb_version()==66) and ".10") or ".21",
		re3 = ((sdk.get_tdb_version()==68) and ".13") or ".21",
		re4 = ".32",
		re8 = ".19",
		re7 = ((sdk.get_tdb_version()==49) and ".6") or ".21",
		dmc5 =".10",
		mhrise = ".23",
		sf6 = ".31",
	},
}

--Temporary table for holding data for 'SF6 Tools' menu
local sf6_data = {
	player_meshes = {},
	distortion_idx = 1,
	overlap_idx = 1,
	distortion_on = false,
	overlap_on = true,
	no_battle_damage = false,
	no_sweat = false,
	show_P1 = true,
	show_P2 = true,
	P1_scale = 1.0,
	P2_scale = 1.0,
	P1_pos = Vector3f.new(0,0,0),
	P2_pos = Vector3f.new(0,0,0),
	P1_rot = Vector3f.new(0,1,0),
	P2_rot = Vector3f.new(0,1,0),
	battle_damage_percent = 0.0,
	sweat_percent = 0.0,
	fps_idx = 1,
	slow_motion_speed = 1.0,
	speed_sfix = isSF6 and ValueType.new(sdk.find_type_definition("via.sfix")):call("From(System.Single)", 1.0),
	anim_names = {},
	tps_parent_joint_name_idx = 1,
}

local hk = require("Hotkeys/Hotkeys")

local function recurse_def_settings(tbl, defaults_tbl)
	for key, value in pairs(defaults_tbl) do
		if type(tbl[key]) ~= type(value) then 
			if type(value) == "table" then
				tbl[key] = recurse_def_settings({}, value)
			else
				tbl[key] = value
			end
		elseif type(value) == "table" then
			tbl[key] = recurse_def_settings(tbl[key], value)
		end
	end
	return tbl
end
freecam_settings = recurse_def_settings(json.load_file("FreeCam.json") or { hotkeys={}, light_settings={} }, default_settings)

hk.setup_hotkeys(freecam_settings.hotkeys, default_settings.hotkeys)

for k, v in pairs(default_settings.light_settings) do 
	freecam_settings.light_settings = freecam_settings.light_settings or {}
	if freecam_settings.light_settings[k] == nil then freecam_settings.light_settings[k] = v end 
	if k=="_Color" then freecam_settings.light_settings[k] = Vector3f.new(freecam_settings.light_settings._Color[1] or 1, freecam_settings.light_settings._Color[2] or 1, freecam_settings.light_settings._Color[3] or 1) end
end
for k, v in pairs(default_settings) do 
	if freecam_settings[k] == nil then freecam_settings[k]=v end
end

local dump_settings = function()
	if freecam_settings.light_settings._Color.x then
		freecam_settings.light_settings._Color = {freecam_settings.light_settings._Color.x, freecam_settings.light_settings._Color.y, freecam_settings.light_settings._Color.z}
	end
	json.dump_file("FreeCam.json", freecam_settings)
end

--Get dictionary size
local function get_table_size(tbl) 
	local i = 0
	for k, v in pairs(tbl) do  i = i + 1 end
	return i
end

local function tooltip(text, do_force)
    if do_force or imgui.is_item_hovered() then
        imgui.set_tooltip(text)
    end
end

local function xform_on_dirty(xform)
	local old = xform:get_SameJointsConstraint()
	xform:set_SameJointsConstraint(not old)
	xform:set_SameJointsConstraint(old)
end

local function getC(gameobj, component_name, is_comp)
	gameobj = is_comp and gameobj:get_GameObject() or gameobj
	return sdk.typeof(component_name) and gameobj:call("getComponent(System.Type)", sdk.typeof(component_name))
end

local function managed_object_control_panel(object)
	if EMV then
		imgui.managed_object_control_panel(object)
	else
		object_explorer:handle_address(object)
	end
end

imgui.drag_float3_euler = function(label, input, inc, min, max)
	local changed, output = imgui.drag_float3(label, input, inc, min, max)
	if math.abs(output.x) > 1.571 then
		--output.x = -output.x
	end
	return changed, output
end

local function write_valuetype(parent_obj, offset_or_field_name, value)
    local offset = tonumber(offset_or_field_name) or parent_obj:get_type_definition():get_field(offset_or_field_name):get_offset_from_base()
    for i=0, value.type:get_valuetype_size()-1 do
        parent_obj:write_byte(offset+i, value:read_byte(i))
    end
end

--Gets a SystemArray, List or WrappedArrayContainer
local function lua_get_system_array(sys_array, allow_empty, convert_to_dict)
	if not sys_array then return (allow_empty and {}) end
	local system_array = sys_array.get_elements and sys_array:get_elements()
	if not system_array then
		system_array = sys_array.get_field and (sys_array:get_field("mItems") or sys_array:get_field("_items"))
		system_array = system_array and system_array.get_elements and system_array:get_elements()
	end
	return (allow_empty and system_array) or (system_array and system_array[1] and system_array)
end

--Create a resource
local function create_resource(resource_type, resource_path)
	local new_resource = resource_path and sdk.create_resource(resource_type, resource_path)
	if not new_resource then return end
	new_resource = new_resource:add_ref()
	local holder = sdk.create_instance(resource_type .. "Holder", true)
	if holder then
		holder = holder:add_ref()
		holder:call(".ctor()")
		holder:write_qword(0x10, new_resource:get_address())
		return holder
	end
end

local function find_player_meshes()
	sf6_data.player_meshes = {}
	for i, player_component in ipairs(lua_get_system_array(scene:call("findComponents(System.Type)", sdk.typeof("via.render.Mesh")), true)) do  
		local gameobj = player_component:call("get_GameObject")
		if gameobj:call("get_Name"):find("^esf0%d%dv") then
			sf6_data.player_meshes[player_component] = player_component
		end
	end
end

local function change_player_mat_params(param_name, value, param_type)
	param_type = param_type or ""
	param_type = "MaterialFloat"..param_type
	if not next(sf6_data.player_meshes) then find_player_meshes() end
	for i, mesh in pairs(sf6_data.player_meshes) do
		for m = 1, mesh:call("get_MaterialNum") do
			for v = 1, mesh:call("getMaterialVariableNum", m-1) do 
				if mesh:call("getMaterialVariableName", m-1, v-1) == param_name then
					mesh:call("set" .. param_type, m-1, v-1, value)
					break
				end
			end
		end
	end
end

local function find_index(tbl, value, key)
	for i, item in ipairs(tbl) do
		if item == value then
			return i
		end
	end
end

local function get_mouse_pos()
	if not mouse then return false end
	local try, mouse_pos = pcall(mouse.call, mouse, "get_Position")
	return try and Vector2f.new(mouse_pos:get_field("x"), mouse_pos:get_field("y"))
end

local function reset_dummy_pos(position, do_reset_xform)
	local was_ons = {}
	for child, tbl in pairs(attached_children) do --EMV.lua_get_enumerator(dummy.xform:get_Children())
		if not pcall(function()
			was_ons[child] = child:call("get_GameObject"):call("get_DrawSelf")
			child:call("set_Parent", nil) 
		end) then 
			attached_children[child] = nil
		end
	end
	position = (position ~= false) and (position or (isSF6 and players[2]:call("get_GameObject"):call("get_Transform"):call("get_Position")) or cam_joint:call("get_Position"))
	
	if position then
		dummy.xform:call("set_Position", position) -- + (players[2]:call("get_GameObject"):call("get_Transform"):call("get_Position") - position))
	end
	if do_reset_xform then
		if do_reset_xform ~= 1 then dummy.xform:call("set_Rotation", Quaternion.new(1,0,0,0)) end
		dummy.xform:call("set_LocalScale", Vector3f.new(1,1,1))
	end
	stage_rot_func = function()
		stage_rot_func = nil
		for child, tbl in pairs(attached_children) do 
			child:call("set_Parent", dummy.xform) 
			child:call("get_GameObject"):call("set_DrawSelf", was_ons[child])
		end
	end
end

local function light_lookat_fn() 
	if freecam_settings.do_lookat then
		for xform, tbl in pairs(attached_children) do 
			xform:lookAt(dummy.xform:get_Position(), xform:get_WorldMatrix()[1]:to_vec3()) 
		end
	end
end

local function move_light_by_dummy_independently(light, func)
	local old = {}
	for i, other_light in ipairs(cam_lights) do 
		old[i] = other_light.orbiting
		if light ~= other_light then 
			other_light.orbiting = false
			other_light.xform:set_Parent(nil) 
		end
	end
	func()
	for i, light in ipairs(cam_lights) do 
		light.orbiting = old[i] 
		if light.orbiting then light.xform:set_Parent(dummy.xform) end
	end
end

local function setup_stage_attach(do_move, do_forget_default, given_arr, do_skip_cam_lights)
	
	do_move = do_move or movestage_only_lights or movestage_on or do_cam_orbit
	
	if do_move and not next(attached_children) then --enable
		
		local gameobj = scene:call("findGameObject(System.String)", "FreeCamGizmo") 
		local spawn_pos = not gameobj and last_camera_matrix[3]:to_vec3()
		if isSF6 and not gameobj and players[2] then
			spawn_pos = players[2]:call("get_GameObject"):call("get_Transform"):call("get_Position") --on P1 position
		end
		gameobj = gameobj or sdk.find_type_definition("via.GameObject"):get_method("create(System.String)"):call(nil, "FreeCamGizmo"):add_ref()
		dummy = {gameobj=gameobj, xform=gameobj:get_Transform()}
		
		if spawn_pos then dummy.xform:set_Position(spawn_pos) end
		local to_search = given_arr or (do_cam_orbit and {}) or (movestage_only_lights and EMV.find("via.render.Light")) or EMV.lua_get_enumerator(scene:call("findFolder", "ess"):call("get_Children"))
		
		if do_cam_orbit and not given_arr then -- and cam_lights[1] then
			for i, light in ipairs(cam_lights) do 
				if light.enabled and not light.attached and not light.orbiting then
					table.insert(to_search, light.xform)
				end
			end
		end
		
		for name, child in pairs(to_search) do
			if not do_skip_cam_lights or not child:call("get_GameObject"):get_Name():find("FreeCamLight") then
				local was_on = child:call("get_GameObject"):call("get_Draw")
				attached_children[child] = {{child:call("get_Position"), child:call("get_Rotation"), child:call("get_LocalScale")}, was_on, child:call("get_Parent")}
				child:call("set_Parent", dummy.xform)
				child:call("get_GameObject"):call("set_DrawSelf", was_on)
			end
		end
		if do_cam_orbit then light_lookat_fn() end
	else --disable
		for child, tbl in pairs(attached_children) do
			if not do_forget_default and tbl[1] and  EMV.is_valid_obj(child) then
				child:call("set_Position", tbl[1][1])
				child:call("set_Rotation", tbl[1][2])
				child:call("set_LocalScale", tbl[1][3])
				child:call("get_GameObject"):call("set_DrawSelf", tbl[2])
			end
			child:call("set_Parent", tbl[3] or nil)
		end 
		--if dummy and not EMV.lua_get_enumerator(dummy.xform:get_Children())[1] then
		--	deferred_calls[dummy.gameobj] = { func="destroy", args={dummy.gameobj} }
		--	dummy = nil
		--end
		attached_children = {}	
		movestage_on, movestage_only_lights = false, false
	end
end

local function move_to_light(light)
	local new_pos, new_rot = light.xform:call("get_Position"), light.xform:call("get_EulerAngle")
	if battlecam then 
		battlecam:call("set_Enabled", false)
	end
	cam_frozen = true
	freecam_on = true
	pos_before_teleport = not (light.cam_attached or cam_light.attached) and {cam_joint:call("get_Position"), cam_joint:call("get_EulerAngle")}
	for i, other_light in ipairs(cam_lights) do 
		other_light.cam_attached = false 
	end
	light.cam_attached = true
	cam_light = light
	temp_fn = function()
		cam_joint:call("set_Position", new_pos)
		cam_joint:call("set_EulerAngle", new_rot)
		last_pos_and_rot = {new_pos, new_rot}
		if cam_attached then cam_attached = light end
	end
	if sf6_data.distortion_idx == 1 then 
		change_player_mat_params("FixProjection_Switch", 0.0)
	end
end

local function apply_shadow_bias(amount)
	for i, obj in pairs(lua_get_system_array(scene:call("findComponents(System.Type)", sdk.typeof("via.render.Light")))) do 
		if obj.set_ShadowBias then
			obj:set_ShadowBias(amount)
		end
	end
end

local function create_or_toggle_cam_light(gameobj, dont_set_cam_light)
	local last_cam_light = cam_light
	cam_light = gameobj and {gameobj=gameobj} or (not dont_set_cam_light and cam_light) or {gameobj=scene:call("findGameObject(System.String)", "FreeCamLight"..get_table_size(cam_lights_map))}
	
	if not cam_light.gameobj then
		cam_light.gameobj = sdk.find_type_definition("via.GameObject"):get_method("create(System.String)"):call(nil, "FreeCamLight"..get_table_size(cam_lights_map)):add_ref()
		cam_light.light = cam_light.gameobj:call("createComponent(System.Type)", sdk.typeof("via.render.ProjectionSpotLight"))
		cam_light.light:call(".ctor()")
		cam_light.light:call("set_ShadowEnable", true)
		cam_light.light:call("set_Intensity", freecam_settings.light_settings._Intensity)
		cam_light.light:call("set_Radius", freecam_settings.light_settings._Radius)
		cam_light.light:call("set_ShadowBias", freecam_settings.light_settings._ShadowBias)
		cam_light.light:call("set_Cone", freecam_settings.light_settings._Cone)
		cam_light.light:call("set_Spread", freecam_settings.light_settings._Spread)
		cam_light.light:set_Texture(create_resource("via.render.TextureResource", "systems/rendering/nullwhite.tex"))
		--cam_light.gameobj:get_Transform():set_Parent(cam_gameobj:get_Transform())
		if isMHR then cam_light.light:call("set_BackGroundShadowEnable", true) end
		if isDMC then cam_light.light:call("set_Unit", 1) end
		cam_light.xform = cam_light.gameobj:call("get_Transform")
		local this = cam_light
		local pos, rot = cam_joint:get_Position(), cam_joint:get_EulerAngle()
		cam_light.xform:set_SameJointsConstraint(true)
		should_expand_cam_lights_menu = (#cam_lights == 0) or nil
		
		mot_fn = function()
			this.xform:set_Position(pos)
			this.xform:set_EulerAngle(rot)
			temp_fn = function()
				cam_light.xform:set_SameJointsConstraint(false) --this shit is so annoying
			end
		end
		pcall(function()
			cam_light.light:call("set_Color", freecam_settings.light_settings._Color)
		end)
	else
		cam_light.light =  cam_light.gameobj:call("getComponent(System.Type)", sdk.typeof("via.render.ProjectionSpotLight"))
		cam_light.xform = cam_light.gameobj:call("get_Transform")		
	end
	cam_light.light:call("set_Unit", 0)
	
	if not cam_lights_map[cam_light.gameobj] then
		cam_lights_map[cam_light.gameobj] = cam_light
		table.insert(cam_lights, cam_light)
		table.sort(cam_lights, function(a, b) return a.gameobj:get_Name() > b.gameobj:get_Name() end)
	end
	cam_light.gameobj:call("set_DrawSelf", true)
	
	--cam_light.proj_light =  cam_light.gameobj:call("getComponent(System.Type)", sdk.typeof("via.render.ProjectionSpotLight")) or cam_light.gameobj:call("createComponent(System.Type)", sdk.typeof("via.render.ProjectionSpotLight"))
	--cam_light.proj_light:set_Texture(create_resource("via.render.TextureResource", "systems/rendering/nullwhite.tex"))
	
	local to_return = cam_light
	if last_cam_light and dont_set_cam_light then
		cam_light = last_cam_light
	end
	return to_return
end

for i=0, 9 do
	local gameobj = scene:call("findGameObject(System.String)", "FreeCamLight"..i)
	if gameobj then 
		create_or_toggle_cam_light(gameobj)
		cam_lights_map[gameobj] = cam_light
		table.insert(cam_lights, cam_light)
		gameobj:call("set_Name", "FreeCamLight"..get_table_size(cam_lights_map)-1) 
	end
	table.sort(cam_lights, function(a, b) return a.gameobj:get_Name() < b.gameobj:get_Name() end)
	local main = scene:call("findGameObject(System.String)", "FreeCamLight0")
	if main and main:call("get_DrawSelf") then
		create_or_toggle_cam_light(main)
	end
end

re.on_pre_gui_draw_element(function(element, context)
    if hud_disabled then
		local game_object = (element:read_qword(0x10) ~= 0) and element:call("get_GameObject")
		if game_object == nil then return true end
        return false
    end
    return true
end)

sdk.call_native_func(sdk.get_native_singleton("via.render.Renderer"), sdk.find_type_definition("via.render.Renderer"), "set_ImageQualityRate", freecam_settings.img_quality)

local function change_quality()

	local current_sz = sceneview and sceneview:call("get_Size")
	--freecam_settings.img_quality = freecam_settings.img_quality or sdk.call_native_func(sdk.get_native_singleton("via.render.Renderer"), sdk.find_type_definition("via.render.Renderer"), "get_ImageQualityRate") 
	
	if hi_quality and current_sz and (hk.check_hotkey("CModifier", true) or hk.check_hotkey("CModifier2", true)) then
		defaults.res = current_sz
		defaults.display_type = sceneview:call("get_DisplayType")
		sdk.call_native_func(sdk.get_native_singleton("via.render.Renderer"), sdk.find_type_definition("via.render.Renderer"), "set_ImageQualityRate", 1.0)
		local sz = ValueType.new(sdk.find_type_definition("via.Size"))
		sz.w, sz.h = defaults.res.w*2, defaults.res.h*2
		sceneview:call("set_CustomDisplaySize", sz)
		sceneview:call("set_DisplayType", 17) --CustomDisplaySize
	else
		if current_sz and defaults.res and current_sz.w ~= defaults.res.w and current_sz.h ~= defaults.res.h then 
			sceneview:call("set_CustomDisplaySize", defaults.res)
			sceneview:call("set_DisplayType", defaults.display_type)
		end
		sdk.call_native_func(sdk.get_native_singleton("via.render.Renderer"), sdk.find_type_definition("via.render.Renderer"), "set_ImageQualityRate", (hi_quality and freecam_settings.img_quality * 2.0) or freecam_settings.img_quality)
	end
	
	local render_config = sdk.call_native_func(sdk.get_native_singleton("via.render.Renderer"), sdk.find_type_definition("via.render.Renderer"), "get_RenderConfig")
	defaults.upscale_type = defaults.upscale_type or render_config:call("get_UpscaleType")
	render_config:call("set_UpscaleType", (hi_quality and 0) or defaults.upscale_type)
end

--attach/detach a cam light object from the camera
local function attach_detach(light_obj)
	light_obj.attached = not light_obj.attached
end

local function create_new_cam_light()
	local last, freecam_on = freecam_on, true
	if not cam_light or not cam_light.xform then
		create_or_toggle_cam_light()
		return cam_light
	end
	freecam_light_enabled = true
	local out = create_or_toggle_cam_light(nil, true)
	cam_light.light:call("set_Enabled", freecam_light_enabled)
	freecam_on = last
	
	return out
end

local makeQuatByOrder = sdk.find_type_definition("via.motion.motmath"):get_method("makeQuatByOrder(via.vec3, via.motion.EulerOrder)")

local function ConvertAxisAngleToQuat(vecX, vecY, vecZ, angle)
    local ha = angle * 0.5
    local sha = math.sin(ha)
    local qx = vecX * sha
    local qy = vecY * sha
    local qz = vecZ * sha
    local qw = math.cos(ha)
	return Quaternion.new(qw, qx, qy, qz):normalized()
end

local function calculateLookQuaternion(pitch, yaw, roll)
	if makeQuatByOrder then
		return makeQuatByOrder(nil, Vector3f.new(-pitch, -yaw, -roll), 1):normalized()
	end
	local xQ = ConvertAxisAngleToQuat(1.0, 0.0, 0.0, -pitch)
	local yQ = ConvertAxisAngleToQuat(0.0, 1.0, 0.0, -yaw)
	local zQ = ConvertAxisAngleToQuat(0.0, 0.0, 1.0, 0.0)
	local qToReturn = xQ * zQ * yQ
	return qToReturn:normalized()
end

local sf6_color_editor_callbacks = require("callbacks")

local sf6_color_editor_context

local function create_sf6_color_editor_context()
	return {
		is_sf6 = isSF6,
		players = players,
		held_transforms = held_transforms,
		runtime = {
			EMV = EMV,
			imgui = imgui,
			json = json,
			re = re,
			sdk = sdk,
		},
		activate_ui = function()
			is_drawing_freecam_ui = true
			graphics_settings_mgr = isSF6 and sdk.get_managed_singleton("app.GraphicsSettingsManager")
		end,
	}
end

function display_sf6_color_editor()
	sf6_color_editor_context = sf6_color_editor_context or create_sf6_color_editor_context()
	local context = sf6_color_editor_context

	sf6_color_editor_callbacks.draw_sf6_color_editor(context, function()
		sf6_color_editor_callbacks.draw_player_one(context, function()
			sf6_color_editor_callbacks.draw_character_name(context)
			sf6_color_editor_callbacks.draw_materials(context)
		end)
		sf6_color_editor_callbacks.draw_player_two(context, function()
			sf6_color_editor_callbacks.draw_character_name(context)
			sf6_color_editor_callbacks.draw_materials(context)
		end)
	end)
end

re.on_draw_ui(function()
	display_sf6_color_editor()
end)

re.on_application_entry("UpdateHID", function()
    
	kb, mouse, pad = hk.kb, hk.mouse, hk.pad
	if isSF6 then
		local dict = sdk.find_type_definition("gBattle"):get_field("PBManager"):get_data().Players
		players[1], players[2] = dict[1], dict[0]
		if isSF6 and not (players[1] or players[2]) and next(attached_children) then
			re.msg("Cleared!")
			setup_stage_attach()
		end
	end
end)

re.on_frame(function()
	
	tics = tics + 1
	main = isSF6 and scene:call("findGameObject(System.String)", "main")
	local scene_spd = sdk.call_native_func(sdk.get_native_singleton("via.Application"), sdk.find_type_definition("via.Application"), "get_GlobalSpeed")
	frozen_scene = (scene_spd < 0.001)
	is_drawing_freecam_ui = false
	local mods_down = hk.check_hotkey("CModifier", true) or hk.check_hotkey("CModifier2", true)
	local mod3_down = hk.check_hotkey("CModifier3", true)
	local is_orbiting = false
	dummy = dummy and dummy.xform:get_Valid() and dummy
	cam_attached = cam_frozen and cam_attached
	
	if not lightconfigs_glob then
		lightconfigs_glob, lightconfig_names = fs.glob("LuaFreeCam\\\\LightConfigs\\\\.*json"), {}
		for i, path in ipairs(lightconfigs_glob) do lightconfig_names[i] = path:match("LuaFreeCam\\LightConfigs\\(.+).json")  end
	end
	
	--Toggle on/off:
	if hk.check_hotkey("Activate FreeCam") then 
		freecam_changed = true
		freecam_on = not freecam_on
		cam_frozen = false
		last_mouse_pos = get_mouse_pos()
		if not freecam_on then --toggle off
			if cam_joint then 
				pcall(function()
					local euler = cam_joint:call("get_EulerAngle"); cam_joint.z = 0 
					cam_joint:call("set_EulerAngle", euler) 
				end)
			end
			--[[if cam_light then 
				cam_light.light:call("set_Enabled", false)
				freecam_light_enabled = false
			end]]
			if cam_joint then --(isRE7 or isRE8 or isDMC) and
				cam_joint:call("set_LocalPosition", Vector3f.new(0,0,0))
				cam_joint:call("set_EulerAngle", Vector3f.new(0,0,0))
			end
		end
		
		if isSF6 and sf6_data.distortion_idx == 1 then
			distortion_on = not freecam_on
			change_player_mat_params("FixProjection_Switch", (distortion_on and 1.0) or 0.0)
		end
		
		if isSF6 and sf6_data.distortion_idx == 1 then
			sf6_data.overlap_on = not freecam_on
		end
	end
	
	if freecam_changed then
		if isRE7 then
			for i, component in ipairs(lua_get_system_array(scene:call("findComponents(System.Type)", sdk.typeof("via.render.Mesh")), true)) do
				component:call("set_IgnoreDepth", false) --dumb
			end
		end
	end
	
	if not mod3_down and #cam_lights < 10 and hk.check_hotkey("Create New Light") then
		create_new_cam_light()
	end
	
	if cam_light and hk.check_hotkey("Attach/Detach Selected Light") then
		attach_detach(cam_light)
	end
	
	for i, light in ipairs(cam_lights) do 
		if not cam_light or light.xform == cam_light.xform then 
			cam_light = light 
		end
		
		light.orbiting = (light.xform:get_Parent() == (dummy and dummy.xform))
		light.cam_attached = cam_frozen and light.cam_attached
		pos_before_teleport = cam_frozen and pos_before_teleport
		cam_attached = cam_attached or (light.cam_attached and light)
		
		if hk.check_hotkey("Move to Light "..(i-1)) then
			if mods_down then
				light.light:set_Enabled(not light.enabled)
				light.enabled = light.light:get_Enabled()
			elseif not light.parent then 
				move_to_light(light)
			end
		end
	end
	
	if cam_light and mods_down then
		if  hk.check_hotkey("Zoom Out", true)  then
			cam_light.light:set_Intensity(cam_light.light:get_Intensity() + 5.0)
		elseif  hk.check_hotkey("Zoom In", true)  then
			local new_intensity = cam_light.light:get_Intensity() - 5.0
			cam_light.light:set_Intensity((new_intensity > 0 and new_intensity) or 0)
		end
	end
	
	--Toggle frozen cam:
	if hk.check_hotkey("Freeze Camera") then 
		cam_frozen = not cam_frozen
		last_mouse_pos = get_mouse_pos()
	end
	
	if hk.check_hotkey("Hide UI") then
		hud_disabled = not hud_disabled
	end
	
	if hk.check_hotkey("2x Quality") then
		hi_quality = not hi_quality
		change_quality()
	end
	
	cam_light = (cam_light and cam_light.light and cam_light.light:call("get_Valid") and cam_light) or nil
	
	if hk.check_hotkey("Toggle FreeCam Light") then
		local had_light = cam_light
		freecam_light_enabled = not freecam_light_enabled
		create_or_toggle_cam_light()
		cam_light.light:call("set_Enabled", freecam_light_enabled)
		if not had_light then cam_light.attached = true end
	end
	
	if isRE8 and hk.check_hotkey("Unequip Weapons (RE8)") then
		local player_updater_list = scene:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase"))
		local weapon_change = player_updater_list and player_updater_list._items[0] and player_updater_list[0]:call("get_playerWeaponChange")
		if weapon_change then
			weapon_change:call("removeWeaponConstraint")
		end
	end
	
	--Freeze time and overlap SF6:
	if isSF6 and main then 
		local gspeed = sdk.call_native_func(sdk.get_native_singleton("via.Application"), sdk.find_type_definition("via.Application"), "get_GlobalSpeed")
		battleflow = scene:call("findComponents(System.Type)", sdk.typeof("app.battle.bBattleFlow"))[0]
		if battleflow or frameskip then 
			local bf_enabled = battleflow:call("get_Enabled")
			if frameskip then
				battleflow:call("set_Enabled", false)
				if frameskip == 1 then
					sdk.call_native_func(sdk.get_native_singleton("via.Application"), sdk.find_type_definition("via.Application"), "set_GlobalSpeed", 0.00001)
				end
				frameskip = false
			end
			if not bf_enabled and hk.check_hotkey("Skip Frame") then
				battleflow:call("set_Enabled", true)
				frameskip = (gspeed <= 0.001) and 1 or true
				if frameskip == 1 then
					sdk.call_native_func(sdk.get_native_singleton("via.Application"), sdk.find_type_definition("via.Application"), "set_GlobalSpeed", 1.0)
				end
			end
			if hk.check_hotkey("Freeze Time") and (hk.check_hotkey("CModifier", true) or (hk.check_hotkey("CModifier2", true))) then
				sdk.call_native_func(sdk.get_native_singleton("via.Application"), sdk.find_type_definition("via.Application"), "set_GlobalSpeed", (scene_spd==1.0 and 0.00001) or 1.0)
			elseif hk.check_hotkey("Freeze Time") or (bf_enabled and hk.check_hotkey("Skip Frame")) then
				battleflow:call("set_Enabled", not bf_enabled)
			end
		end
		
		if players[2] and not sf6_data.overlap_on then
			for i=1, 2 do
				for m, mesh in pairs(players[i].mpMeshes._items) do
					if mesh then
						mesh:set_UseStencilValuePriority(false)
					end
				end
			end
		end
	end
	
	if (not isSF6 and frameskip) or hk.check_hotkey("Freeze Time & Scene") then
		sdk.call_native_func(sdk.get_native_singleton("via.Application"), sdk.find_type_definition("via.Application"), "set_GlobalSpeed", (scene_spd==1.0 and 0.00001) or 1.0)
		if battleflow then battleflow:call("set_Enabled", (scene_spd~=1.0)) end
		--re.msg(scene_spd .. " " .. sdk.call_native_func(sdk.get_native_singleton("via.Application"), sdk.find_type_definition("via.Application"), "get_GlobalSpeed"))
		frameskip = false
	end
	
	if not isSF6 and hk.check_hotkey("Skip Frame") then
		frameskip = true
		sdk.call_native_func(sdk.get_native_singleton("via.Application"), sdk.find_type_definition("via.Application"), "set_GlobalSpeed", 1.0)
	end
	
	if cam then 
		if hk.check_hotkey("Reset Zoom", true) then
			frozenFOV, use_frozen_fov = nil
			if battlecam then battlecam:call("set_Enabled", true) end
		elseif not mods_down and not (cam_attached and mod3_down) and hk.check_hotkey("Zoom Out", true) then 
			frozenFOV = cam:call("get_FOV") + 0.5
		elseif not mods_down and not (cam_attached and mod3_down)and hk.check_hotkey("Zoom In", true) then 
			frozenFOV = cam:call("get_FOV") - 0.5
		end
		
		if isSF6 then
			--Show a gizmo for moving the character's personal light:
			if movelights_on then 
				local char_lights = scene:call("findComponents(System.Type)", sdk.typeof("app.CharacterLightController"))
				for i, light in ipairs((char_lights and char_lights.get_elements and char_lights:get_elements()) or {}) do
					local xform = light:call("get_GameObject"):call("get_Transform")
					local mat = xform:call("get_WorldMatrix"); mat[3].w = 1.0
					changed, mat = draw.gizmo(xform:get_address(), mat)
					local rot = mat:to_quat()
					if changed and rot.x == rot.x then 
						xform:call("set_Position", mat[3]:to_vec3())
						xform:call("set_Rotation", rot)
					end
				end
			end
			
			--Show a gizmo for moving the character:
			if movechars_on and reframework:is_drawing_ui() then 
				for i, character in ipairs(players) do
					local xform = character:call("get_GameObject"):call("get_Transform")
					local joint = xform:call("getJointByName", "Root")
					local mat = joint:call("get_WorldMatrix"); mat[3].w = 1.0
					changed, mat = draw.gizmo(joint:get_address(), mat)
					if changed then 
						frozen_funcs[i] = function()
							if not pcall(function()
								joint:call("set_Position", mat[3])
								joint:call("set_Rotation", mat:to_quat())
							end) then
								frozen_funcs = {}
							end
						end
					end
				end
			end
		end
		
		if not is_drawing_freecam_ui and constant_fn then 
			constant_fn()
		end
	end
	
	if next(cam_lights_map) then
		local new_cam_lights, new_cam_lights_map = {}, {}
		for i, light in pairs(cam_lights_map) do
			if light.xform and light.xform:call("get_Valid") then
				new_cam_lights_map[light.gameobj] = light
				table.insert(new_cam_lights, light)
			end
		end
		cam_lights_map = new_cam_lights_map
		cam_lights = new_cam_lights
		table.sort(cam_lights, function(a, b) return a.gameobj:get_Name() < b.gameobj:get_Name() end)
	end
	
	if show_cam_lights then
		for gameobj, light_obj in pairs(cam_lights_map) do
			draw.world_text(gameobj:get_Name(), light_obj.xform:get_Position(), 0xFF00FF00)
		end
	end
	
	if EMV and dummy then
		for child, tbl in pairs(attached_children) do
			if not EMV.is_valid_obj(child) or (not mods_down and child:get_Parent() ~= dummy.xform) then
				attached_children[child] = nil
			end
		end
	end
	
	if reframework:is_drawing_ui() and do_cam_orbit and dummy and dummy.xform then 
		changed, mat = draw.gizmo(21415634, dummy.xform:get_WorldMatrix()) 
		local rot = mat:to_quat()--:normalized()
		local pos = mat[3]:to_vec3()
		if changed and rot.x == rot.x and pos.x == pos.x then 
			mot_fn = function()
				if hk.check_hotkey("CModifier", true) or hk.check_hotkey("CModifier2", true) then 
					reset_dummy_pos(pos)
				else
					dummy.xform:call("set_Rotation", rot)
					dummy.xform:call("set_Position", pos)
				end
				light_lookat_fn()
			end
		end
	end
	
	if disable_all_lights then
		local lights = scene:call("findComponents(System.Type)", sdk.typeof("via.render.Light"))
		for i, light in pairs(lights.get_elements and lights or {}) do 
			if not light:get_GameObject():get_Name():find("FreeCamLight") then
				light:set_Enabled(false) 
			end
		end
	end
	
	--[[if isSF6 and main and players[2] then
		if false and do_bloody_battle then 
			local try, out = pcall(scene.call, scene, "findComponents(System.Type)", sdk.typeof("app.PlayerBehavior"))
			if try and out and out[1] then
				--change_player_mat_params("Sweat_Rate", 1.0)
				--local addition = 
				change_player_mat_params("Sweat_ColorRate", 5.0)
			end
		else
			--change_player_mat_params("Sweat_Rate", 0.0)
			--change_player_mat_params("Sweat_ColorRate", 0.2)
			if sf6_data.no_battle_damage or sf6_data.no_sweat then
				local try, out = pcall(scene.call, scene, "findComponents(System.Type)", sdk.typeof("app.PlayerBehavior"))
				if try and out and out[1] then
					if sf6_data.no_sweat and tics % 10 == 0 then change_player_mat_params("Sweat_Rate", 0.0) end
					if sf6_data.no_battle_damage and tics % 11 == 0 then change_player_mat_params("DamageLevel", 0.0) end
				end
			end
		end
	end]]
end)

re.on_application_entry("PrepareRendering", function()
	
	if temp_fn then 
		local fn; 
		fn, temp_fn = temp_fn, nil
		fn()
	end
	
	cam = sdk.get_primary_camera()
	cam_gameobj = cam and cam:call("get_GameObject")
	cam_xform = cam_gameobj and cam_gameobj:call("get_Transform")
	cam_joint = cam_xform and cam_xform:call("getJointByName", "Camera")
	if not cam or not cam_joint then return end 
	
	--cam_light = cam_lights[1]
	
	if freecam_settings.use_quick_zoom and hk.check_hotkey("Quick Zoom") then
		if zoom.zoom_timer then --interrupt transition
			if frozenFOV == cam:call("get_FOV") then --if the game is not forcing it, set manually
				cam:call("set_FOV", zoom.saved_fov)
			end
			use_frozen_fov, frozenFOV, zoom.deactivating_zoom, zoom.saved_fov, zoom.zoom_timer = false
		else
			zoom.zoom_timer = os.clock()
			zoom.deactivating_zoom = not not zoom.saved_fov
			zoom.saved_fov = (not zoom.saved_fov and cam:call("get_FOV")) or zoom.saved_fov
			frozenFOV = cam:call("get_FOV")
		end
	end
	
	if frozenFOV then 
		if freecam_settings.use_quick_zoom and zoom.zoom_timer and ((os.clock() - zoom.zoom_timer) <= freecam_settings.zoom_speed) then
			local fov = cam:call("get_FOV")
			local og_fov = ((frozenFOV ~= fov) and fov) or zoom.saved_fov --if the game is forcing a FOV, use that, else use FOV from when quick zoom was first toggled
			frozenFOV = freecam_settings.zoom_fov + (og_fov - freecam_settings.zoom_fov) * math.abs(((zoom.deactivating_zoom and 0) or 1) - ((os.clock() - zoom.zoom_timer)* (1/freecam_settings.zoom_speed)))
			cam:call("set_FOV", frozenFOV)
		else
			cam:call("set_FOV", frozenFOV)
			zoom.zoom_timer = nil
			if zoom.deactivating_zoom then 
				use_frozen_fov, frozenFOV, zoom.deactivating_zoom, zoom.saved_fov = false
			end
		end
	end
	
	if freecam_on and mouse then
		
		battlecam = isSF6 and scene:call("findComponents(System.Type)", sdk.typeof("app.CameraBehavior"))[0]
		if battlecam then 
			battlecam:call("set_Enabled", false)
		end
		
		local mouse_pos = get_mouse_pos()
		if mouse_pos then
			
			local pad_axis_r = hk.pad:get_RawAxisR()
			if not freecam_settings.do_invert_pad then pad_axis_r.y = pad_axis_r.y * -1 end
			mouse_delta = ((freecam_settings.control_type ==3 or (freecam_settings.control_type==1 and (pad_axis_r.x + pad_axis_r.y) ~= 0)) and pad_axis_r * 15.0) or mouse_pos - last_mouse_pos
			last_mouse_pos = mouse_pos
			
			local frozen = (cam_frozen or stage_changed)
			if frozen and last_pos_and_rot then
				cam_joint:call((last_pos_and_rot[2].w and "set_Rotation") or "set_EulerAngle", last_pos_and_rot[2])
				cam_joint:call("set_Position", last_pos_and_rot[1])
			end
			
			local delta = cam_xform:call("get_DeltaTime")
			timescale_mult = 1 / sdk.call_native_func(sdk.get_native_singleton("via.Application"), sdk.find_type_definition("via.Application"), "get_GlobalSpeed")
			
			--Rotation:
			if not last_camera_matrix then return end
			
			local shift_multiplier = ((hk.check_hotkey("CModifier", true) or (hk.check_hotkey("CModifier2", true))) and 3) or (hk.check_hotkey("CModifier3", true) and 0.33) or 1
			local x_rot_multiplier = (frozen and not cam_attached and 0) or (mouse_delta.y * (freecam_settings.rot_speed * 0.01 * shift_multiplier) * delta * timescale_mult)
			local y_rot_multiplier = (frozen and not cam_attached and 0) or (mouse_delta.x * (freecam_settings.rot_speed * 0.01 * shift_multiplier) * delta * timescale_mult)
			local z_rot_multiplier = 0;
			
			if not cam_attached then
				if hk.check_hotkey("Roll Left", true) then
					z_rot_multiplier = -0.025 * shift_multiplier * delta * timescale_mult
					roll_mode = (shift_multiplier ~= 3)
				elseif hk.check_hotkey("Roll Right", true) then
					z_rot_multiplier = 0.025 * shift_multiplier * delta * timescale_mult
					roll_mode = (shift_multiplier ~= 3)
				end
			elseif dummy then --for rotating gizmo when cam is attached
				local light = cam_attached
				last_pos_and_rot = {light.xform:get_Position(), light.xform:get_EulerAngle()} 
				
				local mod3_down = hk.check_hotkey("CModifier3", true)
				local add_vec = Vector3f.new(0,0,0)
				local scale = dummy.xform:get_LocalScale()
				
				local new_parent_joint = tps_parent_joint_name or "C_Move" --(mod3_down and "C_Move") or "C_Hip"
				if tps_dummy and tps_dummy.xform:get_ParentJoint() ~= new_parent_joint then
					local old_pos, old_rot = tps_mount.xform:get_Position(), tps_mount.xform:get_Rotation()
					tps_parent_joint_name = tps_parent_joint_name or "C_Move"
					tps_dummy.xform:set_ParentJoint(new_parent_joint)
					temp_fn = function()
						tps_dummy.xform:set_Position(tps_dummy.xform:get_Parent():getJointByName("C_Hip"):get_Position())
						tps_mount.xform:set_Position(old_pos)
						tps_mount.xform:set_Rotation(old_rot)
					end
				end
				
				if hk.check_hotkey("Cam Forward", true) then
					add_vec.z = add_vec.z - 0.05
				elseif hk.check_hotkey("Cam Backward", true) then
					add_vec.z = add_vec.z  + 0.05
				end 
				if hk.check_hotkey("Cam Left", true) then
					add_vec.x = add_vec.x - 0.05
				elseif hk.check_hotkey("Cam Right", true) then
					add_vec.x = add_vec.x + 0.05
				end 
				if hk.check_hotkey("Cam Down", true) then
					add_vec.y = add_vec.y - 0.05
				elseif hk.check_hotkey("Cam Up", true) then
					add_vec.y = add_vec.y + 0.05
				end 
				if mod3_down and hk.check_hotkey("Zoom Out", true) then
					scale = Vector3f.new(scale.x + 0.025, scale.x + 0.025, scale.x + 0.025)
				elseif mod3_down and hk.check_hotkey("Zoom In", true) then
					scale = Vector3f.new(scale.x - 0.025, scale.x - 0.025, scale.x - 0.025)
				end 
				if mod3_down and hk.check_hotkey("Create New Light") then
					mot_fn = function() reset_dummy_pos(false, true) end
				end
				
				local pos = dummy.xform:get_Position()
				local new_pos = pos + ((dummy.xform:get_Rotation() * add_vec) * (delta * timescale_mult))
				
				--local new_quat = (dummy.xform:get_Rotation() * calculateLookQuaternion(x_rot_multiplier, y_rot_multiplier, 0.0)):normalized()
				local new_rot = dummy.xform:get_EulerAngle()
				new_rot.x = new_rot.x - x_rot_multiplier * 1/shift_multiplier
				new_rot.y = new_rot.y - y_rot_multiplier * 1/shift_multiplier
				new_rot.z = 0
				
				--[[camera_rot = camera_rot or dummy.xform:get_Rotation()
				local camera_distance = (light.xform:get_Position() - dummy.xform:get_Position()):length()
				local new_rot = camera_rot:normalized()
				local actual_camera_delta = new_rot * Vector3f.new(0, 0, camera_distance)
				new_rot = actual_camera_delta:normalized():to_quat()
				
				if mouse_delta:length() > 0 then
					local actual_delta = Vector3f.new(-mouse_delta.y, -mouse_delta.x, 0)
					local last_euler = (new_rot * Vector3f.new(0,0,1)):to_quat():to_euler()
					last_euler.x = last_euler.x + (actual_delta.x * 0.001)
					last_euler.y = last_euler.y + (actual_delta.y * 0.001)
					camera_rot = Quaternion.new(last_euler):normalized()
				end]]
				
				mot_fn = mot_fn or do_third_person and function() 
					if not dummy then return end
					if scale ~= dummy.xform:get_LocalScale() then
						move_light_by_dummy_independently(light, function() dummy.xform:call("set_LocalScale", scale) end)
						reset_dummy_pos(false, 1)
					end 
					if mouse_delta:length() > 0.0 then --and ((freecam_settings.tps_unlocked and not mod3_down) or not (not freecam_settings.tps_unlocked and mod3_down))
						--dummy.xform:set_Rotation(new_rot)
						dummy.xform:set_EulerAngle(new_rot)
						local euler = light.xform:get_LocalEulerAngle()
						light.xform:set_LocalEulerAngle(Vector3f.new(euler.x, euler.y, 0))
						reset_dummy_pos(false, true)
					end 
					if add_vec ~= Vector3f.new(0,0,0) then
						dummy.xform:set_Position(new_pos)
					end
					light_lookat_fn()
				end
				--[[if hk.check_hotkey("Roll Left", true) then
					last_pos_and_rot[2].z = last_pos_and_rot[2].z - 0.05
					mot_fn = function() light.xform:call("set_EulerAngle", last_pos_and_rot[2]); fn() end
				elseif hk.check_hotkey("Roll Right", true) then
					last_pos_and_rot[2].z = last_pos_and_rot[2].z + 0.05
					mot_fn = function() light.xform:call("set_EulerAngle", last_pos_and_rot[2]); fn() end
				]]
			end
			
			--if last_camera_matrix[1].y < 0 then
			--	y_rot_multiplier = -y_rot_multiplier
			--end
			
			--Rotation:
			local last_rot_quat = last_camera_matrix:to_quat()
			
			local new_rot
			local new_quat = (last_rot_quat * calculateLookQuaternion(x_rot_multiplier, y_rot_multiplier, z_rot_multiplier)):normalized()
			
			
			if roll_mode then
				cam_joint:call("set_Rotation", new_quat)
			end
			
			if not frozen then
				
				if not roll_mode then
					new_rot = last_rot_quat:to_euler()
					new_rot.x = new_rot.x - x_rot_multiplier
					new_rot.y = new_rot.y - y_rot_multiplier
					new_rot.z = 0
					cam_joint:call("set_EulerAngle", new_rot)
				end
				
				--Position:
				last_rot_quat.x = last_rot_quat.x - x_rot_multiplier
				last_rot_quat.y = last_rot_quat.y - y_rot_multiplier
				last_rot_quat = last_rot_quat:normalized()
				local dir = Vector3f.new(0, 0, 0)
				
				if not cam_attached then
					if hk.check_hotkey("Cam Forward", true) then
						dir = dir + Vector3f.new(0.0, 0.0, -1.0)
					end
					if hk.check_hotkey("Cam Backward", true) then
						dir = dir + Vector3f.new(0.0, 0.0, 1.0)
					end
					if hk.check_hotkey("Cam Left", true) then
						dir = dir + Vector3f.new(-1.0, 0.0, 0.0)
					end
					if hk.check_hotkey("Cam Right", true) then
						dir = dir + Vector3f.new(1.0, 0.0, 0.0)
					end
					if hk.check_hotkey("Cam Up", true) then
						dir.y =  1.0
					elseif hk.check_hotkey("Cam Down", true) then
						dir.y = -1.0
					end
				end
				
				local new_pos = (mounting_fn and mounting_fn():to_vec4()) or last_camera_matrix[3] + ((last_rot_quat * dir) * ((freecam_settings.dir_speed * 0.01 * shift_multiplier) * delta * timescale_mult)):to_vec4()
				new_pos.w = 1
				
				if new_pos.x == new_pos.x then
					cam_joint:call("set_Position", new_pos:to_vec3())
				end
				
				last_pos_and_rot = {new_pos, new_rot or new_quat}
			end
		end
	else
		roll_mode = false
		last_pos_and_rot = { cam_joint:call("get_Position"), cam_joint:call("get_EulerAngle") }
		if battlecam then 
			battlecam:call("set_Enabled", true)
			battlecam = nil
		end
	end
	
	if last_pos_and_rot then
		for i, light_obj in ipairs(cam_lights) do
			if light_obj.attached then
				light_obj.xform:call("set_Position", last_pos_and_rot[1])
				light_obj.xform:call(last_pos_and_rot[2].w and "set_Rotation" or "set_EulerAngle", last_pos_and_rot[2])
			end
		end
	end
end)
--[[
local function manage_placekeys(do_reset_default)
	sf6_data.placekeys = sf6_data.placekeys or {}
	local vt = ValueType.new(sdk.find_type_definition("via.sfix"))
	do_reset_default = do_reset_default or (sf6_data.slow_motion_speed==1.0)
	for t=0, 1 do
		local dict = sdk.find_type_definition("gBattle"):get_field("Resource"):get_data().Data[t].FAB.StyleDict[0].ActionList
		for i=1, dict._count do
			local item = dict._entries[i-1]
			for l, list in ipairs({lua_get_system_array(item.value.Keys[31], true), lua_get_system_array(item.value.Keys[39], true), lua_get_system_array(item.value.Keys[48], true), lua_get_system_array(item.value.Keys[49], true), }) do
				sf6_data.placekeys[item.key] = sf6_data.placekeys[item.key] or {}
				for k, placekey in pairs(list) do
					if placekey then
						sf6_data.placekeys[item.key][l] = sf6_data.placekeys[item.key][l] or {}
						sf6_data.placekeys[item.key][l][k] = sf6_data.placekeys[item.key][l][k] or placekey:get_EndFrame()-- placekey.Ratio:call("ToFloat()")
						placekey:set_EndFrame(do_reset_default and sf6_data.placekeys[item.key][l][k] or placekey:get_StartFrame())
						--write_valuetype(placekey, "Ratio", sdk.find_type_definition("via.sfix"):get_method("From(System.Single)"):call(nil, sf6_data.placekeys[item.key][l][k] * ((do_reset_default and 1) or 0))) 
					end
				end
			end
		end
	end
end]]

re.on_script_reset(function()
	if graphics_settings_mgr and defaults.upscale_type then graphics_settings_mgr:call("set_UpscaleType", defaults.upscale_type) end
	if freecam_settings.img_quality then sdk.call_native_func(sdk.get_native_singleton("via.render.Renderer"), sdk.find_type_definition("via.render.Renderer"), "set_ImageQualityRate", freecam_settings.img_quality) end
	if EMV and next(attached_children) then setup_stage_attach() end
	--if isSF6 and sf6_data.placekeys then
	--	manage_placekeys(true)
	--end
end)

re.on_application_entry("UpdateMotion", function()
	
	if mot_fn then
		local fn; fn, mot_fn = mot_fn, nil
		fn()
	end
	for key, fn in pairs(temp_fns) do
		fn()
	end
	
	if dummy then 
		dummy.worldmatrix = dummy.xform:get_WorldMatrix() --You CANNOT get the worldmatrix for a gizmo on on-frame or it flickers like mad
		dummy.worldmatrix[3].w = 1.0
	end
	
	if freecam_on then  
		if cam_joint and last_camera_matrix then
			cam_joint = pcall(function()
				cam_joint:call("set_Position", last_camera_matrix[3])
				cam_joint:call("set_Rotation", last_camera_matrix:to_quat())
			end) and cam_joint
		end
	end
	
	if next(frozen_funcs) then 
		for i, move_func in pairs(frozen_funcs) do
			move_func()
		end
	end
	
	if stage_rot_func then
		stage_rot_func()
	end
end)

re.on_application_entry("EndRendering", function()
	cam_joint = (cam_joint and sdk.is_managed_object(cam_joint) and cam_joint) or nil
	if cam_joint and not pcall(function()
		last_camera_matrix = cam_joint:call("get_Rotation"):to_mat4()
		last_camera_matrix[3] = cam_joint:call("get_Position"):to_vec4()
		last_camera_matrix[3].w = 1
	end) then
		cam_joint = nil
	end
end)

if isSF6 then
	framerate = sdk.create_instance("app.bFlowManager.FrameRateSetting"):add_ref()
	framerate.PlatformType = 1
	nActions = {}
	sdk.hook(sdk.find_type_definition("app.battle.bBattleFlow"):get_method("setupBattleDesc"),
		function(args)
			sf6_data.no_battle_damage, sf6_data.distortion_on, sf6_data.show_p1, sf6_data.show_p2 = false, true, true, true
			sf6_data.slow_motion_speed  = 1.0
			sf6_data.fps_idx = 1
			sf6_data.player_meshes = {}
		end
	)
	sdk.hook(sdk.find_type_definition("app.bFlowManager.FlowWork"):get_method("applyFrameRate"),
		function(args)
			local flow_work = sdk.to_managed_object(args[2])
			flow_work:call("setFrameRateSetting(app.bFlowManager.FrameRateSetting)", framerate)
		end
	)
	nActions = {}
	sdk.hook(sdk.find_type_definition("nAction.Engine"):get_method("Prepare"),
		function(args)
			if sf6_data.slow_motion_speed ~= 1.0 then
				local obj = sdk.to_managed_object(args[2])
				obj:call("set_Speed(via.sfix)", sf6_data.speed_sfix)
				nActions[obj] = obj
				--if last_slow_motion_speed ~= sf6_data.slow_motion_speed then
				--	manage_placekeys()
				--end
				--last_slow_motion_speed = sf6_data.slow_motion_speed
			end
		end
	)
end

sdk.hook(sdk.find_type_definition("via.effect.EffectPlayer"):get_method("set_Action"),
	function(args)
		if disable_all_efx then
			pcall(function()
				sdk.to_managed_object(args[1]):get_GameObject():set_DrawSelf(false)
			end)
		end
	end
)
