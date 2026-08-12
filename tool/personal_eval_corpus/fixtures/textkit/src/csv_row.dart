/// Parses one line of RFC 4180-ish CSV.
///
/// Supports quoted fields, embedded commas, and a doubled quote as an escaped
/// quote. Kept single-line on purpose: the fixture tasks are about field
/// splitting, not multi-line records.
class CsvRowParser {
  const CsvRowParser({this.separator = ','});

  final String separator;

  List<String> parse(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    var index = 0;

    while (index < line.length) {
      final char = line[index];
      if (inQuotes) {
        if (char == '"') {
          final isEscapedQuote =
              index + 1 < line.length && line[index + 1] == '"';
          if (isEscapedQuote) {
            buffer.write('"');
            index += 2;
            continue;
          }
          inQuotes = false;
          index += 1;
          continue;
        }
        buffer.write(char);
        index += 1;
        continue;
      }
      if (char == '"') {
        inQuotes = true;
        index += 1;
        continue;
      }
      if (char == separator) {
        fields.add(buffer.toString());
        buffer.clear();
        index += 1;
        continue;
      }
      buffer.write(char);
      index += 1;
    }
    fields.add(buffer.toString());
    return fields;
  }
}
