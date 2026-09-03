import 'package:chat_media/chat_media.dart';
import 'package:chat_media_picker/chat_media_picker.dart';
import 'package:flutter/material.dart';
import 'package:homeserver_client/homeserver_client.dart';

import '../features/home/everyday_home_page.dart';
import '../l10n/everyday_localizations.dart';

class EverydayChatApp extends StatelessWidget {
  const EverydayChatApp({
    this.mediaPicker,
    this.messageSync,
    this.locale,
    super.key,
  });

  /// Override for tests and embedders. Production uses the native file picker.
  final MediaPickerPort? mediaPicker;

  /// Explicit production/test bridge to the encrypted durable outbox.
  /// When absent, the UI labels new messages as local-only.
  final HomeserverMessageSync? messageSync;

  /// Optional override for tests, previews, and embedders. Production follows
  /// Korean or English system preferences and falls back to Korean.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    const lime = Color(0xFFB8F05A);
    const limeDark = Color(0xFF456800);
    const purple = Color(0xFF6D3DB4);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: limeDark,
          brightness: Brightness.light,
          surface: const Color(0xFFFAFCF7),
        ).copyWith(
          primary: limeDark,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFD9FFA2),
          onPrimaryContainer: const Color(0xFF132200),
          secondary: purple,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFEBDDFF),
          onSecondaryContainer: const Color(0xFF260052),
          tertiary: const Color(0xFF5A358F),
          onTertiary: Colors.white,
          tertiaryContainer: const Color(0xFFEADDFF),
          onTertiaryContainer: const Color(0xFF241040),
          surfaceContainerHighest: const Color(0xFFF0F4EA),
          outline: const Color(0xFF72796A),
          outlineVariant: const Color(0xFFC3C9B9),
        );

    return MaterialApp(
      onGenerateTitle: (context) => EverydayLocalizations.of(context).appTitle,
      locale: locale,
      supportedLocales: EverydayLocalizations.supportedLocales,
      localizationsDelegates: EverydayLocalizations.localizationsDelegates,
      localeListResolutionCallback: _resolveSupportedLocale,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        splashFactory: InkRipple.splashFactory,
        scaffoldBackgroundColor: colorScheme.surface,
        visualDensity: VisualDensity.standard,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF4FAEA),
          foregroundColor: purple,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: colorScheme.surface,
          indicatorColor: colorScheme.secondaryContainer,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            return IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? colorScheme.secondary
                  : colorScheme.onSurfaceVariant,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              color: states.contains(WidgetState.selected)
                  ? colorScheme.secondary
                  : colorScheme.onSurfaceVariant,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            );
          }),
        ),
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: colorScheme.surface,
          indicatorColor: lime,
          selectedIconTheme: const IconThemeData(color: purple),
          selectedLabelTextStyle: const TextStyle(
            color: purple,
            fontWeight: FontWeight.w700,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: purple,
          foregroundColor: Colors.white,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: purple,
          linearTrackColor: Color(0xFFD9FFA2),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: EverydayHomePage(
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
