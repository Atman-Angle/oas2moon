///|
/// Return the version of the published oas2moon umbrella suite.
pub fn version() -> String {
  "0.1.0"
}

///|
/// Return the component modules that make up the complete oas2moon suite.
pub fn component_packages() -> Array[String] {
  [
    "Atman-Angle/oas2moon_frontend", "Atman-Angle/oas2moon_core", "Atman-Angle/oas2moon_codegen",
    "Atman-Angle/oas2moon_runtime",
  ]
}
