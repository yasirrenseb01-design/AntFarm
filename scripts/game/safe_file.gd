extends RefCounted
## Files of the keeper's that are written over and over (the saves, slotN.json, harmony.json, home.json, the chart
## sets): written so that a crash, a power cut or a full disk mid-write never costs the last good copy (v0.12.32).
##   write: to <file>.tmp, read back and checked; the file there before kept as <file>.bak; then .tmp renamed to <file>
##   read: <file>, else <file>.tmp (a write cut off between its two renames), else <file>.bak (the one before)
## A file that was there but could not be used when read is not put in .bak at the next write (that would push out
## the last good copy): it is kept as <file>.bad instead. Before v0.12.32 the old file was deleted before the rename
## (power cut between the two: only .tmp left - the slot looked empty and a new colony began over it), nothing was
## checked (a full disk: half a file in place of a good one), and the small files were written over in place.

const SIDES := [".tmp", ".bak", ".bad"]

static var _bad := {}        # path -> true: there when read, and not usable


## Put the written and checked `tmp` in place of `path`, keeping the file there before as path.bak (path.bad if it
## could not be read). False if it could not: the file at `path` then is the one there before, if any.
static func replace(tmp: String, path: String) -> bool:
	var had := FileAccess.file_exists(path)
	var keep := path + (".bad" if _bad.has(path) else ".bak")
	if had:
		if FileAccess.file_exists(keep):
			DirAccess.remove_absolute(keep)
		if DirAccess.rename_absolute(path, keep) != OK:
			return false
	if DirAccess.rename_absolute(tmp, path) != OK:
		if had:
			DirAccess.rename_absolute(keep, path)          # (back as it was)
		return false
	_bad.erase(path)
	return true


## Write `text` to `path` safely (above). False if it could not be written whole: the file there is left as it was.
static func write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	var good := f.get_error() == OK
	f.close()
	if not good or FileAccess.get_file_as_string(tmp) != text:
		DirAccess.remove_absolute(tmp)
		return false
	return replace(tmp, path)


## What `parse` makes of the text of `path` (it returns null for text it cannot use), else of the file's .tmp, else of
## its .bak; null if none (or none there). Files over max_len bytes are not read.
static func read_text(path: String, max_len: int, parse: Callable) -> Variant:
	for p in candidates(path):
		var v = null
		var f := FileAccess.open(p, FileAccess.READ)
		if f != null and f.get_length() <= max_len:
			v = parse.call(f.get_as_text())
		if v != null:
			return v
		if p == path:
			_bad[path] = true
	return null


## The files `path` may be read from, in order (those there).
static func candidates(path: String) -> Array:
	var out: Array = []
	for p in [path, path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(p):
			out.append(p)
	return out


## The file at `path` was there and could not be used (the binary saves: save_store.load_slot).
static func mark_bad(path: String) -> void:
	_bad[path] = true


static func any(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".tmp") or FileAccess.file_exists(path + ".bak")


## Remove the file and its .tmp/.bak/.bad.
static func remove(path: String) -> void:
	for p in [path] + SIDES.map(func(s): return path + s):
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	_bad.erase(path)
