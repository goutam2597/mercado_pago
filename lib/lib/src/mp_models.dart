class MPCheckoutResult {
  final String status; // APPROVED | PENDING | REJECTED | UNKNOWN
  final String? paymentId;
  final String? preferenceId;
  final Map<String, String> params; // raw query params
  final String? returnUri;

  const MPCheckoutResult({
    required this.status,
    this.paymentId,
    this.preferenceId,
    this.params = const {},
    this.returnUri,
  });

  bool get isApproved => status.toUpperCase() == 'APPROVED';
}
