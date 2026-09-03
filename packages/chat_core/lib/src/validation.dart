String requireNonBlank(String value, String argumentName) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, argumentName, 'must not be empty');
  }
  return normalized;
}
