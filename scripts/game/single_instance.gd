extends Node
## One game at a time (PART EA2). The game listens on a local port (127.0.0.1 only: nothing leaves the computer); a
## second copy started from the desktop shortcut finds it there, says "show" and quits before it touches a save. The
## one running comes forward - out of the wallpaper if it is the wallpaper (the shortcut works as the tray icon does).
## Two copies used to run side by side and write the same save in turn.

signal wake                          # a second copy was started: come forward

const PORT := 47815                  # (+1 with --sandbox: tests run beside the keeper's game)
# (PART EA-R R8) any program on this computer can connect here: only a few bytes are read, a connection that says
# nothing is dropped, only a few are held at once, and the game comes forward at most once a second
const MAX_SAID := 64
const PEER_TIMEOUT_MS := 2000
const MAX_PEERS := 8
const WAKE_GAP_MS := 1000

var _server: TCPServer
var _peers: Array = []
var _port := 0
var _retry_t := 0.0
var _woke_at := -WAKE_GAP_MS


## Whether a game is running already (then it has been told to come forward).
static func tell_running(port: int) -> bool:
	var c := StreamPeerTCP.new()
	if c.connect_to_host("127.0.0.1", port) != OK:
		return false
	var until := Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < until:
		c.poll()
		match c.get_status():
			StreamPeerTCP.STATUS_CONNECTED:
				c.put_data("show\n".to_utf8_buffer())
				c.poll()
				OS.delay_msec(50)            # (let it go out before this copy quits)
				c.disconnect_from_host()
				return true
			StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
				return false
		OS.delay_msec(10)
	return false


func listen(port: int) -> void:
	_port = port
	_server = TCPServer.new()
	if _server.listen(port, "127.0.0.1") != OK:
		_server = null                     # (still held, or taken by something else: tried again every 2 s)


## Stops listening (the game is about to start itself again as the wallpaper: the new copy takes the port over).
func stop() -> void:
	_port = 0
	if _server != null:
		_server.stop()
		_server = null


func _process(delta: float) -> void:
	if _server == null:
		_retry_t += delta
		if _port != 0 and _retry_t >= 2.0:
			_retry_t = 0.0
			listen(_port)
		return
	while _server.is_connection_available():
		var c := _server.take_connection()
		if _peers.size() >= MAX_PEERS:
			c.disconnect_from_host()
		else:
			_peers.append([c, Time.get_ticks_msec()])
	var now := Time.get_ticks_msec()
	for e in _peers.duplicate():
		var p: StreamPeerTCP = e[0]
		p.poll()
		var n := p.get_available_bytes()
		if p.get_status() != StreamPeerTCP.STATUS_CONNECTED or n > 0 or now - e[1] > PEER_TIMEOUT_MS:
			var said: String = p.get_utf8_string(mini(n, MAX_SAID)) if n > 0 else ""
			_peers.erase(e)
			p.disconnect_from_host()
			if said.begins_with("show") and now - _woke_at >= WAKE_GAP_MS:
				_woke_at = now
				wake.emit()


func _exit_tree() -> void:
	if _server != null:
		_server.stop()
