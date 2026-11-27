///|
/// Canonical Client IR type definitions.
///
/// These types are the single authority for code generation. Every field is
/// pre-resolved and pre-named so that emitters never need to consult the
/// original OpenAPI document or the Frontend Model.

///|
/// Http method. Only the methods supported by V1 are listed.
#derive(Eq, Debug, Hash)
pub enum HttpMethod {
  Get
  Post
  Put
  Patch
  Delete
}

///|
/// Parameter location: path, query, or header.
#derive(Eq, Debug, Hash)
pub enum ParamLocation {
  Path
  Query
  Header
}

///|
/// Presence semantics for a field or parameter.
#derive(Eq, Debug, Hash)
pub enum Presence {
  Required
  RequiredNullable
  Optional
  OptionalNullable
}

///|
/// A MoonBit type reference in the IR.
#derive(Eq, Debug, Hash)
pub enum TypeRef {
  Scalar(String)
  Named(String)
  Array(TypeRef)
  Nullable(TypeRef)
}

///|
/// Source location as a JSON Pointer (RFC 6901).
#derive(Eq, Debug)
pub struct SourceLocation {
  pointer : String
}

///|
/// Serialization style for a parameter.
#derive(Eq, Debug)
pub enum SerializationStyle {
  Simple
  Form
  UnsupportedStyle(String)
}

///|
/// A single parameter in the Canonical IR.
#derive(Eq, Debug)
pub struct ParameterIr {
  name : String
  wire_name : String
  location : ParamLocation
  required : Bool
  nullable : Bool
  style : SerializationStyle
  explode : Bool
  type_ref : TypeRef
  source : SourceLocation
}

///|
/// A request body in the Canonical IR.
#derive(Eq, Debug)
pub struct RequestBodyIr {
  type_ref : TypeRef?
  required : Bool
  media_type : String?
}

///|
/// A single response in the Canonical IR.
#derive(Eq, Debug)
pub struct ResponseIr {
  status : Int32
  type_ref : TypeRef?
  media_type : String?
}

///|
/// One variant in a response enum strategy.
#derive(Eq, Debug)
pub struct ResponseVariant {
  status : Int32
  type_ref : TypeRef
}

///|
/// Computed response strategy for an operation.
///
/// Determined during lowering from the success_responses array.
/// Codegen emitters read this to decide the operation's return type shape.
#derive(Eq, Debug)
pub enum ResponseStrategy {
  /// Single effective schema -> direct typed result (e.g. Pet)
  SingleResult(TypeRef)
  /// 204 only (no body) -> Unit
  UnitResult
  /// Multiple different success schemas -> generated response enum
  ResponseEnum(Array[ResponseVariant])
  /// No body content in any success response
  NoContent
  /// Unsupported media type - must not silently generate wrong wire code
  UnsupportedMediaType(String)
}

///|
/// Security scheme in the Canonical IR.
#derive(Eq, Debug)
pub struct AuthSchemeIr {
  name : String
  kind : String
  location : String?
  key_name : String?
}

///|
/// A single operation in the Canonical IR.
#derive(Eq, Debug)
pub struct OperationIr {
  operation_id : String
  fn_name : String
  response_name : String
  http_method : HttpMethod
  path : String
  tags : Array[String]
  parameters : Array[ParameterIr]
  request_body : RequestBodyIr?
  body_name : String?
  success_responses : Array[ResponseIr]
  error_responses : Array[ResponseIr]
  response_strategy : ResponseStrategy
  security : Array[Array[String]]
  source : SourceLocation
}

///|
/// A model in the Canonical IR: an enum, a struct, or a transparent type alias.
#derive(Eq, Debug)
pub enum ModelIr {
  EnumModel(EnumModelIr)
  StructModel(StructModelIr)
  AliasModel(AliasModelIr)
}

///|
/// A transparent type alias for a non-object component schema (array or
/// primitive). It lowers to `type Name = T` so a legal wire value decodes
/// through T's own codec instead of an empty struct.
#derive(Eq, Debug)
pub struct AliasModelIr {
  name : String
  type_ref : TypeRef
}

///|
/// An enum model.
#derive(Eq, Debug)
pub struct EnumModelIr {
  name : String
  members : Array[(String, String)]
}

///|
/// A struct model field.
#derive(Eq, Debug)
pub struct FieldIr {
  name : String
  wire_name : String
  type_ref : TypeRef
  presence : Presence
}

///|
/// A struct model.
#derive(Eq, Debug)
pub struct StructModelIr {
  name : String
  fields : Array[FieldIr]
  additional_properties : Bool
  additional_properties_field : String?
}

///|
/// The full Canonical Client IR for one API.
#derive(Eq, Debug)
pub struct ApiIr {
  module_name : String
  title : String
  version : String
  servers : Array[String]
  auth_schemes : Array[AuthSchemeIr]
  models : Array[ModelIr]
  operations : Array[OperationIr]
}
