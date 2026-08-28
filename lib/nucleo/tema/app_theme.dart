import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

/// Tema principal de la aplicacion.
///
/// Esta clase arma el `ThemeData` que usa Flutter. Los valores base salen de
/// `app_design_tokens.dart`, asi evitamos colores y tamanos sueltos en la UI.
class AppTheme {
  const AppTheme._();

  static const String fontFamily = 'Roboto';

  // Alias de compatibilidad: permiten migrar pantallas poco a poco.
  static const Color blue = AppColors.brandBlue;
  static const Color blueDark = AppColors.brandBlueDark;
  static const Color blueMid = AppColors.brandBlueMid;
  static const Color yellow = AppColors.brandYellow;
  static const Color yellowSoft = AppColors.yellowSoft;
  static const Color yellowSurface = AppColors.yellowSurface;
  static const Color yellowField = AppColors.yellowField;
  static const Color yellowLight = AppColors.yellowLight;
  static const Color orangeWarm = AppColors.orangeWarm;
  static const Color actionYellowStrong = AppColors.actionYellowStrong;
  static const Color actionSurfaceSoft = AppColors.actionSurfaceSoft;
  static const Color confirmBlue = AppColors.confirmBlue;
  static const Color confirmBlueDark = AppColors.confirmBlueDark;
  static const Color successGreen = AppColors.success;
  static const Color warningYellow = AppColors.warning;
  static const Color errorRed = AppColors.error;
  static const Color errorSoft = AppColors.errorSoft;
  static const Color softBorder = AppColors.borderSoft;
  static const Color lightBorder = AppColors.borderLight;
  static const Color strongBorder = AppColors.borderStrong;
  static const Color dialogBarrier = AppColors.dialogBarrier;
  static const Color strongShadow = AppColors.shadowStrong;
  static const Color softShadow = AppColors.shadowSoft;
  static const Color overlayBorder = AppColors.overlayBorder;

  static const double borderWidth = AppBorders.width;
  static const BorderRadius radiusSmall = AppRadii.small;
  static const BorderRadius radiusMedium = AppRadii.medium;
  static const BorderRadius radiusLarge = AppRadii.large;
  static const BorderRadius radiusXLarge = AppRadii.xLarge;
  static const BorderRadius radiusPill = AppRadii.pill;

  static const EdgeInsets pagePadding = AppSpacing.page;
  static const EdgeInsets pageCompactPadding = AppSpacing.pageCompact;
  static const EdgeInsets panelPadding = AppSpacing.panel;
  static const EdgeInsets sectionPadding = AppSpacing.section;
  static const double maxPageBodyWidth = AppLayout.maxPageBodyWidth;

  static const LinearGradient pageGradient = AppGradients.page;
  static const LinearGradient warmPageGradient = AppGradients.warmPage;
  static const LinearGradient drawerGradient = AppGradients.drawer;
  static const LinearGradient actionGradient = AppGradients.action;
  static const LinearGradient loginGradient = AppGradients.login;
  static const BoxDecoration pageDecoration = BoxDecoration(
    gradient: pageGradient,
  );
  static const BoxDecoration warmPageDecoration = BoxDecoration(
    gradient: warmPageGradient,
  );
  static const BoxDecoration loginPageDecoration = BoxDecoration(
    color: yellow,
    gradient: loginGradient,
  );

  static BoxDecoration buildPanelDecoration({
    Color backgroundColor = yellowSoft,
    BorderRadius borderRadius = radiusXLarge,
    Color borderColor = softBorder,
    List<BoxShadow>? boxShadow,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: borderRadius,
      border: Border.all(color: borderColor, width: borderWidth),
      boxShadow: boxShadow ?? AppShadows.panel,
    );
  }

  static BoxDecoration buildSoftCardDecoration({
    Color backgroundColor = yellowSurface,
    BorderRadius borderRadius = radiusMedium,
    Color borderColor = lightBorder,
    List<BoxShadow> boxShadow = const [],
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: borderRadius,
      border: Border.all(color: borderColor, width: borderWidth),
      boxShadow: boxShadow,
    );
  }

  static BoxDecoration buildDialogDecoration({
    Color backgroundColor = yellowField,
    BorderRadius borderRadius = radiusLarge,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: borderRadius,
      border: Border.all(color: blue, width: borderWidth),
    );
  }

  static BoxDecoration buildActionDecoration({
    BorderRadius borderRadius = radiusLarge,
    Color borderColor = softBorder,
    List<BoxShadow>? boxShadow,
  }) {
    return BoxDecoration(
      gradient: actionGradient,
      borderRadius: borderRadius,
      border: Border.all(color: borderColor, width: borderWidth),
      boxShadow: boxShadow ?? AppShadows.action,
    );
  }

  static TextTheme _buildTextTheme() {
    final base = Typography.material2021().black.apply(
      fontFamily: fontFamily,
      bodyColor: blue,
      displayColor: blue,
    );

    return base.copyWith(
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: AppFontWeights.black,
        fontSize: AppTextSizes.display,
        height: 1.05,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: AppFontWeights.black,
        fontSize: AppTextSizes.titleLarge,
        height: 1.1,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: AppFontWeights.extraBold,
        fontSize: AppTextSizes.titleMedium,
        height: 1.15,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: AppFontWeights.extraBold,
        fontSize: AppTextSizes.titleSmall,
        height: 1.2,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontWeight: AppFontWeights.semiBold,
        fontSize: AppTextSizes.bodyLarge,
        height: 1.3,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontWeight: AppFontWeights.semiBold,
        fontSize: AppTextSizes.bodyMedium,
        height: 1.3,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontWeight: AppFontWeights.semiBold,
        fontSize: AppTextSizes.bodySmall,
        height: 1.25,
        color: blueMid,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: AppFontWeights.extraBold,
        fontSize: AppTextSizes.labelLarge,
        height: 1.1,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: AppFontWeights.extraBold,
        fontSize: AppTextSizes.labelMedium,
        height: 1.1,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontWeight: AppFontWeights.bold,
        fontSize: AppTextSizes.labelSmall,
        height: 1.1,
      ),
    );
  }

  static ThemeData buildTheme() {
    final textTheme = _buildTextTheme();
    // ColorScheme alimenta los widgets Material que no reciben colores propios.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: yellow,
      primary: blue,
      secondary: yellow,
      surface: yellowSurface,
      error: errorRed,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      colorScheme: colorScheme,
      scaffoldBackgroundColor: yellow,
      appBarTheme: AppBarTheme(
        backgroundColor: yellow,
        foregroundColor: blue,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: blue),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: blue,
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      bannerTheme: const MaterialBannerThemeData(
        backgroundColor: blue,
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: yellowField,
        hintStyle: textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
        prefixIconColor: yellow,
        contentPadding: AppSpacing.input,
        border: OutlineInputBorder(
          borderRadius: radiusMedium,
          borderSide: const BorderSide(color: blue, width: borderWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusMedium,
          borderSide: const BorderSide(color: blue, width: borderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMedium,
          borderSide: const BorderSide(color: blue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusMedium,
          borderSide: const BorderSide(color: errorRed, width: borderWidth),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radiusMedium,
          borderSide: const BorderSide(color: errorRed, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: yellowField,
          minimumSize: const Size.fromHeight(AppLayout.buttonHeight),
          shape: RoundedRectangleBorder(borderRadius: radiusMedium),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: radiusMedium),
          textStyle: textTheme.labelMedium,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: blue,
          backgroundColor: yellowField,
          side: const BorderSide(color: blue, width: borderWidth),
          shape: RoundedRectangleBorder(borderRadius: radiusMedium),
          textStyle: textTheme.labelMedium,
          padding: AppSpacing.button,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blue,
        foregroundColor: Colors.white,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: yellowField,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLarge,
          side: const BorderSide(color: blue, width: borderWidth),
        ),
      ),
    );
  }
}
