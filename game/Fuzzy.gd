extends RefCounted
class_name Fuzzy

static func aggression(energy: float, max_energy: float, pos_x: float, field_mid_x: float) -> float:
	var e: float = 0.0
	if max_energy > 0.0:
		e = clamp(energy / max_energy, 0.0, 1.0)

	var abs_mid: float = abs(field_mid_x)
	var denom: float = 1.0 if abs_mid <= 1.0 else abs_mid

	var raw: float = (pos_x - field_mid_x) / denom
	var pos_bias: float = 0.5 + clamp(raw, -0.5, 0.5)

	return clamp(0.3 * e + 0.7 * pos_bias, 0.0, 1.0)
