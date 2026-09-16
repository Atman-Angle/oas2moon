///|
/// Diagnostic types for the support validation and lowering pipeline.
///
/// Every diagnostic is deterministic and includes a JSON Pointer.

///|
/// Severity of a diagnostic.
pub enum Severity {
  Error
  Warning
} derive(Eq, Debug)

///|
/// A single diagnostic message.
pub struct Diagnostic {
  code : String
  severity : Severity
  json_pointer : String
  message : String
  operation_id : String?
  suggestion : String?
} derive(Eq, Debug)

///|
/// Render a diagnostic as a human-readable string.
pub fn diagnostic_to_string(d : Diagnostic) -> String {
  let mut result = severity_label(d.severity) +
    ": " +
    d.code +
    ": " +
    d.json_pointer
  match d.operation_id {
    Some(id) => result = result + " [" + id + "]"
    None => ()
  }
  result = result + ": " + d.message
  match d.suggestion {
    Some(s) => result = result + " suggestion=" + s
    None => ()
  }
  result
}

///|
fn severity_label(s : Severity) -> String {
  match s {
    Error => "ERROR"
    Warning => "WARNING"
  }
}

///|
/// Create an error diagnostic.
pub fn error_diagnostic(
  code : String,
  pointer : String,
  message : String,
) -> Diagnostic {
  {
    code,
    severity: Error,
    json_pointer: pointer,
    message,
    operation_id: None,
    suggestion: None,
  }
}

///|
/// Create a warning diagnostic.
pub fn warning_diagnostic(
  code : String,
  pointer : String,
  message : String,
) -> Diagnostic {
  {
    code,
    severity: Warning,
    json_pointer: pointer,
    message,
    operation_id: None,
    suggestion: None,
  }
}
