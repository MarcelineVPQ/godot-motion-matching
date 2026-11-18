@tool
extends EditorPlugin
# Editor cases, run headless by tests/run_tests.sh with MM_TEST_CASE set:
#   fix05_empty_feature_slot   select a character whose library has an empty feature slot, then press Bake
#   fix08_gizmo_default_library  open a character whose library uses the default "" name, redraw its gizmo
# Prints "STEP <case> <what>" markers and "RESULT <case> PASS ..." at the end. A crash prints no RESULT.


func _enter_tree() -> void:
	var case_name := OS.get_environment("MM_TEST_CASE")
	if case_name.begins_with("fix0"):
		_run.call_deferred(case_name)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _run(case_name: String) -> void:
	await _wait(10)
	var main := Node3D.new()
	main.name = "Main"
	var character = ClassDB.instantiate("MMCharacter")
	character.name = "Character"
	main.add_child(character)
	character.owner = main
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	skeleton.add_bone("root")
	character.add_child(skeleton)
	skeleton.owner = main
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	character.add_child(tree)
	tree.owner = main

	var library = ClassDB.instantiate("MMAnimationLibrary")
	var animation := Animation.new()
	animation.length = 1.0
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, "Skeleton3D:root")
	animation.position_track_insert_key(track, 0.0, Vector3())
	library.add_animation(&"idle", animation)
	library.sampling_rate = 10.0
	if case_name == "fix05_empty_feature_slot":
		library.features = [null]
		tree.add_animation_library(&"mm", library)
	else:
		library.features = [ClassDB.instantiate("MMTrajectoryFeature")]
		tree.add_animation_library(&"", library) # default name, not baked
	tree.root_motion_track = NodePath("Skeleton3D:root")
	character.skeleton = skeleton
	character.animation_tree = tree

	var scene := PackedScene.new()
	scene.pack(main)
	ResourceSaver.save(scene, "res://case_scene.tscn")
	EditorInterface.open_scene_from_path("res://case_scene.tscn")
	await _wait(10)
	print("STEP %s scene open" % case_name)
	var edited = EditorInterface.get_edited_scene_root().get_node("Character")
	EditorInterface.edit_node(edited) # MM editor: data tab calls needs_baking()
	await _wait(10)
	print("STEP %s character selected" % case_name)
	if case_name == "fix05_empty_feature_slot":
		for button in EditorInterface.get_base_control().find_children("*", "Button", true, false):
			if button.text == "Bake":
				button.emit_signal("pressed")
				print("STEP %s bake pressed" % case_name)
		await _wait(5)
	else:
		edited.update_gizmos() # MMEditorGizmoPlugin redraw -> display_data("", pose)
		await _wait(10)
		print("STEP %s gizmo update requested" % case_name)
	print("RESULT %s PASS editor survived every step" % case_name)
	get_tree().quit()
