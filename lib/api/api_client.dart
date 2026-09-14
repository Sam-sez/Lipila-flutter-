import 'package:dio/dio.dart';

/// Base URL is injected at build time so the same code works against local
/// dev, a preview deploy, or production without editing source:
///   flutter build apk --dart-define=API_BASE_URL=https://lipila.vercel.app/api
///
/// Defaults to the live production API if nothing is passed, since this is
/// a native app with no CORS/same-origin concept — there's no reason to
/// point it at localhost by default the way the web app does.
const String _defaultBaseUrl = 'https://lipila.vercel.app/api';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;

  ApiClient._internal() {
    const baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: _defaultBaseUrl);
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));
  }
}
