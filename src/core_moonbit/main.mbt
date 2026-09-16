///|
/// Canonical Client IR builder entry point.
///
/// Reads a Frontend Model JSON (from the MoonContract-based adapter),
/// lowers it to the typed Canonical Client IR, and writes the result
/// as deterministic canonical JSON for the codegen backends.
///
/// Usage: oas2moon-core <normalized.json> <canonical-ir.json> [module-name]
fn main raise {
  let args = @env.args()
  guard args.length() >= 3 else {
    println(
      "usage: oas2moon-core <normalized.json> <canonical-ir.json> [module-name]",
    )
    @sys.exit(2)
    return
  }
  let module_name = if args.length() >= 4 {
    args[3]
  } else {
    "oas2moon/generated"
  }
  let source = @fs.read_file_to_string(args[1])
  let root = @json.parse(source)
  let api = lower(root, module_name)
  @fs.write_string_to_file(args[2], api_to_json_string(api))
}
