import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../../models/category.dart';
import '../../models/category_update.dart';

/// 호출이 실패한 이유. 메시지에는 요청·응답 본문(OCR 원문 포함 가능)을 담지 않는다.
enum ApiFailure {
  /// 서버에 닿지 못했다(네트워크 없음, 서버 꺼짐, 시간 초과).
  offline,

  /// 서버가 오류 응답을 줬다(5xx 등).
  server,

  /// 요청이 거절됐다(4xx). 앱 버그이거나 기기 등록이 사라진 경우.
  rejected,
}

class ApiException implements Exception {
  const ApiException(this.failure, [this.statusCode]);

  final ApiFailure failure;
  final int? statusCode;

  @override
  String toString() => 'ApiException(${failure.name}, $statusCode)';
}

/// GET /api/config. 기준값·상한은 서버 설정이 정하고 앱은 받아서 쓴다.
class ApiConfig {
  const ApiConfig({
    required this.imageThresholdChars,
    required this.maxBatchSize,
    required this.imageMaxBytes,
    required this.imageMaxLongSide,
    required this.maxRequestBytes,
    this.classifyIntervalMs = 0,
  });

  final int imageThresholdChars;
  final int maxBatchSize;
  final int imageMaxBytes;
  final int imageMaxLongSide;
  final int maxRequestBytes;

  /// 서버가 캡처 한 장을 분류하는 데 드는 최소 간격(ms). 남은 시간을 처음부터 예상하는 데 쓴다. 옛 서버에는 없어 0.
  final int classifyIntervalMs;

  factory ApiConfig.fromJson(Map<String, dynamic> j) => ApiConfig(
    imageThresholdChars: (j['imageThresholdChars'] as num).toInt(),
    maxBatchSize: (j['maxBatchSize'] as num).toInt(),
    imageMaxBytes: (j['imageMaxBytes'] as num).toInt(),
    imageMaxLongSide: (j['imageMaxLongSide'] as num).toInt(),
    maxRequestBytes: (j['maxRequestBytes'] as num).toInt(),
    classifyIntervalMs: (j['classifyIntervalMs'] as num?)?.toInt() ?? 0,
  );
}

/// analyze로 보내는 한 장. **파일명·앱 이름 필드가 없다** — asset id, 촬영 시각, 텍스트(+이미지)뿐이다.
class AnalyzeItem {
  const AnalyzeItem({
    required this.assetId,
    required this.takenAt,
    required this.text,
    this.image,
  });

  final String assetId;
  final DateTime takenAt;
  final String text;
  final Uint8List? image;
}

class AnalyzedShot {
  const AnalyzedShot(this.assetId, this.category);

  final String assetId;
  final Category category;
}

/// 서버의 `failed.reason`. 모르는 값은 [other].
enum FailReason {
  imageTooLarge('IMAGE_TOO_LARGE'),
  imageInvalid('IMAGE_INVALID'),
  llmCallFailed('LLM_CALL_FAILED'),
  llmInvalidResponse('LLM_INVALID_RESPONSE'),
  other('');

  const FailReason(this.code);
  final String code;

  static FailReason parse(String code) =>
      values.firstWhere((r) => r.code == code, orElse: () => other);
}

class AnalyzeFailure {
  const AnalyzeFailure(this.assetId, this.reason);

  final String assetId;
  final FailReason reason;
}

class AnalyzeResult {
  const AnalyzeResult({
    required this.analyzed,
    required this.skipped,
    required this.failed,
  });

  final List<AnalyzedShot> analyzed;
  final List<String> skipped;
  final List<AnalyzeFailure> failed;
}

/// 서버 REST 호출. [http.Client]를 주입받아 테스트에서 가짜로 바꾼다.
/// 예외에 요청·응답 내용을 싣지 않는다. 로그는 [log]가 있을 때(디버그 빌드)만, 요청마다 한 줄
/// `메서드 경로 → 결과 시간`뿐이다. 쿼리(태그 이름이 들어감)·헤더(기기 id)·본문(OCR·토큰)은 찍지 않는다.
class RemineApi {
  RemineApi(
    this.baseUrl,
    this._client, {
    this.timeout = const Duration(minutes: 2), // 장당 LLM 호출이 있어 20장 배치는 오래 걸린다
    this.log,
  });

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// 디버그 빌드에서만 넘긴다(main.dart). 릴리스는 null이라 아무것도 남지 않는다.
  final void Function(String line)? log;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Map<String, String> _headers(int? deviceId) => {
    if (deviceId != null) 'X-Device-Id': '$deviceId',
  };

  /// 요청을 보내고 2xx 본문을 돌려준다. 실패는 [ApiException]으로만 나온다.
  Future<Map<String, dynamic>> _send(http.BaseRequest request) async {
    final watch = Stopwatch()..start();
    void note(Object result) => log?.call(
      '[api] ${request.method} ${request.url.path} → $result '
      '${watch.elapsedMilliseconds}ms',
    );
    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      note('timeout');
      throw const ApiException(ApiFailure.offline);
    } on SocketException {
      note('socket');
      throw const ApiException(ApiFailure.offline);
    } on http.ClientException {
      note('client');
      throw const ApiException(ApiFailure.offline);
    } on HandshakeException {
      note('tls');
      throw const ApiException(ApiFailure.offline);
    }
    final code = response.statusCode;
    if (code >= 500) {
      note(code);
      throw ApiException(ApiFailure.server, code);
    }
    if (code < 200 || code >= 300) {
      note(code);
      throw ApiException(ApiFailure.rejected, code);
    }
    if (response.bodyBytes.isEmpty) {
      note(code);
      return const {}; // 204 No Content
    }
    try {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      note(code);
      return json;
    } on FormatException {
      note('$code bad-json');
      throw ApiException(ApiFailure.server, code);
    } on TypeError {
      note('$code bad-json');
      throw ApiException(ApiFailure.server, code);
    }
  }

  Future<Map<String, dynamic>> _getJson(
    String path,
    int? deviceId, [
    Map<String, String>? query,
  ]) {
    final request = http.Request('GET', _uri(path, query));
    request.headers.addAll(_headers(deviceId));
    return _send(request);
  }

  /// POST /api/devices → 기기 id. 토큰을 못 받았으면 null로 등록한다(푸시만 안 간다).
  Future<int> registerDevice(String? fcmToken) async {
    final request = http.Request('POST', _uri('/api/devices'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'fcmToken': fcmToken});
    final json = await _send(request);
    return (json['deviceId'] as num).toInt();
  }

  /// PUT /api/devices/me/fcm-token. 앱 시작 때·FCM이 토큰을 바꿀 때.
  Future<void> updateFcmToken(int deviceId, String fcmToken) async {
    final request = http.Request('PUT', _uri('/api/devices/me/fcm-token'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'fcmToken': fcmToken});
    request.headers.addAll(_headers(deviceId));
    await _send(request);
  }

  /// DELETE /api/devices/me/fcm-token. 사용자가 알림을 끄면 서버가 이 기기에 보내지 않게 한다.
  Future<void> deleteFcmToken(int deviceId) async {
    final request = http.Request('DELETE', _uri('/api/devices/me/fcm-token'));
    request.headers.addAll(_headers(deviceId));
    await _send(request);
  }

  /// [개발용] POST /api/dev/push-test. 서버가 dev 프로필일 때만 있고, 아니면 404.
  Future<void> sendTestPush(int deviceId) async {
    final request = http.Request('POST', _uri('/api/dev/push-test'));
    request.headers.addAll(_headers(deviceId));
    await _send(request);
  }

  Future<ApiConfig> config() async =>
      ApiConfig.fromJson(await _getJson('/api/config', null));

  /// POST /api/screenshots/analyze. 이미지가 하나라도 있으면 multipart, 없으면 JSON.
  Future<AnalyzeResult> analyze(int deviceId, List<AnalyzeItem> items) async {
    final body = jsonEncode({
      'screenshots': [
        for (final i in items)
          {
            'localAssetId': i.assetId,
            'takenAt': _localDateTime(i.takenAt),
            'ocrText': i.text,
          },
      ],
    });
    final http.BaseRequest request;
    if (items.any((i) => i.image != null)) {
      request = http.MultipartRequest('POST', _uri('/api/screenshots/analyze'))
        ..files.add(
          http.MultipartFile.fromString(
            'request',
            body,
            contentType: MediaType('application', 'json'),
          ),
        )
        ..files.addAll([
          for (final i in items)
            if (i.image != null)
              http.MultipartFile.fromBytes(
                'image.${i.assetId}',
                i.image!,
                filename: 'image.jpg', // 원본 파일명이 아니라 고정 이름
                contentType: MediaType('image', 'jpeg'),
              ),
        ]);
    } else {
      request = http.Request('POST', _uri('/api/screenshots/analyze'))
        ..headers['Content-Type'] = 'application/json'
        ..body = body;
    }
    request.headers.addAll(_headers(deviceId));
    final json = await _send(request);
    return AnalyzeResult(
      analyzed: [
        for (final a in json['analyzed'] as List)
          AnalyzedShot(
            (a as Map<String, dynamic>)['localAssetId'] as String,
            Category.fromJson(a['category'] as String),
          ),
      ],
      skipped: (json['skipped'] as List).cast<String>(),
      failed: [
        for (final f in json['failed'] as List)
          AnalyzeFailure(
            (f as Map<String, dynamic>)['localAssetId'] as String,
            FailReason.parse(f['reason'] as String),
          ),
      ],
    );
  }

  /// 응답 JSON을 그대로 돌려준다(로컬 캐시에 저장하려고). 해석은 호출한 쪽이 한다.
  Future<Map<String, dynamic>> listJson(
    int deviceId, {
    Category? category,
    String? tag,
    int page = 0,
    int size = 30,
  }) => _getJson('/api/screenshots', deviceId, {
    if (category != null) 'category': category.code,
    if (tag != null && tag.isNotEmpty) 'tag': tag,
    'page': '$page',
    'size': '$size',
  });

  Future<Map<String, dynamic>> summaryJson(int deviceId) =>
      _getJson('/api/categories/summary', deviceId);

  Future<Map<String, dynamic>> interestsJson(int deviceId) =>
      _getJson('/api/interests', deviceId);

  Future<CategoryUpdate> updateCategory(
    int deviceId,
    int id,
    Category category,
  ) async {
    final request = http.Request('PATCH', _uri('/api/screenshots/$id/category'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'category': category.code});
    request.headers.addAll(_headers(deviceId));
    return CategoryUpdate.fromJson(await _send(request));
  }

  void close() => _client.close();
}

/// 서버의 LocalDateTime 형식(시간대 없음, 초 단위).
String _localDateTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = t.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)}'
      'T${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}
