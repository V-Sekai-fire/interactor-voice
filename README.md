# interactor-voice

Voice as sequenced Opus packets in a godot-sandbox guest, with a concealed frame for each lost packet.

## What it is for

`voice.elf` carries the voice codec in a guest, so the engine carries no voice code (RFD 2287). Each packet carries a sequence number, so a loss is counted and concealed in place and the output stays aligned with the input. Carrying the packets is the zone's job, not this repository's. The tests are a Lean package that links the codec natively; Lean is never in the running path.

## Build and run

With a `clang++` that has a riscv64 target on `PATH`:

```sh
RISCV64_SYSROOT=<riscv64 sysroot with toolchain.cmake> ./build.sh
cd tests && lake build && lake exe tests
```

## Licence

MIT; see `LICENSE`. The vendored codec under `vendor/opus/` keeps its own licence.
