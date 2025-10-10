extends Node
class_name Util

static func create_circle_texture(radius: float, color: Color) -> Texture2D:
	var r: int = int(ceil(max(radius, 1.0)))
	var size: int = max(1, r * 2)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(r, r)
	var rr := float(r)
	var rr2 := rr * rr
	for y in range(size):
		for x in range(size):
			var d2 := (Vector2(x, y) - center).length_squared()
			if d2 <= rr2:
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	return tex