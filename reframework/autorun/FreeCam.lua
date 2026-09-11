local ce = require("callbacks")

local is_sf6 = reframework.get_game_name():sub(1, 3):upper() == "SF6"
local players = {}
local sf6_color_editor_context

local function create_sf6_color_editor_context()
	return {
		is_sf6 = is_sf6,
		players = players,
		held_transforms = _G.held_transforms or {},
		runtime = {
			EMV = _G.EMV,
			imgui = imgui,
			json = json,
			re = re,
			sdk = sdk,
		},
	}
end

function display_sf6_color_editor()
	local context = sf6_color_editor_context or create_sf6_color_editor_context()
	sf6_color_editor_context = context

	ce.draw_sf6_color_editor(context, function()
		ce.draw_player_one(context, function()
			ce.draw_materials(context)
		end)
		ce.draw_player_two(context, function()
			ce.draw_materials(context)
		end)
	end)
end

re.on_draw_ui(function()
	display_sf6_color_editor()
end)

if is_sf6 then
	re.on_application_entry("UpdateHID", function()
		local player_manager = sdk.find_type_definition("gBattle"):get_field("PBManager"):get_data()
		local battle_players = player_manager.Players
		players[1], players[2] = battle_players[1], battle_players[0]
	end)
end
