extends Node

# here they'll be keyed by steam user ids
var tracked_players = {}
var connection

# The id of this player, in direct ip connections this will be 1 for the host.
# in steam connections this will be a steam id against which a username can
# be queried
var self_peer_id

# True iff the user hosted the lobby
var is_host = false

var is_source_of_truth = true
var game_mode = GameMode.VERSUS

enum GameMode {
	VERSUS, 
	COOP, 
}

# A counter user to assign ids for game components
var id_count = 0

var GameStateController = load("res://mods-unpacked/Pasha-Brotatogether/networking/game_state_controller.gd")

const toggle_scene = preload("res://mods-unpacked/Pasha-Brotatogether/ui/toggle.tscn")
const button_scene = preload("res://mods-unpacked/Pasha-Brotatogether/ui/button.tscn")
const explosion_scene = preload("res://projectiles/explosion.tscn")

var current_scene_name = ""
var run_updates = false
var disable_pause = false
var back_to_lobby = false
var all_players_ready = true

var ready_toggle

var extra_enemies_next_wave = {}
var effects_next_wave = {}
var game_state_controller 

signal complete_player_update

func _init():
	game_state_controller = GameStateController.new()
	game_state_controller.parent = self
	add_child(game_state_controller)

func _process(_delta):
	var scene_name = get_tree().get_current_scene().get_name()
	if is_coop() and is_host:
		# TODO i can't seem to override Shop.gd because it errors trying to get
		# a RunData field, we'll do this gargbage instead.
		if scene_name != current_scene_name:
			if current_scene_name == "Shop":
				# First frame where we left the shop
				var wave_data = {"current_wave":RunData.current_wave, "mode":game_mode}
				send_start_game(wave_data)
	if scene_name != current_scene_name:
		if scene_name == "Shop":
			enter_async_shop()
			
	current_scene_name = scene_name

func enter_async_shop() -> void:
	if $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer":
		$"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer".update_bought_items(tracked_players)
		
	if is_host:
		init_shop_go_button()
		
	else:
		$"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/GoButton".hide()
		$"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2".add_child(create_ready_toggle())

func create_extra_creatures_map() -> Dictionary:
	var extra_creatures_map = {}
	
	for player_id in tracked_players:
		extra_creatures_map[player_id] = tracked_players[player_id]["extra_enemies_next_wave"]
	return extra_creatures_map
	
func create_effects_map() -> Dictionary:
	var effects_map = {}
	
	for player_id in tracked_players:
		effects_map[player_id] = tracked_players[player_id]["effects"]
	
	return effects_map

func init_shop_go_button() -> void:
	var shop = get_tree().get_current_scene()
	var button = $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/GoButton"
	
	button.disconnect("pressed", shop, "_on_GoButton_pressed")
	button.connect("pressed", self, "_on_GoButton_pressed")
	
	update_go_button()

func _on_GoButton_pressed()-> void:
	var shop = get_tree().get_current_scene()
	if shop._go_button_pressed:
		return 
	
	shop._go_button_pressed = true
	
	extra_enemies_next_wave = create_extra_creatures_map()
	effects_next_wave = create_effects_map()
	
	RunData.current_wave += 1
	MusicManager.tween(0)
	
	var wave_data = {"current_wave":RunData.current_wave, "mode":game_mode}	
	var extra_creatures_map = extra_enemies_next_wave
	
	wave_data["extra_enemies_next_wave"] = extra_creatures_map
	wave_data["effects"] = effects_next_wave
	
	send_start_game(wave_data)
	reset_extra_creatures()
	reset_ready_map()
	
#	RunData.effects["extra_enemies_next_wave"] = tracked_players[self_peer_id]["extra_enemies_next_wave"]
	
	var _error = get_tree().change_scene(MenuData.game_scene)

func init_all_player_data():
	for player_id in tracked_players:
		init_player_data(tracked_players[player_id], player_id)

func init_player_data(player:Dictionary, player_id) -> void:
	var run_data = {}
	
	# Randomly useful in places
	run_data["player_id"] = player_id
	
	run_data["effects"] = RunData.init_effects()
		
	run_data["items"] = []
	run_data["weapons"] = []
	run_data["additional_weapon_effects"] = []
	run_data["active_set_effects"] = []
	run_data["gold"] = DebugService.starting_gold
	run_data["current_xp"] = 0
	run_data["current_level"] = 0
		
	run_data["tier_i_weapon_effects"] = []
	run_data["tier_iv_weapon_effects"] = []
		
	run_data["unique_effects"] = []
	run_data["appearances_displayed"] = []
	run_data["tracked_item_effects"] = RunData.init_tracked_effects()
		
	player["linked_stats"] = {}
	player["consumables_to_process"] = []
	player["linked_stats"]["stats"] = RunData.init_stats(true)
	player["linked_stats"]["update_on_gold_chance"] = false
		
	player["temp_stats"] = {}
	player["temp_stats"]["stats"] = RunData.init_stats(true)
	player["run_data"] = run_data

func start_game(game_info: Dictionary):
	reset_extra_creatures()
	reset_ready_map()
	disable_pause = true
	
	if not is_host:
		is_source_of_truth = false
	
	game_mode = game_info.mode
	if is_coop():
		if game_info.current_wave == 1:
			var run_data_node = $"/root/MultiplayerRunData"
			init_all_player_data()
			
			# TODO this should go away
			RunData.weapons = []
			RunData.items = []
			RunData.effects = RunData.init_effects()
#			RunData.current_character = null
#			RunData.starting_weapon = null
			
			var lobby_info = game_info.lobby_info
			
			var danger = lobby_info.danger
			
			var character_data = load(lobby_info.character)
			
			# Needed for random checks in main
			RunData.add_character(character_data)
						
			for player_id in tracked_players:
				if lobby_info.has("weapon"):
					var weapon_data = load(lobby_info.weapon)
#					var _unused = RunData.add_weapon(weapon_data, true)
					run_data_node.add_weapon(player_id, weapon_data, true)
					
				run_data_node.add_character(player_id, character_data)
				
	#			RunData.add_starting_items_and_weapons()
				run_data_node.add_starting_items_and_weapons(player_id)
				
#				run_data_node.add_item(player_id, load("res://items/all/ricochet/ricochet_data.tres"))
			
			var character_difficulty = ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone)
			character_difficulty.difficulty_selected_value = danger
			RunData.init_elites_spawn()
			
			for effect in ItemService.difficulties[danger].effects:
				effect.apply()
			
			back_to_lobby = false
			
			var num_players = tracked_players.size()
			var speed_multi = 1 + (num_players - 1.0) * .25 
			
			RunData.current_run_accessibility_settings = ProgressData.settings.enemy_scaling.duplicate()
			RunData.current_run_accessibility_settings.health = RunData.current_run_accessibility_settings.health * num_players
			RunData.current_run_accessibility_settings.damage = RunData.current_run_accessibility_settings.damage * num_players
			RunData.current_run_accessibility_settings.speed = RunData.current_run_accessibility_settings.speed * speed_multi
			
#		tracked_players = {}
#		RunData.current_wave = game_info.current_wave
		
		# MIGRATE reset_client_items()
		run_updates = true
		RunData.current_wave = game_info.current_wave
		if is_host:
			var _change_error = get_tree().change_scene(MenuData.game_scene)
		else:
			var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/client/client_main.tscn")
		
	elif game_mode == GameMode.VERSUS:
		if game_info.current_wave == 1:
			RunData.weapons = []
			RunData.items = []
			RunData.effects = RunData.init_effects()
			RunData.current_character = null
			RunData.starting_weapon = null
			
			var lobby_info = game_info.lobby_info
			
			var character_data = load(lobby_info.character)
			
			if lobby_info.has("weapon"):
				var weapon_data = load(lobby_info.weapon)
				var _unused = RunData.add_weapon(weapon_data, true)
			var danger = lobby_info.danger
			
			RunData.add_character(character_data)
			
			RunData.add_starting_items_and_weapons()
			
			var character_difficulty = ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone)
			character_difficulty.difficulty_selected_value = danger
			RunData.init_elites_spawn()
			
			for effect in ItemService.difficulties[danger].effects:
				effect.apply()
			
			back_to_lobby = false
			
		RunData.current_wave = game_info.current_wave
		if game_info.has("extra_enemies_next_wave"):
			extra_enemies_next_wave  = game_info.extra_enemies_next_wave
		if game_info.has("effects"):
			effects_next_wave = game_info.effects
		var _change_error = get_tree().change_scene(MenuData.game_scene)

func send_death() -> void:
	disable_pause = false
	run_updates = false
	if is_host:
		receive_death(self_peer_id)
	
	connection.send_death()

func receive_death(source_player_id:int) -> void:
	tracked_players[source_player_id]["dead"] = true
	if is_host:
		connection.send_tracked_players(tracked_players)
	if source_player_id != self_peer_id:
		check_win()

func check_win() -> void:
	var all_others_dead = true
	for tracked_player_id in tracked_players:
		if tracked_player_id == self_peer_id:
			continue
		var tracked_player = tracked_players[tracked_player_id]
		if not tracked_player.has("dead") or not tracked_player.dead:
			all_others_dead = false
	
	if all_others_dead:
		disable_pause = false
		var main = get_tree().get_current_scene()
		var did_win = not is_coop()
		main._is_run_won = did_win
		main._is_run_lost = not did_win
		RunData.run_won = did_win
			
		main.clean_up_room(false, main._is_run_lost, main._is_run_won)
		
		if not is_host:
			send_complete_player_request()
			yield(self, "complete_player_update")
		var _error = get_tree().change_scene("res://ui/menus/run/end_run.tscn")

func on_consumable_to_process_added(player_id, consumable_data) -> void:
	if player_id == self_peer_id:
		receive_add_consumable_to_process(player_id, consumable_data.get_path())
	else:
		connection.send_add_consumable_to_process(player_id, consumable_data.get_path())

func receive_add_consumable_to_process(player_id, consumable_data_path) -> void:
	if player_id == self_peer_id:
		var consumable_data = load(consumable_data_path)
		tracked_players[self_peer_id].consumables_to_process.push_back(consumable_data)
		get_tree().get_current_scene().emit_signal("consumable_to_process_added", consumable_data)

func on_upgrade_selected(upgrade_data:UpgradeData)->void :
	if is_host:
		receive_uprade_selected(upgrade_data.my_id, self_peer_id)
	else:
		connection.send_upgrade_selection(upgrade_data.my_id)

func send_complete_player_request() -> void:
	connection.send_complete_player_request()
	
func send_complete_player(player_id:int) -> void:
	var player_dict = tracked_players[player_id].duplicate()
	player_dict.run_data = player_dict.run_data.duplicate()
	
	var new_items = []
	
	for item in player_dict.run_data.items:
		var to_add = {}
		to_add["my_id"] = item.my_id 
		new_items.push_back(to_add)
	player_dict.run_data["items"] = new_items

	player_dict.run_data.current_character = player_dict.run_data.current_character.my_id
	
	var new_weapons = []
	for weapon in player_dict.run_data.weapons:
		var to_add = {}
		to_add["my_id"] = weapon.my_id
		new_weapons.push_back(to_add)
	player_dict.run_data["weapons"] = new_weapons
	
	var burn_chance = {}
	burn_chance.chance = player_dict.run_data.effects.burn_chance.chance
	burn_chance.damage = player_dict.run_data.effects.burn_chance.damage
	burn_chance.duration = player_dict.run_data.effects.burn_chance.duration
	player_dict.run_data.effects.burn_chance = burn_chance
	
	connection.send_complete_player(player_id, player_dict)
	
func receive_complete_player(player_id:int, player_dict: Dictionary) -> void:
	if player_id == self_peer_id:
		tracked_players[player_id]["run_data"] = player_dict.run_data
		
		var new_items = []
		
		for item in player_dict.run_data.items:
			for query_item in ItemService.items:
				if query_item.my_id == item.my_id:
					new_items.push_back(query_item.duplicate())
					
		tracked_players[player_id]["run_data"]["items"] = new_items
		
		for query_character in ItemService.characters:
			if query_character.my_id == player_dict.run_data.current_character:
				player_dict.run_data.current_character = query_character
				break
				
		var new_weapons = []
		
		for weapon in player_dict.run_data.weapons:
			for query_weapon in ItemService.weapons:
				if query_weapon.my_id == weapon.my_id:
					new_weapons.push_back(query_weapon.duplicate())
		tracked_players[player_id]["run_data"]["weapons"] = new_weapons
		
		RunData.emit_signal("gold_changed", tracked_players[player_id]["run_data"].gold)
		emit_signal("complete_player_update")

func on_item_box_take_button_pressed(item_data:ItemParentData) -> void:
	if is_host:
		receive_item_box_take(item_data.my_id, self_peer_id)
	else:
		connection.send_take_item_box(self_peer_id, item_data.my_id)

func receive_item_box_take(item_id, player_id) -> void:
	var run_data_node = $"/root/MultiplayerRunData"
	
	for item in ItemService.items:
		if item.my_id == item_id:
			run_data_node.add_item(player_id, item)
			return

func reroll_upgrades() -> void:
	var upgrades_ui = get_tree().get_current_scene()._upgrades_ui
	var reroll_price = upgrades_ui._reroll_price
	if is_host:
		receive_reroll_upgrades(self_peer_id, reroll_price)
	else:
		connection.send_reroll_upgrades(reroll_price)

func receive_reroll_upgrades(player_id:int, reroll_price:int) -> void:
	if not is_host:
		return

	var run_data_node = $"/root/MultiplayerRunData"
	run_data_node.remove_gold(player_id, reroll_price)
	
	if player_id == self_peer_id:
		var upgrades_ui = get_tree().get_current_scene()._upgrades_ui
		upgrades_ui._reroll_price = ItemService.get_reroll_price(RunData.current_wave, reroll_price)
		upgrades_ui.show_upgrade_options(upgrades_ui._level)
	else:
		send_complete_player(player_id)

func on_item_discard_button_pressed(weapon_data:WeaponData) -> void:
	if is_host:
		receive_item_discard(weapon_data.my_id, self_peer_id)
	else:
		connection.send_weapon_discard(weapon_data.my_id)

func receive_item_discard(weapon_id, player_id) -> void:
	var run_data_node = $"/root/MultiplayerRunData"
	
	var run_data = tracked_players[player_id].run_data
	var weapon_data = null
	
	for weapon in run_data.weapons:
		if weapon.my_id == weapon_id:
			weapon_data = weapon
		
	var _weapon = run_data_node.remove_weapon(player_id, weapon_data)
	run_data_node.add_gold(player_id, ItemService.get_recycling_value(RunData.current_wave, weapon_data.value, true))
	
	if player_id != self_peer_id:
		send_complete_player(player_id)

func receive_player_enter_shop(player_id:int) -> void:
	var run_data = tracked_players[player_id].run_data
	var run_data_node = $"/root/MultiplayerRunData"
	
	if run_data.effects["destroy_weapons"]:
		run_data_node.remove_all_weapons(player_id)
	
	if run_data.effects["upgrade_random_weapon"].size() > 0:
		for effect in run_data.effects["upgrade_random_weapon"]:
			
			var possible_upgrades = []
			
			for weapon in run_data.weapons:
				if weapon.upgrades_into != null and weapon.tier < run_data.effects["max_weapon_tier"]:
					possible_upgrades.push_back(weapon)
			
			if possible_upgrades.size() > 0:
				var weapon_to_upgrade = Utils.get_rand_element(possible_upgrades)
				receive_item_combine(weapon_to_upgrade.my_id, true, player_id)
			else :
				run_data_node.add_stat(player_id, effect[0], effect[1])
	
	if player_id != self_peer_id:
		send_complete_player(player_id)

func on_item_combine_button_pressed(weapon_data:WeaponData, is_upgrade:bool = false) -> void:
	if is_host:
		receive_item_combine(weapon_data.my_id, is_upgrade, self_peer_id)
	else:
		connection.send_combine_item(weapon_data.my_id, is_upgrade, self_peer_id)

func receive_item_combine(weapon_id, is_upgrade, player_id) -> void:
	var run_data_node = $"/root/MultiplayerRunData"
	var shop = $"/root/Shop"
	
	var nb_to_remove = 2
	var removed_weapons_tracked_value = 0

	if is_upgrade:
		nb_to_remove = 1
		
	var run_data = tracked_players[player_id].run_data
	var weapon_data = null
	
	for weapon in run_data.weapons:
		if weapon.my_id == weapon_id:
			weapon_data = weapon
			
	removed_weapons_tracked_value += run_data_node.remove_weapon(player_id, weapon_data)

	if not is_upgrade:
		removed_weapons_tracked_value += run_data_node.remove_weapon(player_id, weapon_data)
	
	var new_weapon = run_data_node.add_weapon(player_id, weapon_data.upgrades_into)

	new_weapon.tracked_value = removed_weapons_tracked_value

	if is_upgrade:
		new_weapon.dmg_dealt_last_wave = weapon_data.dmg_dealt_last_wave

	if player_id == self_peer_id:
		shop._weapons_container._elements.remove_element(weapon_data, nb_to_remove)
		shop.reset_item_popup_focus()
		shop._stats_container.update_stats()
		shop._weapons_container._elements.add_element(new_weapon)
		SoundManager.play(Utils.get_rand_element(shop.combine_sounds), 0, 0.1, true)
		shop._weapons_container.set_label(shop.get_weapons_label_text())
		if Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN:
			shop._weapons_container._elements.focus_element(new_weapon)



func receive_uprade_selected(upgrade_data_id, player_id):
	for upgrade in ItemService.upgrades:
		if upgrade.my_id == upgrade_data_id:
			var run_data = tracked_players[player_id].run_data
			var run_data_node = $"/root/MultiplayerRunData"
			run_data_node.apply_item_effects(player_id, upgrade, run_data)

# Send normal item
func send_bought_item_by_id(item_id:String, value:int) -> void:
	if is_host:
		receive_bought_item_by_id(item_id, self_peer_id, value)
	else:
		connection.send_bought_item_by_id(item_id, value)

func receive_bought_item_by_id(item_id:String, player_id:int, value:int) -> void:
	var run_data_node = $"/root/MultiplayerRunData"
	var run_data = tracked_players[player_id].run_data
	run_data_node.remove_currency(player_id, value)
	var nb_coupons = run_data_node.get_nb_item(player_id, "item_coupon")
	
	var shop_item_data = null
	
	for weapon in ItemService.weapons:
		if weapon.my_id == item_id:
			shop_item_data = weapon
	for item in ItemService.items:
		if item.my_id == item_id:
			shop_item_data = item
	
	if nb_coupons > 0:
		
#		var coupon_value = get_coupon_value() reimplemented in place
		var coupon_value = 0
		for item in run_data.items:
			if item.my_id == "item_coupon":
				coupon_value = abs(item.effects[0].value)
				break
			
		var coupon_effect = nb_coupons * (coupon_value / 100.0)
		var base_value = ItemService.get_value(RunData.current_wave, shop_item_data.value, false, shop_item_data is WeaponData, shop_item_data.my_id)
		run_data.tracked_item_effects["item_coupon"] += (base_value * coupon_effect) as int
		
#	emit_signal("item_bought", shop_item_data)
	
	if shop_item_data.get_category() == Category.ITEM:
		run_data_node.add_item(player_id, shop_item_data)
	elif shop_item_data.get_category() == Category.WEAPON:
		if not run_data_node.has_weapon_slot_available(player_id, shop_item_data.type):
			for weapon in run_data.weapons:
				if weapon.my_id == shop_item_data.my_id and weapon.upgrades_into != null:
					var _weapon = run_data_node.add_weapon(player_id, shop_item_data)
					on_item_combine_button_pressed(weapon)
					break
		else :
			var _weapon = run_data_node.add_weapon(player_id, shop_item_data)
	
	if player_id != self_peer_id:
		send_complete_player(player_id)

func send_bought_item(shop_item:Resource) -> void:
	if is_host:
		receive_bought_item(shop_item, self_peer_id)
	else:
		connection.send_bought_item(shop_item)

func send_client_entered_shop() -> void:
	connection.send_client_entered_shop()

func receive_bought_item(shop_item:Resource, source_player_id:int) -> void:
	var effect_path = shop_item.effect.get_path()
	for player_id in tracked_players:
		if player_id != source_player_id:
			var effect = shop_item.effect
			if effect is WaveGroupData:
				if not tracked_players[player_id]["extra_enemies_next_wave"].has(effect_path):
					tracked_players[player_id]["extra_enemies_next_wave"][effect_path] = 0
				tracked_players[player_id]["extra_enemies_next_wave"][effect_path] = tracked_players[player_id]["extra_enemies_next_wave"][effect_path] + 1
			elif effect is Effect:
				if not tracked_players[player_id]["effects"].has(effect_path):
					tracked_players[player_id]["effects"][effect_path] = 0
				tracked_players[player_id]["effects"][effect_path] = tracked_players[player_id]["effects"][effect_path] + 1
	
	if is_host:
		connection.send_tracked_players(tracked_players)
	if $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer":
		$"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer".update_bought_items(tracked_players)

func update_tracked_players(updated_tracked_players: Dictionary) -> void:
	# Actual Player state is updated elsewhere
	for player_id in updated_tracked_players:
		if tracked_players.has(player_id) and tracked_players[player_id].has("player"):
			updated_tracked_players[player_id]["player"] = tracked_players[player_id]["player"]
		else:
			updated_tracked_players[player_id].erase("player")
		
	var scene_name = get_tree().get_current_scene().get_name()
	
	tracked_players = updated_tracked_players
	if scene_name == "Shop":
		$"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer".update_bought_items(tracked_players)
	elif scene_name == "Main":
		update_health_ui()
		check_win()
	elif scene_name == "ClientMain":
		update_health_ui()

func create_ready_toggle() -> Node:
	ready_toggle = toggle_scene.instance()
	ready_toggle.connect("pressed", self, "_on_ready_toggle")
	return ready_toggle

func _on_ready_toggle() -> void:
	connection.send_ready(ready_toggle.pressed)

func display_floating_text(text_info:Dictionary):
	if $"/root/ClientMain":
		$"/root/ClientMain/FloatingTextManager".display(text_info.value, text_info.position, text_info.color)

func display_hit_effect(effect_info: Dictionary):
	if $"/root/ClientMain/EffectsManager":
		var effects_manager = $"/root/ClientMain/EffectsManager"
		effects_manager.play_hit_particles(effect_info.position, effect_info.direction, effect_info.scale)
		effects_manager.play_hit_effect(effect_info.position, effect_info.direction, effect_info.scale)

func discard_item_box(item_data:ItemParentData) -> void:
	if is_host:
		receive_discard_item_box(self_peer_id, item_data.my_id)
	else:
		connection.send_discard_item_box(item_data.my_id)
	
func receive_discard_item_box(player_id:int, item_id:String) -> void:
	var run_data_node = $"/root/MultiplayerRunData"
	for query_item in ItemService.items:
		if query_item.my_id == item_id:
			var actual_value = ItemService.get_recycling_value(RunData.current_wave, query_item.value)
			run_data_node.add_gold(player_id, actual_value)
	
func end_wave():
	run_updates = false
	game_state_controller.reset_client_items()
	
	for player_id in tracked_players:
		tracked_players[player_id].erase("player")

func send_ready(is_ready:bool) -> void:
	connection.send_ready(is_ready)

func send_game_state() -> void:
	if run_updates:
		connection.send_state(game_state_controller.get_game_state())

func send_start_game(game_info:Dictionary) -> void:
	connection.send_start_game(game_info)

func send_display_floating_text(text_info:Dictionary) -> void:
	connection.send_display_floating_text(text_info)

func send_display_hit_effect(effect_info: Dictionary) -> void:
	connection.send_display_hit_effect(effect_info)

func send_enemy_death(enemy_id:int) -> void:
	connection.send_enemy_death(enemy_id)

func send_end_wave() -> void:
	connection.send_end_wave()

func send_flash_enemy(enemy_id:int) -> void:
	connection.send_flash_enemy(enemy_id)
	
func send_shot(player_id:int, weapon_index:int) -> void:
	connection.send_shot(player_id, weapon_index)
	
func receive_shot(player_id:int, weapon_index:int) -> void:
	if tracked_players.has(player_id):
		if tracked_players[player_id].has("player"):
			var player = tracked_players[player_id]["player"]
			
			if is_instance_valid(player):
				var weapon = player.current_weapons[weapon_index]
				if is_instance_valid(weapon):
					SoundManager.play(Utils.get_rand_element(weapon.current_stats.shooting_sounds), weapon.current_stats.sound_db_mod, 0.2)


func send_explosion(pos: Vector2, scale: float) -> void:
	connection.send_explosion(pos, scale)
	
func receive_explosion(pos: Vector2, scale: float) -> void:
	var main = get_tree().current_scene
	var instance = explosion_scene.instance()
	instance.set_deferred("global_position", pos)
	main.call_deferred("add_child", instance)
	instance.call_deferred("set_area", scale)

func send_enemy_take_damage(enemy_id:int, is_dodge: bool) -> void:
	connection.send_enemy_take_damage(enemy_id, is_dodge)

func receive_enemy_take_damage(enemy_id:int, is_dodge:bool) -> void:
	if game_state_controller.client_enemies.has(enemy_id):
		var enemy = game_state_controller.client_enemies[enemy_id]
		if is_instance_valid(enemy):
			var sound
			if is_dodge:
				sound = Utils.get_rand_element(enemy.dodge_sounds)
			else:
				sound = Utils.get_rand_element(enemy.hurt_sounds)
			SoundManager2D.play(sound, enemy.global_position, 0, 0.2, enemy.always_play_hurt_sound)

func send_flash_neutral(neutral_id:int) -> void:
	connection.send_flash_neutral(neutral_id)

func send_lobby_update(lobby_info:Dictionary) -> void:
	connection.send_lobby_update(lobby_info)

func receive_lobby_update(lobby_info:Dictionary) -> void:
	if current_scene_name == "MultiplayerLobby":
		$"/root/MultiplayerLobby".remote_update_lobby(lobby_info)
	
func update_multiplayer_lobby() -> void:
	if current_scene_name == "MultiplayerLobby":
		$"/root/MultiplayerLobby".update_selections()

func send_client_position() -> void:
	if not tracked_players.has(self_peer_id) or not tracked_players[self_peer_id].has("player"):
		return
	var my_player = tracked_players[self_peer_id]["player"]
	if not is_instance_valid(my_player):
		return
	var client_position = {}
	client_position["player"] = my_player.position
	client_position["id"] = self_peer_id
	client_position["movement"] = my_player._current_movement
	var weapons = []
	for weapon in my_player.current_weapons:
		var weapon_data = {}
		weapon_data["weapon_id"] = weapon.weapon_id
		weapon_data["position"] = weapon.sprite.position
		weapon_data["rotation"] = weapon.sprite.rotation
		weapon_data["hitbox_disabled"] = weapon._hitbox._collision.disabled
		weapons.push_back(weapon_data)
	client_position["weapons"] = weapons
	
	connection.send_client_position(client_position)

func update_client_position(client_position:Dictionary) -> void:
	if is_source_of_truth:
		var id = client_position.id
		if tracked_players.has(id):
			if tracked_players[id].has("player"):
				var player = tracked_players[id]["player"]
				if not is_instance_valid(player):
					return
				player.position = client_position.player
				player.maybe_update_animation(client_position.movement, true)

func update_ready_state(sender_id, is_ready):
	if is_host:
		tracked_players[sender_id]["is_ready"] = is_ready
	if current_scene_name == "Shop":
		update_go_button()

func reset_ready_map():
	for player_id in tracked_players:
		tracked_players[player_id]["is_ready"] = false
		
func reset_extra_creatures():
	for player_id in tracked_players:
		tracked_players[player_id]["extra_enemies_next_wave"] = {}
		tracked_players[player_id]["effects"] = {}

func update_go_button():
	var should_enable = true
	
	for player_id in tracked_players:
		if player_id != self_peer_id and not tracked_players[player_id]["is_ready"]:
			should_enable = false
			break
	
	var shop_button = $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/GoButton"
	
	if not should_enable:
		shop_button.disabled = true
	else:
		shop_button.disabled = false

func get_items_state() -> Dictionary:
	var main = $"/root/Main"
	var items = []
	for item in main._items_container.get_children():
		var item_data = {}

		item_data["id"]  = item.id
		item_data["scale_x"] = item.scale.x
		item_data["scale_y"] = item.scale.y
		item_data["position"] = item.global_position
		item_data["rotation"] = item.rotation
		item_data["push_back_destination"]  = item.push_back_destination

		# TODO we may want textures propagated
		items.push_back(item_data)
	return items

func get_projectiles_state() -> Dictionary:
	var main = $"/root/Main"
	var projectiles = []
	for child in main.get_children():
		if child is PlayerProjectile:
			var projectile_data = {}
			projectile_data["id"] = child.id
			projectile_data["filename"] = child.filename
			projectile_data["position"] = child.position
			projectile_data["global_position"] = child.global_position
			projectile_data["rotation"] = child.rotation

			projectiles.push_back(projectile_data)
	return projectiles

func send_player_level_up(player_id: int, level:int) -> void:
	connection.send_player_level_up(player_id, level)
	
func receive_player_level_up(player_id: int, level:int) -> void:
	if player_id == self_peer_id:
		var main = $"/root/ClientMain"
		main._ui_upgrades_to_process.add_element(ItemService.upgrade_to_process_icon, level)
		main._upgrades_to_process.push_back(level)

func receive_health_update(current_health:int, max_health:int, source_player_id:int) -> void:
	tracked_players[source_player_id]["max_health"] = max_health
	tracked_players[source_player_id]["current_health"] = current_health
	
#	if is_host:
#		connection.send_tracked_players(tracked_players)
	update_health_ui()

func update_health_ui() -> void:
	if current_scene_name == "Main":
		if $"/root/Main/UI/HealthTracker":
			$"/root/Main/UI/HealthTracker".update_health_bars(tracked_players)
	if current_scene_name == "ClientMain":
		if $"/root/ClientMain/UI/HealthTracker":
			$"/root/ClientMain/UI/HealthTracker".update_health_bars(tracked_players)
	
func update_health(current_health:int, max_health:int) -> void:
	# If this player owns all the players, all the updates will come through
	# here.
	if is_coop() and is_host:
		for player_id in tracked_players:
			var player_dict = tracked_players[player_id]
			if player_dict.has("player") and is_instance_valid(player_dict.player):
				var player = player_dict.player
				
				tracked_players[player_id]["max_health"] = player.max_stats.health
				tracked_players[player_id]["current_health"] = player.current_stats.health
	
	receive_health_update(current_health, max_health, self_peer_id)
	connection.send_health_update(current_health, max_health)

func update_game_state(data: PoolByteArray) -> void:
	if get_tree().get_current_scene().get_name() != "ClientMain":
		return
	game_state_controller.update_game_state(data)
	update_health_ui()

func enemy_death(enemy_id):
	game_state_controller.enemy_death(enemy_id)

func flash_enemy(enemy_id):
	game_state_controller.flash_enemy(enemy_id)

func flash_neutral(neutral_id):
	game_state_controller.flash_neutral(neutral_id)

func is_coop() -> bool:
	return game_mode == GameMode.COOP
