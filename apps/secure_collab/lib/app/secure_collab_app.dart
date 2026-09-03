import 'package:chat_media/chat_media.dart';
import 'package:chat_media_picker/chat_media_picker.dart';
import 'package:flutter/material.dart';
import 'package:homeserver_client/homeserver_client.dart';

import '../features/workspace/secure_workspace_page.dart';
import '../l10n/secure_localizations.dart';

class SecureCollabApp extends StatelessWidget {
  const SecureCollabApp({
    super.key,
    this.mediaPicker,
    this.messageSync,
    this.locale,
  });

  /// Tests and alternate platform shells can inject their own picker without
  /// coupling the workspace UI to a particular native file-selection plugin.
  final MediaPickerPort? mediaPicker;

  /// Explicit production/test bridge to the encrypted durable outbox.
  /// When absent, the UI labels new messages as local-only.
  final HomeserverMessageSync? messageSync;

  /// Optional override for tests, previews, and embedders. Production follows
  /// Korean or English system preferences and falls back to Korean.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF6739B6);
    const lime = Color(0xFFB8F05A);
    const limeDark = Color(0xFF456800);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: purple,
          brightness: Brightness.light,
          surface: const Color(0xFFFBF9FD),
        ).copyWith(
          primary: purple,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFECDDFF),
          onPrimaryContainer: const Color(0xFF250050),
          secondary: limeDark,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFD9FFA2),
          onSecondaryContainer: const Color(0xFF132200),
          tertiary: limeDark,
          onTertiary: Colors.white,
          tertiaryContainer: const Color(0xFFE2FFB8),
          onTertiaryContainer: const Color(0xFF172600),
          surfaceContainerHighest: const Color(0xFFF1EDF5),
          outline: const Color(0xFF79717F),
          outlineVariant: const Color(0xFFCBC3D0),
        );
    return MaterialApp(
      onGenerateTitle: (context) => SecureLocalizations.of(context).appTitle,
      locale: locale,
      supportedLocales: SecureLocalizations.supportedLocales,
      localizationsDelegates: SecureLocalizations.localizationsDelegates,
      localeListResolutionCallback: _resolveSupportedLocale,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        splashFactory: InkRipple.splashFactory,
        scaffoldBackgroundColor: colorScheme.surface,
        appBarTheme: const AppBarTheme(
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF6F0FA),
          foregroundColor: purple,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: colorScheme.surface,
          indicatorColor: lime,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            return IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              color: states.contains(WidgetState.selected)
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            );
          }),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          indicatorColor: lime,
          selectedIconTheme: IconThemeData(color: purple),
          selectedLabelTextStyle: TextStyle(
            color: purple,
            fontWeight: FontWeight.w700,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: lime,
          foregroundColor: Color(0xFF172600),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: purple,
          linearTrackColor: Color(0xFFD9FFA2),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: SecureWorkspacePage(
        mediaPicker: mediaPicker ?? FileSelectorMediaPicker(),
        messageSync: messageSync,
      ),
    );
  }
}

Locale _resolveSupportedLocale(
  List<Locale>? preferredLocales,
  Iterable<Locale> supportedLocales,
) {
  for (final locale in preferredLocales ?? const <Locale>[]) {
    if (locale.languageCode == 'ko' || locale.languageCode == 'en') {
      return Locale(locale.languageCode);
    }
  }
  return const Locale('ko');
}
