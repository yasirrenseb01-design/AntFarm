extends Node
## One game at a time (PART EA2). The game listens on a local port (127.0.0.1 only: nothing leaves the computer); a
## second copy started from the desktop shortcut finds it there, says "show" and quits before it touches a save. The
## one running comes forward - out of the wallpaper if it is the wallpaper (the shortcut works as the tray icon does).
## Two copies used to run side by side and write the same save in turn.

signal wake                          # a second copy was started: come forward

const PORT := 47815                  # (+1 with --sandbox: tests run beside the keeper's game)

var _server: TCPServer
var _peers: Array = []
var _port := 0
var _retry_t := 0.0


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
		_peers.append(_server.take_connection())
	for p in _peers.duplicate():
		p.poll()
		if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_peers.erase(p)
		elif p.get_available_bytes() > 0:
			var said: String = p.get_utf8_string(p.get_available_bytes())
			_peers.erase(p)
			p.disconnect_from_host()
			if said.begins_with("show"):
				wake.emit()


func _exit_tree() -> void:
	if _server != null:
		_server.stop()
