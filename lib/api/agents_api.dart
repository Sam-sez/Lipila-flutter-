import 'package:dio/dio.dart';
import 'api_client.dart';
import '../models/transaction.dart';

class AgentsApi {
  final Dio _dio = ApiClient().dio;

  /// User pays agent, receives cash. Collections flow — user authorizes.
  Future<LipilaTransaction> cashOut({
    required String userId, required String agentQrToken, required double amount,
  }) async {
    final res = await _dio.post('/agents/cash-out', data: {
      'user_id': userId, 'agent_qr_token': agentQrToken, 'amount': amount,
    });
    return LipilaTransaction.fromJson(res.data);
  }

  /// Agent receives cash, pushes funds to user. Disbursements — agent authorizes.
  Future<LipilaTransaction> cashIn({
    required String agentId, required String userQrToken, required double amount,
  }) async {
    final res = await _dio.post('/agents/cash-in', data: {
      'agent_id': agentId, 'user_qr_token': userQrToken, 'amount': amount,
    });
    return LipilaTransaction.fromJson(res.data);
  }

  Future<String> disclaimer(String agentId) async {
    final res = await _dio.get('/agents/$agentId/disclaimer');
    return res.data['disclaimer'];
  }
}
