extends RefCounted
## The developer's own machine (the keeper, 2026-11-21): there the Colony Harmony points have no cap (game/harmony.gd)
## and the menu has the developer's tab (PART 0.14 steps 8-10). Known by a hash of the machine's id (OS.get_unique_id,
## salted) - the id itself is not in the code; another machine is a player's, whatever build it runs (the store's zip
## too). A new machine of the developer's: run tools/dev/machine_hash.gd on it and add its line to HASHES.
##   --as-player (command line): this machine as a player's (to see the cap, the menu without the tab)

const SALT := "antfarm-dev:"
const HASHES := [
	"eb293f365ba5359db5094b6c0d33a3d3887b848207a5ff4bafa9e7ab35f4c8c5",     # the keeper's laptop (2026-11-21)
]

static var forced := -1          # (tests: 1 a developer's, 0 a player's; -1 as the machine is)
static var _known := -1


static func is_dev() -> bool:
	if forced >= 0:
		return forced == 1
	if _known < 0:
		var id := OS.get_unique_id()
		_known = 1 if id != "" and hash_of(id) in HASHES and not OS.get_cmdline_user_args().has("--as-player") else 0
	return _known == 1


static func hash_of(id: String) -> String:
	return (SALT + id).sha256_text()
