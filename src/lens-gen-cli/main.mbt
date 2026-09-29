// lens-gen CLI: .mbti file in, lens accessor source out (js target).
//
//   moon info                                              # produce the .mbti
//   moon run src/lens-gen-cli --target js -- <pkg.mbti>    # print to stdout
//   moon run src/lens-gen-cli --target js -- <pkg.mbti> -o <out.mbt>
//
// The optional core_alias argument (default "@core") names the import
// alias the generated code should use for moonform/core.

///|
extern "js" fn js_cli_args() -> FixedArray[String] =
  #| () => globalThis.process.argv.slice(2)

///|
extern "js" fn js_read_file(path : String) -> String =
  #| (path) => require("node:fs").readFileSync(path, "utf8")

///|
extern "js" fn js_write_file(path : String, content : String) -> Unit =
  #| (path, content) => require("node:fs").writeFileSync(path, content)

///|
extern "js" fn js_file_exists(path : String) -> Bool =
  #| (path) => require("node:fs").existsSync(path)

///|
fn cli_usage() -> Unit {
  println("lens-gen: .mbti in, lens accessor source out")
  println(
    "usage: moon run src/lens-gen-cli -- <path.mbti> [core_alias] [-o <out.mbt>]",
  )
  println("  core_alias  import alias for moonform/core, default @core")
  println("  -o          write to a file instead of stdout")
}

///|
fn cli_error(message : String) -> Unit {
  println("lens-gen: error: \{message}")
  cli_usage()
}

///|
fn main {
  let fixed = js_cli_args()
  let args : Array[String] = []
  for i in 0..<fixed.length() {
    args.push(fixed[i])
  }
  if args.length() < 1 {
    cli_usage()
    return
  }
  // positional tokens (input path first, then the optional core alias);
  // `-o` takes the next token — flags anywhere, position-independent
  let positional : Array[String] = []
  let mut out_path : String? = None
  let mut i = 0
  while i < args.length() {
    if args[i] == "-o" {
      if i + 1 >= args.length() {
        cli_error("-o requires a value (the output file path)")
        return
      }
      out_path = Some(args[i + 1])
      i = i + 2
    } else if args[i].has_prefix("-") {
      cli_error("unknown flag \{args[i]}")
      return
    } else {
      positional.push(args[i])
      i = i + 1
    }
  }
  if positional.length() > 2 {
    cli_error(
      "too many arguments: expected <path.mbti> [core_alias], got \{positional.length()}",
    )
    return
  }
  let input = positional[0]
  let core_alias = if positional.length() == 2 {
    positional[1]
  } else {
    "@core"
  }
  if !js_file_exists(input) {
    cli_error("input file not found: \{input}")
    return
  }
  let content = js_read_file(input)
  let code = @lensgen.generate(content, core_alias)
  match out_path {
    Some(p) => {
      js_write_file(p, code)
      println("lens-gen: wrote \{p}: \{code.length()} bytes")
    }
    // stdout mode: for inspection; -o writes the exact bytes
    None => println(code)
  }
}
