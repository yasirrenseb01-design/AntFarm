// AntNative: loops of the nest view written in C++ - each the very sums its GDScript did (GDScript's float is a double,
// the engine's vectors are floats: kept so here, so the picture is the same to the last bit - checked with --view-hash).
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class AntNative : public RefCounted {
	GDCLASS(AntNative, RefCounted)

protected:
	static void _bind_methods();

public:
	static double density_at(const PackedFloat32Array &soft, const PackedInt32Array &dims, const Vector3 &p);
	static Array soil_hits(const PackedFloat32Array &soft, const PackedInt32Array &dims, const Transform3D &t2,
			const PackedVector3Array &pts, const Vector3 &up, const Vector3 &side);
};

} // namespace godot
