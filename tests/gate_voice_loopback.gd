# The voice loopback gate (RFD 2401): a known tone through voice.elf with nothing lost. Every 20 ms
# frame is encoded and its packet decoded straight back. PASS needs voice_open to report 48 kHz and
# 960-sample frames, one packet and one decoded frame for each frame in, no frame concealed or late,
# and the output, aligned at the encoder's lookahead, within BOUND_DB of the input.
#
# A control must FAIL, each at its own check:
#   --control=corrupt     every packet's Opus payload XORed with 0xA5 (header left intact): "FAIL snr"
#                         or "FAIL frames", whichever the decoder hits first
#   --control=frame_size  959 samples a frame instead of 960, which the encoder refuses: "FAIL packets"
#
#   godot --headless --path project --script "$PWD/tests/gate_voice_loopback.gd" [++ --control=<name>]
extends SceneTree

const FRAMES := 50
const FRAME := 960
const RATE := 48000.0
const HZ := 1000.0
const AMP := 8000.0
const WARMUP := 4
const BOUND_DB := 20.0

var _failures: PackedStringArray = []

func _check(p_ok: bool, p_name: String, p_detail: String) -> void:
	if p_ok:
		print("ok %s: %s" % [p_name, p_detail])
	else:
		print("FAIL %s: %s" % [p_name, p_detail])
		_failures.append(p_name)

func _initialize() -> void:
	var control := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--control="):
			control = arg.trim_prefix("--control=")
	if control not in ["", "corrupt", "frame_size"]:
		print("RESULT: FAIL (unknown control %s)" % control)
		quit(2)
		return
	if not ClassDB.class_exists("Sandbox"):
		print("RESULT: FAIL (no Sandbox class: the godot_sandbox addon is not in project/addons)")
		quit(1)
		return
	var sb = ClassDB.instantiate("Sandbox")
	sb.program = load("res://voice.elf")
	var opened: String = sb.vmcall("voice_open")
	_check(opened.begins_with("OK 48000 Hz, 960 samples a frame"), "open", opened)
	var lookahead := int(opened.get_slice("lookahead ", 1)) if opened.contains("lookahead ") else -1

	var frame := FRAME - 1 if control == "frame_size" else FRAME
	var input := PackedFloat32Array()
	var output := PackedFloat32Array()
	var packets := 0
	for f in FRAMES:
		var pcm := PackedByteArray()
		pcm.resize(frame * 2)
		for i in frame:
			var t := f * frame + i
			var s := int(round(AMP * sin(TAU * HZ * float(t) / RATE)))
			pcm.encode_s16(i * 2, s)
			input.append(s)
		var packet: PackedByteArray = sb.vmcall("voice_encode_frame", pcm)
		if packet.size() <= 2:
			continue
		packets += 1
		if control == "corrupt":
			for i in range(2, packet.size()):
				packet[i] = packet[i] ^ 0xA5
		var out: PackedByteArray = sb.vmcall("voice_decode_packet", packet)
		for i in out.size() / 2:
			output.append(out.decode_s16(i * 2))
	var stats: String = sb.vmcall("voice_stats")
	sb.free()

	_check(packets == FRAMES, "packets", "%d of %d frames encoded" % [packets, FRAMES])
	var frames_out := output.size() / FRAME
	_check(frames_out == FRAMES and output.size() % FRAME == 0, "frames",
			"%d samples out, %d of %d frames" % [output.size(), frames_out, FRAMES])
	var want_stats := "received %d concealed 0 late 0" % FRAMES
	_check(stats == want_stats, "stats", "%s (want %s)" % [stats, want_stats])

	# Missing output reads as silence, so a short decode fails the bound instead of indexing past the end.
	var n := input.size()
	output.resize(n + 2 * FRAME)
	var best := -INF
	var best_delay := -1
	# Within half a period of the lookahead: a pure tone aligns again every RATE / HZ samples.
	var centre := lookahead if lookahead >= 0 else 312
	var half := int(RATE / HZ / 2.0)
	for delay in range(maxi(0, centre - half), centre + half + 1):
		var s := 0.0
		var e := 0.0
		for t in range(WARMUP * FRAME, n - FRAME):
			s += input[t] * input[t]
			e += (input[t] - output[t + delay]) ** 2
		var snr := 10.0 * log(s / (e + 1e-9)) / log(10.0)
		if snr > best:
			best = snr
			best_delay = delay
	_check(best >= BOUND_DB, "snr", "%.1f dB at a delay of %d samples (bound %.1f dB, lookahead %d)" % [
			best, best_delay, BOUND_DB, lookahead])

	var label := " (control %s)" % control if control != "" else ""
	if _failures.is_empty():
		print("RESULT: PASS%s" % label)
		quit(0)
	else:
		print("RESULT: FAIL (%s)%s" % [", ".join(_failures), label])
		quit(1)
