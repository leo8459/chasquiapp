class ContractPackagePickupResult {
  const ContractPackagePickupResult({
    required this.pickedUpCount,
    required this.codes,
    required this.unprocessedCodes,
    required this.message,
  });

  final int pickedUpCount;
  final List<String> codes;
  final List<String> unprocessedCodes;
  final String message;
}
