# interactor-voice

Voice as sequenced Opus packets in a godot-sandbox guest: 48 kHz mono, 20 ms frames, and a concealed frame for each lost packet.

`voice.elf` is the codec part of the speech module (`modules/speech` in the org's engine fork) moved
into a guest, so the engine carries no voice code (RFD 2287, step 7). It uses the speech module's
settings: 128 kbit/s full-band audio, complexity 10, in-band FEC tuned for 10% loss. Opus 1.6.1 is
built as the classic float codec, without its neural extensions. Carrying the packets, as
WebTransport datagrams, is the zone's job, not this repository's.

## The guest's calls

| Call | In | Out |
| --- | --- | --- |
| `voice_open()` | | `OK ...` with the lookahead, or `FAIL: ...` |
| `voice_encode_frame(pcm)` | 960 16-bit samples as 1920 bytes | one packet: a 16-bit sequence number, then the Opus payload |
| `voice_decode_packet(packet)` | one packet | 16-bit samples: one concealed frame for each packet the sequence says is missing, then the packet's own |
| `voice_stats()` | | packets received, frames concealed, late or repeated packets dropped |

## What is measured

The decoded signal trails the input by 310 samples. The encoder reports a lookahead of 312, and the
tests pin both numbers. The test signal is a tone whose pitch and level change every frame, so
concealment cannot guess a lost frame.

| Frames | Bound | Measured floor (300 lossy streams) |
| --- | --- | --- |
| Frames a loss does not touch, from the fourth on | 15 dB | 17.3 dB |
| The two frames after a lost one, while the decoder settles | 8 dB | 9.4 dB |
| The lost frame itself, concealed | none | 16.2 dB |

Audio quality alone cannot show a loss: a concealed frame can sound as close to the input as a
delivered one. The sequence number shows it. Each loss is counted, and the output stays aligned with
the input.

## Build and test

```sh
RISCV64_SYSROOT=<riscv64 sysroot with toolchain.cmake> ./build.sh   # project/voice.elf
cd tests && lake build && lake exe tests                            # the codec, natively
tools/link_addon.sh <path to a godot_sandbox addon>                  # the harness needs the addon
godot --headless --path project --import
godot --headless --path project --script harness.gd                  # a tone through voice.elf
godot --headless --path project --script harness.gd ++ --control     # the loss hidden: must fail
```

The tests are a Lean package that links `src/voice_codec.cpp` and the vendored Opus through a small
FFI shim. Lean is never in the running path. The property, "a lost packet is counted and concealed
in place, and frames stay within their bounds", has a control that hides the loss by renumbering
the later packets, and the property check must catch it.
