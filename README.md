# interactor-voice

Voice as sequenced Opus packets in a godot-sandbox guest, with a concealed frame for each lost packet.

## What it is for

`voice.elf` carries the voice codec in a guest, so the engine carries no voice code (RFD 2287). Each packet carries a sequence number, so a loss is counted and concealed in place and the output stays aligned with the input. Carrying the packets is the zone's job, not this repository's. The tests are a Lean package that links the codec natively; Lean is never in the running path.

## Build and run

With a `clang++` that has a riscv64 target on `PATH` (the sysroot's pixi environment has one), a `repository-riscv64-sysroot` checkout, and a `contract-guest-runtime` checkout at `../../2-contract/guest-runtime` or named by `GUEST_RUNTIME_ROOT`:

```sh
RISCV64_SYSROOT=<repository-riscv64-sysroot> ./build.sh
cd tests && lake build && lake exe tests
```

The harness runs `voice.elf` in the engine once a godot_sandbox addon is linked in. It plays a tone through the guest, and with `--control` it hides the loss, which the check must catch:

```sh
tools/link_addon.sh <path to a godot_sandbox addon>
godot --path project --import
godot --path project --script harness.gd
godot --path project --script harness.gd ++ --control
godot --headless --path project --script "$PWD/tests/gate_voice_loopback.gd"
godot --headless --path project --script "$PWD/tests/gate_voice_loopback.gd" ++ --control=corrupt
godot --headless --path project --script "$PWD/tests/gate_voice_loopback.gd" ++ --control=frame_size
```

The loopback gate sends a 1 kHz tone through the guest with nothing lost and checks the frame count, the decoder's counts and the SNR. Each control must fail it. The `guest` workflow builds `voice.elf` from source and runs the harness and the gate, with their controls, on the ELF it built.

## Licence

MIT; see `LICENSE`. The vendored codec under `vendor/opus/` keeps its own licence.
