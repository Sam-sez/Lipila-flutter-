class LipilaTransaction {
  final String id;
  final String payerId;
  final String payeeId;
  final double amount;
  final String currency;
  final String method;
  final String? note;
  final String? autoTag;
  final String status;
  final String? providerReference;

  LipilaTransaction({
    required this.id,
    required this.payerId,
    required this.payeeId,
    required this.amount,
    required this.currency,
    required this.method,
    this.note,
    this.autoTag,
    required this.status,
    this.providerReference,
  });

  factory LipilaTransaction.fromJson(Map<String, dynamic> json) => LipilaTransaction(
        id: json['id'],
        payerId: json['payer_id'],
        payeeId: json['payee_id'],
        amount: (json['amount'] as num).toDouble(),
        currency: json['currency'] ?? 'ZMW',
        method: json['method'],
        note: json['note'],
        autoTag: json['auto_tag'],
        status: json['status'],
        providerReference: json['provider_reference'],
      );
}
