import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullTechBrand {
  const FullTechBrand._();

  static const corporateBlack = Color(0xFF0E0E0E);
  static const blackDeep = Color(0xFF000000);
  static const blackElevated = Color(0xFF1B1B1B);

  static const backgroundWhite = Color(0xFFFFFFFF);
  static const softGray = Color(0xFFF6F7F9);
  static const outlineSoft = Color(0x1F0E0E0E);

  /// Global black gradient used for headers/app bars.
  static const LinearGradient blackGradient = LinearGradient(
    colors: [blackDeep, corporateBlack, blackElevated],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Used behind the bottom navigation.
  static const LinearGradient navGradient = LinearGradient(
    colors: [corporateBlack, blackDeep],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const SystemUiOverlayStyle lightSystemUi = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );
}

class FullTechAppBarBackground extends StatelessWidget {
  const FullTechAppBarBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: FullTechBrand.blackGradient),
    );
  }
}
