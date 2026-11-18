extends SceneTree
# Runtime test cases for the motion matching extension. One case per process:
#   godot --headless --fixed-fps 120 --path <project> -s cases.gd -- <case>
# Each case prints "RESULT <case> PASS|FAIL <details>". A crash prints no RESULT line.
# tests/run_tests.sh runs every case and also checks the log where noted.
#
# The pose databases are written by hand (Raw normalization, two or three poses), so no
# bake is needed. MMAnimationNode sits in a BlendTree as in a real project: tree_root must
# be an AnimationRootNode, which an AnimationNodeExtension is not.

var case_name := ""
var frame := 0
var matches := [] # [physics frame, animation] for every on_query_result
var character: Node
var character2: Node
var tree: AnimationTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	case_name = args[0] if args.size() > 0 else ""
	if not has_method("setup_" + case_name):
		print("RESULT %s FAIL unknown case" % case_name)
		quit(1)
		return
	call("setup_" + case_name)


func _physics_process(_delta: float) -> bool:
	frame += 1
	return call("check_" + case_name)


func finish(ok: bool, details: String) -> bool:
	print("RESULT %s %s %s" % [case_name, "PASS" if ok else "FAIL", details])
	quit(0 if ok else 1)
	return true


# ---------------------------------------------------------------- helpers

func add_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	root.add_child(body)


func make_character(pos: Vector3, yaw: float) -> Node:
	var c = ClassDB.instantiate("MMCharacter")
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.position = Vector3(0, 1, 0)
	c.add_child(shape)
	c.position = pos
	c.rotation = Vector3(0, yaw, 0)
	c.check_environment = false
	return c


func make_skeleton() -> Skeleton3D:
	var s := Skeleton3D.new()
	s.name = "Skeleton3D"
	s.add_bone("root")
	return s


func trajectory_feature(future: int, height: bool) -> Resource:
	var f = ClassDB.instantiate("MMTrajectoryFeature")
	f.normalization_mode = 0 # Raw
	f.future_frames = future
	f.past_frames = 0
	f.include_height = height
	f.include_facing = false
	return f


# rows: animation name -> feature values of its one pose (time 0).
# with_file_path: pretend the library was loaded from res://mm.tres, so the clip names of
# the old file-name-based code ("mm/<animation>") also resolve. Only fix14 leaves it empty.
func make_library(features: Array, rows: Dictionary, with_file_path := true) -> Resource:
	var lib = ClassDB.instantiate("MMAnimationLibrary")
	if with_file_path:
		lib.resource_path = "res://mm.tres"
	for anim_name in rows.keys():
		var a := Animation.new()
		a.length = 1.0
		a.loop_mode = Animation.LOOP_LINEAR
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, "Skeleton3D:root")
		a.position_track_insert_key(t, 0.0, Vector3())
		lib.add_animation(anim_name, a)
	lib.features = features
	var names = lib.get_animation_list()
	var data := PackedFloat32Array()
	var anim_index := PackedInt32Array()
	var time_index := PackedFloat32Array()
	var pose_offset := PackedInt32Array()
	var kd_nodes := PackedInt32Array()
	for i in names.size():
		pose_offset.append(data.size())
		data.append_array(rows[String(names[i])])
		anim_index.append(i)
		time_index.append(0.0)
		# K-D tree in pre-order, -1 = no child: a chain of right children. Valid because the
		# rows used here never decrease on any split axis.
		kd_nodes.append(i)
		kd_nodes.append(-1)
	kd_nodes.append(-1)
	lib.motion_data = data
	lib.db_anim_index = anim_index
	lib.db_time_index = time_index
	lib.db_pose_offset = pose_offset
	lib.node_indices = kd_nodes
	return lib


func blend_tree_with(node: AnimationNode) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	bt.add_node(&"mm", node)
	bt.connect_node(&"output", 0, &"mm")
	return bt


# Character on a floor with a skeleton and an AnimationTree playing MMAnimationNode.
func make_rig(lib: Resource, library_key: StringName = &"mm") -> void:
	add_floor()
	character = make_character(Vector3(0, 0.05, 0), 0.0)
	character.trajectory_point_count = 2
	character.trajectory_delta_time = 0.5
	character.history_point_count = 1
	character.emit_result_signal = true
	var skeleton := make_skeleton()
	character.add_child(skeleton)
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	var node = ClassDB.instantiate("MMAnimationNode")
	node.library = library_key
	node.query_frequency = 0.01 # periodic queries only every 100 s
	node.blending_enabled = false
	tree.tree_root = blend_tree_with(node)
	if lib:
		tree.add_animation_library(&"mm", lib)
	tree.root_motion_track = NodePath("Skeleton3D:root")
	character.add_child(tree)
	character.skeleton = skeleton
	character.animation_tree = tree
	character.connect("on_query_result", func(d): matches.append([frame, String(d["animation"])]))
	root.add_child(character)


func first_match() -> String:
	return matches[0][1] if matches.size() > 0 else ""


# ---------------------------------------------------------------- cases

# fix01: a character standing still (or falling straight down) keeps its facing.
func setup_fix01_keep_facing_when_still() -> void:
	add_floor()
	character = make_character(Vector3(0, 0.05, 0), 1.0) # standing
	character2 = make_character(Vector3(50, 20, 0), 1.0) # falling
	root.add_child(character)
	root.add_child(character2)


func check_fix01_keep_facing_when_still() -> bool:
	if frame < 60:
		return false
	var ok: bool = absf(character.rotation.y - 1.0) < 1e-3 and absf(character2.rotation.y - 1.0) < 1e-3
	for p in character.get_trajectory() + character2.get_trajectory():
		ok = ok and absf(p["facing"] - 1.0) < 1e-3
	return finish(ok, "standing yaw=%.3f falling yaw=%.3f standing trajectory facing=%.3f falling trajectory facing=%.3f" % [
		character.rotation.y, character2.rotation.y,
		character.get_trajectory()[-1]["facing"], character2.get_trajectory()[-1]["facing"]])


# fix02: a sudden target velocity forces a query (periodic queries are 100 s apart).
func setup_fix02_target_velocity_forces_query() -> void:
	make_rig(make_library([trajectory_feature(2, false)], {
		"idle": PackedFloat32Array([0, 0, 0, 0]),
		"walk": PackedFloat32Array([0, 1, 0, 2])}))


func check_fix02_target_velocity_forces_query() -> bool:
	if frame == 60:
		character.target_velocity = Vector3(0, 0, 3) # straight ahead: no facing change
	if frame < 70:
		return false
	var walk_frames := matches.filter(func(m): return m[1].ends_with("walk")).map(func(m): return m[0])
	var ok: bool = first_match().ends_with("idle") and walk_frames.size() > 0 and walk_frames[0] <= 62
	return finish(ok, "matches [frame, animation]: %s" % str(matches))


# fix03: the motion matching input parameter holds no MMQueryInput.
func setup_fix03_null_query_input() -> void:
	tree = AnimationTree.new()
	var node = ClassDB.instantiate("MMAnimationNode")
	node.library = &"mm"
	tree.tree_root = blend_tree_with(node)
	tree.add_animation_library(&"mm", make_library([trajectory_feature(2, false)], {"idle": PackedFloat32Array([0, 0, 0, 0])}))
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	root.add_child(tree)


func check_fix03_null_query_input() -> bool:
	tree.set("parameters/mm/motion_matching_input", null)
	return false if frame < 10 else finish(true, "survived 10 physics frames")


# fix04: with include_height, height_weight scales the height (y), not z.
# Standing still the query is (0, 0, 0). "up" differs only in y (0.5), "ahead" only in z (0.6).
func setup_fix04_height_weight_on_height() -> void:
	var f = trajectory_feature(1, true)
	f.height_weight = 0.1
	make_rig(make_library([f], {
		"ahead": PackedFloat32Array([0, 0, 0.6]),
		"up": PackedFloat32Array([0, 0.5, 0])}))


func check_fix04_height_weight_on_height() -> bool:
	if frame < 20:
		return false
	return finish(first_match().ends_with("up"), "matches: %s (expected up)" % str(matches))


# fix06a: a library baked before the K-D tree existed (no node_indices).
func setup_fix06a_stale_database_no_kd_tree() -> void:
	var lib = make_library([trajectory_feature(2, false)], {"idle": PackedFloat32Array([0, 0, 0, 0])})
	lib.node_indices = PackedInt32Array()
	make_rig(lib)


func check_fix06a_stale_database_no_kd_tree() -> bool:
	return false if frame < 10 else finish(true, "survived 10 physics frames")


# fix06b: all features removed after baking (the query has 0 dimensions).
func setup_fix06b_stale_database_no_features() -> void:
	var lib = make_library([trajectory_feature(2, false)], {"idle": PackedFloat32Array([0, 0, 0, 0])})
	lib.features = []
	make_rig(lib)


func check_fix06b_stale_database_no_features() -> bool:
	return false if frame < 10 else finish(true, "survived 10 physics frames")


# fix07: the node's library does not exist. run_tests.sh fails the case on "Invalid node info".
func setup_fix07_missing_library_valid_result() -> void:
	make_rig(null, &"no_such_library")


func check_fix07_missing_library_valid_result() -> bool:
	return false if frame < 10 else finish(true, "ran 10 physics frames")


# fix09: at 120 Hz, 3 history points 0.5 s apart all get written (none left at the origin).
func setup_fix09_history_buffer_120hz() -> void:
	add_floor()
	character = make_character(Vector3(10, 0.05, 10), 0.0)
	character.history_point_count = 3
	character.history_delta_time = 0.5
	character.target_velocity = Vector3(1, 0, 0)
	root.add_child(character)


func check_fix09_history_buffer_120hz() -> bool:
	if frame < 480: # 4 s
		return false
	var history: Array = character.get_trajectory_history()
	var ok: bool = history.size() == 3
	for p in history:
		ok = ok and (p["position"] as Vector3).length() > 5.0
	return finish(ok, "physics_ticks=%d history=%s" % [Engine.physics_ticks_per_second,
		str(history.map(func(p): return (p["position"] as Vector3).snappedf(0.01)))])


# fix10: a skeleton is set but no AnimationTree.
func setup_fix10_skeleton_without_tree() -> void:
	character = make_character(Vector3(), 0.0)
	var skeleton := make_skeleton()
	character.add_child(skeleton)
	character.skeleton = skeleton
	root.add_child(character)


func check_fix10_skeleton_without_tree() -> bool:
	return false if frame < 10 else finish(true, "survived 10 physics frames")


# fix11: MMBoneDataFeature names a bone the skeleton does not have.
# run_tests.sh needs the error that names the bone in the log.
func setup_fix11_missing_bone_name() -> void:
	var f = ClassDB.instantiate("MMBoneDataFeature")
	f.normalization_mode = 0
	f.bone_names = PackedStringArray(["no_such_bone"])
	make_rig(make_library([f], {"idle": PackedFloat32Array([0, 0, 0])}))


func check_fix11_missing_bone_name() -> bool:
	return false if frame < 10 else finish(true, "survived 10 physics frames")


# fix13: db_pose_offset is registered as PackedInt32Array.
func setup_fix13_pose_offset_type() -> void:
	pass


func check_fix13_pose_offset_type() -> bool:
	for p in ClassDB.class_get_property_list("MMAnimationLibrary", true):
		if p["name"] == "db_pose_offset":
			return finish(p["type"] == TYPE_PACKED_INT32_ARRAY, "type=%s" % type_string(p["type"]))
	return finish(false, "property not found")


# fix14: the matched clip is named after the library's name in the AnimationTree ("mm"),
# not its resource path (empty here, as for a library made in code).
func setup_fix14_clip_name_uses_library_key() -> void:
	make_rig(make_library([trajectory_feature(2, false)], {"idle": PackedFloat32Array([0, 0, 0, 0])}, false))


func check_fix14_clip_name_uses_library_key() -> bool:
	if frame < 10:
		return false
	return finish(first_match() == "mm/idle", "first match: \"%s\" (expected \"mm/idle\")" % first_match())
