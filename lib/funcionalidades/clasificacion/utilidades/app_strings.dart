class AppStrings {
  const AppStrings._();

  static const String labelBarcode = 'Código de barras';
  static const String labelNombre = 'Nombre';
  static const String labelTelefono = 'Teléfono';
  static const String labelCiudad = 'Ciudad';
  static const String labelTipo = 'Tipo';
  static const String labelAduana = 'Aduana';
  static const String labelVentanilla = 'Ventanilla';
  static const String labelPesoManual = 'Peso (manual)';

  static const String hintSelectVentanilla = 'SELECCIONA VENTANILLA';

  static const String errorSelectVentanilla = 'Selecciona una ventanilla.';
  static const String errorBarcodeRequired =
      'El código de barras es obligatorio.';
  static const String errorBarcodeInvalid =
      'Código de barra incorrecto. Debe comenzar con R, U o L.';
  static const String errorNombreRequired = 'El nombre es obligatorio.';
  static const String errorTelefonoRequired = 'El teléfono es obligatorio.';
  static const String errorTelefonoInvalid =
      'El teléfono debe tener entre 7 y 15 dígitos.';
  static const String errorPesoRequired = 'El peso es obligatorio.';
  static const String errorPesoNumeric = 'El peso debe ser numérico.';
}
