import 'package:flutter/material.dart';

/// Tokens visuales del sistema ScanAGBC.
///
/// La idea es que colores, tamanos y espaciados vivan aqui y no queden
/// repartidos por las pantallas. Asi la identidad visual se cambia desde un
/// solo lugar y la app mantiene consistencia.
class AppColors {
  const AppColors._();

  static const Color brandBlue = Color(0xFF1B305F);
  static const Color brandBlueDark = Color(0xFF142A54);
  static const Color brandBlueMid = Color(0xFF2B4C88);

  static const Color brandYellow = Color(0xFFF5BD28);
  static const Color yellowSoft = Color(0xFFFBE19A);
  static const Color yellowSurface = Color(0xFFFFF7E7);
  static const Color yellowField = Color(0xFFFFF1CF);
  static const Color yellowLight = Color(0xFFFFF8E8);
  static const Color orangeWarm = Color(0xFFF8CF6A);

  static const Color actionYellowStrong = Color(0xFFFFCD45);
  static const Color actionSurfaceSoft = Color(0xFFFFF5DA);
  static const Color confirmBlue = Color(0xFF2B6FC4);
  static const Color confirmBlueDark = Color(0xFF235DA5);

  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFFFEA00);
  static const Color error = Color(0xFFDC2626);
  static const Color errorSoft = Color(0xFFFFE4E6);

  static const Color textPrimary = brandBlue;
  static const Color textSecondary = brandBlueMid;
  static const Color textMuted = Color(0xFF6B7280);
  static const Color onDark = Colors.white;

  static const Color borderSoft = Color(0x661B305F);
  static const Color borderLight = Color(0x401B305F);
  static const Color borderStrong = Color(0xB3142A54);
  static const Color overlayBorder = Color(0xCCFDECC0);

  static const Color dialogBarrier = Color(0x551B305F);
  static const Color shadowStrong = Color(0x3D1B305F);
  static const Color shadowSoft = Color(0x281B305F);
  static const Color shadowPanel = Color(0x140F1E3D);
  static const Color shadowAction = Color(0x331B305F);
}

class AppTextSizes {
  const AppTextSizes._();

  static const double display = 30;
  static const double titleLarge = 24;
  static const double titleMedium = 18;
  static const double titleSmall = 16;
  static const double bodyLarge = 16;
  static const double bodyMedium = 14;
  static const double bodySmall = 12;
  static const double labelLarge = 16;
  static const double labelMedium = 14;
  static const double labelSmall = 12;
}

class AppFontWeights {
  const AppFontWeights._();

  static const FontWeight black = FontWeight.w900;
  static const FontWeight extraBold = FontWeight.w800;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight semiBold = FontWeight.w600;
}

class AppSpacing {
  const AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 28;

  static const EdgeInsets page = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: xl,
  );
  static const EdgeInsets pageCompact = EdgeInsets.fromLTRB(lg, sm, lg, xl);
  static const EdgeInsets panel = EdgeInsets.all(lg);
  static const EdgeInsets section = EdgeInsets.all(md);
  static const EdgeInsets input = EdgeInsets.symmetric(
    horizontal: md,
    vertical: md,
  );
  static const EdgeInsets button = EdgeInsets.symmetric(
    horizontal: bodyHorizontal,
    vertical: bodyVertical,
  );

  static const double bodyHorizontal = 14;
  static const double bodyVertical = 14;
}

class AppRadii {
  const AppRadii._();

  static const BorderRadius small = BorderRadius.all(Radius.circular(12));
  static const BorderRadius medium = BorderRadius.all(Radius.circular(18));
  static const BorderRadius large = BorderRadius.all(Radius.circular(24));
  static const BorderRadius xLarge = BorderRadius.all(Radius.circular(28));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

class AppBorders {
  const AppBorders._();

  static const double width = 1.2;
}

class AppLayout {
  const AppLayout._();

  static const double maxPageBodyWidth = 1120;
  static const double buttonHeight = 56;
}

class AppGradients {
  const AppGradients._();

  static const LinearGradient page = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.yellowLight, AppColors.brandYellow],
  );

  static const LinearGradient warmPage = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.yellowLight, AppColors.orangeWarm],
  );

  static const LinearGradient drawer = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.yellowLight, Color(0xFFF3DEAA)],
  );

  static const LinearGradient action = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.brandBlue, AppColors.brandBlueMid],
  );

  static const LinearGradient login = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.yellowLight,
      AppColors.orangeWarm,
      AppColors.brandYellow,
    ],
    stops: [0, 0.5, 1],
  );
}

class AppShadows {
  const AppShadows._();

  static const List<BoxShadow> panel = [
    BoxShadow(
      color: AppColors.shadowPanel,
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ];

  static const List<BoxShadow> action = [
    BoxShadow(
      color: AppColors.shadowAction,
      blurRadius: 12,
      offset: Offset(0, 6),
    ),
  ];
}
