import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library/library.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: ReadingApp()));
}

class ReadingApp extends StatelessWidget {
  const ReadingApp({super.key});
  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF835C3E),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF121213)
          : const Color(0xFFFBFAF8),
      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? const Color(0xFF121213)
            : const Color(0xFFFBFAF8),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF242426) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Reading',
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const LibraryPage(),
  );
}

Future<void> showAcknowledgments(BuildContext context) async {
  final text = await rootBundle.loadString('assets/licenses/NOTICE.txt');
  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('开源许可与致谢')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(text, style: const TextStyle(height: 1.7)),
            const SizedBox(height: 24),
            for (final name in [
              'ECDICT',
              'Wiktionary',
              'Literata',
              'SourceSerif4',
              'EBGaramond',
              'AtkinsonHyperlegible',
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final license = await rootBundle.loadString(
                    'assets/licenses/$name.txt',
                  );
                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: Text(name)),
                        body: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: SelectableText(license),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Flutter 与依赖项'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Reading',
                applicationVersion: '0.2.0',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
