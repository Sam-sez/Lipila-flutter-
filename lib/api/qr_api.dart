import 'package:dio/dio.dart';
import 'api_client.dart';
import '../models/display_identity.dart';

class StaticQrResult {
  final String qrToken;
  final String qrPayload;
  final String qrImage; // base64 PNG data URI, ready to decode and display
  StaticQrResult({required this.qrToken, required this.qrPayload, required this.qrImage});
}

class DynamicQrResult {
  final String qrToken;
  final DisplayIdentity payee;
  final double amount;
  final int expiresInSeconds;
  DynamicQrResult({
    required this.qrToken, required this.payee, required this.amount, required this.expiresInSeconds,
  });
}

class DynamicQrResolved {
  final DisplayIdentity payee;
  final double amount;
  final String? note;
  DynamicQrResolved({required this.payee, required this.amount, this.note});
}

class QrApi {
  final Dio _dio = ApiClient().dio;

  Future<StaticQrResult> getStatic(String userId) async {
    final res = await _dio.get('/qr/static/$userId');
    return StaticQrResult(
      qrToken: res.data['qr_token'],
      qrPayload: res.data['qr_payload'],
      qrImage: res.data['qr_image'],
    );
  }

  /// Call immediately after a scan, BEFORE showing any amount field.
  Future<DisplayIdentity> resolveStatic(String qrToken) async {
    final res = await _dio.post('/qr/static/resolve', data: {'qr_token': qrToken});
    return DisplayIdentity.fromJson(res.data);
  }

  Future<DynamicQrResult> createDynamic(String payeeId, double amount, String? note) async {
    final res = await _dio.post('/qr/dynamic', data: {
      'payee_id': payeeId, 'amount': amount, if (note != null) 'note': note,
    });
    return DynamicQrResult(
      qrToken: res.data['qr_token'],
      payee: DisplayIdentity.fromJson(res.data['payee']),
      amount: (res.data['amount'] as num).toDouble(),
      expiresInSeconds: res.data['expires_in_seconds'],
    );
  }

  Future<String> getDynamicImage(String qrToken) async {
    final res = await _dio.get('/qr/dynamic/$qrToken/image');
    return res.data['qr_image'];
  }

  /// Throws DioException with statusCode 410 if expired — handle that in the UI.
  Future<DynamicQrResolved> resolveDynamic(String qrToken) async {
    final res = await _dio.post('/qr/dynamic/resolve', data: {'qr_token': qrToken});
    return DynamicQrResolved(
      payee: DisplayIdentity.fromJson(res.data['payee']),
      amount: (res.data['amount'] as num).toDouble(),
      note: res.data['note'],
    );
  }
}
