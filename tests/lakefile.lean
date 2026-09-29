-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-License-Identifier: MIT
import Lake
open Lake DSL System

package VoiceTests where
  leanOptions := #[⟨`autoImplicit, false⟩]

require «plausible-witness-dag» from git
  "https://github.com/fire/plausible-witness-dag" @ "160b94c9c6eed3bb9ebffce919fc6f989dcafba8"

def opusRoot (pkg : Package) : FilePath := pkg.dir / ".." / "vendor" / "opus"

-- vendor/opus/sources.txt, compiled natively with the same config.h the guest uses.
def opusObj (pkg : Package) (rel : String) : FetchM (Job FilePath) := do
  let root := opusRoot pkg
  let dirs : Array String := #["", "celt", "silk", "silk/float", "opus"]
  let includes := dirs.foldl (fun (acc : Array String) (d : String) => acc ++ #["-I", (root / d).toString]) #[]
  let src ← inputTextFile (root / rel)
  buildO (pkg.buildDir / "opus" / s!"{rel.replace "/" "_"}.o") src includes
    #["-DHAVE_CONFIG_H", "-O2", "-fPIC", "-w"] "cc"

def cppObj (pkg : Package) (name : String) (src : FilePath) : FetchM (Job FilePath) := do
  let includes := #["-I", (← getLeanIncludeDir).toString, "-I", (pkg.dir / ".." / "src").toString,
    "-I", (opusRoot pkg / "opus").toString]
  buildO (pkg.buildDir / "ffi" / s!"{name}.o") (← inputTextFile src) includes #["-std=c++17", "-O2", "-fPIC", "-fno-exceptions", "-fno-rtti"] "c++"

extern_lib voice_ffi pkg := do
  let sources ← IO.FS.lines (opusRoot pkg / "sources.txt")
  let opus ← (sources.filter (· ≠ "")).mapM (opusObj pkg)
  let codec ← cppObj pkg "voice_codec" (pkg.dir / ".." / "src" / "voice_codec.cpp")
  let shim ← cppObj pkg "shim" (pkg.dir / "ffi" / "shim.cpp")
  buildStaticLib (pkg.staticLibDir / nameToStaticLib "voice_ffi") (opus ++ #[codec, shim])

lean_lib VoiceTests

@[default_target]
lean_exe tests where
  root := `Main
  moreLinkArgs := #["-lm"]
