extends Node

var client_enemies = {}
var client_births = {}
var client_players = {}
var client_items = {}
var client_player_projectiles = {}
var client_consumables = {}
var client_neutrals = {}

var parent
var run_updates = false

const gold_scene = preload("res://items/materials/gold.tscn")
const entity_birth_scene = preload("res://entities/birth/entity_birth.tscn")
const consumable_scene = preload("res://items/consumables/consumable.tscn")
const consumable_texture = preload("res://items/consumables/fruit/fruit.png")
const player_scene = preload("res://entities/units/player/player.tscn")

#TODO this is the sussiest of bakas
var weapon_stats_resource = ResourceLoader.load("res://weapons/ranged/pistol/1/pistol_stats.tres")

# TODO all neutrals are going to be trees for now
const tree_scene = preload("res://entities/units/neutral/tree.tscn")

const ClientMovementBehavior = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/entities/units/enemies/client_movement_behavior.gd")
const ClientAttackBehavior = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/entities/units/enemies/client_attack_behavior.gd")

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

func update_items(items:Array) -> void:
	var server_items = {}
	for item_data in items:
		if not client_items.has(item_data.id):
			client_items[item_data.id] = spawn_gold(item_data)
		if is_instance_valid(client_items[item_data.id]):
			client_items[item_data.id].global_position = item_data.position
			# The item will try to float around on its own
			client_items[item_data.id].push_back_destination = item_data.position

		server_items[item_data.id] = true
	for item_id in client_items:
		if not server_items.has(item_id):
			var item = client_items[item_id]
			if not client_items[item_id]:
				continue

			client_items.erase(item_id)
			if not $"/root/ClientMain/Items":
				continue 
			if not item:
				continue
				
			# This sometimes throws a C++ error
			$"/root/ClientMain/Items".remove_child(item)

func spawn_gold(item_data:Dictionary):
	var gold = gold_scene.instance()
	
	gold.global_position = item_data.position
	gold.scale.x = item_data.scale_x
	gold.scale.y = item_data.scale_y
	gold.rotation = item_data.rotation
	gold.push_back_destination = item_data.push_back_destination
	
	$"/root/ClientMain/Items".add_child(gold)
	
	return gold

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

func update_player_projectiles(projectiles:Array) -> void:
	var server_player_projectiles = {}
	for player_projectile_data in projectiles:
		var projectile_id = player_projectile_data.id
		if not client_player_projectiles.has(projectile_id):
			client_player_projectiles[projectile_id] = spawn_player_projectile(player_projectile_data)

		var player_projectile = client_player_projectiles[projectile_id]
		if is_instance_valid(player_projectile):
			player_projectile.position = player_projectile_data.position
			player_projectile.rotation = player_projectile_data.rotation
		server_player_projectiles[projectile_id] = true

	for projectile_id in client_player_projectiles:
		if not server_player_projectiles.has(projectile_id):
			var player_projectile = client_player_projectiles[projectile_id]
			client_player_projectiles.erase(projectile_id)
			if is_instance_valid(player_projectile):
				get_tree().current_scene.remove_child(player_projectile)

func spawn_player_projectile(projectile_data:Dictionary):
	var main = $"/root/ClientMain"
	var projectile = load(projectile_data.filename).instance()
	
	projectile.position = projectile_data.position
	projectile.spawn_position = projectile_data.global_position
	projectile.global_position = projectile_data.global_position
	projectile.rotation = projectile_data.rotation
	# TODO this is probably wrong?
	projectile.weapon_stats = weapon_stats_resource.duplicate()
	projectile.set_physics_process(false)
	
	main.add_child(projectile, true)
	
	projectile.call_deferred("set_physics_process", false)
	
	return projectile

func enemy_death(enemy_id):
	if client_enemies.has(enemy_id):
		if is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].die()

func flash_enemy(enemy_id):
	if client_enemies.has(enemy_id):
		if is_instance_valid(client_enemies[enemy_id]):
			client_enemies[enemy_id].flash()

func flash_neutral(neutral_id):
	if client_neutrals.has(neutral_id):
		if is_instance_valid(client_neutrals[neutral_id]):
			client_neutrals[neutral_id].flash()
			
func update_enemies(enemies:Array) -> void:
	var server_enemies = {}
	for enemy_data in enemies:
		if not client_enemies.has(enemy_data.id):
			if not enemy_data.has("filename"):
				continue
			var enemy = spawn_enemy(enemy_data)
			client_enemies[enemy_data.id] = enemy

		var stored_enemy = client_enemies[enemy_data.id]
		if is_instance_valid(stored_enemy):
			server_enemies[enemy_data.id] = true
			stored_enemy.position = enemy_data.position
			stored_enemy.call_deferred("update_animation", enemy_data.movement)
	for enemy_id in client_enemies:
		if not server_enemies.has(enemy_id):
			# TODO clean this up when the animation finishes
#			$"/root/ClientMain/Entities".remove_child(client_enemies[enemy_id])
			client_enemies.erase(enemy_id)

func spawn_enemy(enemy_data: Dictionary):
	var entity = load(enemy_data.filename).instance()

	entity.position = enemy_data.position
	entity.stats = load(enemy_data.resource)

	_clear_movement_behavior(entity)

	$"/root/ClientMain/Entities".add_child(entity)

	return entity


# TODO: DEDUPE
func _clear_movement_behavior(entity:Entity, is_player:bool = false) -> void:
	# Players will only move via client calls, locally make them do
	# nothing
	# Since the player is added before it's children can be manipulatd,
	# manually set the current movement behavior to set it correctly
	var movement_behavior = entity.get_node("MovementBehavior")
	entity.remove_child(movement_behavior)
	var client_movement_behavior = ClientMovementBehavior.new()
	client_movement_behavior.set_name("MovementBehavior")
	entity.add_child(client_movement_behavior, true)
	entity._current_movement_behavior = client_movement_behavior
	
	if not is_player:
		var attack_behavior = entity.get_node("AttackBehavior")
		entity.remove_child(attack_behavior)
		var client_attack_behavior = ClientAttackBehavior.new()
		client_attack_behavior.set_name("AttackBehavior")
		entity.add_child(client_attack_behavior, true)
		entity._current_attack_behavior = client_attack_behavior
	
	if is_player:
		entity.call_deferred("remove_weapon_behaviors")

func update_game_state(data):
	if not run_updates or get_tree().get_current_scene().get_name() != "ClientMain":
		return
	update_enemies(data.enemies)
	update_births(data.births)
	update_items(data.items)
	update_player_projectiles(data.projectiles)
	update_consumables(data.consumables)
	update_neutrals(data.neutrals)
	update_players(data.players)

func update_births(births:Array) -> void:
	var server_births = {}
	for birth_data in births:
		if not client_births.has(birth_data.id):
			var birth = spawn_entity_birth(birth_data)
			client_births[birth_data.id] = birth
		server_births[birth_data.id] = true
	for birth_id in client_births:
		if not server_births.has(birth_id):
			var birth_to_delete = client_births[birth_id]
			if birth_to_delete:
#				Children go away on their own when they time out?
#				$"/root/ClientMain/Births".remove_child(birth_to_delete)
				client_births.erase(birth_id)
				
func update_consumables(consumables:Array) -> void:
	var server_consumables = {}
	for server_consumable_data in consumables:
		var consumable_id = server_consumable_data.id
		if not client_consumables.has(consumable_id):
			client_consumables[consumable_id] = spawn_consumable(server_consumable_data)

		var consumable = client_consumables[consumable_id]
		if is_instance_valid(consumable):
			consumable.global_position = server_consumable_data.position
		server_consumables[consumable_id] = true
	for consumable_id in client_consumables:
		if not server_consumables.has(consumable_id):
			var consumable = client_consumables[consumable_id]
			client_consumables.erase(consumable_id)
			if is_instance_valid(consumable):
				$"/root/ClientMain/Consumables".remove_child(consumable)


func update_neutrals(neutrals:Array) -> void:
	var server_neutrals = {}
	for server_neutral_data in neutrals:
		var neutral_id = server_neutral_data.id
		if not client_neutrals.has(neutral_id):
			client_neutrals[neutral_id] = spawn_neutral(server_neutral_data)
		var neutral = client_neutrals[neutral_id]
		if is_instance_valid(neutral):
			neutral.global_position = server_neutral_data.position
		server_neutrals[neutral_id] = true
	for neutral_id in client_neutrals:
		if not server_neutrals.has(neutral_id):
			var neutral = client_neutrals[neutral_id]
			client_neutrals.erase(neutral_id)
			if is_instance_valid(neutral):
				$"/root/ClientMain/Entities".remove_child(neutral)

func spawn_entity_birth(entity_birth_data:Dictionary):
	var entity_birth = entity_birth_scene.instance()
	
	entity_birth.color = entity_birth_data.color
	entity_birth.global_position = entity_birth_data.position
	
	$"/root/ClientMain/Entities".add_child(entity_birth)
	
	return entity_birth

func spawn_consumable(consumable_data:Dictionary):
	var consumable = consumable_scene.instance()
	
	consumable.global_position = consumable_data.position
	consumable.call_deferred("set_texture", consumable_texture)
	consumable.call_deferred("set_physics_process", false)
	
	$"/root/ClientMain/Consumables".add_child(consumable)
	
	return consumable

func spawn_neutral(neutral_data:Dictionary):
	var neutral = tree_scene.instance()
	neutral.global_position = neutral_data.position
	
	$"/root/ClientMain/Entities".add_child(neutral)
	
	return neutral

func reset_client_items():
	client_enemies = {}
	client_births = {}
	client_players = {}
	client_items = {}
	client_player_projectiles = {}
	client_consumables = {}
	client_neutrals = {}
	
	parent.tracked_players = {}

func update_players(players:Array) -> void:
	var tracked_players = parent.tracked_players
	for player_data in players:
		var player_id = player_data.id
		if not player_id in tracked_players:
			tracked_players[player_id] = {}
			tracked_players[player_id]["player"] = spawn_player(player_data)

		var player = tracked_players[player_id]["player"]
		if player_id == parent.self_peer_id:
			if $"/root/ClientMain":
				var main = $"/root/ClientMain"
				main._life_bar.update_value(player_data.current_health, player_data.max_health)
				main.set_life_label(player_data.current_health, player_data.max_health)
				main._damage_vignette.update_from_hp(player_data.current_health, player_data.max_health)
				RunData.gold = player_data.gold
				$"/root/ClientMain"._ui_gold.on_gold_changed(player_data.gold)
		else:
			if is_instance_valid(player):
				player.position = player_data.position
				player.call_deferred("maybe_update_animation", player_data.movement, true)

		for weapon_data_index in player.current_weapons.size():
			var weapon_data = player_data.weapons[weapon_data_index]
			var weapon = player.current_weapons[weapon_data_index]
			weapon.sprite.position = weapon_data.position
			weapon.sprite.rotation = weapon_data.rotation
			weapon._is_shooting = weapon_data.shooting

func spawn_player(player_data:Dictionary):
	var spawned_player = player_scene.instance()
	spawned_player.position = player_data.position
	spawned_player.current_stats.speed = player_data.speed

	for weapon in player_data.weapons:
		spawned_player.call_deferred("add_weapon", load(weapon.data_path), spawned_player.current_weapons.size())

	$"/root/ClientMain/Entities".add_child(spawned_player)

	if player_data.id == parent.self_peer_id:
		spawned_player.get_remote_transform().remote_path = $"/root/ClientMain/Camera".get_path()
	spawned_player.call_deferred("remove_weapon_behaviors")

	return spawned_player

func get_game_state() -> Dictionary:
	var data = {}
	
	print_debug("tree" , get_tree().get_current_scene())
	
	if "/root/Main":
		var main = $"/root/Main"
		print_debug("here ", get_tree().get_current_scene().get_name())
		if main:
			data["enemies"] = get_enemies_state()
			data["births"] = get_births_state()
			data["items"] = get_items_state()
			data["players"] = get_players_state()
			data["projectiles"] = get_projectiles_state()
			data["consumables"] = get_consumables_state()
			data["neutrals"] = get_neutrals_state()

	return data

func get_enemies_state() -> Dictionary:
	var main = $"/root/Main"
	var enemies = []
	var entity_spawner = main._entity_spawner
	for enemy in entity_spawner.enemies:
		if is_instance_valid(enemy):
				var network_id = enemy.id
				var enemy_data = {}
				enemy_data["id"] = network_id

				# TODO Details only needed on spawn, send sparingly
				enemy_data["resource"] = enemy.stats.resource_path
				enemy_data["filename"] = enemy.filename

				enemy_data["position"] = enemy.position
				enemy_data["movement"] = enemy._current_movement

				enemies.push_back(enemy_data)
	return enemies

func get_births_state() -> Dictionary:
	var main = $"/root/Main"
	var births = []
	for birth in main._entity_spawner.births:
		if is_instance_valid(birth):
			var birth_data = {}
			birth_data["position"] = birth.global_position
			birth_data["color"] = birth.color
			birth_data["id"] = birth.id
			births.push_back(birth_data)
	return births

func get_players_state() -> Dictionary:
	var tracked_players = parent.tracked_players
	var players = []
	for player_id in tracked_players:
		var player_data = {}
		var tracked_player = tracked_players[player_id]["player"]
		player_data["id"] = player_id
		player_data["position"] = tracked_player.position
		player_data["speed"] = tracked_player.current_stats.speed
		player_data["movement"] = tracked_player._current_movement
		player_data["current_health"] = tracked_player.current_stats.health
		player_data["max_health"] = tracked_player.max_stats.health

		# This would be where individual inventories are sent out instead of
		# RunData.gold
		player_data["gold"] = RunData.gold

		var weapons = []
		for weapon in tracked_player.current_weapons:
			var weapon_data = {}
			weapon_data["weapon_id"] = weapon.weapon_id
			weapon_data["position"] = weapon.sprite.position
			weapon_data["rotation"] = weapon.sprite.rotation
			weapon_data["shooting"] = weapon._is_shooting

			if weapon.has_node("data_node"):
				var weapon_data_path = RunData.weapon_paths[weapon.get_node("data_node").weapon_data.my_id]
				weapon_data["data_path"] = weapon_data_path

			weapons.push_back(weapon_data)

		player_data["weapons"] = weapons
		players.push_back(player_data)
	return players

func get_consumables_state() -> Dictionary:
	var main = $"/root/Main"
	var consumables = []
	for consumable in main._consumables_container.get_children():
		var consumable_data = {}
		consumable_data["position"] = consumable.global_position
		consumable_data["id"] = consumable.id
		consumables.push_back(consumable_data)
	return consumables

func get_neutrals_state() -> Dictionary:
	var main = $"/root/Main"
	var neutrals = []
	for neutral in main._entity_spawner.neutrals:
		if is_instance_valid(neutral):
			var neutral_data = {}
			neutral_data["id"] = neutral.id
			neutral_data["position"] = neutral.global_position
			neutrals.push_back(neutral_data)
	return neutrals