extends Node3D
## Wires the world together: spawns the walker, shows the HUD, and lets you
## press N to roll a brand-new world.

@onready var terrain: Node3D = $Terrain
@onready var player: CharacterBody3D = $Player
@onready var hud: Label = $HUD/Help


func _ready() -> void:
	# Children are ready first, so the terrain has already generated.
	_place_player()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("new_world"):
		terrain.world_seed = randi() % 100000
		terrain.generate()
		_place_player()
		_update_hud()


func _place_player() -> void:
	player.respawn(terrain.spawn_point())


func _update_hud() -> void:
	hud.text = "discwalk  ·  seed %d\nWASD walk · mouse look · Shift stroll faster · Space hop\nN new world · Esc free mouse" % terrain.world_seed
