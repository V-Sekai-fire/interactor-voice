-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-License-Identifier: MIT
import PlausibleWitnessDag
import VoiceTests.Ffi

/-!
# Tests for the voice codec

Unit checks call the codec through `VoiceTests.Ffi`. The property is a plausible-witness-dag query
for a candidate that breaks it, over deterministic candidates derived from an index. The real code
must come back `.provablyNone` inside `searchWidth`; its control, which plants the defect the
property rules out, must come back `.found`. `.budgetHit` is a failure, never a pass.
-/

open PlausibleWitnessDag VoiceTests

namespace VoiceTests

def get (a : FloatArray) (i : Nat) : Float := a.get! i

/-- The delay, in samples, at which the decoded signal best matches its input: measured, then pinned. -/
def delay : UInt32 := 310
def frames : UInt32 := 24
/-- Every frame from the fourth on that no loss touches is at least this close to its input. -/
def boundDb : Float := 15.0
/-- The two frames after a lost one, while the decoder settles out of concealment (measured floor 9.4 dB). -/
def recoveryDb : Float := 8.0

def concealed (r : FloatArray) : Float := get r 0
def late (r : FloatArray) : Float := get r 1
def framesOut (r : FloatArray) : Float := get r 2
def worstDb (r : FloatArray) : Float := get r 3
def besideDb (r : FloatArray) : Float := get r 5

def unitChecks : List (String × Bool) :=
  let clean := Ffi.roundtrip 7 frames 0 0 delay
  let repeated := Ffi.roundtrip 7 frames 9 3 delay
  [ ("the encoder reports a lookahead of 312 samples", get clean 4 == 312.0),
    ("the decoded signal trails the input by 310 samples on five signals",
      (List.range 5).all fun s => Ffi.bestDelay s.toUInt32 == delay),
    ("with no loss nothing is concealed and every frame comes out",
      concealed clean == 0.0 && late clean == 0.0 && framesOut clean == frames.toFloat),
    ("with no loss every delivered frame is within the bound", worstDb clean ≥ boundDb),
    ("a repeated packet is dropped as late and adds no frame",
      late repeated == 1.0 && framesOut repeated == frames.toFloat && worstDb repeated ≥ boundDb) ]

-- ── The property, with a control that plants the defect ──────────────────────

def searchWidth : Nat := 300

def lostAt (c : Nat) : UInt32 := (4 + c % 18).toUInt32

/-- Real: packet `lostAt c` is lost; the decoder must count it, conceal it in place, keep every frame
    the loss does not touch within `boundDb` and the two after it within `recoveryDb`. Control: the same loss hidden by renumbering the later
    packets, which the check must catch. -/
def lossBreaks (broken : Bool) (c : Nat) : Bool :=
  let r := Ffi.roundtrip c.toUInt32 frames (lostAt c) (if broken then 2 else 1) delay
  !(concealed r == 1.0 && framesOut r == frames.toFloat && worstDb r ≥ boundDb && besideDb r ≥ recoveryDb)

def firstViolation (breaks : Nat → Bool) (steps : Nat) : Option Nat :=
  (List.range steps).find? breaks

def query (name : String) (breaks : Nat → Bool) : IO TraceEntry := do
  let readback : Nat → Readback (Option Nat) := fun steps =>
    match firstViolation breaks steps with
    | some w => { value := some w, found := true, witnessIdx := w, budgetHit := false }
    | none => { value := none, found := false, budgetHit := (firstViolation breaks searchWidth).isSome }
  let (_, _, trace) ← resolve name (fun _ c => breaks c) readback
  pure trace

def properties : List (String × (Bool → Nat → Bool)) := [
  ("a lost packet is counted and concealed in place; untouched frames stay within 15 dB and the two " ++
    "after it within 8 dB (control: the loss hidden by renumbering)", lossBreaks) ]

/-- The worst delivered frame over every candidate the property searched: the measured floor. -/
def measuredFloor : Float :=
  (List.range searchWidth).foldl (fun acc c =>
    min acc (worstDb (Ffi.roundtrip c.toUInt32 frames (lostAt c) 1 delay))) 1e9

/-- The worst of the two frames after each lost one, over the same candidates. -/
def besideFloor : Float :=
  (List.range searchWidth).foldl (fun acc c =>
    min acc (besideDb (Ffi.roundtrip c.toUInt32 frames (lostAt c) 1 delay))) 1e9

end VoiceTests

open VoiceTests in
def main : IO UInt32 := do
  let mut bad := 0
  for (name, ok) in unitChecks do
    IO.println s!"{if ok then "ok  " else "FAIL"} {name}"
    unless ok do bad := bad + 1
  for (name, breaks) in properties do
    let real ← query name (breaks false)
    let control ← query s!"control: {name}" (breaks true)
    let realOk := real.outcome == .provablyNone
    let controlOk := match control.outcome with | .found _ => true | _ => false
    IO.println s!"{if realOk && controlOk then "ok  " else "FAIL"} {name}: real {repr real.outcome}, control {repr control.outcome}"
    unless realOk && controlOk do bad := bad + 1
  IO.println s!"measured: the worst delivered frame over {searchWidth} lossy streams is {measuredFloor} dB (bound {boundDb} dB); the two frames after a loss {besideFloor} dB (bound {recoveryDb} dB)"
  IO.println s!"{unitChecks.length} checks and {properties.length} property, {bad} failures"
  return if bad == 0 then 0 else 1
