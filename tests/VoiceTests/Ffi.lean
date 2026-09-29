-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-License-Identifier: MIT
/-!
# The voice codec, through tests/ffi/shim.cpp

`roundtrip seed frames at mode delay` sends a candidate signal through `src/voice_codec` as the
guest does. Mode 0 delivers every packet, 1 loses packet `at`, 2 loses it and renumbers the later
packets so the loss is hidden, 3 sends it twice. The result is
[concealed, late, frames out, worst delivered-frame SNR in dB, lookahead].
-/

namespace VoiceTests.Ffi

@[extern "vt_lean_roundtrip"] opaque roundtrip : UInt32 → UInt32 → UInt32 → UInt8 → UInt32 → FloatArray
@[extern "vt_lean_best_delay"] opaque bestDelay : UInt32 → UInt32

end VoiceTests.Ffi
