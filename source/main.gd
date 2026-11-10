extends Node3D
## Moonshot Nutcracker - native OpenXR build.
## Feet come from foot trackers when present, otherwise from the two controllers
## (strap one to each ankle). A fast foot through the bullseye launches the victim
## into the moon. Players on the same network find each other automatically.

const MOON := Vector3(0, 70, -150)
const MR := 22.0
const ARENA := 8.6
const KT := 0.34
const FLY := 2.4
const HIT_R := 0.34
const HIT_SPEED := 1.5
const PORT0 := 47420
const NPORTS := 8
const NET_TAG := "mnc1"
const BUILD := "2026-11-10.4"
const BOT_GRACE := 8.0   # seconds before practice dummies start kicking back
const ALIVE := 0
const FLYING := 1
const GONE := 2

const C_NIGHT := Color("0d0f2b")
const C_MOON := Color("f4e8c1")
const C_LAMP := Color("ffb23e")
const C_HIT := Color("ff4d6d")


class Ent:
	var id := ""
	var name := ""
	var hue := 0.0
	var bot := false
	var x := 0.0
	var z := 0.0
	var yaw := 0.0
	var h := 1.7
	var ph := 0.0
	var fl := Vector3(0, 0.08, 0)
	var fr := Vector3(0, 0.08, 0)
	var pfl := Vector3.ZERO
	var pfr := Vector3.ZERO
	var vl := 0.0
	var vr := 0.0
	var tx := 0.0
	var tz := 0.0
	var tyaw := 0.0
	var th := 1.7
	var tfl := Vector3(0, 0.08, 0)
	var tfr := Vector3(0, 0.08, 0)
	var st := 0
	var fly_t := 0.0
	var gone_t := 0.0
	var pos := Vector3.ZERO
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var c := Vector3.ZERO
	var kick_t := -1.0
	var kick_side := 1
	var side := 1
	var cd := {}
	var score := 0
	var deaths := 0
	var last_k := -1
	var saw_fly := false
	var last_seen := 0.0
	# bot brain
	var wait := 0.0
	var gx := 0.0
	var gz := 0.0
	var wind := 0.0
	var rest := 2.0
	# nodes
	var root: Node3D
	var spin: Node3D
	var torso: MeshInstance3D
	var head: MeshInstance3D
	var arm_l: MeshInstance3D
	var arm_r: MeshInstance3D
	var tag: Label3D
	var boot_l: MeshInstance3D
	var boot_r: MeshInstance3D
	var leg_l: MeshInstance3D
	var leg_r: MeshInstance3D
	var body_visible := true


var origin: XROrigin3D
var cam: XRCamera3D
var xr: XRInterface
var in_vr := false
var me: Ent
var ents := {}          # id -> Ent, other players
var bots: Array[Ent] = []
var booms := []
var craters := []
var now := 0.0

var board3d: Label3D
var toast3d: Label3D
var hud: Label
var hint: Label
var toast_t := 0.0
var last_event := "Kick the bullseye. March in place to walk."
var board_dirty := true

var udp := PacketPeerUDP.new()
var net_ok := false
var my_id := ""
var my_port := 0
var extra_peers: PackedStringArray = []
var last_send := 0.0
var kseq := 0
var kvictim := ""

var sfx := {}
var march := 0.0
var mouse_moved := 0.0

# test switches (command line, after "--")
var opt_log := false
var opt_autokick := false
var opt_shot := ""
var log_t := 0.0
var last_note := ""
# diagnostics: where the main loop is, so a watchdog thread can report a hang
var stage := "startup"
var frame_no := 0
var wd: Thread
var wd_stop := false
# switches for narrowing a problem down (set remotely through the ARGS file)
var test_stall := false
var no_net := false
var no_bots := false
var no_audio := false
var no_labels := false
var no_feet := false
var debug3d: Label3D
var frames := 0
var beat_t := 0.0
var src_l := "-"
var src_r := "-"


func fwd_of(y: float) -> Vector3:
	return Vector3(-sin(y), 0, -cos(y))


func right_of(y: float) -> Vector3:
	return Vector3(cos(y), 0, -sin(y))


func mat(col: Color, unshaded := false, nofog := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = nofog
	return m


func mesh_node(mesh: Mesh, material: Material, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	if parent == null:
		add_child(mi)
	else:
		parent.add_child(mi)
	return mi


func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func disc(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 48
	m.rings = 1
	return m


func ball(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 24
	m.rings = 12
	return m


# ---------------------------------------------------------------- setup

func _ready() -> void:
	randomize()
	for arg in OS.get_cmdline_user_args():
		if arg == "--log":
			opt_log = true
		elif arg == "--autokick":
			opt_autokick = true
		elif arg.begins_with("--shot="):
			opt_shot = arg.substr(7)
		elif arg.begins_with("--peer="):
			extra_peers.append(arg.substr(7))
		elif arg == "--test-stall":
			test_stall = true
		elif arg == "--no-net":
			no_net = true
		elif arg == "--no-bots":
			no_bots = true
		elif arg == "--no-audio":
			no_audio = true
		elif arg == "--no-labels":
			no_labels = true
		elif arg == "--no-feet":
			no_feet = true
	log_system()
	build_world()
	build_audio()
	build_hud()

	origin = XROrigin3D.new()
	add_child(origin)
	cam = XRCamera3D.new()
	cam.far = 800.0
	cam.near = 0.05
	cam.fov = 65.0
	origin.add_child(cam)
	toast3d = Label3D.new()
	toast3d.font_size = 64
	toast3d.pixel_size = 0.0022
	toast3d.modulate = C_MOON
	toast3d.outline_modulate = C_HIT
	toast3d.outline_size = 14
	toast3d.no_depth_test = true
	toast3d.render_priority = 10
	toast3d.position = Vector3(0, 0.28, -1.6)
	toast3d.visible = false
	cam.add_child(toast3d)
	debug3d = Label3D.new()
	debug3d.font_size = 28
	debug3d.pixel_size = 0.0016
	debug3d.modulate = Color("a9acd6")
	debug3d.outline_size = 6
	debug3d.no_depth_test = true
	debug3d.render_priority = 10
	debug3d.position = Vector3(0, -0.42, -1.6)
	cam.add_child(debug3d)

	var pname := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--name="):
			pname = arg.substr(7)
	if pname == "":
		pname = OS.get_environment("SteamAppUser")
	if pname == "":
		pname = "Kicker %d" % (10 + randi() % 90)
	me = make_ent("me", pname.substr(0, 14), randf(), false)
	spawn(me)
	set_bots(true)

	start_xr()
	start_net()
	cam.current = true
	if no_labels:
		board3d.visible = false
		debug3d.visible = false
		me.tag.visible = false
	wd = Thread.new()
	wd.start(_watchdog)
	note("ready")


func _exit_tree() -> void:
	wd_stop = true
	if wd != null and wd.is_started():
		wd.wait_to_finish()


func _watchdog() -> void:
	# runs beside the game; if the main loop stops advancing it says where it was
	var seen := -1
	var since := Time.get_ticks_msec()
	var reported := 0
	while not wd_stop:
		OS.delay_msec(250)
		var t := Time.get_ticks_msec()
		if frame_no != seen:
			if reported > 0:
				print("RESUMED after %.1f s" % ((t - since) / 1000.0))
			seen = frame_no
			since = t
			reported = 0
		elif t - since > 3000 * (reported + 1):
			reported += 1
			print("STALL main loop stuck for %.0f s  frame=%d  stage=%s  last=%s" % [(t - since) / 1000.0, frame_no, stage, last_note])


func log_system() -> void:
	print("== Moonshot Nutcracker build %s ==" % BUILD)
	print("args: ", OS.get_cmdline_args(), " user args: ", OS.get_cmdline_user_args())
	print("os: %s / %s / %s   cpu: %s (%d threads)   arch: %s" % [OS.get_name(), OS.get_distribution_name(), OS.get_version(), OS.get_processor_name(), OS.get_processor_count(), Engine.get_architecture_name()])
	print("gpu: %s / %s   api: %s   driver: %s   method: %s" % [RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method()])
	print("display: %s   window: %s mode=%d   screens=%d   audio: %s" % [DisplayServer.get_name(), DisplayServer.window_get_size(), DisplayServer.window_get_mode(), DisplayServer.get_screen_count(), AudioServer.get_driver_name()])


func log_xr() -> void:
	print("xr interface: %s   initialized=%s   views=%d   target=%s" % [xr.get_name(), xr.is_initialized(), xr.get_view_count(), xr.get_render_target_size()])
	print("xr system: ", xr.get_system_info())
	print("xr refresh: ", xr.get("display_refresh_rate"), "   available: ", xr.call("get_available_display_refresh_rates"))
	print("xr play area mode: ", xr.get_play_area_mode(), "   tracking status: ", xr.get_tracking_status())
	for sig in ["session_begun", "session_visible", "session_focussed", "session_stopping", "session_loss_pending", "instance_exiting", "pose_recentered"]:
		if xr.has_signal(sig):
			xr.connect(sig, note.bind("xr signal: " + sig))
	XRServer.tracker_added.connect(func(tn: StringName, type: int) -> void: note("tracker added: %s (type %d)" % [tn, type]))
	XRServer.tracker_removed.connect(func(tn: StringName, type: int) -> void: note("tracker removed: %s (type %d)" % [tn, type]))
	print("trackers at start: ", XRServer.get_trackers(XRServer.TRACKER_ANY).keys())


func start_xr() -> void:
	xr = XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		in_vr = true
		me.body_visible = false
		me.spin.visible = false
		me.tag.visible = false
		hud.visible = false
		hint.visible = false
		origin.position = Vector3(me.x, 0, me.z)
		log_xr()
		note("xr started")
	else:
		in_vr = false
		print("xr interface found: ", xr != null)
		note("no headset, window mode")


func note(msg: String) -> void:
	last_note = msg
	print("[%.1f] %s" % [now, msg])


func build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = C_NIGHT
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8fa3ff")
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = C_MOON
	sun.light_energy = 0.8
	add_child(sun)
	sun.look_at_from_position(MOON, Vector3.ZERO, Vector3.UP)
	var lamp := OmniLight3D.new()
	lamp.light_color = C_LAMP
	lamp.light_energy = 2.0
	lamp.omni_range = 30.0
	lamp.position = Vector3(0, 7, 0)
	add_child(lamp)

	var ground := mesh_node(disc(130.0, 0.02), mat(Color("1d4a3c")))
	ground.position.y = -0.01
	var chalk := mesh_node(disc(9.6, 0.02), mat(C_MOON, true))
	chalk.position.y = 0.0
	var dirt := mesh_node(disc(9.35, 0.02), mat(Color("7a6544")))
	dirt.position.y = 0.01

	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.07
	pole_mesh.bottom_radius = 0.09
	pole_mesh.height = 4.2
	var pole_mat := mat(Color("2a2f66"))
	var bulb_mat := mat(C_LAMP, true, true)
	for i in 10:
		var ang := float(i) / 10.0 * TAU
		var px := sin(ang) * 11.0
		var pz := cos(ang) * 11.0
		mesh_node(pole_mesh, pole_mat).position = Vector3(px, 2.1, pz)
		mesh_node(ball(0.22), bulb_mat).position = Vector3(px, 4.3, pz)

	# moon with a generated crater texture
	var img := Image.create(256, 128, false, Image.FORMAT_RGB8)
	img.fill(C_MOON)
	for i in 45:
		var cx := randi() % 256
		var cy := randi() % 128
		var rad := 2 + randi() % 10
		var shade := C_MOON.darkened(randf_range(0.12, 0.35))
		for yy in range(maxi(cy - rad, 0), mini(cy + rad, 127) + 1):
			for xx in range(cx - rad, cx + rad + 1):
				if (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy) <= rad * rad:
					img.set_pixel(posmod(xx, 256), yy, shade)
	var moon_mat := mat(Color.WHITE, true, true)
	moon_mat.albedo_texture = ImageTexture.create_from_image(img)
	var moon_mesh := ball(MR)
	moon_mesh.radial_segments = 48
	moon_mesh.rings = 24
	mesh_node(moon_mesh, moon_mat).position = MOON

	# stars
	var star_quad := QuadMesh.new()
	star_quad.size = Vector2(1.8, 1.8)
	var star_mat := mat(C_MOON, true, true)
	star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_quad.material = star_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star_quad
	mm.instance_count = 400
	for i in 400:
		var az := randf() * TAU
		var el := randf() * 1.4 + 0.08
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)) * 500.0))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	add_child(stars)

	# scoreboard on the edge of the ring
	var panel := mesh_node(box(Vector3(4.4, 3.0, 0.1)), mat(Color("171b4a"), true, true))
	panel.position = Vector3(0, 3.4, -11.6)
	board3d = Label3D.new()
	board3d.font_size = 56
	board3d.pixel_size = 0.0045
	board3d.modulate = C_MOON
	board3d.outline_size = 0
	board3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	board3d.position = Vector3(0, 3.4, -11.5)
	board3d.width = 900.0
	add_child(board3d)


func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", C_MOON)
	layer.add_child(hud)
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(16, -40)
	hint.add_theme_color_override("font_color", Color("a9acd6"))
	hint.text = "No headset found: WASD to move, hold the mouse button and drag to turn, Space or click to kick."
	layer.add_child(hint)


# ---------------------------------------------------------------- audio

func make_wav(dur: float, f: Callable) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v: float = clampf(f.call(float(i) / rate, float(i) / n), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func build_audio() -> void:
	if no_audio:
		return
	var lp := [0.0]
	var streams := {
		"swing": make_wav(0.14, func(_t: float, p: float) -> float:
			lp[0] = lp[0] * 0.7 + randf_range(-1.0, 1.0) * 0.3
			return lp[0] * 0.5 * (1.0 - p) * (1.0 - p)),
		"thwack": make_wav(0.25, func(t: float, p: float) -> float:
			var f := 170.0 - 125.0 * p
			return sin(TAU * f * t) * 0.8 * (1.0 - p) * (1.0 - p) + randf_range(-1.0, 1.0) * 0.5 * pow(1.0 - p, 8.0)),
		"scream": make_wav(FLY, func(_t: float, p: float) -> float:
			var ratio := 1900.0 / 420.0
			var phase := TAU * 420.0 * FLY / log(ratio) * (pow(ratio, p) - 1.0)
			return (sin(phase) * 0.5 + sin(phase * 2.0) * 0.2 + sin(phase * 3.0) * 0.1) * (1.0 - p * 0.7) * minf(p * 20.0, 1.0)),
		"boom": make_wav(1.4, func(t: float, p: float) -> float:
			lp[0] = lp[0] * 0.9 + randf_range(-1.0, 1.0) * 0.1
			return (lp[0] * 4.0 + sin(TAU * (90.0 - 60.0 * p) * t) * 0.6) * (1.0 - p) * (1.0 - p)),
	}
	for key in streams:
		var pl := AudioStreamPlayer.new()
		pl.stream = streams[key]
		pl.max_polyphony = 4
		add_child(pl)
		sfx[key] = pl


func play(key: String, loud: bool) -> void:
	if not sfx.has(key):
		return
	var pl: AudioStreamPlayer = sfx[key]
	pl.volume_db = 0.0 if loud else -9.0
	pl.play()


func buzz(strength: float, seconds: float) -> void:
	if in_vr and xr != null:
		xr.trigger_haptic_pulse("haptic", "left_hand", 0.0, strength, seconds, 0.0)
		xr.trigger_haptic_pulse("haptic", "right_hand", 0.0, strength, seconds, 0.0)


# ---------------------------------------------------------------- avatars

func make_ent(id: String, pname: String, hue: float, is_bot: bool) -> Ent:
	var e := Ent.new()
	e.id = id
	e.name = pname
	e.hue = hue
	e.bot = is_bot
	e.ph = randf() * 6.0
	var col := Color.from_hsv(hue, 0.65, 0.9)
	var dark := Color.from_hsv(hue, 0.6, 0.45)
	var m := mat(col)
	var md := mat(dark)
	e.root = Node3D.new()
	add_child(e.root)
	e.spin = Node3D.new()
	e.root.add_child(e.spin)
	e.torso = mesh_node(box(Vector3(0.42, 1.0, 0.24)), m, e.spin)
	var hips := mesh_node(box(Vector3(0.38, 0.2, 0.23)), md, e.spin)
	e.head = mesh_node(ball(0.16), mat(Color("f0c9a0")), e.spin)
	e.arm_l = mesh_node(box(Vector3(0.1, 0.5, 0.1)), m, e.spin)
	e.arm_r = mesh_node(box(Vector3(0.1, 0.5, 0.1)), m, e.spin)
	var t1 := mesh_node(disc(0.11, 0.01), mat(C_MOON, true), hips)
	t1.rotation.x = PI / 2.0
	t1.position = Vector3(0, -0.02, -0.12)
	var t2 := mesh_node(disc(0.06, 0.01), mat(C_HIT, true), hips)
	t2.rotation.x = PI / 2.0
	t2.position = Vector3(0, -0.02, -0.127)
	e.tag = Label3D.new()
	e.tag.text = pname
	e.tag.font_size = 48
	e.tag.pixel_size = 0.004
	e.tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	e.tag.modulate = C_MOON
	e.tag.outline_modulate = C_NIGHT
	e.tag.outline_size = 12
	e.root.add_child(e.tag)
	if no_labels:
		e.tag.visible = false
	var boot_mat := mat(C_MOON)
	e.boot_l = mesh_node(box(Vector3(0.13, 0.12, 0.28)), boot_mat)
	e.boot_r = mesh_node(box(Vector3(0.13, 0.12, 0.28)), boot_mat)
	e.leg_l = mesh_node(box(Vector3(0.1, 1.0, 0.1)), md)
	e.leg_r = mesh_node(box(Vector3(0.1, 1.0, 0.1)), md)
	return e


func show_ent(e: Ent, on: bool) -> void:
	e.root.visible = on
	e.boot_l.visible = on
	e.boot_r.visible = on
	e.leg_l.visible = on
	e.leg_r.visible = on
	if on:
		e.spin.visible = e.body_visible
		e.tag.visible = e.body_visible


func free_ent(e: Ent) -> void:
	for n in [e.root, e.boot_l, e.boot_r, e.leg_l, e.leg_r]:
		n.queue_free()


func place_leg(leg: MeshInstance3D, boot: MeshInstance3D, foot: Vector3, hip: Vector3, yaw: float) -> void:
	boot.position = foot
	boot.rotation = Vector3(0, yaw, 0)
	var d := hip - foot
	var length := maxf(d.length(), 0.05)
	var y := d / length
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y)
	leg.transform = Transform3D(Basis(x, y * length, z), foot + d * 0.5)


func pose(e: Ent, base: Vector3, yaw: float, spin: float, sc: float) -> void:
	var hip_y := e.h * 0.5
	var head_y := e.h - 0.1
	var th := maxf(0.2, head_y - 0.2 - hip_y)
	e.root.position = base
	e.root.rotation = Vector3(0, yaw, 0)
	e.root.scale = Vector3.ONE * sc
	e.spin.position.y = hip_y
	e.spin.rotation.x = spin
	e.torso.scale.y = th
	e.torso.position.y = 0.1 + th / 2.0
	e.head.position.y = head_y - hip_y
	e.arm_l.position = Vector3(-0.27, 0.1 + th - 0.27, 0)
	e.arm_r.position = Vector3(0.27, 0.1 + th - 0.27, 0)
	e.tag.position.y = e.h + 0.35
	var r := right_of(yaw)
	var hy := base.y + hip_y * sc
	place_leg(e.leg_l, e.boot_l, e.fl, Vector3(base.x - r.x * 0.12, hy, base.z - r.z * 0.12), yaw)
	place_leg(e.leg_r, e.boot_r, e.fr, Vector3(base.x + r.x * 0.12, hy, base.z + r.z * 0.12), yaw)


func spawn(e: Ent) -> void:
	var ang := randf() * TAU
	var rad := 2.5 + randf() * 5.0
	e.x = sin(ang) * rad
	e.z = cos(ang) * rad
	e.yaw = atan2(e.x, e.z)   # face the centre
	e.st = ALIVE
	e.kick_t = -1.0
	show_ent(e, true)


func set_bots(on: bool) -> void:
	if on and no_bots:
		return
	if on and bots.is_empty():
		var names := ["Dummy Dave", "Crash Test Carl", "Practice Pete"]
		for i in names.size():
			var b := make_ent("bot%d" % i, names[i], fmod(0.08 + i * 0.31, 1.0), true)
			spawn(b)
			b.wait = 1.0 + randf() * 2.0
			b.gx = b.x
			b.gz = b.z
			bots.append(b)
	elif not on and not bots.is_empty():
		for b in bots:
			free_ent(b)
		bots.clear()


# ---------------------------------------------------------------- movement and kicks

func gait(e: Ent, dt: float, speed: float) -> void:
	if speed > 0.1:
		e.ph += dt * (5.0 + speed * 2.2)
	var f := fwd_of(e.yaw)
	var r := right_of(e.yaw)
	var amp := minf(speed / 2.5, 1.0)
	for s in [-1, 1]:
		var phase := e.ph + (PI if s > 0 else 0.0)
		var fw := cos(phase) * 0.22 * amp
		var y := 0.08 + maxf(0.0, sin(phase)) * 0.14 * amp
		var p := Vector3(e.x + r.x * 0.14 * s + f.x * fw, y, e.z + r.z * 0.14 * s + f.z * fw)
		if s < 0:
			e.fl = p
		else:
			e.fr = p
	if e.kick_t >= 0.0:
		e.kick_t += dt
		var k := e.kick_t / KT
		if k >= 1.0:
			e.kick_t = -1.0
		else:
			var sw := sin(PI * k)
			var lat := 0.14 * e.kick_side * (1.0 - sw)
			var p2 := Vector3(e.x + r.x * lat + f.x * 0.9 * sw, 0.08 + 0.84 * sw * (e.h / 1.7), e.z + r.z * lat + f.z * 0.9 * sw)
			if e.kick_side < 0:
				e.fl = p2
			else:
				e.fr = p2


func start_kick(e: Ent) -> void:
	if e.kick_t >= 0.0 or e.st != ALIVE:
		return
	e.kick_t = 0.0
	e.kick_side = e.side
	e.side = -e.side
	if e == me:
		play("swing", true)


func foot_speeds(e: Ent, dt: float) -> void:
	e.vl = e.fl.distance_to(e.pfl) / dt
	e.vr = e.fr.distance_to(e.pfr) / dt
	e.pfl = e.fl
	e.pfr = e.fr


func hits(att: Ent, tgt: Ent) -> bool:
	if att.st != ALIVE or tgt.st != ALIVE:
		return false
	if float(att.cd.get(tgt.id, 0.0)) > now:
		return false
	var f := fwd_of(tgt.yaw)
	var c := Vector3(tgt.x + f.x * 0.08, tgt.h * 0.5, tgt.z + f.z * 0.08)
	if (att.vl > HIT_SPEED and att.fl.distance_to(c) < HIT_R) or (att.vr > HIT_SPEED and att.fr.distance_to(c) < HIT_R):
		att.cd[tgt.id] = now + 1.0
		return true
	return false


func launch(e: Ent) -> bool:
	if e.st != ALIVE:
		return false
	e.st = FLYING
	e.fly_t = 0.0
	e.gone_t = 0.0
	e.saw_fly = false
	e.kick_t = -1.0
	e.a = Vector3(e.x, e.h * 0.5, e.z)
	var d := (Vector3(e.x + (randf() - 0.5) * 20.0, 10.0 + randf() * 20.0, e.z + 60.0) - MOON).normalized()
	e.b = MOON + d * MR
	e.c = (e.a + e.b) * 0.5 + Vector3(0, 28, 0)
	note("launch " + e.name)
	play("thwack", e == me)
	play("scream", e == me)
	if e == me:
		buzz(1.0, 0.45)
	return true


func explode(p: Vector3, loud: bool) -> void:
	note("explode")
	play("boom", loud)
	var out := (p - MOON).normalized()
	var parts := CPUParticles3D.new()
	parts.amount = 140
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.lifetime = 1.8
	parts.direction = out
	parts.spread = 110.0
	parts.gravity = Vector3.ZERO
	parts.initial_velocity_min = 6.0
	parts.initial_velocity_max = 24.0
	parts.scale_amount_min = 0.5
	parts.scale_amount_max = 1.4
	var pm := ball(0.6)
	pm.radial_segments = 6
	pm.rings = 3
	parts.mesh = pm
	parts.material_override = mat(C_LAMP, true, true)
	parts.position = p
	add_child(parts)
	parts.emitting = true
	var flash_mat := mat(C_HIT, true, true)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var flash := mesh_node(ball(1.0), flash_mat)
	flash.position = p
	booms.append({"parts": parts, "flash": flash, "mat": flash_mat, "t": 0.0})
	var crater := mesh_node(disc(2.4, 0.05), mat(Color("4a4032"), true, true))
	var x := out.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	crater.transform = Transform3D(Basis(x, out, x.cross(out)), MOON + out * (MR + 0.1))
	craters.append(crater)
	if craters.size() > 30:
		craters.pop_front().queue_free()


func update_booms(dt: float) -> void:
	for i in range(booms.size() - 1, -1, -1):
		var b: Dictionary = booms[i]
		b["t"] += dt
		var k: float = b["t"] / 1.8
		var s := 2.0 + k * 14.0
		b["flash"].scale = Vector3.ONE * s
		var m: StandardMaterial3D = b["mat"]
		m.albedo_color.a = maxf(0.0, 1.0 - k * 2.2)
		if k >= 1.3:
			b["parts"].queue_free()
			b["flash"].queue_free()
			booms.remove_at(i)


func update_flight(e: Ent, dt: float) -> void:
	if e.st == FLYING:
		e.fly_t += dt
		var p := minf(e.fly_t / FLY, 1.0)
		var q := p * p * (3.0 - 2.0 * p) * 0.35 + p * 0.65
		e.pos = e.a.lerp(e.c, q).lerp(e.c.lerp(e.b, q), q)
		var sp := e.fly_t * 13.0
		var sc := 1.0 + p * 5.0   # grow in flight so it stays readable from the ground
		e.fl = e.pos + Vector3(-0.14, -0.5 * cos(sp), -0.5 * sin(sp)) * sc
		e.fr = e.pos + Vector3(0.14, -0.5 * cos(sp + 0.6), -0.5 * sin(sp + 0.6)) * sc
		pose(e, e.pos - Vector3(0, e.h * 0.5 * sc, 0), 0.0, sp, sc)
		if p >= 1.0:
			e.st = GONE
			e.gone_t = 0.0
			show_ent(e, false)
			explode(e.b, e == me)
	elif e.st == GONE:
		e.gone_t += dt


# ---------------------------------------------------------------- scoreboard

func toast(msg: String) -> void:
	last_event = msg
	toast3d.text = msg
	toast3d.visible = not no_labels
	toast_t = 2.6
	board_dirty = true


func draw_board() -> void:
	board_dirty = false
	var rows := [{"n": me.name + " (you)", "s": me.score, "d": me.deaths}]
	for e in ents.values():
		rows.append({"n": e.name, "s": e.score, "d": e.deaths})
	rows.sort_custom(func(a, b): return a["s"] > b["s"] or (a["s"] == b["s"] and a["d"] < b["d"]))
	var text := "SCOREBOARD\n"
	for i in mini(rows.size(), 7):
		var r: Dictionary = rows[i]
		text += "%s   %d kicks   %d moons\n" % [r["n"], r["s"], r["d"]]
	board3d.text = text + "\n" + last_event
	var where := "Playing solo. Others on your network join automatically."
	if ents.size() > 0:
		where = "%d players in the arena" % (ents.size() + 1)
	hud.text = text + where


# ---------------------------------------------------------------- network (LAN, no server)

func start_net() -> void:
	my_id = "%08x%08x" % [randi(), randi()]
	if no_net:
		note("network off")
		return
	for i in NPORTS:
		if udp.bind(PORT0 + i) == OK:
			my_port = PORT0 + i
			net_ok = true
			break
	note("network listening=%s port=%d" % [net_ok, my_port])
	for iface in IP.get_local_interfaces():
		var masked := []
		for addr in iface.get("addresses", []):
			var parts := str(addr).split(".")
			masked.append("%s.%s.x.x" % [parts[0], parts[1]] if parts.size() == 4 else "v6")
		print("net interface %s: %s" % [iface.get("name", "?"), masked])


func r2(v: float) -> float:
	return snappedf(v, 0.01)


func net_targets() -> PackedStringArray:
	var out := PackedStringArray(["255.255.255.255", "127.0.0.1"])
	for addr in IP.get_local_addresses():
		var parts := addr.split(".")
		if parts.size() == 4 and not addr.begins_with("127."):
			var bc := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if not out.has(bc):
				out.append(bc)
	for p in extra_peers:
		out.append(p)
	return out


var _targets: PackedStringArray = []
var _targets_t := -100.0


# Sending goes through one non-blocking socket per destination. A plain PacketPeerUDP send
# retries forever when the system says "try again", and a network interface that never
# transmits fills the send buffer and triggers exactly that, hanging the whole game.
# With a socket per destination, a dead interface can only drop its own packets.
var senders := {}
var sent_count := 0


func sender_for(ip: String) -> ENetConnection:
	if senders.has(ip):
		return senders[ip]
	var h := ENetConnection.new()
	if h.create_host_bound("*", 0, 1) != OK:
		h = null
	senders[ip] = h
	note("sender %d opened: %s" % [senders.size(), h != null])
	return h


func net_send() -> void:
	if not net_ok or now - last_send < 0.066:
		return
	last_send = now
	if now - _targets_t > 5.0:
		_targets = net_targets()
		_targets_t = now
	var pkt := var_to_bytes({
		"g": NET_TAG, "id": my_id, "nm": me.name, "hue": r2(me.hue),
		"p": [r2(me.x), r2(me.z), r2(me.yaw), r2(me.h)],
		"f": [r2(me.fl.x), r2(me.fl.y), r2(me.fl.z), r2(me.fr.x), r2(me.fr.y), r2(me.fr.z)],
		"st": 0 if me.st == ALIVE else 1, "sc": me.score, "dt": me.deaths,
		"kv": kvictim, "ks": kseq,
	})
	for ip in _targets:
		var h := sender_for(ip)
		if h == null:
			continue
		if ip == "127.0.0.1":
			# several copies on one machine (testing) listen on neighbouring ports
			for i in NPORTS:
				if PORT0 + i != my_port:
					h.socket_send(ip, PORT0 + i, pkt)
		else:
			h.socket_send(ip, PORT0, pkt)
		sent_count += 1


func nums(v, count: int) -> bool:
	if not (v is Array) or v.size() < count:
		return false
	for i in count:
		if not (v[i] is float or v[i] is int) or is_nan(float(v[i])) or is_inf(float(v[i])):
			return false
	return true


func net_receive() -> void:
	if not net_ok:
		return
	var budget := 200
	while budget > 0 and udp.get_available_packet_count() > 0:
		budget -= 1
		var raw := udp.get_packet()
		if raw.size() < 8 or raw.size() > 1400:
			continue
		var d = bytes_to_var(raw)
		if not (d is Dictionary) or d.get("g") != NET_TAG:
			continue
		var id = d.get("id")
		if not (id is String) or id == my_id or id.length() > 32:
			continue
		if not nums(d.get("p"), 4) or not nums(d.get("f"), 6):
			continue
		var p: Array = d["p"]
		var f: Array = d["f"]
		var nm := str(d.get("nm", "Someone")).substr(0, 14)
		var st := 1 if d.get("st") == 1 else 0
		var e: Ent = ents.get(id)
		var tfl := Vector3(clampf(f[0], -13, 13), clampf(f[1], 0, 3), clampf(f[2], -13, 13))
		var tfr := Vector3(clampf(f[3], -13, 13), clampf(f[4], 0, 3), clampf(f[5], -13, 13))
		var ks := int(d.get("ks", 0)) if (d.get("ks") is int or d.get("ks") is float) else 0
		if e == null:
			var hue := float(d.get("hue", 0.5)) if (d.get("hue") is float or d.get("hue") is int) else 0.5
			e = make_ent(id, nm, fposmod(hue, 1.0), false)
			e.x = clampf(p[0], -12, 12)
			e.z = clampf(p[1], -12, 12)
			e.yaw = p[2]
			e.h = clampf(p[3], 0.8, 2.3)
			e.fl = tfl
			e.fr = tfr
			e.last_k = ks
			if st == 1:
				e.st = GONE
				e.saw_fly = true
				show_ent(e, false)
			ents[id] = e
			note("player joined: " + nm)
			set_bots(false)
			board_dirty = true
		e.last_seen = now
		if e.name != nm:
			e.name = nm
			e.tag.text = nm
			board_dirty = true
		e.tx = clampf(p[0], -12, 12)
		e.tz = clampf(p[1], -12, 12)
		e.tyaw = p[2]
		e.th = clampf(p[3], 0.8, 2.3)
		e.tfl = tfl
		e.tfr = tfr
		var sc := maxi(0, int(d.get("sc", 0))) if (d.get("sc") is int or d.get("sc") is float) else 0
		var dth := maxi(0, int(d.get("dt", 0))) if (d.get("dt") is int or d.get("dt") is float) else 0
		if e.score != sc or e.deaths != dth:
			e.score = sc
			e.deaths = dth
			board_dirty = true
		if ks != e.last_k:
			e.last_k = ks
			if d.get("kv") is String and d.get("kv") == my_id and launch(me):
				me.deaths += 1
				toast("%s sent you to the moon" % e.name)
		if st == 1:
			e.saw_fly = true
			if e.st == ALIVE:
				launch(e)
		elif e.st == GONE and e.saw_fly:
			e.st = ALIVE
			e.x = e.tx
			e.z = e.tz
			e.yaw = e.tyaw
			e.fl = tfl
			e.fr = tfr
			show_ent(e, true)
	# drop players we have not heard from
	for id in ents.keys():
		var e2: Ent = ents[id]
		if now - e2.last_seen > 3.0:
			free_ent(e2)
			ents.erase(id)
			board_dirty = true
	if ents.is_empty() and bots.is_empty():
		set_bots(true)


# ---------------------------------------------------------------- VR tracking

func tracked_point(tracker_name: String, pose_names: Array) -> Variant:
	var t := XRServer.get_tracker(tracker_name) as XRPositionalTracker
	if t == null:
		return null
	for pn in pose_names:
		var ps := t.get_pose(pn)
		if ps != null and ps.has_tracking_data:
			return origin.global_transform * ps.get_adjusted_transform().origin
	return null


func find_foot(which: String) -> Variant:
	# 1. dedicated foot trackers, 2. the hand controller strapped to that ankle
	var p = tracked_point("/user/vive_tracker_htcx/role/%s_foot" % which, ["default", "aim", "grip"])
	if p != null:
		_src = "tracker"
		return p
	p = tracked_point(which + "_hand", ["grip", "default", "aim"])
	_src = "controller" if p != null else "none"
	return p


var _src := "-"


func stick() -> Vector2:
	var v := Vector2.ZERO
	for tn in ["left_hand", "right_hand"]:
		var t := XRServer.get_tracker(tn) as XRPositionalTracker
		if t != null:
			var s = t.get_input("primary")
			if s is Vector2 and s.length() > 0.2:
				v += s
	return v


func update_vr(dt: float) -> void:
	stage = "vr_head"
	var head_local := cam.position
	var hf := cam.global_transform.basis * Vector3.FORWARD
	var hyaw := atan2(-hf.x, -hf.z)
	stage = "vr_feet"
	var lf = null
	var rf = null
	if not no_feet:
		lf = find_foot("left")
		if _src != src_l:
			note("left foot source: " + _src)
		src_l = _src
		rf = find_foot("right")
		if _src != src_r:
			note("right foot source: " + _src)
		src_r = _src
	stage = "vr_move"
	if lf != null:
		me.fl = lf
	if rf != null:
		me.fr = rf
	if me.st != ALIVE:
		return
	var f := fwd_of(hyaw)
	var r := right_of(hyaw)
	var mv := Vector3.ZERO
	var s := stick()
	if s != Vector2.ZERO:
		mv = (r * s.x + f * s.y) * 2.2
	elif lf != null and rf != null and me.fl.y < 0.45 and me.fr.y < 0.45:
		# march in place: lifting your feet walks you where you are looking
		var energy := absf(me.fl.y - me.pfl.y) / dt + absf(me.fr.y - me.pfr.y) / dt
		march = march * 0.9 + energy * 0.1
		if march > 0.45 and me.vl < 2.2 and me.vr < 2.2:
			mv = f * minf(march * 1.6, 2.4)
	var step := mv * dt
	origin.position += step
	origin.position.y = 0.0
	me.fl += step
	me.fr += step
	me.pfl += step
	me.pfr += step
	var hw := origin.position + head_local
	var dist := Vector2(hw.x, hw.z).length()
	if dist > ARENA:
		var k := (dist - ARENA) / dist
		origin.position.x -= hw.x * k
		origin.position.z -= hw.z * k
		hw.x -= hw.x * k
		hw.z -= hw.z * k
	me.x = hw.x
	me.z = hw.z
	me.yaw = hyaw
	me.h = clampf(head_local.y, 1.0, 2.2)
	if lf == null:
		me.fl = Vector3(me.x - r.x * 0.14, 0.08, me.z - r.z * 0.14)
	if rf == null:
		me.fr = Vector3(me.x + r.x * 0.14, 0.08, me.z + r.z * 0.14)


# ---------------------------------------------------------------- flat-screen input

func _unhandled_input(event: InputEvent) -> void:
	if in_vr:
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		me.yaw -= event.relative.x * 0.006
		mouse_moved += absf(event.relative.x) + absf(event.relative.y)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_moved = 0.0
		elif mouse_moved < 6.0:
			start_kick(me)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			start_kick(me)
		elif event.physical_keycode == KEY_ESCAPE:
			get_tree().quit()


func key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


# ---------------------------------------------------------------- bots

func update_bot(b: Ent, dt: float) -> void:
	if b.st != ALIVE:
		update_flight(b, dt)
		if b.st == GONE and b.gone_t > 2.0:
			spawn(b)
			b.rest = 2.0
		return
	var speed := 0.0
	var dx := me.x - b.x
	var dz := me.z - b.z
	var dist := sqrt(dx * dx + dz * dz)
	b.rest -= dt
	if now > BOT_GRACE and me.st == ALIVE and dist < 5.5:
		b.yaw = atan2(-dx, -dz)
		if dist > 0.95:
			speed = 1.7
			b.wind = 0.0
		elif b.rest <= 0.0:
			b.wind += dt
			if b.wind > 0.55:
				start_kick(b)
				b.wind = 0.0
				b.rest = 2.6
	else:
		b.wait -= dt
		var gx := b.gx - b.x
		var gz := b.gz - b.z
		if sqrt(gx * gx + gz * gz) > 0.3:
			b.yaw = atan2(-gx, -gz)
			speed = 1.2
		elif b.wait <= 0.0:
			var ang := randf() * TAU
			var rad := randf() * 7.0
			b.gx = sin(ang) * rad
			b.gz = cos(ang) * rad
			b.wait = 1.0 + randf() * 3.0
	var f := fwd_of(b.yaw)
	b.x += f.x * speed * dt
	b.z += f.z * speed * dt
	gait(b, dt, speed)
	foot_speeds(b, dt)
	pose(b, Vector3(b.x, 0, b.z), b.yaw, 0.0, 1.0)
	if hits(b, me) and launch(me):
		me.deaths += 1
		toast("%s sent you to the moon" % b.name)


# ---------------------------------------------------------------- main loop

func _process(delta: float) -> void:
	var dt := clampf(delta, 0.001, 0.05)
	now += dt
	if toast_t > 0.0:
		toast_t -= dt
		if toast_t <= 0.0:
			toast3d.visible = false

	if test_stall and now > 3.0:
		test_stall = false
		stage = "test_stall (deliberate 10 s hang)"
		OS.delay_msec(10000)
	stage = "net_rx"
	net_receive()

	stage = "player"
	if me.st == ALIVE:
		if in_vr:
			update_vr(dt)
		else:
			var ix := key(KEY_D) + key(KEY_RIGHT) - key(KEY_A) - key(KEY_LEFT)
			var iy := key(KEY_W) + key(KEY_UP) - key(KEY_S) - key(KEY_DOWN)
			me.yaw += (key(KEY_Q) - key(KEY_E)) * dt * 2.4
			if opt_autokick:
				var target: Ent = null
				var best := 99.0
				for o in ents.values() + bots:
					var dd := Vector2(o.x - me.x, o.z - me.z).length()
					if o.st == ALIVE and dd < best:
						best = dd
						target = o
				ix = 0.0
				iy = 0.0
				if target != null:
					me.yaw = atan2(-(target.x - me.x), -(target.z - me.z))
					if best > 0.85:
						iy = 1.0
					else:
						start_kick(me)
			var l := Vector2(ix, iy).length()
			if l > 1.0:
				ix /= l
				iy /= l
			var f := fwd_of(me.yaw)
			var r := right_of(me.yaw)
			me.x += (f.x * iy + r.x * ix) * 3.2 * dt
			me.z += (f.z * iy + r.z * ix) * 3.2 * dt
			var d := Vector2(me.x, me.z).length()
			if d > ARENA:
				me.x *= ARENA / d
				me.z *= ARENA / d
			for o in ents.values() + bots:
				if o.st == ALIVE:
					var away := Vector2(me.x - o.x, me.z - o.z)
					var al := away.length()
					if al < 0.5 and al > 0.001:
						me.x += away.x / al * (0.5 - al)
						me.z += away.y / al * (0.5 - al)
			gait(me, dt, minf(l, 1.0) * 3.2)
		foot_speeds(me, dt)
		pose(me, Vector3(me.x, 0, me.z), me.yaw, 0.0, 1.0)
		for e in ents.values():
			if hits(me, e) and launch(e):
				me.score += 1
				kseq += 1
				kvictim = e.id
				buzz(0.8, 0.12)
				toast("You kicked %s to the moon" % e.name)
		for b in bots:
			if hits(me, b) and launch(b):
				me.score += 1
				buzz(0.8, 0.12)
				toast("You kicked %s to the moon" % b.name)
	else:
		if in_vr:
			update_vr(dt)
		update_flight(me, dt)
		if in_vr and me.st == FLYING:
			origin.position = me.pos - cam.position + Vector3(0, 0.4, 0)
		if me.st == GONE and me.gone_t > 1.6:
			spawn(me)
			if in_vr:
				origin.position = Vector3(me.x - cam.position.x, 0, me.z - cam.position.z)

	stage = "net_tx"
	net_send()

	stage = "remote"
	# other players: ease toward their last reported pose
	var k := 1.0 - exp(-dt * 14.0)
	for e in ents.values():
		if e.st == ALIVE:
			e.x += (e.tx - e.x) * k
			e.z += (e.tz - e.z) * k
			e.h += (e.th - e.h) * k
			e.yaw += angle_difference(e.yaw, e.tyaw) * k
			e.fl = e.fl.lerp(e.tfl, k)
			e.fr = e.fr.lerp(e.tfr, k)
			pose(e, Vector3(e.x, 0, e.z), e.yaw, 0.0, 1.0)
		else:
			update_flight(e, dt)
			if e.st == GONE and e.gone_t > 6.0 and not e.saw_fly:
				e.st = ALIVE
				show_ent(e, true)
	stage = "bots"
	for b in bots:
		update_bot(b, dt)
	stage = "booms"
	update_booms(dt)
	stage = "board"
	if board_dirty:
		draw_board()
	stage = "camera"

	# flat-screen camera (the headset drives it in VR)
	if not in_vr:
		if me.st == ALIVE:
			var f2 := fwd_of(me.yaw)
			cam.look_at_from_position(Vector3(me.x - f2.x * 3.4, 2.4, me.z - f2.z * 3.4), Vector3(me.x + f2.x * 1.2, 1.0, me.z + f2.z * 1.2), Vector3.UP)
		elif me.st == FLYING:
			var dir := (me.b - me.a).normalized()
			var want := me.pos - dir * (6.0 + me.fly_t * 4.0) + Vector3(0, 2, 0)
			want.y = maxf(want.y, 1.5)
			cam.look_at_from_position(cam.global_position.lerp(want, 0.2), me.b, Vector3.UP)

	stage = "heartbeat"
	frames += 1
	beat_t += delta
	if beat_t >= 1.0:
		var fps := frames / beat_t
		frames = 0
		beat_t = 0.0
		var states := ["alive", "flying", "gone"]
		var line := "build %s  t=%.0f  fps=%.0f  %s  feet L:%s R:%s  head=%.2f  players=%d  last: %s" % [BUILD, now, fps, states[me.st], src_l, src_r, me.h, ents.size() + 1, last_note]
		stage = "debug_label"
		if not no_labels:
			debug3d.text = line
		print("%s  frame=%d  cam=%s  sent=%d" % [line, frame_no, cam.position.snappedf(0.01), sent_count])
		if in_vr and (src_l == "none" or src_r == "none") and int(now) % 5 == 1:
			for tn in ["left_hand", "right_hand"]:
				var t := XRServer.get_tracker(tn) as XRPositionalTracker
				var info := []
				if t != null:
					for pn in ["default", "aim", "grip", "palm"]:
						var ps := t.get_pose(pn)
						info.append("%s=%s" % [pn, "missing" if ps == null else ("tracked" if ps.has_tracking_data else "no data")])
				print("  %s poses: %s  profile: %s" % [tn, info, t.profile if t != null else "no tracker"])
	if opt_log:
		log_t += dt
		if log_t > 2.0:
			log_t = 0.0
			print("STATUS t=%.0f vr=%s net=%s port=%d peers=%d bots=%d score=%d moons=%d" % [now, in_vr, net_ok, my_port, ents.size(), bots.size(), me.score, me.deaths])
	if opt_shot != "" and now > 4.0:
		get_viewport().get_texture().get_image().save_png(opt_shot)
		opt_shot = ""
		get_tree().quit()
	# everything after this until the next frame is the engine: rendering and the headset's frame timing
	stage = "engine (render / headset frame wait)"
	frame_no += 1
