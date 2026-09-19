// moonform/schema: moonschema (QuietlyChan, vendored) adapter over the
// core Validator protocol — the "schema resolver".
//
// Form value structs convert to Json via `derive(ToJson)`; the adapter
// validates the whole-form Json against a compiled schema and reports,
// in each field's error slot, only the errors addressed to that field
// (JSON-Pointer path "/email" → field "email").
//
// Caveat handled: JSON Schema `required` errors attach to the parent
// object (empty path at the form root) with the field name inside the
// message — the adapter extracts the quoted property name.

///|
/// A per-field validator over a compiled schema: converts the WHOLE form
/// value to Json, validates once, and reports only the errors addressed
/// to `field_name` in this field's slot.
pub fn[A, V : ToJson] schema_field_validator(
  schema : @moonschema.Schema,
  field_name : String,
  field_lens : @core.Lens[V, A],
) -> @core.Validator[A, V] {
  @core.validator_with_form((_field_value, form_value) => {
    let errors = schema.validate(ToJson::to_json(form_value))
    let out : Array[String] = []
    for e in errors {
      if error_targets_field(e, field_name) {
        out.push(e.message)
      }
    }
    ignore(field_lens)
    out
  })
}

///|
/// Does this schema error belong to `field_name`?
/// - direct: instance_path == "/<field_name>" (or nested below it)
/// - required: instance_path == "" and message contains "<field_name>"
fn error_targets_field(
  e : @moonschema.ValidationError,
  field_name : String,
) -> Bool {
  if e.instance_path == "/\{field_name}" {
    return true
  }
  // nested under the field: "/field/..." pointers
  if e.instance_path.has_prefix("/\{field_name}/") {
    return true
  }
  // missing-required errors sit on the parent with the name in the message
  if e.keyword == "required" && e.instance_path == "" {
    return message_mentions(e.message, field_name)
  }
  false
}

///|
fn message_mentions(message : String, field_name : String) -> Bool {
  // JSON-Schema style: must have required property "email"
  message.contains("\"\{field_name}\"")
}
