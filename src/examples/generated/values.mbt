// Generated-accessors demo (library package): the lens accessors in
// profile_lenses.generated.mbt are produced by the lens-gen CLI from this
// package's .mbti —
//
//   moon info
//   moon run src/lens-gen-cli --target js -- \
//     src/examples/generated/pkg.generated.mbti -o \
//     src/examples/generated/profile_lenses.generated.mbt
//
// CI regenerates and diffs the file (freshness guard); run_demo drives a
// real form flow through the generated accessors, proving generated code
// compiles and behaves.

///|
pub struct Profile {
  nickname : String
  age : Int
} derive(Eq, Debug)

///|
pub extend Profile with Debug::{to_repr}

///|
pub extend Profile with Eq::{not_equal, equal}
