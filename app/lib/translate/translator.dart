abstract interface class Translator {
  Future<bool> isAvailable(String from, String to);
  Future<void> prepare(String from, String to);
  Future<String> translate(String text, String from, String to);
}

// Platform translation implementations belong to phase 3. No fake translation.
