class_name RwModel
## Helpers for the original models exported by tools/export_models.py (placeholders).

const FRAME_SHADER := preload("res://viewer/rw_frame.gdshader")
const FRAME_SIZE := 128


## Replace the glTF materials of every textured surface under `root` with the frame shader so
## multi-frame textures (128 x n*128) show `frame` instead of the whole stack. Surfaces with
## transparency (blend) keep their material.
static func apply_frames(root: Node, frame := 0) -> void:
	var cache := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if m == null or m.albedo_texture == null or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			if not cache.has(m):
				var tex := m.albedo_texture
				var frames := maxi(tex.get_height() / FRAME_SIZE, 1)
				var sm := ShaderMaterial.new()
				sm.shader = FRAME_SHADER
				sm.set_shader_parameter("albedo_tex", tex)
				sm.set_shader_parameter("frames", float(frames))
				sm.set_shader_parameter("frame", float(mini(frame, frames - 1)))
				sm.set_shader_parameter("tint", m.albedo_color)
				sm.set_shader_parameter("roughness", m.roughness)
				cache[m] = sm
			mi.set_surface_override_material(si, cache[m])
