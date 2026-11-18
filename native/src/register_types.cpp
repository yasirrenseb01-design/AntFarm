// AntFarm native part: registers AntNative (src/ant_native.h).
#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include "ant_native.h"
#include "forager_step.h"
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>

using namespace godot;

// ForagerStep reads GDScript objects (the ants: RefCounted) and the colony's RandomNumberGenerator through Variants: their
// engine classes' bindings registered (godot-cpp registers only the engine classes the code refers to by name)
static internal::EngineClassRegistration<Object> reg_object;
static internal::EngineClassRegistration<RefCounted> reg_ref_counted;
static internal::EngineClassRegistration<RandomNumberGenerator> reg_rng;

static void init_ant_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(AntNative);
	GDREGISTER_CLASS(ForagerStep);
}

static void uninit_ant_native(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT ant_native_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(init_ant_native);
	init_obj.register_terminator(uninit_ant_native);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
