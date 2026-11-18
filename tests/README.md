# Tests

Each fix has one test case (fix 6 has two) named `fixNN_<what it checks>`. Every case runs in its own
headless Godot process, so a crash fails that case and the rest still run. Godot gets a temporary
HOME and XDG folders, so your editor settings and projects are not touched. No GPU is used.

| Case | Checks |
|---|---|
| fix01_keep_facing_when_still | A character standing still or falling straight down keeps its facing |
| fix02_target_velocity_forces_query | A sudden target velocity forces a query |
| fix03_null_query_input | No crash when the query input parameter is empty |
| fix04_height_weight_on_height | `height_weight` scales the height, not z |
| fix05_empty_feature_slot (editor) | No crash when selecting a character with an empty feature slot; Bake reports it |
| fix06a_stale_database_no_kd_tree | No crash on a library without K-D tree data |
| fix06b_stale_database_no_features | No crash when features were removed after baking |
| fix07_missing_library_valid_result | A missing library gives no "Invalid node info" error |
| fix08_gizmo_default_library (editor) | No crash drawing the gizmo of an unbaked library under the default "" name |
| fix09_history_buffer_120hz | At 120 Hz every history point is written |
| fix10_skeleton_without_tree | No crash with a skeleton but no AnimationTree |
| fix11_missing_bone_name | A bone name not in the skeleton gives an error, no out-of-bounds read |
| fix12_stats_precision (C++) | The feature standard deviation stays accurate for a large mean |
| fix13_pose_offset_type | `db_pose_offset` is registered as `PackedInt32Array` |
| fix14_clip_name_uses_library_key | The matched clip is named after the library's name in the AnimationTree |

## Build the library

Build against the Godot binary you test with. On Linux:

```sh
git submodule update --init --recursive
godot --headless --dump-extension-api        # writes extension_api.json in the current folder
scons platform=linux target=template_debug custom_api_file=/path/to/extension_api.json
```

The library lands in `bin/linux/libgdmotionmatching.linux.template_debug.x86_64.so`.

## Run

```sh
GODOT=/path/to/godot tests/run_tests.sh bin/linux/libgdmotionmatching.linux.template_debug.x86_64.so
```

It prints one `RESULT <case> PASS|FAIL <evidence>` line per case and exits non-zero if any case fails.
To test another checkout's library, pass its `src/` folder as the second argument (used by the C++
stats check). Set `KEEP_LOGS=<folder>` to keep the Godot logs. Needs bash, coreutils and a C++17 compiler.
