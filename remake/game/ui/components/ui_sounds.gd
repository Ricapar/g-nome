class_name UiSounds
extends Node
## Menu sound effects: play(&"hover" | &"slot" | &"key" | &"back").
## Sounds come from remake/art/ui/sounds/make_sounds.py (placeholders until R8).

const SOUNDS := {
	&"hover": preload("res://ui/sounds/hover.wav"),
	&"slot": preload("res://ui/sounds/slot.wav"),
	&"key": preload("res://ui/sounds/key.wav"),
	&"back": preload("res://ui/sounds/back.wav"),
}

var _players := {}


func _ready() -> void:
	for id: StringName in SOUNDS:
		var p := AudioStreamPlayer.new()
		p.stream = SOUNDS[id]
		p.max_polyphony = 3
		add_child(p)
		_players[id] = p


func play(id: StringName) -> void:
	var p: AudioStreamPlayer = _players.get(id)
	if p:
		p.play()
