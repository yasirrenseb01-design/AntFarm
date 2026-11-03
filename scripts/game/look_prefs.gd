extends RefCounted
## How the mouse turns the view (the keeper, 2026-11-03: a mouse sensitivity setting): one speed for the Home's look
## round and the colony's cameras turning by a drag, and the up-and-down the other way if wanted. Set from the settings
## ("look_speed" 0.25-3, "look_invert") by main.gd as they change; read where the mouse turns a camera.

const MIN := 0.25
const MAX := 3.0

static var speed := 1.0
static var invert := false


static func apply(s: Dictionary) -> void:
	speed = clampf(float(s.get("look_speed", 1.0)), MIN, MAX)
	invert = bool(s.get("look_invert", false))


## The mouse's pixels as the turn: x across, y up and down (turned over when invert).
static func turn(rel: Vector2) -> Vector2:
	return Vector2(rel.x, -rel.y if invert else rel.y) * speed
