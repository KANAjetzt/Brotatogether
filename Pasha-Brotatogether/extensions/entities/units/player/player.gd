extends "res://entities/units/player/player.gd"

var player_network_id

func add_weapon(weapon_data:WeaponData, pos:int)->void :
	.add_weapon(weapon_data, pos)
	var weapon = current_weapons[current_weapons.size() - 1]
	var data_node = load("res://mods-unpacked/Pasha-Brotatogether/extensions/entities/units/player/weapon_data_node.gd").new()
	data_node.weapon_data = weapon_data
	data_node.set_name("data_node")
	weapon.call_deferred("add_child", data_node)

func take_damage(value:int, hitbox:Hitbox = null, dodgeable:bool = true, armor_applied:bool = true, custom_sound:Resource = null, base_effect_scale:float = 1.0, bypass_invincibility:bool = false)->Array:
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
			return [0, 0 ,0]
	return .take_damage(value, hitbox, dodgeable, armor_applied, custom_sound, base_effect_scale, bypass_invincibility)

func remove_weapon_behaviors():
	for weapon in current_weapons:
		var shooting_behavior = weapon.get_node("ShootingBehavior")
		weapon.remove_child(shooting_behavior)
		var client_shooting_behavior = WeaponShootingBehavior.new()
		client_shooting_behavior.set_name("ShootingBehavior")
		weapon.add_child(client_shooting_behavior)
		weapon._shooting_behavior = client_shooting_behavior
		
func update_animation(movement:Vector2)->void :
	maybe_update_animation(movement, false)

func update_player_stats_multiplayer()->void :
	if not $"/root".has_node("GameController"):
		.update_player_stats()
		return
	
	print_debug("max health before ", max_stats.health)
	
	print_debug("multiplayer update player stats ", player_network_id)
	var old_max_health = max_stats.health
	
	var game_controller = $"/root/GameController"
	var run_data = game_controller.tracked_players[player_network_id]["run_data"]
	var multiplayer_utils = $"/root/MultiplayerUtils"
	var multiplayer_weapon_service = $"/root/MultiplayerWeaponService"
	
	print_debug("max health after (1)", max_stats.health)
	
	max_stats.health = clamp(multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_max_hp"), 1, run_data.effects["hp_cap"]) as int
	max_stats.speed = stats.speed * (1 + (min(multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_speed"), run_data.effects["speed_cap"]) / 100.0)) as float
	max_stats.armor = multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_armor") as int
	max_stats.dodge = min(run_data.effects["dodge_cap"] / 100.0, multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_dodge") / 100.0)
#
#	print_debug("max health after (1.1)", max_stats.health)
#	print_debug("max health from utils", multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_max_hp"))
#
	
	if run_data.effects["explode_on_hit"].size() > 0:
#		init_exploding_stats()
		_explode_on_hit_stats = multiplayer_weapon_service.init_base_stats_multiplayer(run_data, run_data.effects["explode_on_hit"][0].stats, "", [], [ExplodingEffect.new()])
	
	print_debug("max health after (1.2)", max_stats.health)
	current_stats.copy(max_stats, true)
	print_debug("max health after (2)", max_stats.health)
	
	if old_max_health != max_stats.health:
		emit_signal("health_updated", current_stats.health, max_stats.health)
	
#	check_hp_regen()
#	func check_hp_regen()->void :

#	set_hp_regen_timer_value()
#	func set_hp_regen_timer_value()->void :
	_health_regen_timer.wait_time = RunData.get_hp_regeneration_timer(multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_hp_regeneration") as int)
	
	if run_data.effects["torture"] > 0:
		_health_regen_timer.wait_time = 1
		
	if (run_data.effects["torture"] > 0 or multiplayer_utils.get_stat_multiplayer(player_network_id, "stat_hp_regeneration") > 0) and _health_regen_timer.is_stopped() and current_stats.health < max_stats.health and not cleaning_up:
		_health_regen_timer.start()
		
	print_debug("max health after (end)", max_stats.health)

func maybe_update_animation(movement:Vector2, force_animation:bool)->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if (not game_controller) or force_animation or game_controller.game_mode != "shared" or (game_controller.tracked_players.has(game_controller.self_peer_id) and game_controller.tracked_players[game_controller.self_peer_id].has("player") and game_controller.tracked_players[game_controller.self_peer_id]["player"] == self) or not game_controller.run_updates:
			pass
		else:
			return
	check_not_moving_stats(movement)
	check_moving_stats(movement)
	
	if movement.x > 0:
		_shadow.scale.x = abs(_shadow.scale.x)
		for sprite in $Animation.get_children():
			sprite.scale.x = abs(sprite.scale.x)
	elif movement.x < 0:
		_shadow.scale.x = - abs(_shadow.scale.x)
		for sprite in $Animation.get_children():
			sprite.scale.x = - abs(sprite.scale.x)

	if _animation_player.current_animation == "idle" and movement != Vector2.ZERO:
		_animation_player.play("move")
		_running_smoke.emit()
	elif _animation_player.current_animation == "move" and movement == Vector2.ZERO:
		_animation_player.play("idle")
		_running_smoke.stop()
	
func _on_ItemAttractArea_area_entered(area:Area2D)->void :
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		if game_controller and game_controller.game_mode == "shared" and not game_controller.is_source_of_truth:
			return
	._on_ItemAttractArea_area_entered(area)
