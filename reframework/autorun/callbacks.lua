local function install_callbacks(callbacks, scope_anchor)
	-- Resolve FreeCam's module locals by name while leaving engine globals on _G.
	local bindings = {}
	local index = 1

	while true do
		local name = debug.getupvalue(scope_anchor, index)
		if not name then break end
		bindings[name] = index
		index = index + 1
	end

	local scope = setmetatable({}, {
		__index = function(_, name)
			local binding = bindings[name]
			if binding then
				local _, value = debug.getupvalue(scope_anchor, binding)
				return value
			end
			return _G[name]
		end,
		__newindex = function(_, name, value)
			local binding = bindings[name]
			if binding then
				debug.setupvalue(scope_anchor, binding, value)
			else
				_G[name] = value
			end
		end,
	})
	local _ENV = scope

	local function draw_named_node(name)
		local callback = callbacks[name]
		if callback then
			callback({ name = name, children = {} }, function() end)
		end
	end

	local function draw_enable_freecam()
		freecam_changed, freecam_on = imgui.checkbox("Enable FreeCam        ", freecam_on)
		if freecam_changed then
			last_mouse_pos = get_mouse_pos()
		end
	end

	local function draw_hide_ui()
		imgui.same_line()
		changed, hud_disabled = imgui.checkbox("Hide UI", hud_disabled)
	end

	local function draw_quality_toggle()
		imgui.same_line()
		changed, hi_quality = imgui.checkbox("2x Quality", hi_quality)
		tooltip("Renders the game at double your resolution, then scales it down")
		if changed then
			change_quality()
		end
	end

	local function draw_freeze_time_and_scene()
		changed, frozen_scene = imgui.checkbox("Freeze Time & Scene", frozen_scene)
		if changed then
			sdk.call_native_func(sdk.get_native_singleton("via.Application"), sdk.find_type_definition("via.Application"), "set_GlobalSpeed", (frozen_scene and 0.00001) or 1.0)
			if battleflow then battleflow:call("set_Enabled", not frozen_scene) end
		end
	end

	local function draw_orthographic_cam()
		if cam and not imgui.same_line() then
			changed, use_orthographic = imgui.checkbox("Orthographic Cam", (cam:call("get_ProjectionType") == 1))
			if changed then
				cam:call("set_ProjectionType", use_orthographic and 1 or 0)
			end
		end
	end

	local function draw_enable_cam_light()
		if not cam then return end
		changed, freecam_light_enabled = imgui.checkbox("Enable Cam Light", freecam_light_enabled)
		tooltip("Attaches a configurable light to the camera")

		if changed then
			local had_light = cam_light
			create_or_toggle_cam_light()
			cam_light.light:call("set_Enabled", freecam_light_enabled)
			if not had_light then cam_light.attached = true end
		end
	end

	local function draw_sf6_tools()
		if isSF6 and players[2] then
			if imgui.tree_node("SF6 Tools") then
				imgui.begin_rect()
				if graphics_settings_mgr and imgui.tree_node("Graphics") then
					managed_object_control_panel(graphics_settings_mgr)
					imgui.tree_pop()
				end
				changed, sf6_data.distortion_idx = imgui.combo("2D Distortion Effect", sf6_data.distortion_idx, {"Auto", "On", "Off"})
				if changed then
					distortion_on = ((sf6_data.distortion_idx == 1 and not freecam_on) or sf6_data.distortion_idx==2)
					change_player_mat_params("FixProjection_Switch", (distortion_on and 1.0) or 0.0)
				end

				changed, sf6_data.overlap_idx = imgui.combo("Overlapping Fighters", sf6_data.overlap_idx, {"Auto", "On", "Off"})
				if changed then
					sf6_data.overlap_on = ((sf6_data.overlap_idx == 1 and not freecam_on) or sf6_data.overlap_idx==2)
				end

				changed, sf6_data.fps_idx = imgui.combo("Frame Rate", sf6_data.fps_idx, {"60fps", "30fps", "120fps"})
				if changed then
					sdk.find_type_definition("app.Helper"):get_method("setAplicationFPS"):call(nil, (sf6_data.fps_idx==2 and 1) or (sf6_data.fps_idx==3 and 6) or 4, true)
				end

				changed, sf6_data.battle_damage_percent = imgui.slider_float("Set Battle Damage", sf6_data.battle_damage_percent, 0, 1)
				if changed then
					change_player_mat_params("DamageLevel", sf6_data.battle_damage_percent)
				end
				tooltip("Ctrl+click to type-in")
				changed, sf6_data.sweat_percent = imgui.slider_float("Set Sweat", sf6_data.sweat_percent, 0, 1)
				if changed then
					change_player_mat_params("Sweat_Rate", sf6_data.sweat_percent)
				end
				tooltip("Ctrl+click to type-in")

				changed, sf6_data.slow_motion_speed = imgui.slider_float("Slow Motion", sf6_data.slow_motion_speed, 0, 1)
				tooltip("Use with 'Show Character Gizmos' to stop stuttering")
				if changed then
					sf6_data.speed_sfix = sf6_data.speed_sfix:call("From(System.Single)", sf6_data.slow_motion_speed)
					--sdk.find_type_definition("via.sfix"):get_method("From(System.Single)"):call(nil, sf6_data.slow_motion_speed)
				end

				changed, movechars_on = imgui.checkbox("Show Character Gizmos", movechars_on)

				if next(frozen_funcs) then
					if frozen_funcs[2] and not imgui.same_line() and imgui.button("Reset P1") then
						frozen_funcs[2] = nil
					end
					if frozen_funcs[1] and not imgui.same_line() and imgui.button("Reset P2") then
						frozen_funcs[1] = nil
					end
				end
				changed, movelights_on = imgui.checkbox("Show Character Lights Gizmos", movelights_on)

				if EMV then
					local changed1, changed2
					changed1, movestage_on = imgui.checkbox("Move Stage", movestage_on)
					imgui.same_line()
					changed2, movestage_only_lights = imgui.checkbox("Move Lights", movestage_only_lights)
					if changed1 or changed2 then
						do_cam_orbit = false
						mot_fn = function() ; setup_stage_attach(nil, nil, nil, true) end
					end

					if (movestage_only_lights or movestage_on) and next(attached_children) and not imgui.same_line() then
						if imgui.button("Save") then
							mot_fn = function() ; setup_stage_attach(false, true) end
						end
						tooltip("Save the changes as the new default positions/rotations for the "..(movestage_on and "Stage" or "Lights").." (until reload)")
					end
					--if next(attached_children) and not imgui.same_line() and imgui.button("Center Axis") then
					--	temp_fn = reset_dummy_pos
					--end
					if (movestage_on or movestage_only_lights) and dummy then
						local prefix = movestage_on and "Stage" or "Lights"
						local changed2, dummy_pos = imgui.drag_float3(prefix.." Position", dummy.xform:call("get_Position"), 0.01, -10000, 10000)
						local changed1, dummy_rot = imgui.drag_float3(prefix.." Rotation", dummy.xform:call("get_EulerAngle"), 0.01, -360, 360)
						local changed3, dummy_scale = imgui.drag_float3(prefix.." Scale", dummy.xform:call("get_LocalScale"), 0.01, 0.001, 100.0)
						if changed1 or changed2 or changed3 then
							last_move_timer = os.clock()
							stage_rot_func = function()
								stage_rot_func = nil
								dummy.xform:call("set_Position", dummy_pos)
								dummy.xform:call("set_EulerAngle", dummy_rot)
								dummy.xform:call("set_LocalScale", dummy_scale)
							end
						end

						if last_move_timer and os.clock() - last_move_timer > 0.25 then
							last_move_timer = nil
							reset_dummy_pos()
						end
					end
				end

				if battleflow and imgui.tree_node("Stage Display") then
					imgui.begin_rect()
						local vfx_gameobj = scene:call("findGameObject(System.String)", "NoParentEffects")
						if vfx_gameobj then
							local changed, enabled = imgui.checkbox("Fighter VFX", vfx_gameobj:get_DrawSelf())
							if changed then  vfx_gameobj:set_DrawSelf(enabled) end
						end

						local stage_id = string.format("%04d", battleflow.m_desc.Stage.StageId * 0.01)
						local names = {"Env", "Light", "VFX", "Level", "High"}

						for i, name in ipairs(names) do
							local folder = scene:call("findFolder", "ess"..stage_id..((name=="High") and "_00v_" or "_00_")..name)
							if folder then
								local changed, enabled = imgui.checkbox(name, folder:get_DrawSelf())
								if changed then  folder:set_DrawSelf(enabled) end
								local bb = (name=="Env" and enabled) and scene:call("findFolder", "BillboardCrowd")
								if bb and not imgui.same_line() then
									changed, enabled = imgui.checkbox("BillboardCrowd", bb:get_DrawSelf())
									if changed then  bb:set_DrawSelf(enabled) end
								end
							end
						end
					imgui.end_rect(2)
					imgui.tree_pop()
				end

				for i=2, 1, -1 do
					local name = "P"..(i==2 and 1 or 2)
					imgui.push_id(name)
						changed, sf6_data["show_"..name] = imgui.checkbox("", sf6_data["show_"..name])
						if changed then
							for m, mesh in ipairs(lua_get_system_array(getC(players[i], "app.PlayerBehavior", true).mpMeshes) or {}) do
								mesh:call("set_Enabled", sf6_data["show_"..name])
							end
						end
						imgui.same_line()

						if imgui.tree_node(name) then
							imgui.begin_rect()
								local xform, changed1, changed2 = players[i]:get_GameObject():get_Transform(), nil, nil
								if movechars_on then
									changed1, sf6_data[name.."_pos"] = imgui.drag_float3(name.." Position", xform:call("get_Position"), 0.01, -10000, 10000)
									changed2, sf6_data[name.."_rot"] = imgui.drag_float3(name.." Rotation", xform:call("get_EulerAngle"), 0.01, -360, 360)
								end
								changed, sf6_data[name.."_scale"] = imgui.drag_float(name.." Scale", sf6_data[name.."_scale"], 0.001, 0.01, 50.0)
								if changed then
									xform:set_LocalScale(Vector3f.new(sf6_data[name.."_scale"], sf6_data[name.."_scale"], sf6_data[name.."_scale"]))
								end
								if changed1 or changed2 then
									frozen_funcs[i] = function()
										if not pcall(function()
											xform:set_Position(sf6_data[name.."_pos"])
											xform:set_EulerAngle(sf6_data[name.."_rot"])
										end) then
											frozen_funcs = {}
										end
									end
								end

								tps_dummy = (tps_dummy and tps_dummy.xform:get_Valid() and dummy == tps_dummy) and tps_dummy

								if imgui.button(name.." Third Person") then
									do_third_person = true
									mot_fn = function()
										freecam_settings.do_lookat = true
										if not tps_dummy then
											local gameobj = scene:call("findGameObject(System.String)", "TPSGizmo")
											tps_dummy = {gameobj = gameobj or sdk.find_type_definition("via.GameObject"):get_method("create(System.String)"):call(nil, "TPSGizmo"):add_ref()}
											tps_dummy.xform = tps_dummy.gameobj:get_Transform()
										end
										tps_dummy.xform:set_ParentJoint(tps_parent_joint_name or "C_Move")
										tps_dummy.xform:set_Parent(xform)
										local pos = xform:getJointByName("C_Hip"):get_Position()
										tps_dummy.xform:set_Position(Vector3f.new(pos.x, pos.y+0.25, pos.z))
										tps_mount = (tps_mount and tps_mount.xform:get_Valid()) and tps_mount
										if not tps_mount then
											local gameobj = scene:call("findGameObject(System.String)", "TPSMount")
											tps_mount = {gameobj = gameobj or sdk.find_type_definition("via.GameObject"):get_method("create(System.String)"):call(nil, "TPSMount"):add_ref()}
											tps_mount.xform = tps_mount.gameobj:get_Transform()
										end
										tps_mount.xform:set_Parent(tps_dummy.xform)
										local wm = xform:get_WorldMatrix()
										wm[3] = wm[3] + (wm[2]*-2.5)
										tps_mount.xform:set_Position(Vector3f.new(wm[3].x, wm[3].y+1.5, wm[3].z+0.5))
										dummy = tps_dummy
										tps_mount.cam_attached = true
										cam_attached = tps_mount
										attached_children[tps_mount.xform] = {}
										do_cam_orbit = true
										move_to_light(tps_mount)
										reset_dummy_pos(false, true)
									end
								end
								tooltip("Creates a gizmo for orbiting on the fighter's hip and mounts the camera to it.\nWhile orbiting, use the mouse to rotate and hold "..hk.hotkeys.CModifier3.." + use the standard camera and zoom controls to manipulate position and distance to center")

								if tps_mount and cam_attached and cam_attached.xform == tps_mount.xform then --and not imgui.same_line() then
									--changed, freecam_settings.tps_unlocked = imgui.checkbox("Unlocked", freecam_settings.tps_unlocked)
									--tooltip("Hold ALT to lock/unlock")
									local bone_names = {}
									for i, bone in ipairs(lua_get_system_array(xform:get_Joints())) do
										bone_names[i] = bone:get_Name()
									end
									changed, sf6_data.tps_parent_joint_name_idx = imgui.combo("Parent joint", sf6_data.tps_parent_joint_name_idx, bone_names)
									if changed then
										tps_parent_joint_name = bone_names[sf6_data.tps_parent_joint_name_idx]
										tps_dummy.xform:set_ParentJoint()
									end
								end

								if players[i].mpFace and imgui.tree_node(name.." Facial Animation") then

									local layer0 = players[i].mpFace:getLayer(0)
									local layer1 = players[i].mpFace:getLayer(1)
									local mnode = layer0:get_HighestWeightMotionNode()
									local mname = mnode and mnode:get_MotionName()
									local player_id = players[i]:get_GameObject():get_Name():match("esf(.+)v")
									freecam_settings.sf6_anims = freecam_settings.sf6_anims or {}
									freecam_settings.sf6_anims[player_id] = freecam_settings.sf6_anims[player_id] or {}
									sf6_data.anim_names[player_id] = sf6_data.anim_names[player_id] or {}
									if not sf6_data.anim_names[player_id][1] then
										for name, tbl in pairs(freecam_settings.sf6_anims[player_id]) do table.insert(sf6_data.anim_names[player_id], name) end
										table.sort(sf6_data.anim_names[player_id], function(a, b) return a < b end)
									end

									imgui.same_line()
									imgui.text_colored(mname, 0xFFE0853D)

									changed, players[i]._Facial._IsEnable = imgui.checkbox("Action System", players[i]._Facial._IsEnable, 0.0, 1.0)
									tooltip("Changes facial animations based on the current move\nLeave this on unless the game is not letting you seek in an animation")

									changed, sf6_data[name.."_animated_face"] = imgui.slider_float("Animation Rate", layer1:get_BlendRate(), 0.0, 1.0)
									if changed then
										layer1:set_BlendRate(sf6_data[name.."_animated_face"])
									end

									changed, sf6_data[name.."_face_motbank"] = imgui.drag_int("MotionBankID", layer0:get_MotionBankID(), 1, 0, 10000)
									if changed then
										layer0:set_MotionBankID(sf6_data[name.."_face_motbank"])
									end

									changed, sf6_data[name.."_face_motion"] = imgui.drag_int("MotionID", layer0:get_MotionID(), 1, 0, 10000)
									if changed then
										layer0:set_MotionID(sf6_data[name.."_face_motion"])
									end
									tooltip("An animation is a MotionID within a MotionBankID")

									if mname and not freecam_settings.sf6_anims[player_id][mname] then
										freecam_settings.sf6_anims[player_id][mname] = {bank=sf6_data[name.."_face_motbank"], mot=sf6_data[name.."_face_motion"]}
										table.insert(sf6_data.anim_names[player_id], mname)
										table.sort(sf6_data.anim_names[player_id], function(a, b) return a < b end)
										was_changed = true
									end

									changed, sf6_data[name.."_select_anim_idx"] = imgui.combo("Select Anim", find_index(sf6_data.anim_names[player_id], mname), sf6_data.anim_names[player_id])
									if changed then
										local old_speed = layer0:get_Speed()
										layer0:set_Speed(1000.0)
										local new_mot_name = sf6_data.anim_names[player_id][sf6_data[name.."_select_anim_idx"] ]
										local tbl = freecam_settings.sf6_anims[player_id][new_mot_name]
										layer0:set_MotionBankID(tbl.bank)
										layer0:set_MotionID(tbl.mot)
										layer0:set_WrapMode(2) --loop
										mot_fn = function()
											layer0:set_Frame(0)
											layer0:set_Speed(old_speed)
										end
									end

									changed, sf6_data[name.."_animation_frame"] = imgui.slider_float("Frame", layer0:get_Frame(), 0, layer0:get_EndFrame())
									if changed then
										mot_fn = function() layer0:set_Frame(sf6_data[name.."_animation_frame"]) end
									end

									changed, sf6_data[name.."_animation_speed"] = imgui.slider_float("Speed", layer0:get_Speed(), 0, 1)
									if changed then
										mot_fn = function() layer0:set_Speed(sf6_data[name.."_animation_speed"]) end
									end

									imgui.tree_pop()
								end

								if EMV then
									local go = held_transforms[xform] or EMV.GameObject:new{xform=xform}
									EMV.imgui_anim_object_viewer(go)
								end
							imgui.end_rect(2)
							imgui.tree_pop()
						end
					imgui.pop_id()
				end
				imgui.end_rect(2)
				imgui.tree_pop()
			end
		else
			imgui.text()
			imgui.spacing()
		end
	end

	local function draw_lua_freecam_root(node)
		if imgui.tree_node(node.name) then

		is_drawing_freecam_ui = true
		graphics_settings_mgr = isSF6 and sdk.get_managed_singleton("app.GraphicsSettingsManager")

		imgui.spacing()

		imgui.begin_rect()

				draw_named_node("Enable FreeCam")
				draw_named_node("Hide UI")
				draw_named_node("2x Quality")

				--[[if (defaults.img_quality or 0) > 1.0 and not imgui.same_line() and imgui.button("Reset to 1.0") then
					freecam_settings.img_quality = 1.0
					sdk.call_native_func(sdk.get_native_singleton("via.render.Renderer"), sdk.find_type_definition("via.render.Renderer"), "set_ImageQualityRate", 1.0)
				end]]

				draw_named_node("Freeze Time & Scene")
				draw_named_node("Orthographic Cam")

				if cam then

					draw_named_node("Enable Cam Light")

					if true then

					imgui.begin_rect()
					if should_expand_cam_lights_menu then
						should_expand_cam_lights_menu = nil
						imgui.set_next_item_open(true)
					end

					if imgui.tree_node_str_id("FL", cam_light and cam_light.gameobj:get_Name() or "Cam Light Settings") then

						if #cam_lights < 10 and not imgui.same_line() then
							if imgui.button("Create New") then
								create_new_cam_light()
								cam_light.selected = true
							end
							tooltip("Create a new camera light, detaching the old one at the current position")
							imgui.same_line()
						end

						if cam_light then

							if imgui.button("Set Shadows") then
								was_changed = true
								cam_light.light:call("set_ForceShadowCacheEnable", false)
								temp_fn = function()
									cam_light.light:call("set_ForceShadowCacheEnable", true)
								end
							end
							tooltip("Enables shadow-casting on some lights")

							imgui.same_line()
							if imgui.button(cam_light.attached and "Detach" or "Attach") then
								attach_detach(cam_light)
							end
							tooltip("Hotkey: " .. hk.hotkeys["Attach/Detach Selected Light"])

							if cam_light.light:call("get_ForceShadowCacheEnable") and not imgui.same_line() and imgui.button("Clear Shadow Cache") then
								cam_light.light:call("set_ForceShadowCacheEnable", false)
							end

							local val_names = {"_Color", "_Intensity", "_Radius", "_Cone", "_Spread", "_Falloff", "_ShadowBias"}
							local intensity_increment = ((isMHR or isRE7) and 0.1*candela_multi) or 1.0*candela_multi --or (isDMC and 10.0*candela_multi)

							for i, val_name in ipairs(val_names) do
								if val_name=="_Color" then
									changed, freecam_settings.light_settings[val_name] = imgui.color_edit3(val_name, cam_light.light:call("get_Color"), 17301504); cs()
								elseif val_name=="_ShadowBias" then
									changed, freecam_settings.light_settings[val_name] = imgui.drag_float(val_name, cam_light.light:call("get"..val_name), 0.0000001, 0, 1.0, "%.7f"); cs()
								else
									changed, freecam_settings.light_settings[val_name] = imgui.drag_float(val_name, cam_light.light:call("get"..val_name), (i==2 and intensity_increment) or 0.01, -100000.0, 100000.0); cs()
								end
								if val_name == "_Intensity" then tooltip("Press "..hk.hotkeys.CModifier.." + "..hk.hotkeys["Zoom Out"].." to increase\nPress "..hk.hotkeys.CModifier.." + "..hk.hotkeys["Zoom In"].." to decrease") end
								if changed then
									cam_light.light:call("set"..val_name, freecam_settings.light_settings[val_name])
									if do_force_shadow_bias and val_name == "_ShadowBias" then
										apply_shadow_bias(freecam_settings.light_settings[val_name])
									end
								end
							end
							if imgui.button("Reset to Defaults") then
								for i, val_name in ipairs(val_names) do
									freecam_settings.light_settings[val_name] = default_settings.light_settings[val_name]
									cam_light.light:call("set"..val_name, default_settings.light_settings[val_name])
								end
								was_changed = true
							end
							imgui.same_line()
							changed, do_force_shadow_bias = imgui.checkbox("Force Shadow Bias Everywhere", do_force_shadow_bias)
							tooltip("Forces all lights to use this shadow bias")
						end

						imgui.spacing()
						imgui.text_colored("Existing Lights:", 0xFFCCFFFF)

						if pos_before_teleport and not imgui.same_line() and imgui.button("Return to last Camera Position") then
							for i, other_light in ipairs(cam_lights) do other_light.cam_attached = false end
							last_pos_and_rot = pos_before_teleport
							pos_before_teleport = nil
						end

						if cam_lights[1] then
							changed, show_cam_lights = imgui.checkbox("Show Positions", show_cam_lights)
							tooltip("Display the lights position as green text in the world")
						end

						if EMV and (not cam_lights[1] or not imgui.same_line()) then

							changed, do_cam_orbit = imgui.checkbox("Orbit Gizmo", do_cam_orbit)
							tooltip("Creates a gizmo to move and rotate detached cam lights\nDisabled and attached lights will not orbit\nHold " .. hk.hotkeys["CModifier"] .. " to move gizmo independently from its children")
							if changed and (do_cam_orbit or next(attached_children)) then
								mot_fn = function()  setup_stage_attach() end
							end

							local dummy_gameobj = not dummy and scene:call("findGameObject(System.String)", "FreeCamGizmo")
							dummy = dummy or (dummy_gameobj and {gameobj=dummy_gameobj, xform=dummy_gameobj:get_Transform()})

							if do_cam_orbit then
								imgui.same_line()
								if imgui.button("Save") then
									mot_fn = function() setup_stage_attach(false, true) end
									do_cam_orbit = false
								end
								tooltip("Saves the orbited camera positions")
							end

							if dummy then
								changed, do_third_person = imgui.checkbox("Allow Mouse Control", do_third_person)
								tooltip("Allows the mouse to move the camera after clicking 'Move To' on a light (with an Orbit Gizmo)")
								imgui.same_line()
								if imgui.button("Move Gizmo to Cam") then
									mot_fn = function()
										dummy.xform:set_Position(last_camera_matrix[3]:to_vec3())
									end
								end
								tooltip("Moves the gizmo and lights the camera")

								imgui.same_line()
								if imgui.button("Reset Xform") then
									reset_dummy_pos(false, true)
								end
								tooltip("Resets the gizmo's rotation and scale without moving lights")

								if do_cam_orbit then
									local changed, position = imgui.drag_float3("Gizmo Position", dummy.xform:get_Position(), 0.01, -10000, 10000)
									if changed then mot_fn = function() dummy.xform:call("set_Position", position); light_lookat_fn(true) end end
									local changed, rotation = imgui.drag_float3("Gizmo Rotation", dummy.xform:get_EulerAngle(), 0.01, -10000, 10000)
									if changed then mot_fn = function() dummy.xform:call("set_EulerAngle", rotation); light_lookat_fn() end end
									local old_scale = dummy.xform:get_LocalScale()
									local changed, scale = imgui.drag_float3("Gizmo Scale", old_scale, 0.001, -10000, 10000)
									if changed then
										if freecam_settings.change_scale_together then
											if old_scale.x ~= scale.x then scale = Vector3f.new(scale.x, scale.x, scale.x)
											elseif old_scale.y ~= scale.y then scale = Vector3f.new(scale.y, scale.y, scale.y)
											elseif old_scale.z ~= scale.z then scale = Vector3f.new(scale.z, scale.z, scale.z) end
										end
										mot_fn = function()
											dummy.xform:call("set_LocalScale", scale); light_lookat_fn()
											if pos_before_teleport then reset_dummy_pos(false, 1) end
										end
									end
									changed, freecam_settings.do_lookat = imgui.checkbox("Look at Gizmo", freecam_settings.do_lookat)
									tooltip("Orbiting lights always point towards the gizmo")
									imgui.same_line()
									changed, freecam_settings.change_scale_together = imgui.checkbox("Scale XYZ", freecam_settings.change_scale_together)
									tooltip("Scale X, Y and Z together")
									imgui.same_line()
									changed, freecam_settings.tps_unlocked = imgui.checkbox("Unlocked", freecam_settings.tps_unlocked)
									tooltip("After clicking 'Move To' on an orbiting light, hold ALT to lock/unlock")
								end
							end
						end

						imgui.spacing()

						for i, light in ipairs(cam_lights) do

							light.selected = cam_light and (light.gameobj==cam_light.gameobj)
							if light.selected then imgui.begin_rect() imgui.begin_rect() end

							imgui.push_id("sw"..i)
							changed, light.enabled = imgui.checkbox("", light.gameobj:call("get_DrawSelf") and light.light:get_Enabled())
							tooltip("Enable/Disable this light")
							if changed then
								light.gameobj:call("set_DrawSelf", light.enabled)
								light.light:set_Enabled(light.enabled)
							end
							imgui.same_line()

							if dummy then
								imgui.push_id("sz"..i)
								changed, light.orbiting = imgui.checkbox("", light.orbiting)
								tooltip("Orbit this light around the Orbit Gizmo")
								imgui.same_line()
								imgui.pop_id()
								if changed then
									attached_children[light.xform] = light.orbiting and (attached_children[light.xform] or light)
									light.xform:call("set_Parent", light.orbiting and dummy.xform or nil)
								end
							end

							if imgui.button("Select") then
								cam_light = light
							end
							tooltip("Makes light hotkeys and the light control panel be used for this light")

							imgui.same_line()
							if imgui.button("Del") then
								temp_fn = function()
									cam_lights_map[light.gameobj] = nil
									light.gameobj:call("destroy", light.gameobj)
									local idx = tonumber(light.gameobj:get_Name():match(".*(%d)"))+1
									table.remove(cam_lights, idx)
									for i, light in ipairs(cam_lights) do
										light.gameobj:set_Name("FreeCamLight"..i-1)
									end
									if light.selected then
										cam_light = cam_lights[idx-1] or cam_lights[idx]
										freecam_light_enabled = cam_light and freecam_light_enabled
									end
									do_cam_orbit = cam_lights[1] and do_cam_orbit
								end
							end
							tooltip("Delete this light")

							imgui.same_line()
							if imgui.button(light.attached and "Detach" or "Attach") then
								attach_detach(light)
							end
							tooltip("Attach or Detach this light from the camera")

							local cam_no = light.gameobj:get_Name():match(".*(%d)")

							if not light.attached then
								imgui.same_line()
								if (imgui.button("Move To")) then
									move_to_light(light)
								end
								tooltip("Teleport the camera to this light\nThe camera will move with this light when it or its orbit gizmo is moved or rotated"..
								"\nWhile orbiting, use the mouse to rotate and hold "..hk.hotkeys.CModifier3.." + use the standard camera and zoom controls to manipulate position and distance to center"..
								"\nHotkey: ".. hk.hotkeys["Move to Light "..cam_no])
							end
							imgui.pop_id()

							if not imgui.same_line() and imgui.tree_node(light.gameobj:get_Name()) then
								local changed, position = imgui.drag_float3("Position", light.xform:get_Position(), 0.01, -10000, 10000)
								if changed then
									if light.orbiting and dummy then light.xform:set_Parent(nil) end
									light.xform:call("set_Position", position)
									if light.orbiting and dummy then
										light_lookat_fn()
										temp_fn = function() light.xform:set_Parent(dummy.xform) end
									end
								end
								local changed, rotation = imgui.drag_float3_euler("Rotation", light.orbiting and dummy and dummy.xform:get_EulerAngle() or light.xform:get_EulerAngle(), 0.01, -10000, 10000)
								if changed then
									if light.orbiting and dummy then
										temp_fn = function()
											move_light_by_dummy_independently(light, function() dummy.xform:call("set_EulerAngle", rotation); light_lookat_fn()  end)
										end
									else
										light.xform:call("set_EulerAngle", rotation)
									end
								end
								changed = hk.hotkey_setter("Move to Light "..cam_no); cs()
								tooltip("Use with secondary modifier '"..hk.hotkeys["CModifier2"].." + "..hk.hotkeys["Move to Light "..cam_no].."' to enable/disable lights")

								if imgui.tree_node("GameObject") then
									managed_object_control_panel(light.xform)
									imgui.tree_pop()
								end
								imgui.tree_pop()
							end
							if light.selected then imgui.end_rect(2) imgui.end_rect(3) end
						end

						if dummy then
							if imgui.button("Save Light Configuration") and imgui_data.lightconfig_text:len() > 0 then
								txt = imgui_data.lightconfig_text:gsub("%.json", "") .. ".json"
								local to_dump = {}
								for i, light in ipairs(cam_lights) do
									if light.orbiting then
										local pos, rot = light.xform:get_LocalPosition(), light.xform:get_LocalRotation()
										to_dump[i] = {
											pos = {pos.x, pos.y, pos.z},
											rot = {rot.x, rot.y, rot.z, rot.w},
										}
									end
								end
								if json.dump_file("LuaFreeCam\\LightConfigs\\"..txt, to_dump) then
									was_changed, lightconfigs_glob = true
									re.msg("Saved to\nreframework\\data\\LuaFreeCam\\LightConfigs\\"..txt)
								end
							end
							--tooltip("Input new skill name and save the current settings to a json file in\n[DD2 Game Directory]\\reframework\\data\\SkillMaker\\Skills\\")

							imgui.same_line()
							changed, imgui_data.lightconfig_text = imgui.input_text("  ", imgui_data.lightconfig_text)

							local clicked_button = imgui.button("Load Light Configuration")
							tooltip("Load settings from a json file in\n[DD2 Game Directory]\\reframework\\data\\LuaFreeCam\\LightConfigs\\")
							imgui.same_line()

							changed, imgui_data.lightconfig_idx = imgui.combo(" ", imgui_data.lightconfig_idx, lightconfig_names)

							if clicked_button then
								local lightconfig = json.load_file(lightconfigs_glob[imgui_data.lightconfig_idx])
								local frames = 0
								temp_fns.setup_lightconfig = function()
									temp_fns.setup_lightconfig = frames < 5 and temp_fns.setup_lightconfig or nil
									frames = frames + 1
									for j, light_json in ipairs(lightconfig) do --I dont know why the fuck this has to run 5 times to take effect
										local light = cam_lights[j] or create_new_cam_light()
										light.xform:set_Parent(nil)
										light.xform:set_Parent(dummy.xform)
										light.xform:set_LocalPosition(Vector3f.new(light_json.pos[1], light_json.pos[2], light_json.pos[3]))
										light.xform:set_LocalRotation(Quaternion.new(light_json.rot[4], light_json.rot[1], light_json.rot[2], light_json.rot[3]))
									end
								end
								temp_fns.setup_lightconfig()
								was_changed, lightconfigs_glob = true
							end

							if EMV and imgui.tree_node("Gizmo") then
								managed_object_control_panel(dummy.xform)
								imgui.tree_pop()
							end
						end

						if was_changed then
							freecam_light_enabled = true
							create_or_toggle_cam_light()
						end

						imgui.tree_pop()
					end
					imgui.spacing()
					imgui.end_rect(2)
				end

				changed, freecam_settings.use_quick_zoom = imgui.checkbox(freecam_settings.use_quick_zoom and "Quick Zoom:" or "Quick Zoom", freecam_settings.use_quick_zoom); cs()
				tooltip("Press the Quick Zoom key/button to zoom in from the game's current FOV to the Zoom FOV")
				if changed and use_frozen_fov and not freecam_settings.use_quick_zoom then --and frozenFOV == freecam_settings.zoom_fov then
					use_frozen_fov, frozenFOV = false
				end
				if freecam_settings.use_quick_zoom then
					imgui.same_line()
					changed = hk.hotkey_setter("Quick Zoom", nil, true); cs()
					imgui.same_line()
					if imgui.button("Reset Quick Zoom") then
						was_changed = true
						freecam_settings.zoom_fov = default_settings.zoom_fov
						freecam_settings.zoom_speed = default_settings.zoom_speed
					end
					changed, freecam_settings.zoom_fov = imgui.drag_float("Quick Zoom FOV", freecam_settings.zoom_fov, 0.1, 0.1, 180.0, "%.4f"); cs()
					changed, freecam_settings.zoom_speed = imgui.drag_float("Quick Zoom Speed", freecam_settings.zoom_speed, 0.01, 0.1, 10.0, "%.4f"); cs()
				end
				local had_frozen_fov = use_frozen_fov
				imgui.push_id("frz")
					changed, use_frozen_fov = imgui.checkbox((use_frozen_fov and "") or "Freeze FOV", use_frozen_fov or frozenFOV)
				imgui.pop_id()
				if changed and not use_frozen_fov then frozenFOV = nil end
				if use_frozen_fov and had_frozen_fov == use_frozen_fov then
					imgui.same_line()
					changed, frozenFOV = imgui.drag_float("Freeze FOV", frozenFOV or cam:call("get_FOV"), 0.1, 0.1, 180.0)
				end

				local changed2
				changed, mount_obj_name = imgui.input_text("Mount Object Name", mount_obj_name)
				tooltip("Enter the name of a GameObject to mount the camera to it")
				if mount_obj_name ~= "" then
					changed2, mount_obj_jname = imgui.input_text("Mount Joint Name", mount_obj_jname)
					tooltip("Enter the name of a joint belonging to the Mount Object to mount the camera to that joint")
				end
				if changed or changed2 then
					local mount_obj = scene:call("findGameObject(System.String)", mount_obj_name)
					if mount_obj then
						local xform = mount_obj:get_Transform()
						local bone = xform:getJointByName(mount_obj_jname) or xform:get_Joints()[0]

						mounting_fn = function()
							mounting_fn = mount_obj and mount_obj:get_Valid() and mounting_fn or nil
							return mounting_fn and bone:get_Position()
						end
					end
				end

			end

			pcall(function()
				sceneview = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), scene_mgr_typedef, "get_MainView")
				changed, display_mode = imgui.combo("Display Mode", display_mode or sceneview:call("get_DisplayType")+1, display_type_names)
				if changed then
					sceneview:call("set_DisplayType", display_mode - 1)
				end
			end)

			changed, freecam_settings.rot_speed = imgui.drag_float("Cam Rotation Speed", freecam_settings.rot_speed, 0.01, 0, 100); cs()

			changed, freecam_settings.dir_speed = imgui.drag_float("Cam Movement Speed", freecam_settings.dir_speed, 0.5, 0, 100); cs()

			changed, freecam_settings.control_type = imgui.combo("Cam Control Type", freecam_settings.control_type, {"Mouse + Gamepad", "Mouse", "Gamepad"})
			tooltip("Which means of input controls the free camera's direction")

			changed, freecam_settings.do_invert_pad = imgui.checkbox("Invert Gamepad Y", freecam_settings.do_invert_pad)
			tooltip("Flip the Y-axis when controlling the freecam via GamePad")

			if freecam_settings.do_invert_pad ~= 2 then
				changed, disable_all_efx = imgui.checkbox("Disable VFX", disable_all_efx)
				tooltip("Tries to disable all Visual Effects")
			end

			imgui.same_line()

			changed, disable_all_lights = imgui.checkbox("Disable Lights", disable_all_lights)
			tooltip("Tries to disable all via.render.Lights")

			if not EMV then
				imgui.same_line()
				imgui.text_colored("Install EMV Engine to enable extra features", 0xFF0000FF)
				tooltip("https://github.com/alphazolam/EMV-Engine")
			end

			if changed then
				temp_fn = function()
					for n, name in ipairs({"Light", "LightProbes"}) do
						for i, light in ipairs(lua_get_system_array(scene:call("findComponents(System.Type)", sdk.typeof("via.render."..name)))) do
							if disable_all_lights and not cam_lights_map[light:get_GameObject()] then
								all_lights[light] = light:get_Enabled()
								light:set_Enabled(false)
								light:get_GameObject():set_DrawSelf(false)
							elseif all_lights[light] ~= nil then
								light:set_Enabled(all_lights[light])
								light:get_GameObject():set_DrawSelf(all_lights[light])
							end
						end
					end
				end
			end

			if imgui.tree_node("Hotkeys") then
				imgui.spacing()
				imgui.text()
				imgui.same_line()
				imgui.begin_rect()
					changed = hk.hotkey_setter("Activate FreeCam"); cs()
					changed = hk.hotkey_setter("Toggle FreeCam Light"); cs()
					changed = hk.hotkey_setter("2x Quality"); cs()
					changed = hk.hotkey_setter("Hide UI"); cs()
					changed = hk.hotkey_setter("Create New Light"); cs()
					changed = hk.hotkey_setter("Attach/Detach Selected Light"); cs()
					imgui.text("Modifier:"); imgui.same_line()
					changed = hk.hotkey_setter("CModifier", nil, true); cs()
					imgui.same_line()
					changed = hk.hotkey_setter("CModifier2", nil, true); cs()
					imgui.text("Modifier 2:"); imgui.same_line()
					changed = hk.hotkey_setter("CModifier3", nil, true); cs()
					changed = hk.hotkey_setter("Cam Forward"); cs()
					changed = hk.hotkey_setter("Cam Backward"); cs()
					changed = hk.hotkey_setter("Cam Left"); cs()
					changed = hk.hotkey_setter("Cam Right"); cs()
					changed = hk.hotkey_setter("Cam Up"); cs()
					changed = hk.hotkey_setter("Cam Down"); cs()
					changed = hk.hotkey_setter("Roll Left"); cs()
					changed = hk.hotkey_setter("Roll Right"); cs()
					changed = hk.hotkey_setter("Freeze Camera"); cs()
					changed = hk.hotkey_setter("Zoom In"); cs()
					changed = hk.hotkey_setter("Zoom Out"); cs()
					changed = hk.hotkey_setter("Reset Zoom"); cs()
					changed = hk.hotkey_setter("Freeze Time & Scene"); cs()

					if isSF6 then
						changed = hk.hotkey_setter("Freeze Time"); cs()
					end
					changed = hk.hotkey_setter("Skip Frame"); cs()
					if isRE8 then
						changed = hk.hotkey_setter("Unequip Weapons (RE8)"); cs()
					end

					imgui.text_colored("	Hold [Modifier] to move/rotate at 3x speed\n", 0xFFCCFFFF)
					imgui.text_colored("	Hold [Modifier2] to move/rotate at 1/3rd speed\n", 0xFFCCFFFF)
					imgui.text_colored("	Press [Modifier] + Roll to reset roll\n", 0xFFCCFFFF)
					imgui.text_colored("	Hold [Modifier2] and use camera controls when attached to an orbiting cam light to move and rotate it\n", 0xFFCCFFFF)
					if isSF6 then
						imgui.text_colored("	Hold [Modifier] and press [Freeze Time] to freeze the scene only", 0xFFCCFFFF)
					end
					if imgui.button("Reset to Defaults") then
						--[[freecam_settings.hotkeys = {}
						for k, v in pairs(default_settings.hotkeys) do freecam_settings.hotkeys[k] = default_settings.hotkeys[k] end
						hotkeys = freecam_settings.hotkeys]]
						freecam_settings.hotkeys = recurse_def_settings({}, default_settings.hotkeys)
						hk.reset_from_defaults_tbl(default_settings.hotkeys)
						hk.update_hotkey_table(freecam_settings.hotkeys)
						dump_settings()
					end
				imgui.end_rect(3)
				imgui.tree_pop()
			end

			if cam_xform and imgui.tree_node("Visual Settings") then

				imgui.begin_rect()

					local try, renderer = pcall(cam_gameobj.call, cam_gameobj, "getComponent(System.Type)", sdk.typeof("via.render.RenderOutput"))

					if try and renderer then

						orig_render_output_id = renderer:call("get_RenderOutputID")
						local fog = 	 getC(cam_gameobj, "via.render.Fog")
						local tonemap = getC(cam_gameobj, "via.render.ToneMapping")
						local softbloom = getC(cam_gameobj, "via.render.SoftBloom")
						local dof = getC(cam_gameobj, "via.render.DepthOfField")
						local ssao = getC(cam_gameobj, "via.render.SSAOControl")
						local ldrpp = getC(cam_gameobj, "via.render.LDRPostProcess")
						local cc = ldrpp and ldrpp:call("get_ColorCorrect")
						local rt = can_rt and getC(cam_gameobj, "via.render.ExperimentalRayTrace")
						local filter = getC(cam_gameobj, "via.render.CustomFilter") or getC(cam_gameobj, "via.render.CustomFilterBeforeTransparent")
						local vol = getC(cam_gameobj, "via.render.VolumetricFogControl")

						changed, freecam_settings.img_quality = imgui.slider_float("Default Image Quality", freecam_settings.img_quality, 0.1, 1.0); cs()
						tooltip("The game will be internally rendered at this multiplier of your game resolution")

						changed, is_constant = imgui.checkbox("Constant Settings", is_constant)
						tooltip("Forces settings every frame")

						if is_constant then
							imgui.same_line()
							changed, do_remember = imgui.checkbox("Remember", do_remember)
							tooltip("Forces settings on every future camera")
						end
						local do_constant = is_constant and do_remember

						if dof then
							changed, dof_on = imgui.checkbox("Depth of Field (Blur)", do_constant and dof_on or not do_constant and dof:call("get_Enabled"))
							if changed or is_constant then
								dof:call("set_Enabled", dof_on)
							end
							if dof_on and not imgui.same_line() and imgui.tree_node_str_id("dof", "Options") then
								changed, dof_options.sensor_size = imgui.drag_float("Sensor Size", do_constant and dof_options.sensor_size or not do_constant and dof:get_SensorSize(), 0.01, 0, 100000)
								if changed or is_constant then
									dof:set_SensorSize(dof_options.sensor_size)
								end
								changed, dof_options.focus_distance = imgui.drag_float("Focus Distance", do_constant and dof_options.focus_distance or not do_constant and dof:get_FocusDistance(), 0.01, 0, 100000)
								if changed or is_constant then
									dof:set_FocusDistance(dof_options.focus_distance)
								end
								changed, dof_options.fnumber = imgui.drag_float("FNumber", do_constant and dof_options.fnumber or not do_constant and dof:get_FNumber(), 0.01, 0, 100000)
								if changed or is_constant then
									dof:set_FNumber(dof_options.fnumber)
								end
								changed, dof_options.use_fixed_fov = imgui.checkbox("Use Fixed FOV", do_constant and dof_options.use_fixed_fov or not do_constant and dof:call("get_EnableFixFOV"))
								if changed or is_constant then
									dof:set_EnableFixFOV(dof_options.use_fixed_fov)
								end
								if dof_options.use_fixed_fov then
									changed, dof_options.fixed_fov = imgui.drag_float("Fixed FOV", do_constant and dof_options.fixed_fov or not do_constant and dof:get_FOV(), 0.01, 0, 100000)
									if changed or is_constant then
										dof:set_FOV(dof_options.fixed_fov)
									end
								end
								imgui.tree_pop()
							end
						end

						if ssao then
							--if ssao_on and ssao.getSSAOAlgorithm then imgui.begin_rect() end
							changed, ssao_on = imgui.checkbox("SSAO", do_constant and ssao_on or not do_constant and ssao:call("get_Enabled"))
							if changed or is_constant then
								ssao:call("set_Enabled", ssao_on)
							end
							if ssao_on and ssao.getSSAOAlgorithm then
								imgui.same_line()
								changed, temporal_ssao = imgui.checkbox("Temporal SSAO", (ssao:getSSAOAlgorithm() == 1))
								if changed then
									ssao:setSSAOAlgorithm(temporal_ssao and 1 or 0)
								end
								changed, ssao_intensity = imgui.drag_float("SSAO Intensity", ssao:get_AOIntensity(), 0.01, 0.0, 50.0)
								if changed then
									ssao:set_AOIntensity(ssao_intensity)
								end
								changed, ssao_tint = imgui.color_edit3("SSAO Color", ssao:get_AOTint(), 17301504)
								if changed then
									ssao:set_AOTint(ssao_tint)
								end
							end
							--if ssao_on and ssao.getSSAOAlgorithm then imgui.end_rect(2) end
						end

						if softbloom then
							changed, softbloom_on = imgui.checkbox("SoftBloom", do_constant and softbloom_on or not do_constant and softbloom:call("get_Enabled"))
							if changed or is_constant then
								softbloom:call("set_Enabled", softbloom_on)
							end
						end

						if filter then
							changed, filter_on = imgui.checkbox("Custom Filter (Lut)", do_constant and filter_on or not do_constant and filter:call("get_Enabled"))
							if changed or is_constant then
								filter:call("set_Enabled", filter_on)
							end
							local fshader = filter_on and filter:getFilterShader(0)
							if fshader then
								local resource = fshader:get_Filter()
								local rpath = resource and resource:get_ResourcePath()
								if rpath and not freecam_settings.cached_luts[rpath] then
									freecam_settings.cached_luts[rpath] = true
									filter_options.do_update = true
								end
								if filter_options.do_update or (not filter_options.mdf_names[1] and next(freecam_settings.cached_luts)) then
									filter_options.do_update = nil
									filter_options.mdf_names = {}
									for path, non in pairs(freecam_settings.cached_luts) do
										table.insert(filter_options.mdf_names, path)
									end
									table.sort(filter_options.mdf_names, function(a, b) return a < b end)
									dump_settings()
								end
								if imgui.button(" + ") then
									filter_options.show_mdf_input = not filter_options.show_mdf_input
								end
								imgui.same_line()
								changed, filter_options.filter_mdf_idx = imgui.combo("Lut MDF", filter_options.filter_mdf_idx or find_index(filter_options.mdf_names, rpath or ""), filter_options.mdf_names)
								if changed then
									local new_res = create_resource("via.render.MeshMaterialResource", filter_options.mdf_names[filter_options.filter_mdf_idx])
									fshader:set_Filter(new_res)
								end
								if filter_options.show_mdf_input then
									filter_options.mdf_text_input = filter_options.mdf_text_input or filter_options.mdf_names[filter_options.filter_mdf_idx]
									if imgui.button("Set") and not freecam_settings.cached_luts[filter_options.mdf_text_input] then
										local new_res = create_resource("via.render.MeshMaterialResource", filter_options.mdf_text_input)
										if new_res and sdk.find_type_definition("via.io.file"):get_method("exists"):call(nil, "natives/stm/"..filter_options.mdf_text_input..filter_options.mdf_exts[reframework:get_game_name()]) then
											freecam_settings.cached_luts[filter_options.mdf_text_input] = true
											filter_options.do_update = true
											filter_options.show_mdf_input = false
											fshader:set_Filter(new_res)
										end
									end
									imgui.same_line()
									changed, filter_options.mdf_text_input = imgui.input_text("Input New Lut MDF", filter_options.mdf_text_input)
								end
							end
						end

						if tonemap then
							changed, vignette_on = imgui.checkbox("Vignette", do_constant and vignette_on or not do_constant and (tonemap:call("getVignetting") ~= 2))
							if changed or is_constant then
								tonemap:call("setVignetting", (vignette_on and 0) or 2)
							end

							changed, ev_value = imgui.drag_float("EV", do_constant and ev_value or not do_constant and tonemap:call("get_EV"), 0.01, -15, 15)
							if changed or is_constant then
								tonemap:call("set_EV", ev_value)
							end

							changed, contrast = imgui.drag_float("Contrast", do_constant and contrast or not do_constant and tonemap:call("get_Contrast"), 0.01, 0, 15)
							if changed or is_constant then
								tonemap:call("set_Contrast", contrast)
							end
						end

						if cc then
							changed, cc_on = imgui.checkbox("Color Correction", do_constant and cc_on or not do_constant and cc:call("get_Enabled"), 0.01, 0, 15)
							if changed or is_constant then
								cc:call("set_Enabled", cc_on)
							end

							if cc_on and cc:call("get_LinearParamsCount")~=0 then
								for i=1, cc:call("get_LinearParamsCount") do
									cc_factors[i] = cc_factors[i] or {
										color=cc_item:call("get_LinearFactor"),
										type=cc_item:call("get_LinearCorrectorType")+1,
									}
									if imgui.tree_node("Color Parameter " .. i) then
										local cc_item = cc:call("getLinearParamsAt", i-1)
										changed, cc_factors[i].type = imgui.combo("Type", cc_factors[i].type or cc_item:call("get_LinearCorrectorType")+1, {"None", "Hue", "Chroma", "Brightness", "Sepia", "Scale", "NegiPosi", "GrayScale"})
										if changed or is_constant then
											cc_item:call("set_LinearCorrectorType", cc_factors[i].type-1)
										end
										changed, cc_factors[i].color = imgui.color_edit4("Linear Factor", cc_factors[i].color or cc_item:call("get_LinearFactor"), 17301504) -- fog:call("get_InscatteringColor")
										if changed or is_constant then
											cc_item:call("set_LinearFactor", cc_factors[i].color)
										end
										imgui.tree_pop()
									end
								end
							end
						end

						if vol then
							changed, vol_on = imgui.checkbox("Volumetric Fog", do_constant and vol_on or not do_constant and vol:call("get_Enabled"), 0.01, 0, 15)
							if changed or is_constant then
								vol:call("set_Enabled", vol_on)
							end
						end

						if can_rt then
							changed, rt_enabled = imgui.checkbox("Ray Tracing", rt and rt:get_Enabled())
							if changed or is_constant then
								if not rt and changed then
									cam_gameobj:call("createComponent(System.Type)", sdk.typeof("via.render.ExperimentalRayTrace"))
									temp_fn = function()
										local rt = getC(cam_gameobj, "via.render.ExperimentalRayTrace")
										rt:set_RaytracingMode(6)
										rt:set_DenoiserDebugView(1)
									end
								elseif rt then
									rt:set_Enabled(rt_enabled)
								end
							end

							if rt then
								imgui.same_line()
								changed, rt_reflections_enabled = imgui.checkbox("Reflection", (rt:get_DenoiserDebugView()==0))
								if changed or is_constant then
									rt:set_DenoiserDebugView(rt_reflections_enabled and 0 or 1)
								end
								imgui.same_line()
								if imgui.tree_node_str_id("rt", "Options") then
									managed_object_control_panel(rt)
									imgui.tree_pop()
								end
							end
						end

						if fog then
							local gs_name = (isSF6 and "Greenscreen") or "Fog"
							changed, greenscreen_on = imgui.checkbox(gs_name, greenscreen_on)
							if isSF6 then tooltip("Works best in the 'Training Room' stage") end

							if changed or is_constant then
								if greenscreen_on then
									if isSF6 then renderer:call("set_RenderOutputID", 2) end
									fog:call("set_Enabled", true)
									fog:call("set_Intensity", 100.0)
									fog:call("set_HeightFalloff", 0.0)
									fog:call("set_InscatteringColor", gs_color or (isSF6 and Vector3f.new(0,1,0)) or Vector3f.new(1,1,1))
								elseif changed then
									renderer:call("set_RenderOutputID", ((isSF6 or isDMC or isMHR) and 1) or orig_render_output_id)
									if isSF6 or isRE3 then fog:call("set_Enabled", false) end
								end
							end

							if greenscreen_on then
								changed, gs_color = imgui.color_edit3(gs_name .. " Color", gs_color or (isSF6 and Vector3f.new(0,1,0)) or Vector3f.new(1,1,1), 17301504) -- fog:call("get_InscatteringColor")
								if changed or is_constant then
									fog:call("set_InscatteringColor", gs_color)
								end
							else
								imgui.text()
								imgui.spacing()
							end
						end

						constant_fn = is_constant and function()
							if cam_gameobj then
								if dof and not pcall(dof.call, dof, "set_Enabled", dof_on)  then
									constant_fn = nil
									return nil
								end
								if ssao then ssao:call("set_Enabled", ssao_on) end
								if softbloom then softbloom:call("set_Enabled", softbloom_on) end
								if tonemap then
									tonemap:call("setVignetting", (vignette_on and 0) or 2)
									tonemap:call("set_EV", ev_value)
									tonemap:call("set_Contrast", contrast)
								end
								if cc then
									cc:call("set_Enabled", cc_on)
									if cc_on and cc:call("getLinearParamsCount")~=0 then
										for i=1, cc:call("get_LinearParamsCount") do
											local cc_item = cc:call("getLinearParamsAt", i-1)
											if cc_factors[i].type then
												cc_item:call("set_LinearCorrectorType", cc_factors[i].type-1)
												cc_item:call("set_LinearFactor", cc_factors[i].color)
											end
										end
									end
								end
								if fog then
									if greenscreen_on then
										if isSF6 then renderer:call("set_RenderOutputID", 2) end
										fog:call("set_Enabled", true)
										fog:call("set_Intensity", 100.0)
										fog:call("set_HeightFalloff", 0.0)
										fog:call("set_InscatteringColor", gs_color or (isSF6 and Vector3f.new(0,1,0)) or Vector3f.new(1,1,1))
									else
										renderer:call("set_RenderOutputID", ((isSF6 or isDMC or isMHR) and 1) or orig_render_output_id)
									--	if isSF6 or isRE3 then fog:call("set_Enabled", false) end
									end
								end
								if vol then
									vol:call("set_Enabled", vol_on)
								end
								if dof and dof_on then
									dof:set_SensorSize(dof_options.sensor_size)
									dof:set_FocusDistance(dof_options.focus_distance)
									dof:set_FNumber(dof_options.fnumber)
									dof:set_EnableFixFOV(dof_options.use_fixed_fov)
									if dof_options.use_fixed_fov then
										dof:set_FOV(dof_options.fixed_fov)
									end
								end
								if filter then
									filter:set_Enabled(filter_on)
								end
								if rt then
									rt:set_Enabled(rt_enabled)
								end
							end
						end
					end

				if cam_xform and cam_xform:read_qword(0x10) ~= 0 then
					if imgui.tree_node("Camera") then
						managed_object_control_panel(cam_xform)
						imgui.tree_pop()
					end
					local sweetlight = cam_xform:call("find", "SweetLight")
					if sweetlight and imgui.tree_node("SweetLight") then
						managed_object_control_panel(sweetlight)
						imgui.tree_pop()
					end
				end

				if imgui.tree_node("LightProbes") then
					cached_lightprobes = lua_get_system_array(scene:call("findComponents(System.Type)", sdk.typeof("via.render.LightProbes")):add_ref()) or cached_lightprobes
					for i, prb in ipairs(cached_lightprobes) do
						local name = prb:get_GameObject():get_Name()
						if imgui.tree_node(name) then
							managed_object_control_panel(prb, name)
							imgui.tree_pop()
						end
					end
					imgui.tree_pop()
				end

				local scene_layer
				pcall(function() scene_layer = sdk.to_managed_object(sdk.to_valuetype(renderer:read_qword(152), "System.UInt64").mValue) end)

				if scene_layer and imgui.tree_node("Scene Layer") then
					managed_object_control_panel(scene_layer)
					imgui.tree_pop()
				end

				imgui.end_rect(2)
				imgui.tree_pop()
			end



			draw_named_node("SF6 Tools")

			if was_changed then
				hk.update_hotkey_table(freecam_settings.hotkeys)
				dump_settings()
			end

		imgui.end_rect(3)
		imgui.text("																				By alphaZomega")
		imgui.tree_pop()
		end
		imgui.spacing()
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
