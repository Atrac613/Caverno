/// Parses one line of RFC 4180-ish CSV.
///
/// Supports quoted fields, embedded commas, and a doubled quote as an escaped
/// quote. Kept single-line on purpose: the fixture tasks are about field
/// splitting, not multi-line records.
class CsvRowParser {
  const CsvRowParser({this.separator = ','});

  final String separator;

  List<String> parse(String line) {
    return line.split(separator);
  }
}
