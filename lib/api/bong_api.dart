import 'package:dio/dio.dart';
import 'api_client.dart';
import '../models/display_identity.dart';

class BongCandidate {
  final String sessionToken;
  final int estimatedDistanceRank;
  BongCandidate({required this.sessionToken, required this.estimatedDistanceRank});
}

class BongApi {
  final Dio _dio = ApiClient().dio;

  Future<void> announce(String userId, String sessionToken) async {
    await _dio.post('/bong/announce', data: {
      'user_id': userId, 'session_token': sessionToken,
    });
  }

  /// [detected] is the list of {session_token, rssi} pairs picked up by the
  /// real BLE scan (see BongBleService). Returns a RANKED but still
  /// ANONYMOUS list — no identity here yet, by design.
  Future<List<BongCandidate>> candidates(List<Map<String, dynamic>> detected) async {
    final res = await _dio.post('/bong/candidates', data: detected);
    final list = res.data['candidates'] as List;
    return list
        .map((c) => BongCandidate(
              sessionToken: c['session_token'],
              estimatedDistanceRank: c['estimated_distance_rank'],
            ))
        .toList();
  }

  /// The one moment identity crosses from anonymous to revealed — call
  /// only after the user has visually picked a specific candidate.
  Future<DisplayIdentity> reveal(String sessionToken) async {
    final res = await _dio.post('/bong/reveal/$sessionToken');
    return DisplayIdentity.fromJson(res.data);
  }
}
