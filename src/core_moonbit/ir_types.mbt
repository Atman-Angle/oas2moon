///|
/// Canonical Client IR type definitions.
///
/// These types are the single authority for code generation. Every field is
/// pre-resolved and pre-named so that emitters never need to consult the
/// original OpenAPI document or the Frontend Model.

///| Http method. Only the methods supported by V1 are listed.
pub enum HttpMethod {
  Get
  Post
  Put
  Patch
  Delete
} derive(Eq, Debug, Hash)

///| Parameter location: path, query, or header.
pub enum ParamLocation {
  Path
  Query
  Header
} derive(Eq, Debug, Hash)

///| Presence semantics for a field or parameter.
pub enum Presence {
  Required
  RequiredNullable
  Optional
  OptionalNullable
} derive(Eq, Debug, Hash)

///| A MoonBit type reference in the IR.
pub enum TypeRef {
  Scalar(String)
  Named(String)
  Array(TypeRef)
} derive(Eq, Debug, Hash)

///| Source location as a JSON Pointer (RFC 6901).
pub struct SourceLocation {
  pointer : String
} derive(Eq, Debug)

///| Serialization style for a parameter.
pub enum SerializationStyle {
  Simple
  Form
  UnsupportedStyle(String)
} derive(Eq, Debug)

///| A single parameter in the Canonical IR.
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
} derive(Eq, Debug)

///| A request body in the Canonical IR.
pub struct RequestBodyIr {
  type_ref : TypeRef?
  required : Bool
  media_type : String?
} derive(Eq, Debug)

///| A single response in the Canonical IR.
pub struct ResponseIr {
  status : Int
  type_ref : TypeRef?
  media_type : String?
} derive(Eq, Debug)

///| One variant in a response enum strategy.
pub struct ResponseVariant {
  status : Int
  type_ref : TypeRef
} derive(Eq, Debug)

///| Computed response strategy for an operation.
///
/// Determined during lowering from the success_responses array.
/// Codegen emitters read this to decide the operation's return type shape.
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
} derive(Eq, Debug)

///| Security scheme in the Canonical IR.
pub struct AuthSchemeIr {
  name : String
  kind : String
  location : String?
  key_name : String?
} derive(Eq, Debug)

///| A single operation in the Canonical IR.
pub struct OperationIr {
  operation_id : String
  fn_name : String
  method : HttpMethod
  path : String
  tags : Array[String]
  parameters : Array[ParameterIr]
  request_body : RequestBodyIr?
  success_responses : Array[ResponseIr]
  error_responses : Array[ResponseIr]
  response_strategy : ResponseStrategy
  security : Array[String]
  source : SourceLocation
} derive(Eq, Debug)

///| A model in the Canonical IR: either an enum or a struct.
pub enum ModelIr {
  EnumModel(EnumModelIr)
  StructModel(StructModelIr)
} derive(Eq, Debug)

///| An enum model.
pub struct EnumModelIr {
  name : String
  members : Array[(String, String)]
} derive(Eq, Debug)

///| A struct model field.
pub struct FieldIr {
  name : String
  wire_name : String
  type_ref : TypeRef
  presence : Presence
} derive(Eq, Debug)

///| A struct model.
pub struct StructModelIr {
  name : String
  fields : Array[FieldIr]
  additional_properties : Bool
  additional_properties_field : String?
} derive(Eq, Debug)

///| The full Canonical Client IR for one API.
pub struct ApiIr {
  module_name : String
  title : String
  version : String
  servers : Array[String]
  auth_schemes : Array[AuthSchemeIr]
  models : Array[ModelIr]
  operations : Array[OperationIr]
} derive(Eq, Debug)
