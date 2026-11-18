#ifndef MM_FEATURE_H
#define MM_FEATURE_H

#include "common.h"
#include "mm_query.h"

#include <godot_cpp/classes/animation.hpp>
#include <godot_cpp/classes/animation_player.hpp>
#include <godot_cpp/classes/editor_node3d_gizmo.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

using namespace godot;

class MMCharacter;

class MMFeature : public Resource {
    GDCLASS(MMFeature, Resource)

public:
    enum NormalizationMode { Raw,
                             Standard,
                             MinMax };

public:
    MMFeature(/* args */);
    virtual ~MMFeature();
    virtual void setup_skeleton(const MMCharacter* p_character, const AnimationMixer* p_player, const Skeleton3D* p_skeleton) {};

    virtual void setup_for_animation(Ref<Animation> animation) {};

    virtual int64_t get_dimension_count() const = 0;
    // Numbers that belong together (a bone's three position numbers, all trajectory positions) share
    // one spread in the standard normalisation, as in Holden et al. 2020: each number scaled by its
    // own spread lets small-spread, low-information numbers count as much as the big ones.
    // Default: each number is its own group.
    virtual int64_t get_normalization_group(int64_t p_dim) const { return p_dim; }

    virtual PackedFloat32Array bake_animation_pose(Ref<Animation> p_animation, double time) const = 0;

    virtual PackedFloat32Array evaluate_runtime_data(const MMQueryInput& p_query_input) const = 0;

    virtual void display_data(const Ref<EditorNode3DGizmo>& p_gizmo, const Transform3D p_transform, const float* p_data) const {};

    virtual float calculate_normalized_weight(int64_t p_feature_dim) const {
        return weight / get_dimension_count();
    }

    void normalize(float* p_data) const;
    void denormalize(float* p_data) const;

    GETSET(float, weight, 1.0f);
    GETSET(NormalizationMode, normalization_mode, Standard);
    GETSET(PackedFloat32Array, means);
    GETSET(PackedFloat32Array, std_devs);
    GETSET(PackedFloat32Array, maxes);
    GETSET(PackedFloat32Array, mins);

protected:
    static void _bind_methods();
    void _normalize_minmax(float* p_data) const;
    void _denormalize_minmax(float* p_data) const;
    void _normalize_standard(float* p_data) const;
    void _denormalize_standard(float* p_data) const;
};

#endif // MM_FEATURE_H
