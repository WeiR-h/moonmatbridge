///|
test "UTF8 scalar scan agrees with independent standard decoder at boundaries and random byte sequences" {
  let cases = [
    b"", b"\x00", b"\x7f", b"\xc2\x80", b"\xdf\xbf", b"\xe0\xa0\x80", b"\xed\x9f\xbf",
    b"\xef\xbb\xbf", b"\xef\xbf\xbf", b"\xf0\x90\x80\x80", b"\xf4\x8f\xbf\xbf", b"\xc0\x80",
    b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\xf5\x80\x80\x80", b"\xe0\x80\x80", b"\xe1\x80",
  ]
  for i = 0; i < 256; i = i + 1 {
    cases.push(Bytes::makei(1, _ => i.to_byte()))
  }
  let mut seed = 20261017U
  for i = 0; i < 2000; i = i + 1 {
    cases.push(
      Bytes::makei(i % 8 + 1, fn(_) {
        seed = seed * 1664525U + 1013904223U
        (seed >> 24).to_byte()
      }),
    )
  }
  for bytes in cases {
    let expected : Int? = Some(@utf8.decode(bytes[:]).iter().count()) catch {
      _ => None
    }
    match expected {
      Some(count) => assert_eq(utf8_scalar_count(bytes[:]), count)
      None =>
        assert_eq(
          error_code(() => ignore(utf8_scalar_count(bytes[:]))),
          "invalid-char",
        )
    }
  }
}
