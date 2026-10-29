///|
/// Explicit codec for miINT8 variable, field and legacy class names.
pub(all) enum NameEncoding {
  Utf8
  Latin1
} derive(Eq, @debug.Debug)

///|
pub extend NameEncoding with Eq::{equal, not_equal}

///|
pub extend NameEncoding with @debug.Debug::{to_repr}

///|
fn encode_name(text : String, encoding : NameEncoding) -> Bytes raise MatError {
  match encoding {
    Utf8 => @utf8.encode(text[:])
    Latin1 => {
      let values : Array[Byte] = []
      for c in text.iter() {
        if c.to_int() > 255 {
          fail("invalid-name", 0, "Name cannot be represented in Latin1")
        }
        values.push(c.to_int().to_byte())
      }
      Bytes::makei(values.length(), i => values[i])
    }
  }
}

///|
fn decode_name(
  bytes : BytesView,
  encoding : NameEncoding,
  offset : Int32,
) -> String raise MatError {
  match encoding {
    Utf8 =>
      @utf8.decode(bytes) catch {
        _ => {
          fail("invalid-name", offset, "Name must be valid UTF-8")
          ""
        }
      }
    Latin1 => {
      let text = StringBuilder()
      for byte in bytes {
        text.write_char(byte.to_int().unsafe_to_char())
      }
      text.to_string()
    }
  }
}
