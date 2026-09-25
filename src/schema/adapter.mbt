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

// -- group validation --------------------------------------------------------

///|
/// A group validator over a compiled schema describing the GROUP value:
/// converts the group value to Json, validates once, and distributes
/// errors to child fields by their JSON-Pointer paths relative to the
/// group root ("/username" → the group's `username` field;
/// "/items/0/name" → the nested key `items.0.name`). Root-path
/// `required` errors name the missing property in the message and
/// distribute to that field; other root-path errors (e.g. `minItems` on
/// an array group) become group-level errors.
pub fn[G : ToJson, V] schema_group_validator(
  schema : @moonschema.Schema,
) -> @core.GroupValidator[G, V] {
  @core.group_validator((group_value, _form_value) => {
    let errors = schema.validate(ToJson::to_json(group_value))
    let field_map : Map[@core.Key, Array[String]] = Map([])
    let group_errors : Array[String] = []
    for e in errors {
      match pointer_to_key(e.instance_path) {
        Some(k) =>
          match field_map.get(k) {
            Some(msgs) => msgs.push(e.message)
            None => field_map.set(k, [e.message])
          }
        None =>
          // group root: required errors name the property; the rest are
          // group-level errors
          if e.keyword == "required" {
            match quoted_property(e.message) {
              Some(prop) => {
                let k = @core.Key::field(prop)
                match field_map.get(k) {
                  Some(msgs) => msgs.push(e.message)
                  None => field_map.set(k, [e.message])
                }
              }
              None => group_errors.push(e.message)
            }
          } else {
            group_errors.push(e.message)
          }
      }
    }
    let entries : Array[(@core.Key, Array[String])] = []
    for k, msgs in field_map {
      entries.push((k, msgs))
    }
    @core.GroupValidationResult::make(group_errors, entries)
  })
}

///|
/// Parse a JSON-Pointer instance path relative to the group root into a
/// structured key: "/username" → `username`, "/items/0/name" →
/// `items.0.name`. Empty paths (the group root itself) return None.
fn pointer_to_key(path : String) -> @core.Key? {
  if path == "" {
    return None
  }
  let mut key = @core.Key::root()
  let mut any = false
  for seg in path.split("/") {
    if seg.is_empty() {
      continue // leading (and doubled) slashes
    }
    let chars = seg.to_array()
    if all_digits(chars) {
      key = key.push_idx(chars_to_int(chars))
    } else {
      key = key.push_field(chars_to_string(chars))
    }
    any = true
  }
  if any {
    Some(key)
  } else {
    None // "/" alone: no segments under the root
  }
}

///|
fn all_digits(chars : Array[Char]) -> Bool {
  if chars.length() == 0 {
    return false
  }
  for c in chars {
    if c < '0' || c > '9' {
      return false
    }
  }
  true
}

///|
fn chars_to_int(chars : Array[Char]) -> Int {
  let mut n = 0
  for c in chars {
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  n
}

///|
fn chars_to_string(chars : Array[Char]) -> String {
  let b = StringBuilder()
  for c in chars {
    b.write_char(c)
  }
  b.to_string()
}

///|
/// First double-quoted substring of `message` (JSON-Schema `required`
/// messages quote the missing property name).
fn quoted_property(message : String) -> String? {
  let chars = message.to_array()
  let mut start = -1
  for i, c in chars {
    if c == '"' {
      if start == -1 {
        start = i
      } else {
        return Some(message[start + 1:i].to_owned())
      }
    }
  }
  None
}
