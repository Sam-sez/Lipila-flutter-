import 'package:dio/dio.dart';
import 'api_client.dart';
import '../models/display_identity.dart';

class FavoritesApi {
  final Dio _dio = ApiClient().dio;

  Future<List<DisplayIdentity>> list(String ownerId) async {
    final res = await _dio.get('/favorites/$ownerId');
    return (res.data as List).map((f) => DisplayIdentity.fromJson(f)).toList();
  }

  /// Explicit opt-in only — call after the user answers "yes" to a
  /// post-payment "Save as favorite?" prompt, never automatically.
  Future<void> add(String ownerId, String savedUserId) async {
    await _dio.post('/favorites', queryParameters: {
      'owner_id': ownerId, 'saved_user_id': savedUserId,
    });
  }

  Future<void> remove(String ownerId, String savedUserId) async {
    await _dio.delete('/favorites/$ownerId/$savedUserId');
  }
}
