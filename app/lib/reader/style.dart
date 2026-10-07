import 'dart:convert';

import 'package:flutter/material.dart';

enum GlossTier { minimal, brief, full }

enum GlossLanguage { enZh, enEn }

enum GlossExpansion { current, otherLanguage }

enum ReaderTheme { white, paper, quiet, night }

class ReaderPalette {
  final Color background, ink, surface;
  const ReaderPalette(this.background, this.ink, this.surface);
  bool get dark => background.computeLuminance() < .2;
  static const palettes = {
    ReaderTheme.white: ReaderPalette(
      Color(0xFFFFFFFF),
      Color(0xFF1B1B1D),
      Color(0xFFF8F8FA),
    ),
    ReaderTheme.paper: ReaderPalette(
      Color(0xFFF6EEDD),
      Color(0xFF3A2D21),
      Color(0xFFFFF9EF),
    ),
    ReaderTheme.quiet: ReaderPalette(
      Color(0xFF4A4A4E),
      Color(0xFFDEDEE0),
      Color(0xFF58585D),
    ),
    ReaderTheme.night: ReaderPalette(
      Color(0xFF0F0F10),
      Color(0xFFC8C8CD),
      Color(0xFF242426),
    ),
  };
}

class ReaderStyle {
  final String font;
  final double size,
      lineHeight,
      letterSpacing,
      paragraphSpacing,
      margin,
      bubbleSize;
  final bool bold, justify, followSystem, paged, landscapePaged;
  final ReaderTheme theme;
  final GlossTier tier;
  final GlossLanguage glossLanguage;
  final GlossExpansion glossExpansion;
  final int senses;
  const ReaderStyle({
    this.font = 'platform',
    this.size = 19,
    this.lineHeight = 1.6,
    this.letterSpacing = 0,
    this.paragraphSpacing = .4,
    this.margin = 24,
    this.bubbleSize = 15,
    this.bold = false,
    this.justify = true,
    this.followSystem = true,
    this.paged = true,
    this.landscapePaged = true,
    this.theme = ReaderTheme.white,
    this.tier = GlossTier.minimal,
    this.glossLanguage = GlossLanguage.enZh,
    this.glossExpansion = GlossExpansion.current,
    this.senses = 2,
  });
  static bool isWideLandscape(Size size) =>
      size.width >= 900 && size.shortestSide >= 600 && size.width > size.height;

  bool pagedFor(Size size) => isWideLandscape(size) ? landscapePaged : paged;

  ReaderPalette palette(Brightness brightness) =>
      ReaderPalette.palettes[followSystem && brightness == Brightness.dark
          ? ReaderTheme.night
          : theme]!;
  String? family(TargetPlatform platform) => font == 'platform'
      ? (platform == TargetPlatform.iOS ? 'Iowan Old Style' : 'Literata')
      : font == 'system'
      ? null
      : font;
  // Only values that affect measured page geometry belong in a layout key.
  String get paginationKey => jsonEncode([
    font,
    size,
    lineHeight,
    letterSpacing,
    paragraphSpacing,
    margin,
    bold,
    justify,
  ]);
  Map<String, dynamic> toJson() => {
    'version': 1,
    'font': font,
    'size': size,
    'lineHeight': lineHeight,
    'letterSpacing': letterSpacing,
    'paragraphSpacing': paragraphSpacing,
    'margin': margin,
    'bubbleSize': bubbleSize,
    'bold': bold,
    'justify': justify,
    'followSystem': followSystem,
    'paged': paged,
    'landscapePaged': landscapePaged,
    'theme': theme.name,
    'tier': tier.name,
    'glossLanguage': glossLanguage.name,
    'glossExpansion': glossExpansion.name,
    'senses': senses,
  };
  String encode() => jsonEncode(toJson());
  factory ReaderStyle.decode(String? raw) {
    if (raw == null) return const ReaderStyle();
    try {
      return ReaderStyle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ReaderStyle();
    }
  }
  factory ReaderStyle.fromJson(Map<String, dynamic> j) {
    double number(String k, double d, double min, double max) =>
        ((j[k] is num ? j[k] as num : d).toDouble()).clamp(min, max);
    return ReaderStyle(
      font: j['font'] as String? ?? 'platform',
      size: number('size', 19, 14, 34),
      lineHeight: number('lineHeight', 1.6, 1.1, 2.4),
      letterSpacing: number('letterSpacing', 0, -.02, .15),
      paragraphSpacing: number('paragraphSpacing', .4, 0, 2),
      margin: number('margin', 24, 12, 60),
      bubbleSize: number('bubbleSize', 15, 12, 24),
      bold: j['bold'] == true,
      justify: j['justify'] != false,
      followSystem: j['followSystem'] != false,
      paged: j['paged'] == true,
      landscapePaged: j['landscapePaged'] != false,
      theme: ReaderTheme.values.firstWhere(
        (x) => x.name == j['theme'],
        orElse: () => ReaderTheme.white,
      ),
      tier: GlossTier.values.firstWhere(
        (x) => x.name == j['tier'],
        orElse: () => GlossTier.minimal,
      ),
      glossLanguage: GlossLanguage.values.firstWhere(
        (x) => x.name == j['glossLanguage'],
        orElse: () => GlossLanguage.enZh,
      ),
      glossExpansion: GlossExpansion.values.firstWhere(
        (x) => x.name == j['glossExpansion'],
        orElse: () => GlossExpansion.current,
      ),
      senses: (j['senses'] is int ? j['senses'] as int : 2).clamp(1, 3),
    );
  }
  ReaderStyle withValue(String key, dynamic value) =>
      ReaderStyle.fromJson({...toJson(), key: value});
}
