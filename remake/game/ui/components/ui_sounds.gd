class_name UiSounds
extends Node
## Menu sound effects: play(&"hover" | &"slot" | &"key" | &"back" | &"denied" | &"toggle" |
## &"quit" | &"ambience"), stop(id).
##
## Uses the original game's own menu sounds when tools/export_audio.py has written them to
## res://_import/audio (gitignored game data; loaded at runtime, no Godot import step).
## Without the import it falls back to our placeholders from remake/art/ui/sounds/make_sounds.py.
## Wave ids and how they were identified: docs/analysis.md, "Waves".

const IMPORT_DIR := "res://_import/audio/"

## UI event -> original type-12 wave id. The 1997 menu plays no sound on hover, so hover
## keeps the placeholder.
const ORIGINAL := {
	&"key": 8403,       # bottom-bar key select (script 8341)
	&"slot": 8404,      # left/right column slot select (scripts 8353, 8354)
	&"back": 8404,      # no original equivalent; stepping back re-selects a column
	&"denied": 74,      # action not available (script 8350)
	&"toggle": 75,      # option toggled / confirmed (script 8351)
	&"quit": 131,       # Escape on the main menu: quit-confirm prompt (script 8312)
	&"ambience": 8398,  # menu background loop (script 8315, looped)
}

const LOOPING := [&"ambience"]

const PLACEHOLDERS := {
	&"hover": preload("res://ui/sounds/hover.wav"),
	&"slot": preload("res://ui/sounds/slot.wav"),
	&"key": preload("res://ui/sounds/key.wav"),
	&"back": preload("res://ui/sounds/back.wav"),
}

## Placeholder to use for ids that have no placeholder of their own.
const PLACEHOLDER_ALIAS := {&"denied": &"back", &"toggle": &"slot", &"quit": &"back"}

var _players := {}


func _ready() -> void:
	var ids: Array = PLACEHOLDERS.keys()
	for id: StringName in ORIGINAL:
		if not ids.has(id):
			ids.append(id)
	for id: StringName in ids:
		var stream := _stream(id)
		if stream == null:
			continue
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.max_polyphony = 1 if LOOPING.has(id) else 3
		add_child(p)
		_players[id] = p


func play(id: StringName) -> void:
	var p: AudioStreamPlayer = _players.get(id)
	if p and not (LOOPING.has(id) and p.playing):
		p.play()


func stop(id: StringName) -> void:
	var p: AudioStreamPlayer = _players.get(id)
	if p:
		p.stop()


## True when the original sound for this id was found in the import.
func is_original(id: StringName) -> bool:
	var p: AudioStreamPlayer = _players.get(id)
	return p != null and p.stream.has_meta(&"original_wave")


func _stream(id: StringName) -> AudioStream:
	if ORIGINAL.has(id):
		var path := IMPORT_DIR + "wave_%d.wav" % ORIGINAL[id]
		if FileAccess.file_exists(path):
			var wav := AudioStreamWAV.load_from_file(path)
			if wav:
				wav.set_meta(&"original_wave", ORIGINAL[id])
				if LOOPING.has(id):
					var frame_bytes := (2 if wav.stereo else 1) * (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1)
					wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
					wav.loop_begin = 0
					wav.loop_end = wav.data.size() / frame_bytes
				return wav
	if LOOPING.has(id):
		return null  # no placeholder ambience
	return PLACEHOLDERS.get(PLACEHOLDER_ALIAS.get(id, id))
