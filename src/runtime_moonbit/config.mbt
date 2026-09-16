///|
/// Static configuration for one generated SDK client.
pub struct Config {
  origin : String
  base_path : String
  bearer_token : String?
  basic_username : String?
  basic_password : String?
  api_key_name : String?
  api_key_value : String?
  api_key_location : String?
} derive(Debug)

///|
/// Create a runtime configuration.
///
/// `base_url` is split into an origin (`scheme://authority`) and a base path.
/// The split is required because the transport library connects to an origin,
/// while request targets must stay relative. A trailing slash is dropped so
/// that path joining stays deterministic.
pub fn Config::new(
  base_url : String,
  bearer_token? : String,
  basic_username? : String,
  basic_password? : String,
  api_key_name? : String,
  api_key_value? : String,
  api_key_location? : String,
) -> Config {
  let trimmed = if base_url.has_suffix("/") {
    base_url[:base_url.length() - 1].to_owned()
  } else {
    base_url
  }
  let (origin, base_path) = match trimmed.find("://") {
    Some(scheme_end) => {
      let authority_start = scheme_end + 3
      match trimmed[authority_start:].find("/") {
        Some(slash) => {
          let split = authority_start + slash
          (trimmed[:split].to_owned(), trimmed[split:].to_owned())
        }
        None => (trimmed, "")
      }
    }
    None => (trimmed, "")
  }
  {
    origin,
    base_path,
    bearer_token,
    basic_username,
    basic_password,
    api_key_name,
    api_key_value,
    api_key_location,
  }
}

///|
/// The `scheme://authority` part of the configured base URL.
pub fn Config::origin(self : Config) -> String {
  self.origin
}

///|
/// The path prefix that every request target of this client starts with.
pub fn Config::base_path(self : Config) -> String {
  self.base_path
}

///|
/// The configured bearer token, when one was supplied.
pub fn Config::bearer_token(self : Config) -> String? {
  self.bearer_token
}

///|
/// The configured basic auth username, when one was supplied.
pub fn Config::basic_username(self : Config) -> String? {
  self.basic_username
}

///|
/// The configured basic auth password, when one was supplied.
pub fn Config::basic_password(self : Config) -> String? {
  self.basic_password
}

///|
/// The configured API key name (header name or query parameter name), when one was supplied.
pub fn Config::api_key_name(self : Config) -> String? {
  self.api_key_name
}

///|
/// The configured API key value, when one was supplied.
pub fn Config::api_key_value(self : Config) -> String? {
  self.api_key_value
}

///|
/// The configured API key location ("header" or "query"), when one was supplied.
pub fn Config::api_key_location(self : Config) -> String? {
  self.api_key_location
}
