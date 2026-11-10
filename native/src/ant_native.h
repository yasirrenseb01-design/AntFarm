// AntNative: loops of the nest view written in C++ - each the very sums its GDScript did (GDScript's float is a double,
// the engine's vectors are floats: kept so here, so the picture is the same to the last bit - checked with --view-hash).
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class AntNative : public RefCounted {
	GDCLASS(AntNative, RefCounted)

protected:
	static void _bind_methods();

public:
	static double density_at(const PackedFloat32Array &soft, const PackedInt32Array &dims, const Vector3 &p);
	static PackedFloat32Array soft_build(const PackedByteArray &rho, const PackedInt32Array &box);
	static PackedFloat32Array chunk_sample(const PackedByteArray &rho, const PackedInt32Array &box, const Vector3i &k, int64_t ch);
	static Dictionary field_from(const PackedByteArray &rho, const PackedInt32Array &box, const Array &starts);
	static int64_t bend_probe(const PackedFloat32Array &soft, const PackedInt32Array &dims, const Transform3D &tr, const Vector3 &off,
			const Vector2 &b, const Vector2 &lowered, const Vector2 &sb, const PackedVector3Array &head_pts, const PackedVector3Array &gaster_pts);
	static Array soil_hits(const PackedFloat32Array &soft, const PackedInt32Array &dims, const Transform3D &t2,
			const PackedVector3Array &pts, const Vector3 &up, const Vector3 &side);
};

} // namespace godot
