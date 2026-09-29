// Generated-accessors demo (library package): the lens accessors in
// lenses.generated.mbt are produced by the lens-gen CLI from this
// package's .mbti —
//
//   moon info
//   moon run src/lens-gen-cli --target js -- \
//     src/examples/generated/pkg.generated.mbti -o \
//     src/examples/generated/lenses.generated.mbt
//
// CI regenerates and diffs the file (freshness guard); run_demo drives a
// real form flow through the generated accessors, proving generated code
// compiles and behaves. Two structs with derive closing lines and pub(all)
// visibility pin the parser's authentic `moon info` shapes.

///|
pub struct Profile {
  nickname : String
  age : Int
} derive(Eq, Debug)

///|
pub extend Profile with Debug::{to_repr}

///|
pub extend Profile with Eq::{not_equal, equal}

///|
pub(all) struct Address {
  city : String
  zip : Int
} derive(Eq, Debug)

///|
pub extend Address with Debug::{to_repr}

///|
pub extend Address with Eq::{not_equal, equal}
