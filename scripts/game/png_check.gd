extends RefCounted
## Whether the bytes of a PNG say a picture no bigger than max_w x max_h - read from its header, before anything is
## decoded (v0.12.9, the security review of 2026-11-08): a file small enough to be read can still say 16 000 x 16 000
## pixels of one colour (squeezed into under 1 MB) and the decoder would take over a gigabyte of memory before the size
## was looked at. Used by nest_card.gd and outworld_card.gd for the pictures beside the saves.

const SIGNATURE := [137, 80, 78, 71, 13, 10, 26, 10]


static func fits(buf: PackedByteArray, max_w: int, max_h: int) -> bool:
	if buf.size() < 24:
		return false
	for i in SIGNATURE.size():
		if buf[i] != SIGNATURE[i]:
			return false
	if buf.slice(12, 16).get_string_from_ascii() != "IHDR":    # (the first chunk of every PNG)
		return false
	var w := (buf[16] << 24) | (buf[17] << 16) | (buf[18] << 8) | buf[19]
	var h := (buf[20] << 24) | (buf[21] << 16) | (buf[22] << 8) | buf[23]
	return w > 0 and h > 0 and w <= max_w and h <= max_h
