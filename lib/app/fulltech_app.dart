import 'package:flutter/material.dart';

import '../features/auth/auth_gate.dart';
import '../ui/theme/fulltech_brand.dart';

class FullTechApp extends StatelessWidget {
  const FullTechApp({super.key});

  ThemeData _buildLightTheme() {
    const colorScheme = ColorScheme.light(
      primary: FullTechBrand.corporateBlack,
      onPrimary: Colors.white,
      secondary: FullTechBrand.blackElevated,
      onSecondary: Colors.white,
      surface: FullTechBrand.backgroundWhite,
      onSurface: FullTechBrand.corporateBlack,
      error: Color(0xFFB00020),
      onError: Colors.white,
      outline: FullTechBrand.outlineSoft,
    );

    final textTheme = Typography.material2021().black.apply(
          bodyColor: FullTechBrand.corporateBlack,
          displayColor: FullTechBrand.corporateBlack,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: FullTechBrand.softGray,
      canvasColor: FullTechBrand.backgroundWhite,
      dialogTheme: const DialogThemeData(
        backgroundColor: FullTechBrand.backgroundWhite,
      ),
      dividerColor: FullTechBrand.outlineSoft,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: FullTechBrand.corporateBlack,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 1,
        scrolledUnderElevation: 2,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: FullTechBrand.lightSystemUi,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: FullTechBrand.backgroundWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: Colors.black.withAlpha(25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: FullTechBrand.outlineSoft),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: Colors.white.withAlpha(26),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) {
            final isSelected = states.contains(WidgetState.selected);
            return TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: isSelected ? Colors.white : Colors.white.withAlpha(170),
            );
          },
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) {
            final isSelected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: isSelected ? Colors.white : Colors.white.withAlpha(170),
            );
          },
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: FullTechBrand.corporateBlack,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: FullTechBrand.backgroundWhite,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: FullTechBrand.outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: FullTechBrand.outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: FullTechBrand.corporateBlack, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: FullTechBrand.corporateBlack,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: FullTechBrand.corporateBlack,
          side: const BorderSide(color: FullTechBrand.corporateBlack),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: FullTechBrand.corporateBlack,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: FullTechBrand.corporateBlack,
        textColor: FullTechBrand.corporateBlack,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FULLTECH',
      debugShowCheckedModeBanner: false,
      theme: _buildLightTheme(),
      home: const AuthGate(),
    );
  }
}
