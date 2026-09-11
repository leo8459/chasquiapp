class BitacoraDriverOption {
  const BitacoraDriverOption({required this.id, required this.name});

  final int id;
  final String name;
}

class BitacoraVehicleOption {
  const BitacoraVehicleOption({required this.id, required this.label});

  final int id;
  final String label;
}

class BitacoraOptions {
  const BitacoraOptions({required this.drivers, required this.vehicles});

  final List<BitacoraDriverOption> drivers;
  final List<BitacoraVehicleOption> vehicles;
}
