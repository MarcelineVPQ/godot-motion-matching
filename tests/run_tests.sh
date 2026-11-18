#!/usr/bin/env bash
# Runs every test case against one build of the extension. See tests/README.md.
#   GODOT=/path/to/godot tests/run_tests.sh <path/to/libgdmotionmatching...so> [path/to/src]
# [path/to/src] is the source folder for the C++ stats check (default: this repo's src/).
# Each case runs in its own headless Godot process, so a crash cannot hide the other cases.
# Godot gets its own temporary HOME and XDG folders, so your editor settings are not touched.
set -u
TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(dirname "$TESTS_DIR")
LIB=${1:?usage: GODOT=/path/to/godot tests/run_tests.sh <library .so> [src dir]}
LIB=$(realpath "$LIB")
SRC_DIR=$(realpath "${2:-$REPO_DIR/src}")
GODOT=${GODOT:?set GODOT to the Godot editor binary}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mm-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

RUNTIME_CASES="fix01_keep_facing_when_still fix02_target_velocity_forces_query fix03_null_query_input
fix04_height_weight_on_height fix06a_stale_database_no_kd_tree fix06b_stale_database_no_features
fix07_missing_library_valid_result fix09_history_buffer_120hz fix10_skeleton_without_tree
fix11_missing_bone_name fix13_pose_offset_type fix14_clip_name_uses_library_key"
EDITOR_CASES="fix05_empty_feature_slot fix08_gizmo_default_library"

mkdir -p "$WORK/home" "$WORK/config/godot" "$WORK/data" "$WORK/cache" "$WORK/run" "$WORK/logs"
chmod 700 "$WORK/run"
ISOLATED=(env -u DISPLAY -u WAYLAND_DISPLAY HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/config"
    XDG_DATA_HOME="$WORK/data" XDG_CACHE_HOME="$WORK/cache" XDG_RUNTIME_DIR="$WORK/run")
# The editor stays offline (editor settings are per major.minor version).
version=$("${ISOLATED[@]}" "$GODOT" --version 2>/dev/null | cut -d. -f1,2)
printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\nnetwork/connection/network_mode = 0\nnetwork/connection/engine_version_update_mode = 0\n' \
    > "$WORK/config/godot/editor_settings-$version.tres"

fresh_project() { # A clean copy of the test project with the library to test.
    rm -rf "$WORK/project"
    cp -r "$TESTS_DIR/project" "$WORK/project"
    mkdir -p "$WORK/project/addons/motion_matching/bin/linux" "$WORK/project/.godot"
    cp "$REPO_DIR/addons/motion_matching/gdmotionmatching.gdextension" "$WORK/project/addons/motion_matching/"
    cp "$LIB" "$WORK/project/addons/motion_matching/bin/linux/libgdmotionmatching.linux.template_debug.x86_64.so"
    echo "res://addons/motion_matching/gdmotionmatching.gdextension" > "$WORK/project/.godot/extension_list.cfg"
}

failed=0
report() { # report <case> <log> <exit code>
    local line
    line=$(grep -m1 "^RESULT $1 " "$2")
    case $1 in
    fix07_missing_library_valid_result)
        grep -q "Invalid node info" "$2" && line="RESULT $1 FAIL the engine printed 'Invalid node info'" ;;
    fix11_missing_bone_name)
        [ -n "$line" ] && if grep -q 'bone "no_such_bone" is not in' "$2"; then
            line="RESULT $1 PASS $(grep -m1 'bone "no_such_bone" is not in' "$2")"
        else line="RESULT $1 FAIL no error names the missing bone"; fi ;;
    fix05_empty_feature_slot)
        [ -n "$line" ] && ! grep -q "Feature 0 is empty" "$2" && line="RESULT $1 FAIL bake gave no error about the empty slot" ;;
    esac
    if [ -z "$line" ]; then
        local why last
        why=$(grep -m1 -oE "Program crashed with signal [0-9]+" "$2")
        last=$(grep "^STEP" "$2" | tail -1)
        line="RESULT $1 FAIL no result, exit $3${why:+ ($why)}${last:+, last step: $last}"
    fi
    echo "$line"
    case $line in *" PASS "*) ;; *) failed=$((failed + 1)) ;; esac
}

echo "library: $LIB ($(sha256sum "$LIB" | cut -c1-12))"
fresh_project
for c in $RUNTIME_CASES; do
    "${ISOLATED[@]}" timeout 60 "$GODOT" --headless --fixed-fps 120 --path "$WORK/project" -s cases.gd -- "$c" \
        > "$WORK/logs/$c.log" 2>&1
    report "$c" "$WORK/logs/$c.log" $?
done
for c in $EDITOR_CASES; do
    fresh_project
    "${ISOLATED[@]}" MM_TEST_CASE="$c" timeout 180 "$GODOT" --headless --editor --path "$WORK/project" \
        > "$WORK/logs/$c.log" 2>&1
    report "$c" "$WORK/logs/$c.log" $?
done
if ${CXX:-g++} -std=c++17 -O2 -I"$SRC_DIR" "$TESTS_DIR/fix12_stats_precision.cpp" -o "$WORK/fix12" > "$WORK/logs/fix12.log" 2>&1; then
    "$WORK/fix12" > "$WORK/logs/fix12_stats_precision.log" 2>&1
    report fix12_stats_precision "$WORK/logs/fix12_stats_precision.log" $?
else
    echo "RESULT fix12_stats_precision FAIL does not compile: $(head -c 300 "$WORK/logs/fix12.log")"; failed=$((failed + 1))
fi
[ -n "${KEEP_LOGS:-}" ] && { mkdir -p "$KEEP_LOGS" && cp "$WORK"/logs/*.log "$KEEP_LOGS"/; }
echo "$failed failed"
[ "$failed" -eq 0 ]
