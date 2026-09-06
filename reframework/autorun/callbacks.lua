function printTable(tbl, indent)
    indent = indent or 0

    local spacing = string.rep("  ", indent)

    for key, value in pairs(tbl) do
        if type(value) == "table" then
            print(spacing .. tostring(key) .. " = {")
            printTable(value, indent + 1)
            print(spacing .. "}")
        else
            print(spacing .. tostring(key) .. " = " .. tostring(value))
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
			if runtime.imgui.tree_node("SF6 Tools") then
				runtime.imgui.begin_rect()
				if state.graphics_settings_mgr and runtime.imgui.tree_node("Graphics") then
					fn.managed_object_control_panel(state.graphics_settings_mgr)
					runtime.imgui.tree_pop()
				end
				state.changed, sf6.sf6_data.distortion_idx = runtime.imgui.combo("2D Distortion Effect", sf6.sf6_data.distortion_idx, {"Auto", "On", "Off"})
				if state.changed then
					sf6.distortion_on = ((sf6.sf6_data.distortion_idx == 1 and not state.freecam_on) or sf6.sf6_data.distortion_idx==2)
					fn.change_player_mat_params("FixProjection_Switch", (sf6.distortion_on and 1.0) or 0.0)
				end

				state.changed, sf6.sf6_data.overlap_idx = runtime.imgui.combo("Overlapping Fighters", sf6.sf6_data.overlap_idx, {"Auto", "On", "Off"})
				if state.changed then
					sf6.sf6_data.overlap_on = ((sf6.sf6_data.overlap_idx == 1 and not state.freecam_on) or sf6.sf6_data.overlap_idx==2)
				end

				state.changed, sf6.sf6_data.fps_idx = runtime.imgui.combo("Frame Rate", sf6.sf6_data.fps_idx, {"60fps", "30fps", "120fps"})
				if state.changed then
					runtime.sdk.find_type_definition("app.Helper"):get_method("setAplicationFPS"):call(nil, (sf6.sf6_data.fps_idx==2 and 1) or (sf6.sf6_data.fps_idx==3 and 6) or 4, true)
				end

				state.changed, sf6.sf6_data.battle_damage_percent = runtime.imgui.slider_float("Set Battle Damage", sf6.sf6_data.battle_damage_percent, 0, 1)
				if state.changed then
					fn.change_player_mat_params("DamageLevel", sf6.sf6_data.battle_damage_percent)
				end
				fn.tooltip("Ctrl+click to type-in")
				state.changed, sf6.sf6_data.sweat_percent = runtime.imgui.slider_float("Set Sweat", sf6.sf6_data.sweat_percent, 0, 1)
				if state.changed then
					fn.change_player_mat_params("Sweat_Rate", sf6.sf6_data.sweat_percent)
				end
				fn.tooltip("Ctrl+click to type-in")

				state.changed, sf6.sf6_data.slow_motion_speed = runtime.imgui.slider_float("Slow Motion", sf6.sf6_data.slow_motion_speed, 0, 1)
				fn.tooltip("Use with 'Show Character Gizmos' to stop stuttering")
				if state.changed then
					sf6.sf6_data.speed_sfix = sf6.sf6_data.speed_sfix:call("From(System.Single)", sf6.sf6_data.slow_motion_speed)
					--sdk.find_type_definition("via.sfix"):get_method("From(System.Single)"):call(nil, sf6_data.slow_motion_speed)
				end

				state.changed, sf6.movechars_on = runtime.imgui.checkbox("Show Character Gizmos", sf6.movechars_on)

				if next(sf6.frozen_funcs) then
					if sf6.frozen_funcs[2] and not runtime.imgui.same_line() and runtime.imgui.button("Reset P1") then
						sf6.frozen_funcs[2] = nil
					end
					if sf6.frozen_funcs[1] and not runtime.imgui.same_line() and runtime.imgui.button("Reset P2") then
						sf6.frozen_funcs[1] = nil
					end
				end
				state.changed, sf6.movelights_on = runtime.imgui.checkbox("Show Character Lights Gizmos", sf6.movelights_on)

				if runtime.EMV then
					local changed1, changed2
					changed1, sf6.movestage_on = runtime.imgui.checkbox("Move Stage", sf6.movestage_on)
					runtime.imgui.same_line()
					changed2, sf6.movestage_only_lights = runtime.imgui.checkbox("Move Lights", sf6.movestage_only_lights)
					if changed1 or changed2 then
						camera.do_cam_orbit = false
						state.mot_fn = function() ; fn.setup_stage_attach(nil, nil, nil, true) end
					end

					if (sf6.movestage_only_lights or sf6.movestage_on) and next(camera.attached_children) and not runtime.imgui.same_line() then
						if runtime.imgui.button("Save") then
							state.mot_fn = function() ; fn.setup_stage_attach(false, true) end
						end
						fn.tooltip("Save the changes as the new default positions/rotations for the "..(sf6.movestage_on and "Stage" or "Lights").." (until reload)")
					end
					--if next(attached_children) and not imgui.same_line() and imgui.button("Center Axis") then
					--	temp_fn = reset_dummy_pos
					--end
					if (sf6.movestage_on or sf6.movestage_only_lights) and camera.dummy then
						local prefix = sf6.movestage_on and "Stage" or "Lights"
						local changed2, dummy_pos = runtime.imgui.drag_float3(prefix.." Position", camera.dummy.xform:call("get_Position"), 0.01, -10000, 10000)
						local changed1, dummy_rot = runtime.imgui.drag_float3(prefix.." Rotation", camera.dummy.xform:call("get_EulerAngle"), 0.01, -360, 360)
						local changed3, dummy_scale = runtime.imgui.drag_float3(prefix.." Scale", camera.dummy.xform:call("get_LocalScale"), 0.01, 0.001, 100.0)
						if changed1 or changed2 or changed3 then
							state.last_move_timer = os.clock()
							state.stage_rot_func = function()
								state.stage_rot_func = nil
								camera.dummy.xform:call("set_Position", dummy_pos)
								camera.dummy.xform:call("set_EulerAngle", dummy_rot)
								camera.dummy.xform:call("set_LocalScale", dummy_scale)
							end
						end

						if state.last_move_timer and os.clock() - state.last_move_timer > 0.25 then
							state.last_move_timer = nil
							fn.reset_dummy_pos()
						end
					end
				end

				if game.battleflow and runtime.imgui.tree_node("Stage Display") then
					runtime.imgui.begin_rect()
						local vfx_gameobj = game.scene:call("findGameObject(System.String)", "NoParentEffects")
						if vfx_gameobj then
							local changed, enabled = runtime.imgui.checkbox("Fighter VFX", vfx_gameobj:get_DrawSelf())
							if changed then  vfx_gameobj:set_DrawSelf(enabled) end
						end

						local stage_id = string.format("%04d", game.battleflow.m_desc.Stage.StageId * 0.01)
						local names = {"Env", "Light", "VFX", "Level", "High"}

						for i, name in ipairs(names) do
							local folder = game.scene:call("findFolder", "ess"..stage_id..((name=="High") and "_00v_" or "_00_")..name)
							if folder then
								local changed, enabled = runtime.imgui.checkbox(name, folder:get_DrawSelf())
								if changed then  folder:set_DrawSelf(enabled) end
								local bb = (name=="Env" and enabled) and game.scene:call("findFolder", "BillboardCrowd")
								if bb and not runtime.imgui.same_line() then
									changed, enabled = runtime.imgui.checkbox("BillboardCrowd", bb:get_DrawSelf())
									if changed then  bb:set_DrawSelf(enabled) end
								end
							end
						end
					runtime.imgui.end_rect(2)
					runtime.imgui.tree_pop()
				end

				for i=2, 1, -1 do
					local name = "P"..(i==2 and 1 or 2)
					runtime.imgui.push_id(name)
						state.changed, sf6.sf6_data["show_"..name] = runtime.imgui.checkbox("", sf6.sf6_data["show_"..name])
						if state.changed then
							for m, mesh in ipairs(fn.lua_get_system_array(fn.getC(sf6.players[i], "app.PlayerBehavior", true).mpMeshes) or {}) do
								mesh:call("set_Enabled", sf6.sf6_data["show_"..name])
							end
						end
						runtime.imgui.same_line()

						if runtime.imgui.tree_node(name) then
							runtime.imgui.begin_rect()
								local xform, changed1, changed2 = sf6.players[i]:get_GameObject():get_Transform(), nil, nil
								if sf6.movechars_on then
									changed1, sf6.sf6_data[name.."_pos"] = runtime.imgui.drag_float3(name.." Position", xform:call("get_Position"), 0.01, -10000, 10000)
									changed2, sf6.sf6_data[name.."_rot"] = runtime.imgui.drag_float3(name.." Rotation", xform:call("get_EulerAngle"), 0.01, -360, 360)
								end
								state.changed, sf6.sf6_data[name.."_scale"] = runtime.imgui.drag_float(name.." Scale", sf6.sf6_data[name.."_scale"], 0.001, 0.01, 50.0)
								if state.changed then
									xform:set_LocalScale(runtime.Vector3f.new(sf6.sf6_data[name.."_scale"], sf6.sf6_data[name.."_scale"], sf6.sf6_data[name.."_scale"]))
								end
								if changed1 or changed2 then
									sf6.frozen_funcs[i] = function()
										if not pcall(function()
											xform:set_Position(sf6.sf6_data[name.."_pos"])
											xform:set_EulerAngle(sf6.sf6_data[name.."_rot"])
										end) then
											sf6.frozen_funcs = {}
										end
									end
								end

								sf6.tps_dummy = (sf6.tps_dummy and sf6.tps_dummy.xform:get_Valid() and camera.dummy == sf6.tps_dummy) and sf6.tps_dummy

								if runtime.imgui.button(name.." Third Person") then
									state.do_third_person = true
									state.mot_fn = function()
										settings.freecam_settings.do_lookat = true
										if not sf6.tps_dummy then
											local gameobj = game.scene:call("findGameObject(System.String)", "TPSGizmo")
											sf6.tps_dummy = {gameobj = gameobj or runtime.sdk.find_type_definition("via.GameObject"):get_method("create(System.String)"):call(nil, "TPSGizmo"):add_ref()}
											sf6.tps_dummy.xform = sf6.tps_dummy.gameobj:get_Transform()
										end
										sf6.tps_dummy.xform:set_ParentJoint(sf6.tps_parent_joint_name or "C_Move")
										sf6.tps_dummy.xform:set_Parent(xform)
										local pos = xform:getJointByName("C_Hip"):get_Position()
										sf6.tps_dummy.xform:set_Position(runtime.Vector3f.new(pos.x, pos.y+0.25, pos.z))
										sf6.tps_mount = (sf6.tps_mount and sf6.tps_mount.xform:get_Valid()) and sf6.tps_mount
										if not sf6.tps_mount then
											local gameobj = game.scene:call("findGameObject(System.String)", "TPSMount")
											sf6.tps_mount = {gameobj = gameobj or runtime.sdk.find_type_definition("via.GameObject"):get_method("create(System.String)"):call(nil, "TPSMount"):add_ref()}
											sf6.tps_mount.xform = sf6.tps_mount.gameobj:get_Transform()
										end
										sf6.tps_mount.xform:set_Parent(sf6.tps_dummy.xform)
										local wm = xform:get_WorldMatrix()
										wm[3] = wm[3] + (wm[2]*-2.5)
										sf6.tps_mount.xform:set_Position(runtime.Vector3f.new(wm[3].x, wm[3].y+1.5, wm[3].z+0.5))
										camera.dummy = sf6.tps_dummy
										sf6.tps_mount.cam_attached = true
										camera.cam_attached = sf6.tps_mount
										camera.attached_children[sf6.tps_mount.xform] = {}
										camera.do_cam_orbit = true
										fn.move_to_light(sf6.tps_mount)
										fn.reset_dummy_pos(false, true)
									end
								end
								fn.tooltip("Creates a gizmo for orbiting on the fighter's hip and mounts the camera to it.\nWhile orbiting, use the mouse to rotate and hold "..runtime.hk.hotkeys.CModifier3.." + use the standard camera and zoom controls to manipulate position and distance to center")

								if sf6.tps_mount and camera.cam_attached and camera.cam_attached.xform == sf6.tps_mount.xform then --and not imgui.same_line() then
									--changed, freecam_settings.tps_unlocked = imgui.checkbox("Unlocked", freecam_settings.tps_unlocked)
									--tooltip("Hold ALT to lock/unlock")
									local bone_names = {}
									for i, bone in ipairs(fn.lua_get_system_array(xform:get_Joints())) do
										bone_names[i] = bone:get_Name()
									end
									state.changed, sf6.sf6_data.tps_parent_joint_name_idx = runtime.imgui.combo("Parent joint", sf6.sf6_data.tps_parent_joint_name_idx, bone_names)
									if state.changed then
										sf6.tps_parent_joint_name = bone_names[sf6.sf6_data.tps_parent_joint_name_idx]
										sf6.tps_dummy.xform:set_ParentJoint()
									end
								end

								if sf6.players[i].mpFace and runtime.imgui.tree_node(name.." Facial Animation") then

									local layer0 = sf6.players[i].mpFace:getLayer(0)
									local layer1 = sf6.players[i].mpFace:getLayer(1)
									local mnode = layer0:get_HighestWeightMotionNode()
									local mname = mnode and mnode:get_MotionName()
									local player_id = sf6.players[i]:get_GameObject():get_Name():match("esf(.+)v")
									settings.freecam_settings.sf6_anims = settings.freecam_settings.sf6_anims or {}
									settings.freecam_settings.sf6_anims[player_id] = settings.freecam_settings.sf6_anims[player_id] or {}
									sf6.sf6_data.anim_names[player_id] = sf6.sf6_data.anim_names[player_id] or {}
									if not sf6.sf6_data.anim_names[player_id][1] then
										for name, tbl in pairs(settings.freecam_settings.sf6_anims[player_id]) do table.insert(sf6.sf6_data.anim_names[player_id], name) end
										table.sort(sf6.sf6_data.anim_names[player_id], function(a, b) return a < b end)
									end

									runtime.imgui.same_line()
									runtime.imgui.text_colored(mname, 0xFFE0853D)

									state.changed, sf6.players[i]._Facial._IsEnable = runtime.imgui.checkbox("Action System", sf6.players[i]._Facial._IsEnable, 0.0, 1.0)
									fn.tooltip("Changes facial animations based on the current move\nLeave this on unless the game is not letting you seek in an animation")

									state.changed, sf6.sf6_data[name.."_animated_face"] = runtime.imgui.slider_float("Animation Rate", layer1:get_BlendRate(), 0.0, 1.0)
									if state.changed then
										layer1:set_BlendRate(sf6.sf6_data[name.."_animated_face"])
									end

									state.changed, sf6.sf6_data[name.."_face_motbank"] = runtime.imgui.drag_int("MotionBankID", layer0:get_MotionBankID(), 1, 0, 10000)
									if state.changed then
										layer0:set_MotionBankID(sf6.sf6_data[name.."_face_motbank"])
									end

									state.changed, sf6.sf6_data[name.."_face_motion"] = runtime.imgui.drag_int("MotionID", layer0:get_MotionID(), 1, 0, 10000)
									if state.changed then
										layer0:set_MotionID(sf6.sf6_data[name.."_face_motion"])
									end
									fn.tooltip("An animation is a MotionID within a MotionBankID")

									if mname and not settings.freecam_settings.sf6_anims[player_id][mname] then
										settings.freecam_settings.sf6_anims[player_id][mname] = {bank=sf6.sf6_data[name.."_face_motbank"], mot=sf6.sf6_data[name.."_face_motion"]}
										table.insert(sf6.sf6_data.anim_names[player_id], mname)
										table.sort(sf6.sf6_data.anim_names[player_id], function(a, b) return a < b end)
										state.was_changed = true
									end

									state.changed, sf6.sf6_data[name.."_select_anim_idx"] = runtime.imgui.combo("Select Anim", fn.find_index(sf6.sf6_data.anim_names[player_id], mname), sf6.sf6_data.anim_names[player_id])
									if state.changed then
										local old_speed = layer0:get_Speed()
										layer0:set_Speed(1000.0)
										local new_mot_name = sf6.sf6_data.anim_names[player_id][sf6.sf6_data[name.."_select_anim_idx"] ]
										local tbl = settings.freecam_settings.sf6_anims[player_id][new_mot_name]
										layer0:set_MotionBankID(tbl.bank)
										layer0:set_MotionID(tbl.mot)
										layer0:set_WrapMode(2) --loop
										state.mot_fn = function()
											layer0:set_Frame(0)
											layer0:set_Speed(old_speed)
										end
									end

									state.changed, sf6.sf6_data[name.."_animation_frame"] = runtime.imgui.slider_float("Frame", layer0:get_Frame(), 0, layer0:get_EndFrame())
									if state.changed then
										state.mot_fn = function() layer1:set_Frame(sf6.sf6_data[name.."_animation_frame"]) end
									end

									state.changed, sf6.sf6_data[name.."_animation_speed"] = runtime.imgui.slider_float("Speed", layer0:get_Speed(), 0, 1)
									if state.changed then
										state.mot_fn = function() layer0:set_Speed(sf6.sf6_data[name.."_animation_speed"]) end
									end

									runtime.imgui.tree_pop()
								end

								if runtime.EMV then
                                    log.debug("Inside EMV")
									local go = game.held_transforms[xform] or runtime.EMV.GameObject:new{xform=xform}

                                    table_string = printTable(go)
                                    --fs.write("LOGS/go_table.txt", table_string)

									runtime.EMV.imgui_anim_object_viewer(go)
								end
							runtime.imgui.end_rect(2)
							runtime.imgui.tree_pop()
						end
					runtime.imgui.pop_id()
				end
				runtime.imgui.end_rect(2)
				runtime.imgui.tree_pop()
			end
		else
			runtime.imgui.text()
			runtime.imgui.spacing()
		end
	end

	local function draw_lua_freecam_root(node)
		if runtime.imgui.tree_node(node.name) then

		state.is_drawing_freecam_ui = true
		state.graphics_settings_mgr = game.isSF6 and runtime.sdk.get_managed_singleton("app.GraphicsSettingsManager")

		runtime.imgui.spacing()

		runtime.imgui.begin_rect()

				draw_named_node("Enable FreeCam")
				draw_named_node("Hide UI")
				draw_named_node("2x Quality")

				--[[if (defaults.img_quality or 0) > 1.0 and not imgui.same_line() and imgui.button("Reset to 1.0") then
					freecam_settings.img_quality = 1.0
					sdk.call_native_func(sdk.get_native_singleton("via.render.Renderer"), sdk.find_type_definition("via.render.Renderer"), "set_ImageQualityRate", 1.0)
				end]]

				draw_named_node("Freeze Time & Scene")
				draw_named_node("Orthographic Cam")

				if camera.cam then

					draw_named_node("Enable Cam Light")

					if true then

					runtime.imgui.begin_rect()
					if game.should_expand_cam_lights_menu then
						game.should_expand_cam_lights_menu = nil
						runtime.imgui.set_next_item_open(true)
					end

					if runtime.imgui.tree_node_str_id("FL", camera.cam_light and camera.cam_light.gameobj:get_Name() or "Cam Light Settings") then

						if #camera.cam_lights < 10 and not runtime.imgui.same_line() then
							if runtime.imgui.button("Create New") then
								fn.create_new_cam_light()
								camera.cam_light.selected = true
							end
							fn.tooltip("Create a new camera light, detaching the old one at the current position")
							runtime.imgui.same_line()
						end

						if camera.cam_light then

							if runtime.imgui.button("Set Shadows") then
								state.was_changed = true
								camera.cam_light.light:call("set_ForceShadowCacheEnable", false)
								state.temp_fn = function()
									camera.cam_light.light:call("set_ForceShadowCacheEnable", true)
								end
							end
							fn.tooltip("Enables shadow-casting on some lights")

							runtime.imgui.same_line()
							if runtime.imgui.button(camera.cam_light.attached and "Detach" or "Attach") then
								fn.attach_detach(camera.cam_light)
							end
							fn.tooltip("Hotkey: " .. runtime.hk.hotkeys["Attach/Detach Selected Light"])

							if camera.cam_light.light:call("get_ForceShadowCacheEnable") and not runtime.imgui.same_line() and runtime.imgui.button("Clear Shadow Cache") then
								camera.cam_light.light:call("set_ForceShadowCacheEnable", false)
							end

							local val_names = {"_Color", "_Intensity", "_Radius", "_Cone", "_Spread", "_Falloff", "_ShadowBias"}
							local intensity_increment = ((game.isMHR or game.isRE7) and 0.1*game.candela_multi) or 1.0*game.candela_multi --or (isDMC and 10.0*candela_multi)

							for i, val_name in ipairs(val_names) do
								if val_name=="_Color" then
									state.changed, settings.freecam_settings.light_settings[val_name] = runtime.imgui.color_edit3(val_name, camera.cam_light.light:call("get_Color"), 17301504); mark_changed()
								elseif val_name=="_ShadowBias" then
									state.changed, settings.freecam_settings.light_settings[val_name] = runtime.imgui.drag_float(val_name, camera.cam_light.light:call("get"..val_name), 0.0000001, 0, 1.0, "%.7f"); mark_changed()
								else
									state.changed, settings.freecam_settings.light_settings[val_name] = runtime.imgui.drag_float(val_name, camera.cam_light.light:call("get"..val_name), (i==2 and intensity_increment) or 0.01, -100000.0, 100000.0); mark_changed()
								end
								if val_name == "_Intensity" then fn.tooltip("Press "..runtime.hk.hotkeys.CModifier.." + "..runtime.hk.hotkeys["Zoom Out"].." to increase\nPress "..runtime.hk.hotkeys.CModifier.." + "..runtime.hk.hotkeys["Zoom In"].." to decrease") end
								if state.changed then
									camera.cam_light.light:call("set"..val_name, settings.freecam_settings.light_settings[val_name])
									if state.do_force_shadow_bias and val_name == "_ShadowBias" then
										fn.apply_shadow_bias(settings.freecam_settings.light_settings[val_name])
									end
								end
							end
							if runtime.imgui.button("Reset to Defaults") then
								for i, val_name in ipairs(val_names) do
									settings.freecam_settings.light_settings[val_name] = settings.default_settings.light_settings[val_name]
									camera.cam_light.light:call("set"..val_name, settings.default_settings.light_settings[val_name])
								end
								state.was_changed = true
							end
							runtime.imgui.same_line()
							state.changed, state.do_force_shadow_bias = runtime.imgui.checkbox("Force Shadow Bias Everywhere", state.do_force_shadow_bias)
							fn.tooltip("Forces all lights to use this shadow bias")
						end

						runtime.imgui.spacing()
						runtime.imgui.text_colored("Existing Lights:", 0xFFCCFFFF)

						if camera.pos_before_teleport and not runtime.imgui.same_line() and runtime.imgui.button("Return to last Camera Position") then
							for i, other_light in ipairs(camera.cam_lights) do other_light.cam_attached = false end
							camera.last_pos_and_rot = camera.pos_before_teleport
							camera.pos_before_teleport = nil
						end

						if camera.cam_lights[1] then
							state.changed, state.show_cam_lights = runtime.imgui.checkbox("Show Positions", state.show_cam_lights)
							fn.tooltip("Display the lights position as green text in the world")
						end

						if runtime.EMV and (not camera.cam_lights[1] or not runtime.imgui.same_line()) then

							state.changed, camera.do_cam_orbit = runtime.imgui.checkbox("Orbit Gizmo", camera.do_cam_orbit)
							fn.tooltip("Creates a gizmo to move and rotate detached cam lights\nDisabled and attached lights will not orbit\nHold " .. runtime.hk.hotkeys["CModifier"] .. " to move gizmo independently from its children")
							if state.changed and (camera.do_cam_orbit or next(camera.attached_children)) then
								state.mot_fn = function()  fn.setup_stage_attach() end
							end

							local dummy_gameobj = not camera.dummy and game.scene:call("findGameObject(System.String)", "FreeCamGizmo")
							camera.dummy = camera.dummy or (dummy_gameobj and {gameobj=dummy_gameobj, xform=dummy_gameobj:get_Transform()})

							if camera.do_cam_orbit then
								runtime.imgui.same_line()
								if runtime.imgui.button("Save") then
									state.mot_fn = function() fn.setup_stage_attach(false, true) end
									camera.do_cam_orbit = false
								end
								fn.tooltip("Saves the orbited camera positions")
							end

							if camera.dummy then
								state.changed, state.do_third_person = runtime.imgui.checkbox("Allow Mouse Control", state.do_third_person)
								fn.tooltip("Allows the mouse to move the camera after clicking 'Move To' on a light (with an Orbit Gizmo)")
								runtime.imgui.same_line()
								if runtime.imgui.button("Move Gizmo to Cam") then
									state.mot_fn = function()
										camera.dummy.xform:set_Position(camera.last_camera_matrix[3]:to_vec3())
									end
								end
								fn.tooltip("Moves the gizmo and lights the camera")

								runtime.imgui.same_line()
								if runtime.imgui.button("Reset Xform") then
									fn.reset_dummy_pos(false, true)
								end
								fn.tooltip("Resets the gizmo's rotation and scale without moving lights")

								if camera.do_cam_orbit then
									local changed, position = runtime.imgui.drag_float3("Gizmo Position", camera.dummy.xform:get_Position(), 0.01, -10000, 10000)
									if changed then state.mot_fn = function() camera.dummy.xform:call("set_Position", position); fn.light_lookat_fn(true) end end
									local changed, rotation = runtime.imgui.drag_float3("Gizmo Rotation", camera.dummy.xform:get_EulerAngle(), 0.01, -10000, 10000)
									if changed then state.mot_fn = function() camera.dummy.xform:call("set_EulerAngle", rotation); fn.light_lookat_fn() end end
									local old_scale = camera.dummy.xform:get_LocalScale()
									local changed, scale = runtime.imgui.drag_float3("Gizmo Scale", old_scale, 0.001, -10000, 10000)
									if changed then
										if settings.freecam_settings.change_scale_together then
											if old_scale.x ~= scale.x then scale = runtime.Vector3f.new(scale.x, scale.x, scale.x)
											elseif old_scale.y ~= scale.y then scale = runtime.Vector3f.new(scale.y, scale.y, scale.y)
											elseif old_scale.z ~= scale.z then scale = runtime.Vector3f.new(scale.z, scale.z, scale.z) end
										end
										state.mot_fn = function()
											camera.dummy.xform:call("set_LocalScale", scale); fn.light_lookat_fn()
											if camera.pos_before_teleport then fn.reset_dummy_pos(false, 1) end
										end
									end
									changed, settings.freecam_settings.do_lookat = runtime.imgui.checkbox("Look at Gizmo", settings.freecam_settings.do_lookat)
									fn.tooltip("Orbiting lights always point towards the gizmo")
									runtime.imgui.same_line()
									changed, settings.freecam_settings.change_scale_together = runtime.imgui.checkbox("Scale XYZ", settings.freecam_settings.change_scale_together)
									fn.tooltip("Scale X, Y and Z together")
									runtime.imgui.same_line()
									changed, settings.freecam_settings.tps_unlocked = runtime.imgui.checkbox("Unlocked", settings.freecam_settings.tps_unlocked)
									fn.tooltip("After clicking 'Move To' on an orbiting light, hold ALT to lock/unlock")
								end
							end
						end

						runtime.imgui.spacing()

						for i, light in ipairs(camera.cam_lights) do

							light.selected = camera.cam_light and (light.gameobj==camera.cam_light.gameobj)
							if light.selected then runtime.imgui.begin_rect() runtime.imgui.begin_rect() end

							runtime.imgui.push_id("sw"..i)
							state.changed, light.enabled = runtime.imgui.checkbox("", light.gameobj:call("get_DrawSelf") and light.light:get_Enabled())
							fn.tooltip("Enable/Disable this light")
							if state.changed then
								light.gameobj:call("set_DrawSelf", light.enabled)
								light.light:set_Enabled(light.enabled)
							end
							runtime.imgui.same_line()

							if camera.dummy then
								runtime.imgui.push_id("sz"..i)
								state.changed, light.orbiting = runtime.imgui.checkbox("", light.orbiting)
								fn.tooltip("Orbit this light around the Orbit Gizmo")
								runtime.imgui.same_line()
								runtime.imgui.pop_id()
								if state.changed then
									camera.attached_children[light.xform] = light.orbiting and (camera.attached_children[light.xform] or light)
									light.xform:call("set_Parent", light.orbiting and camera.dummy.xform or nil)
								end
							end

							if runtime.imgui.button("Select") then
								camera.cam_light = light
							end
							fn.tooltip("Makes light hotkeys and the light control panel be used for this light")

							runtime.imgui.same_line()
							if runtime.imgui.button("Del") then
								state.temp_fn = function()
									camera.cam_lights_map[light.gameobj] = nil
									light.gameobj:call("destroy", light.gameobj)
									local idx = tonumber(light.gameobj:get_Name():match(".*(%d)"))+1
									table.remove(camera.cam_lights, idx)
									for i, light in ipairs(camera.cam_lights) do
										light.gameobj:set_Name("FreeCamLight"..i-1)
									end
									if light.selected then
										camera.cam_light = camera.cam_lights[idx-1] or camera.cam_lights[idx]
										state.freecam_light_enabled = camera.cam_light and state.freecam_light_enabled
									end
									camera.do_cam_orbit = camera.cam_lights[1] and camera.do_cam_orbit
								end
							end
							fn.tooltip("Delete this light")

							runtime.imgui.same_line()
							if runtime.imgui.button(light.attached and "Detach" or "Attach") then
								fn.attach_detach(light)
							end
							fn.tooltip("Attach or Detach this light from the camera")

							local cam_no = light.gameobj:get_Name():match(".*(%d)")

							if not light.attached then
								runtime.imgui.same_line()
								if (runtime.imgui.button("Move To")) then
									fn.move_to_light(light)
								end
								fn.tooltip("Teleport the camera to this light\nThe camera will move with this light when it or its orbit gizmo is moved or rotated"..
								"\nWhile orbiting, use the mouse to rotate and hold "..runtime.hk.hotkeys.CModifier3.." + use the standard camera and zoom controls to manipulate position and distance to center"..
								"\nHotkey: ".. runtime.hk.hotkeys["Move to Light "..cam_no])
							end
							runtime.imgui.pop_id()

							if not runtime.imgui.same_line() and runtime.imgui.tree_node(light.gameobj:get_Name()) then
								local changed, position = runtime.imgui.drag_float3("Position", light.xform:get_Position(), 0.01, -10000, 10000)
								if changed then
									if light.orbiting and camera.dummy then light.xform:set_Parent(nil) end
									light.xform:call("set_Position", position)
									if light.orbiting and camera.dummy then
										fn.light_lookat_fn()
										state.temp_fn = function() light.xform:set_Parent(camera.dummy.xform) end
									end
								end
								local changed, rotation = runtime.imgui.drag_float3_euler("Rotation", light.orbiting and camera.dummy and camera.dummy.xform:get_EulerAngle() or light.xform:get_EulerAngle(), 0.01, -10000, 10000)
								if changed then
									if light.orbiting and camera.dummy then
										state.temp_fn = function()
											fn.move_light_by_dummy_independently(light, function() camera.dummy.xform:call("set_EulerAngle", rotation); fn.light_lookat_fn()  end)
										end
									else
										light.xform:call("set_EulerAngle", rotation)
									end
								end
								changed = runtime.hk.hotkey_setter("Move to Light "..cam_no); mark_changed()
								fn.tooltip("Use with secondary modifier '"..runtime.hk.hotkeys["CModifier2"].." + "..runtime.hk.hotkeys["Move to Light "..cam_no].."' to enable/disable lights")

								if runtime.imgui.tree_node("GameObject") then
									fn.managed_object_control_panel(light.xform)
									runtime.imgui.tree_pop()
								end
								runtime.imgui.tree_pop()
							end
							if light.selected then runtime.imgui.end_rect(2) runtime.imgui.end_rect(3) end
						end

						if camera.dummy then
							if runtime.imgui.button("Save Light Configuration") and ui.imgui_data.lightconfig_text:len() > 0 then
								state.txt = ui.imgui_data.lightconfig_text:gsub("%.json", "") .. ".json"
								local to_dump = {}
								for i, light in ipairs(camera.cam_lights) do
									if light.orbiting then
										local pos, rot = light.xform:get_LocalPosition(), light.xform:get_LocalRotation()
										to_dump[i] = {
											pos = {pos.x, pos.y, pos.z},
											rot = {rot.x, rot.y, rot.z, rot.w},
										}
									end
								end
								if runtime.json.dump_file("LuaFreeCam\\LightConfigs\\"..state.txt, to_dump) then
									state.was_changed, ui.lightconfigs_glob = true
									runtime.re.msg("Saved to\nreframework\\data\\LuaFreeCam\\LightConfigs\\"..state.txt)
								end
							end
							--tooltip("Input new skill name and save the current settings to a json file in\n[DD2 Game Directory]\\reframework\\data\\SkillMaker\\Skills\\")

							runtime.imgui.same_line()
							state.changed, ui.imgui_data.lightconfig_text = runtime.imgui.input_text("  ", ui.imgui_data.lightconfig_text)

							local clicked_button = runtime.imgui.button("Load Light Configuration")
							fn.tooltip("Load settings from a json file in\n[DD2 Game Directory]\\reframework\\data\\LuaFreeCam\\LightConfigs\\")
							runtime.imgui.same_line()

							state.changed, ui.imgui_data.lightconfig_idx = runtime.imgui.combo(" ", ui.imgui_data.lightconfig_idx, ui.lightconfig_names)

							if clicked_button then
								local lightconfig = runtime.json.load_file(ui.lightconfigs_glob[ui.imgui_data.lightconfig_idx])
								local frames = 0
								state.temp_fns.setup_lightconfig = function()
									state.temp_fns.setup_lightconfig = frames < 5 and state.temp_fns.setup_lightconfig or nil
									frames = frames + 1
									for j, light_json in ipairs(lightconfig) do --I dont know why the fuck this has to run 5 times to take effect
										local light = camera.cam_lights[j] or fn.create_new_cam_light()
										light.xform:set_Parent(nil)
										light.xform:set_Parent(camera.dummy.xform)
										light.xform:set_LocalPosition(runtime.Vector3f.new(light_json.pos[1], light_json.pos[2], light_json.pos[3]))
										light.xform:set_LocalRotation(runtime.Quaternion.new(light_json.rot[4], light_json.rot[1], light_json.rot[2], light_json.rot[3]))
									end
								end
								state.temp_fns.setup_lightconfig()
								state.was_changed, ui.lightconfigs_glob = true
							end

							if runtime.EMV and runtime.imgui.tree_node("Gizmo") then
								fn.managed_object_control_panel(camera.dummy.xform)
								runtime.imgui.tree_pop()
							end
						end

						if state.was_changed then
							state.freecam_light_enabled = true
							fn.create_or_toggle_cam_light()
						end

						runtime.imgui.tree_pop()
					end
					runtime.imgui.spacing()
					runtime.imgui.end_rect(2)
				end

				state.changed, settings.freecam_settings.use_quick_zoom = runtime.imgui.checkbox(settings.freecam_settings.use_quick_zoom and "Quick Zoom:" or "Quick Zoom", settings.freecam_settings.use_quick_zoom); mark_changed()
				fn.tooltip("Press the Quick Zoom key/button to zoom in from the game's current FOV to the Zoom FOV")
				if state.changed and state.use_frozen_fov and not settings.freecam_settings.use_quick_zoom then --and frozenFOV == freecam_settings.zoom_fov then
					state.use_frozen_fov, state.frozenFOV = false
				end
				if settings.freecam_settings.use_quick_zoom then
					runtime.imgui.same_line()
					state.changed = runtime.hk.hotkey_setter("Quick Zoom", nil, true); mark_changed()
					runtime.imgui.same_line()
					if runtime.imgui.button("Reset Quick Zoom") then
						state.was_changed = true
						settings.freecam_settings.zoom_fov = settings.default_settings.zoom_fov
						settings.freecam_settings.zoom_speed = settings.default_settings.zoom_speed
					end
					state.changed, settings.freecam_settings.zoom_fov = runtime.imgui.drag_float("Quick Zoom FOV", settings.freecam_settings.zoom_fov, 0.1, 0.1, 180.0, "%.4f"); mark_changed()
					state.changed, settings.freecam_settings.zoom_speed = runtime.imgui.drag_float("Quick Zoom Speed", settings.freecam_settings.zoom_speed, 0.01, 0.1, 10.0, "%.4f"); mark_changed()
				end
				local had_frozen_fov = state.use_frozen_fov
				runtime.imgui.push_id("frz")
					state.changed, state.use_frozen_fov = runtime.imgui.checkbox((state.use_frozen_fov and "") or "Freeze FOV", state.use_frozen_fov or state.frozenFOV)
				runtime.imgui.pop_id()
				if state.changed and not state.use_frozen_fov then state.frozenFOV = nil end
				if state.use_frozen_fov and had_frozen_fov == state.use_frozen_fov then
					runtime.imgui.same_line()
					state.changed, state.frozenFOV = runtime.imgui.drag_float("Freeze FOV", state.frozenFOV or camera.cam:call("get_FOV"), 0.1, 0.1, 180.0)
				end

				local changed2
				state.changed, ui.mount_obj_name = runtime.imgui.input_text("Mount Object Name", ui.mount_obj_name)
				fn.tooltip("Enter the name of a GameObject to mount the camera to it")
				if ui.mount_obj_name ~= "" then
					changed2, ui.mount_obj_jname = runtime.imgui.input_text("Mount Joint Name", ui.mount_obj_jname)
					fn.tooltip("Enter the name of a joint belonging to the Mount Object to mount the camera to that joint")
				end
				if state.changed or changed2 then
					local mount_obj = game.scene:call("findGameObject(System.String)", ui.mount_obj_name)
					if mount_obj then
						local xform = mount_obj:get_Transform()
						local bone = xform:getJointByName(ui.mount_obj_jname) or xform:get_Joints()[0]

						ui.mounting_fn = function()
							ui.mounting_fn = mount_obj and mount_obj:get_Valid() and ui.mounting_fn or nil
							return ui.mounting_fn and bone:get_Position()
						end
					end
				end

			end

			pcall(function()
				camera.sceneview = runtime.sdk.call_native_func(runtime.sdk.get_native_singleton("via.SceneManager"), game.scene_mgr_typedef, "get_MainView")
				state.changed, state.display_mode = runtime.imgui.combo("Display Mode", state.display_mode or camera.sceneview:call("get_DisplayType")+1, game.display_type_names)
				if state.changed then
					camera.sceneview:call("set_DisplayType", state.display_mode - 1)
				end
			end)

			state.changed, settings.freecam_settings.rot_speed = runtime.imgui.drag_float("Cam Rotation Speed", settings.freecam_settings.rot_speed, 0.01, 0, 100); mark_changed()

			state.changed, settings.freecam_settings.dir_speed = runtime.imgui.drag_float("Cam Movement Speed", settings.freecam_settings.dir_speed, 0.5, 0, 100); mark_changed()

			state.changed, settings.freecam_settings.control_type = runtime.imgui.combo("Cam Control Type", settings.freecam_settings.control_type, {"Mouse + Gamepad", "Mouse", "Gamepad"})
			fn.tooltip("Which means of input controls the free camera's direction")

			state.changed, settings.freecam_settings.do_invert_pad = runtime.imgui.checkbox("Invert Gamepad Y", settings.freecam_settings.do_invert_pad)
			fn.tooltip("Flip the Y-axis when controlling the freecam via GamePad")

			if settings.freecam_settings.do_invert_pad ~= 2 then
				state.changed, state.disable_all_efx = runtime.imgui.checkbox("Disable VFX", state.disable_all_efx)
				fn.tooltip("Tries to disable all Visual Effects")
			end

			runtime.imgui.same_line()

			state.changed, state.disable_all_lights = runtime.imgui.checkbox("Disable Lights", state.disable_all_lights)
			fn.tooltip("Tries to disable all via.render.Lights")

			if not runtime.EMV then
				runtime.imgui.same_line()
				runtime.imgui.text_colored("Install EMV Engine to enable extra features", 0xFF0000FF)
				fn.tooltip("https://github.com/alphazolam/EMV-Engine")
			end

			if state.changed then
				state.temp_fn = function()
					for n, name in ipairs({"Light", "LightProbes"}) do
						for i, light in ipairs(fn.lua_get_system_array(game.scene:call("findComponents(System.Type)", runtime.sdk.typeof("via.render."..name)))) do
							if state.disable_all_lights and not camera.cam_lights_map[light:get_GameObject()] then
								lighting.all_lights[light] = light:get_Enabled()
								light:set_Enabled(false)
								light:get_GameObject():set_DrawSelf(false)
							elseif lighting.all_lights[light] ~= nil then
								light:set_Enabled(lighting.all_lights[light])
								light:get_GameObject():set_DrawSelf(lighting.all_lights[light])
							end
						end
					end
				end
			end

			if runtime.imgui.tree_node("Hotkeys") then
				runtime.imgui.spacing()
				runtime.imgui.text()
				runtime.imgui.same_line()
				runtime.imgui.begin_rect()
					state.changed = runtime.hk.hotkey_setter("Activate FreeCam"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Toggle FreeCam Light"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("2x Quality"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Hide UI"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Create New Light"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Attach/Detach Selected Light"); mark_changed()
					runtime.imgui.text("Modifier:"); runtime.imgui.same_line()
					state.changed = runtime.hk.hotkey_setter("CModifier", nil, true); mark_changed()
					runtime.imgui.same_line()
					state.changed = runtime.hk.hotkey_setter("CModifier2", nil, true); mark_changed()
					runtime.imgui.text("Modifier 2:"); runtime.imgui.same_line()
					state.changed = runtime.hk.hotkey_setter("CModifier3", nil, true); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Cam Forward"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Cam Backward"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Cam Left"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Cam Right"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Cam Up"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Cam Down"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Roll Left"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Roll Right"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Freeze Camera"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Zoom In"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Zoom Out"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Reset Zoom"); mark_changed()
					state.changed = runtime.hk.hotkey_setter("Freeze Time & Scene"); mark_changed()

					if game.isSF6 then
						state.changed = runtime.hk.hotkey_setter("Freeze Time"); mark_changed()
					end
					state.changed = runtime.hk.hotkey_setter("Skip Frame"); mark_changed()
					if game.isRE8 then
						state.changed = runtime.hk.hotkey_setter("Unequip Weapons (RE8)"); mark_changed()
					end

					runtime.imgui.text_colored("	Hold [Modifier] to move/rotate at 3x speed\n", 0xFFCCFFFF)
					runtime.imgui.text_colored("	Hold [Modifier2] to move/rotate at 1/3rd speed\n", 0xFFCCFFFF)
					runtime.imgui.text_colored("	Press [Modifier] + Roll to reset roll\n", 0xFFCCFFFF)
					runtime.imgui.text_colored("	Hold [Modifier2] and use camera controls when attached to an orbiting cam light to move and rotate it\n", 0xFFCCFFFF)
					if game.isSF6 then
						runtime.imgui.text_colored("	Hold [Modifier] and press [Freeze Time] to freeze the scene only", 0xFFCCFFFF)
					end
					if runtime.imgui.button("Reset to Defaults") then
						--[[freecam_settings.hotkeys = {}
						for k, v in pairs(default_settings.hotkeys) do freecam_settings.hotkeys[k] = default_settings.hotkeys[k] end
						hotkeys = freecam_settings.hotkeys]]
						settings.freecam_settings.hotkeys = fn.recurse_def_settings({}, settings.default_settings.hotkeys)
						runtime.hk.reset_from_defaults_tbl(settings.default_settings.hotkeys)
						runtime.hk.update_hotkey_table(settings.freecam_settings.hotkeys)
						fn.dump_settings()
					end
				runtime.imgui.end_rect(3)
				runtime.imgui.tree_pop()
			end

			if camera.cam_xform and runtime.imgui.tree_node("Visual Settings") then

				runtime.imgui.begin_rect()

					local try, renderer = pcall(camera.cam_gameobj.call, camera.cam_gameobj, "getComponent(System.Type)", runtime.sdk.typeof("via.render.RenderOutput"))

					if try and renderer then

						state.orig_render_output_id = renderer:call("get_RenderOutputID")
						local fog = 	 fn.getC(camera.cam_gameobj, "via.render.Fog")
						local tonemap = fn.getC(camera.cam_gameobj, "via.render.ToneMapping")
						local softbloom = fn.getC(camera.cam_gameobj, "via.render.SoftBloom")
						local dof = fn.getC(camera.cam_gameobj, "via.render.DepthOfField")
						local ssao = fn.getC(camera.cam_gameobj, "via.render.SSAOControl")
						local ldrpp = fn.getC(camera.cam_gameobj, "via.render.LDRPostProcess")
						local cc = ldrpp and ldrpp:call("get_ColorCorrect")
						local rt = game.can_rt and fn.getC(camera.cam_gameobj, "via.render.ExperimentalRayTrace")
						local filter = fn.getC(camera.cam_gameobj, "via.render.CustomFilter") or fn.getC(camera.cam_gameobj, "via.render.CustomFilterBeforeTransparent")
						local vol = fn.getC(camera.cam_gameobj, "via.render.VolumetricFogControl")

						state.changed, settings.freecam_settings.img_quality = runtime.imgui.slider_float("Default Image Quality", settings.freecam_settings.img_quality, 0.1, 1.0); mark_changed()
						fn.tooltip("The game will be internally rendered at this multiplier of your game resolution")

						state.changed, state.is_constant = runtime.imgui.checkbox("Constant Settings", state.is_constant)
						fn.tooltip("Forces settings every frame")

						if state.is_constant then
							runtime.imgui.same_line()
							state.changed, state.do_remember = runtime.imgui.checkbox("Remember", state.do_remember)
							fn.tooltip("Forces settings on every future camera")
						end
						local do_constant = state.is_constant and state.do_remember

						if dof then
							state.changed, state.dof_on = runtime.imgui.checkbox("Depth of Field (Blur)", do_constant and state.dof_on or not do_constant and dof:call("get_Enabled"))
							if state.changed or state.is_constant then
								dof:call("set_Enabled", state.dof_on)
							end
							if state.dof_on and not runtime.imgui.same_line() and runtime.imgui.tree_node_str_id("dof", "Options") then
								state.changed, state.dof_options.sensor_size = runtime.imgui.drag_float("Sensor Size", do_constant and state.dof_options.sensor_size or not do_constant and dof:get_SensorSize(), 0.01, 0, 100000)
								if state.changed or state.is_constant then
									dof:set_SensorSize(state.dof_options.sensor_size)
								end
								state.changed, state.dof_options.focus_distance = runtime.imgui.drag_float("Focus Distance", do_constant and state.dof_options.focus_distance or not do_constant and dof:get_FocusDistance(), 0.01, 0, 100000)
								if state.changed or state.is_constant then
									dof:set_FocusDistance(state.dof_options.focus_distance)
								end
								state.changed, state.dof_options.fnumber = runtime.imgui.drag_float("FNumber", do_constant and state.dof_options.fnumber or not do_constant and dof:get_FNumber(), 0.01, 0, 100000)
								if state.changed or state.is_constant then
									dof:set_FNumber(state.dof_options.fnumber)
								end
								state.changed, state.dof_options.use_fixed_fov = runtime.imgui.checkbox("Use Fixed FOV", do_constant and state.dof_options.use_fixed_fov or not do_constant and dof:call("get_EnableFixFOV"))
								if state.changed or state.is_constant then
									dof:set_EnableFixFOV(state.dof_options.use_fixed_fov)
								end
								if state.dof_options.use_fixed_fov then
									state.changed, state.dof_options.fixed_fov = runtime.imgui.drag_float("Fixed FOV", do_constant and state.dof_options.fixed_fov or not do_constant and dof:get_FOV(), 0.01, 0, 100000)
									if state.changed or state.is_constant then
										dof:set_FOV(state.dof_options.fixed_fov)
									end
								end
								runtime.imgui.tree_pop()
							end
						end

						if ssao then
							--if ssao_on and ssao.getSSAOAlgorithm then imgui.begin_rect() end
							state.changed, state.ssao_on = runtime.imgui.checkbox("SSAO", do_constant and state.ssao_on or not do_constant and ssao:call("get_Enabled"))
							if state.changed or state.is_constant then
								ssao:call("set_Enabled", state.ssao_on)
							end
							if state.ssao_on and ssao.getSSAOAlgorithm then
								runtime.imgui.same_line()
								state.changed, state.temporal_ssao = runtime.imgui.checkbox("Temporal SSAO", (ssao:getSSAOAlgorithm() == 1))
								if state.changed then
									ssao:setSSAOAlgorithm(state.temporal_ssao and 1 or 0)
								end
								state.changed, state.ssao_intensity = runtime.imgui.drag_float("SSAO Intensity", ssao:get_AOIntensity(), 0.01, 0.0, 50.0)
								if state.changed then
									ssao:set_AOIntensity(state.ssao_intensity)
								end
								state.changed, state.ssao_tint = runtime.imgui.color_edit3("SSAO Color", ssao:get_AOTint(), 17301504)
								if state.changed then
									ssao:set_AOTint(state.ssao_tint)
								end
							end
							--if ssao_on and ssao.getSSAOAlgorithm then imgui.end_rect(2) end
						end

						if softbloom then
							state.changed, state.softbloom_on = runtime.imgui.checkbox("SoftBloom", do_constant and state.softbloom_on or not do_constant and softbloom:call("get_Enabled"))
							if state.changed or state.is_constant then
								softbloom:call("set_Enabled", state.softbloom_on)
							end
						end

						if filter then
							state.changed, state.filter_on = runtime.imgui.checkbox("Custom Filter (Lut)", do_constant and state.filter_on or not do_constant and filter:call("get_Enabled"))
							if state.changed or state.is_constant then
								filter:call("set_Enabled", state.filter_on)
							end
							local fshader = state.filter_on and filter:getFilterShader(0)
							if fshader then
								local resource = fshader:get_Filter()
								local rpath = resource and resource:get_ResourcePath()
								if rpath and not settings.freecam_settings.cached_luts[rpath] then
									settings.freecam_settings.cached_luts[rpath] = true
									ui.filter_options.do_update = true
								end
								if ui.filter_options.do_update or (not ui.filter_options.mdf_names[1] and next(settings.freecam_settings.cached_luts)) then
									ui.filter_options.do_update = nil
									ui.filter_options.mdf_names = {}
									for path, non in pairs(settings.freecam_settings.cached_luts) do
										table.insert(ui.filter_options.mdf_names, path)
									end
									table.sort(ui.filter_options.mdf_names, function(a, b) return a < b end)
									fn.dump_settings()
								end
								if runtime.imgui.button(" + ") then
									ui.filter_options.show_mdf_input = not ui.filter_options.show_mdf_input
								end
								runtime.imgui.same_line()
								state.changed, ui.filter_options.filter_mdf_idx = runtime.imgui.combo("Lut MDF", ui.filter_options.filter_mdf_idx or fn.find_index(ui.filter_options.mdf_names, rpath or ""), ui.filter_options.mdf_names)
								if state.changed then
									local new_res = fn.create_resource("via.render.MeshMaterialResource", ui.filter_options.mdf_names[ui.filter_options.filter_mdf_idx])
									fshader:set_Filter(new_res)
								end
								if ui.filter_options.show_mdf_input then
									ui.filter_options.mdf_text_input = ui.filter_options.mdf_text_input or ui.filter_options.mdf_names[ui.filter_options.filter_mdf_idx]
									if runtime.imgui.button("Set") and not settings.freecam_settings.cached_luts[ui.filter_options.mdf_text_input] then
										local new_res = fn.create_resource("via.render.MeshMaterialResource", ui.filter_options.mdf_text_input)
										if new_res and runtime.sdk.find_type_definition("via.io.file"):get_method("exists"):call(nil, "natives/stm/"..ui.filter_options.mdf_text_input..ui.filter_options.mdf_exts[runtime.reframework:get_game_name()]) then
											settings.freecam_settings.cached_luts[ui.filter_options.mdf_text_input] = true
											ui.filter_options.do_update = true
											ui.filter_options.show_mdf_input = false
											fshader:set_Filter(new_res)
										end
									end
									runtime.imgui.same_line()
									state.changed, ui.filter_options.mdf_text_input = runtime.imgui.input_text("Input New Lut MDF", ui.filter_options.mdf_text_input)
								end
							end
						end

						if tonemap then
							state.changed, state.vignette_on = runtime.imgui.checkbox("Vignette", do_constant and state.vignette_on or not do_constant and (tonemap:call("getVignetting") ~= 2))
							if state.changed or state.is_constant then
								tonemap:call("setVignetting", (state.vignette_on and 0) or 2)
							end

							state.changed, state.ev_value = runtime.imgui.drag_float("EV", do_constant and state.ev_value or not do_constant and tonemap:call("get_EV"), 0.01, -15, 15)
							if state.changed or state.is_constant then
								tonemap:call("set_EV", state.ev_value)
							end

							state.changed, state.contrast = runtime.imgui.drag_float("Contrast", do_constant and state.contrast or not do_constant and tonemap:call("get_Contrast"), 0.01, 0, 15)
							if state.changed or state.is_constant then
								tonemap:call("set_Contrast", state.contrast)
							end
						end

						if cc then
							state.changed, state.cc_on = runtime.imgui.checkbox("Color Correction", do_constant and state.cc_on or not do_constant and cc:call("get_Enabled"), 0.01, 0, 15)
							if state.changed or state.is_constant then
								cc:call("set_Enabled", state.cc_on)
							end

							if state.cc_on and cc:call("get_LinearParamsCount")~=0 then
								for i=1, cc:call("get_LinearParamsCount") do
									state.cc_factors[i] = state.cc_factors[i] or {
										color=state.cc_item:call("get_LinearFactor"),
										type=state.cc_item:call("get_LinearCorrectorType")+1,
									}
									if runtime.imgui.tree_node("Color Parameter " .. i) then
										local cc_item = cc:call("getLinearParamsAt", i-1)
										state.changed, state.cc_factors[i].type = runtime.imgui.combo("Type", state.cc_factors[i].type or cc_item:call("get_LinearCorrectorType")+1, {"None", "Hue", "Chroma", "Brightness", "Sepia", "Scale", "NegiPosi", "GrayScale"})
										if state.changed or state.is_constant then
											cc_item:call("set_LinearCorrectorType", state.cc_factors[i].type-1)
										end
										state.changed, state.cc_factors[i].color = runtime.imgui.color_edit4("Linear Factor", state.cc_factors[i].color or cc_item:call("get_LinearFactor"), 17301504) -- fog:call("get_InscatteringColor")
										if state.changed or state.is_constant then
											cc_item:call("set_LinearFactor", state.cc_factors[i].color)
										end
										runtime.imgui.tree_pop()
									end
								end
							end
						end

						if vol then
							state.changed, state.vol_on = runtime.imgui.checkbox("Volumetric Fog", do_constant and state.vol_on or not do_constant and vol:call("get_Enabled"), 0.01, 0, 15)
							if state.changed or state.is_constant then
								vol:call("set_Enabled", state.vol_on)
							end
						end

						if game.can_rt then
							state.changed, state.rt_enabled = runtime.imgui.checkbox("Ray Tracing", rt and rt:get_Enabled())
							if state.changed or state.is_constant then
								if not rt and state.changed then
									camera.cam_gameobj:call("createComponent(System.Type)", runtime.sdk.typeof("via.render.ExperimentalRayTrace"))
									state.temp_fn = function()
										local rt = fn.getC(camera.cam_gameobj, "via.render.ExperimentalRayTrace")
										rt:set_RaytracingMode(6)
										rt:set_DenoiserDebugView(1)
									end
								elseif rt then
									rt:set_Enabled(state.rt_enabled)
								end
							end

							if rt then
								runtime.imgui.same_line()
								state.changed, state.rt_reflections_enabled = runtime.imgui.checkbox("Reflection", (rt:get_DenoiserDebugView()==0))
								if state.changed or state.is_constant then
									rt:set_DenoiserDebugView(state.rt_reflections_enabled and 0 or 1)
								end
								runtime.imgui.same_line()
								if runtime.imgui.tree_node_str_id("rt", "Options") then
									fn.managed_object_control_panel(rt)
									runtime.imgui.tree_pop()
								end
							end
						end

						if fog then
							local gs_name = (game.isSF6 and "Greenscreen") or "Fog"
							state.changed, state.greenscreen_on = runtime.imgui.checkbox(gs_name, state.greenscreen_on)
							if game.isSF6 then fn.tooltip("Works best in the 'Training Room' stage") end

							if state.changed or state.is_constant then
								if state.greenscreen_on then
									if game.isSF6 then renderer:call("set_RenderOutputID", 2) end
									fog:call("set_Enabled", true)
									fog:call("set_Intensity", 100.0)
									fog:call("set_HeightFalloff", 0.0)
									fog:call("set_InscatteringColor", state.gs_color or (game.isSF6 and runtime.Vector3f.new(0,1,0)) or runtime.Vector3f.new(1,1,1))
								elseif state.changed then
									renderer:call("set_RenderOutputID", ((game.isSF6 or game.isDMC or game.isMHR) and 1) or state.orig_render_output_id)
									if game.isSF6 or game.isRE3 then fog:call("set_Enabled", false) end
								end
							end

							if state.greenscreen_on then
								state.changed, state.gs_color = runtime.imgui.color_edit3(gs_name .. " Color", state.gs_color or (game.isSF6 and runtime.Vector3f.new(0,1,0)) or runtime.Vector3f.new(1,1,1), 17301504) -- fog:call("get_InscatteringColor")
								if state.changed or state.is_constant then
									fog:call("set_InscatteringColor", state.gs_color)
								end
							else
								runtime.imgui.text()
								runtime.imgui.spacing()
							end
						end

						state.constant_fn = state.is_constant and function()
							if camera.cam_gameobj then
								if dof and not pcall(dof.call, dof, "set_Enabled", state.dof_on)  then
									state.constant_fn = nil
									return nil
								end
								if ssao then ssao:call("set_Enabled", state.ssao_on) end
								if softbloom then softbloom:call("set_Enabled", state.softbloom_on) end
								if tonemap then
									tonemap:call("setVignetting", (state.vignette_on and 0) or 2)
									tonemap:call("set_EV", state.ev_value)
									tonemap:call("set_Contrast", state.contrast)
								end
								if cc then
									cc:call("set_Enabled", state.cc_on)
									if state.cc_on and cc:call("getLinearParamsCount")~=0 then
										for i=1, cc:call("get_LinearParamsCount") do
											local cc_item = cc:call("getLinearParamsAt", i-1)
											if state.cc_factors[i].type then
												cc_item:call("set_LinearCorrectorType", state.cc_factors[i].type-1)
												cc_item:call("set_LinearFactor", state.cc_factors[i].color)
											end
										end
									end
								end
								if fog then
									if state.greenscreen_on then
										if game.isSF6 then renderer:call("set_RenderOutputID", 2) end
										fog:call("set_Enabled", true)
										fog:call("set_Intensity", 100.0)
										fog:call("set_HeightFalloff", 0.0)
										fog:call("set_InscatteringColor", state.gs_color or (game.isSF6 and runtime.Vector3f.new(0,1,0)) or runtime.Vector3f.new(1,1,1))
									else
										renderer:call("set_RenderOutputID", ((game.isSF6 or game.isDMC or game.isMHR) and 1) or state.orig_render_output_id)
									--	if isSF6 or isRE3 then fog:call("set_Enabled", false) end
									end
								end
								if vol then
									vol:call("set_Enabled", state.vol_on)
								end
								if dof and state.dof_on then
									dof:set_SensorSize(state.dof_options.sensor_size)
									dof:set_FocusDistance(state.dof_options.focus_distance)
									dof:set_FNumber(state.dof_options.fnumber)
									dof:set_EnableFixFOV(state.dof_options.use_fixed_fov)
									if state.dof_options.use_fixed_fov then
										dof:set_FOV(state.dof_options.fixed_fov)
									end
								end
								if filter then
									filter:set_Enabled(state.filter_on)
								end
								if rt then
									rt:set_Enabled(state.rt_enabled)
								end
							end
						end
					end

				if camera.cam_xform and camera.cam_xform:read_qword(0x10) ~= 0 then
					if runtime.imgui.tree_node("Camera") then
						fn.managed_object_control_panel(camera.cam_xform)
						runtime.imgui.tree_pop()
					end
					local sweetlight = camera.cam_xform:call("find", "SweetLight")
					if sweetlight and runtime.imgui.tree_node("SweetLight") then
						fn.managed_object_control_panel(sweetlight)
						runtime.imgui.tree_pop()
					end
				end

				if runtime.imgui.tree_node("LightProbes") then
					lighting.cached_lightprobes = fn.lua_get_system_array(game.scene:call("findComponents(System.Type)", runtime.sdk.typeof("via.render.LightProbes")):add_ref()) or lighting.cached_lightprobes
					for i, prb in ipairs(lighting.cached_lightprobes) do
						local name = prb:get_GameObject():get_Name()
						if runtime.imgui.tree_node(name) then
							fn.managed_object_control_panel(prb, name)
							runtime.imgui.tree_pop()
						end
					end
					runtime.imgui.tree_pop()
				end

				local scene_layer
				pcall(function() scene_layer = runtime.sdk.to_managed_object(runtime.sdk.to_valuetype(renderer:read_qword(152), "System.UInt64").mValue) end)

				if scene_layer and runtime.imgui.tree_node("Scene Layer") then
					fn.managed_object_control_panel(scene_layer)
					runtime.imgui.tree_pop()
				end

				runtime.imgui.end_rect(2)
				runtime.imgui.tree_pop()
			end



			draw_named_node("SF6 Tools")

			if state.was_changed then
				runtime.hk.update_hotkey_table(settings.freecam_settings.hotkeys)
				fn.dump_settings()
			end

		runtime.imgui.end_rect(3)
		runtime.imgui.text("																				By alphaZomega")
		runtime.imgui.tree_pop()
		end
		runtime.imgui.spacing()
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
