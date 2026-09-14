import 'package:dio/dio.dart';
import 'api_client.dart';
import '../models/user.dart';

class UsersApi {
  final Dio _dio = ApiClient().dio;

  Future<LipilaUser> create({
    required String mobileNumber,
    required String legalName,
    String provider = 'MTN',
    bool isAgent = false,
    String? merchantCategory,
  }) async {
    final res = await _dio.post('/users', data: {
      'mobile_number': mobileNumber,
      'legal_name': legalName,
      'provider': provider,
      'is_agent': isAgent,
      if (merchantCategory != null) 'merchant_category': merchantCategory,
    });
    return LipilaUser.fromJson(res.data);
  }

  Future<LipilaUser> get(String userId) async {
    final res = await _dio.get('/users/$userId');
    return LipilaUser.fromJson(res.data);
  }

  /// Returns null (not throw) on 404 — callers use this to decide between
  /// "log this returning user in" and "this is a new number, ask for a name".
  Future<LipilaUser?> getByNumber(String mobileNumber) async {
    try {
      final res = await _dio.get('/users/by-number/$mobileNumber');
      return LipilaUser.fromJson(res.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
