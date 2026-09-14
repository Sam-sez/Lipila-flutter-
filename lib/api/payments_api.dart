import 'package:dio/dio.dart';
import 'api_client.dart';
import '../models/transaction.dart';

class PaymentsApi {
  final Dio _dio = ApiClient().dio;

  Future<LipilaTransaction> confirm({
    required String payerId,
    required String payeeId,
    required double amount,
    required String method, // static_qr | dynamic_qr | bong | favorite
    String? note,
    bool saveAsFavorite = false,
  }) async {
    final res = await _dio.post('/payments/confirm', data: {
      'payer_id': payerId,
      'payee_id': payeeId,
      'amount': amount,
      'method': method,
      if (note != null) 'note': note,
      'save_as_favorite': saveAsFavorite,
    });
    return LipilaTransaction.fromJson(res.data);
  }

  Future<LipilaTransaction> status(String transactionId) async {
    final res = await _dio.get('/payments/$transactionId/status');
    return LipilaTransaction.fromJson(res.data);
  }

  /// Mock provider resolves pending -> successful/failed only when polled,
  /// not instantly. Poll a few times with a short delay after confirm.
  Future<LipilaTransaction> confirmAndPoll({
    required String payerId,
    required String payeeId,
    required double amount,
    required String method,
    String? note,
    bool saveAsFavorite = false,
  }) async {
    var txn = await confirm(
      payerId: payerId, payeeId: payeeId, amount: amount, method: method,
      note: note, saveAsFavorite: saveAsFavorite,
    );
    for (var i = 0; i < 4 && txn.status == 'pending'; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      txn = await status(txn.id);
    }
    return txn;
  }

  Future<List<LipilaTransaction>> history(String userId) async {
    final res = await _dio.get('/payments/history/$userId');
    return (res.data as List).map((t) => LipilaTransaction.fromJson(t)).toList();
  }
}
