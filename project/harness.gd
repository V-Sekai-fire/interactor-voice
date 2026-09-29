# A tone through voice.elf: encode each 20 ms frame, drop one packet, decode, and report how far the
# decoded frames are from the input. Frames the loss does not touch must be within BOUND_DB; the two
# after it, while the decoder settles out of concealment, within RECOVERY_DB. Exits 1 otherwise, or
# if the loss is not counted. With --control the loss is hidden by renumbering the later packets,
# and the check must fail; the harness exits 0 only if it does.
#
#   godot --headless --path project --script harness.gd [++ --control]
extends SceneTree

const FRAMES := 50
const FRAME := 960
const RATE := 48000.0
const DROP := 20
const WARMUP := 4
const BOUND_DB := 15.0
const RECOVERY_DB := 8.0

func _initialize() -> void:
	var sb = ClassDB.instantiate("Sandbox")
	if sb == null:
		print("FAIL: no Sandbox class (link the godot_sandbox addon into project/addons)")
		quit(1)
		return
	sb.program = load("res://voice.elf")
	var control := OS.get_cmdline_user_args().has("--control")
	print(sb.vmcall("voice_open"))
	var input := PackedFloat32Array()
	var output := PackedFloat32Array()
	var phase := 0.0
	for f in FRAMES:
		var h := (f * 40503 + 12345) % 1000003
		var hz := 150.0 + float(h % 2000)
		var amp := 3000.0 + float((h / 7) % 9000)
		var pcm := PackedByteArray()
		pcm.resize(FRAME * 2)
		for i in FRAME:
			phase += TAU * hz / RATE
			var s := int(amp * sin(phase))
			pcm.encode_s16(i * 2, s)
			input.append(s)
		var packet: PackedByteArray = sb.vmcall("voice_encode_frame", pcm)
		if f == DROP:
			continue
		if control and f > DROP:
			packet.encode_u16(0, packet.decode_u16(0) - 1)
		var out: PackedByteArray = sb.vmcall("voice_decode_packet", packet)
		for i in out.size() / 2:
			output.append(out.decode_s16(i * 2))
	var stats: String = sb.vmcall("voice_stats")
	# Missing frames read as silence, so a short output fails the bounds instead of indexing past the end.
	var frames_out := output.size() / FRAME
	output.resize(FRAMES * FRAME + 2 * FRAME)
	var best_delay := 0
	var best := -INF
	for delay in range(300, 325):
		var s := 0.0
		var e := 0.0
		for t in range(WARMUP * FRAME, (FRAMES - 1) * FRAME):
			s += input[t] * input[t]
			e += (input[t] - output[t + delay]) ** 2
		var snr := 10.0 * log(s / (e + 1e-9)) / log(10.0)
		if snr > best:
			best = snr
			best_delay = delay
	var worst := INF
	var recovery := INF
	for f in range(WARMUP, FRAMES - 1):
		if f == DROP:
			continue
		var s := 0.0
		var e := 0.0
		for i in FRAME:
			var t := f * FRAME + i
			s += input[t] * input[t]
			e += (input[t] - output[t + best_delay]) ** 2
		var snr := 10.0 * log(s / (e + 1e-9)) / log(10.0)
		if f == DROP + 1 or f == DROP + 2:
			recovery = minf(recovery, snr)
		else:
			worst = minf(worst, snr)
	var ok := worst >= BOUND_DB and recovery >= RECOVERY_DB and stats.contains("concealed 1 ") and frames_out == FRAMES
	print("%s; delay %d samples; worst untouched frame %.1f dB (bound %.1f); after the loss %.1f dB (bound %.1f); %d of %d frames out" % [
			stats, best_delay, worst, BOUND_DB, recovery, RECOVERY_DB, frames_out, FRAMES])
	sb.free()
	if control:
		print("RESULT: control %s" % ("fails, as it must" if not ok else "DID NOT FAIL"))
		quit(1 if ok else 0)
		return
	print("RESULT: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
