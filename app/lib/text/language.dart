class WordRange {
  final int start, end;
  final String text;
  const WordRange(this.start, this.end, this.text);
}

abstract interface class LanguageSupport {
  String get code;
  WordRange? wordAt(String text, int offset);
  WordRange sentenceAt(String text, int offset);
  List<String> candidates(String word);
}

class EnglishLanguage implements LanguageSupport {
  @override
  String get code => 'en';
  static final _word = RegExp(r"[A-Za-z]+(?:[-'’][A-Za-z]+)*");
  @override
  WordRange? wordAt(String text, int offset) {
    for (final m in _word.allMatches(text)) {
      if (offset >= m.start && offset < m.end) {
        return WordRange(m.start, m.end, m.group(0)!);
      }
    }
    return null;
  }

  @override
  List<String> candidates(String word) {
    final w = word.toLowerCase().replaceAll('’', "'");
    return [w, if (w.endsWith("'s")) w.substring(0, w.length - 2)];
  }

  @override
  WordRange sentenceAt(String text, int offset) {
    final ends = <int>[0];
    final punctuation = RegExp(r'''[.!?]+[”"’']*(?:\s+|$)''');
    for (final m in punctuation.allMatches(text)) {
      final prefix = text.substring(0, m.start);
      if (RegExp(
        r'\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|St|e\.g|i\.e)$',
        caseSensitive: false,
      ).hasMatch(prefix)) {
        continue;
      }
      if (RegExp(r'\b[A-Z]$').hasMatch(prefix)) continue;
      ends.add(m.end);
    }
    if (ends.last != text.length) ends.add(text.length);
    for (int i = 1; i < ends.length; i++) {
      if (offset < ends[i]) {
        return WordRange(
          ends[i - 1],
          ends[i],
          text.substring(ends[i - 1], ends[i]).trim(),
        );
      }
    }
    return WordRange(0, text.length, text);
  }
}
