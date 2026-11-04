/// Helpers for reading loosely typed JSON from the Tieba APIs.
///
/// Every helper tolerates missing or wrongly typed values and returns an
/// empty/zero result instead of throwing.
library;

typedef Json = Map<String, dynamic>;

Json object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> objects(dynamic value) =>
    value is List ? value.map(object).toList() : [];
int number(dynamic value) => int.tryParse('$value') ?? 0;
bool flag(dynamic value) => value == true || number(value) == 1;
String firstText(Iterable<dynamic> values, [String fallback = '']) => values
    .map((v) => v == null ? '' : '$v')
    .firstWhere((v) => v.isNotEmpty, orElse: () => fallback);
