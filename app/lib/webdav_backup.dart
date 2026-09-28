import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// WebDAV 云备份配置与最小客户端实现（仅依赖 dart:io + shared_preferences）。
///
/// 支持坚果云 / Nextcloud / 群晖 / Alist 等标准 WebDAV 服务：
/// - PROPFIND 列出远端备份、测试连接
/// - PUT 上传、GET 下载、DELETE 删除
class WebdavConfig {
  const WebdavConfig({
    this.server = '',
    this.username = '',
    this.password = '',
    this.remoteDir = 'zhibing',
  });

  final String server; // 如 https://dav.jianguoyun.com/dav/
  final String username;
  final String password;
  final String remoteDir; // 远端目录，如 zhibing（自动创建）

  bool get isConfigured => server.trim().isNotEmpty;

  /// 规范化后的服务根地址（去掉末尾 /）。
  String get baseUrl {
    var s = server.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// 规范化后的远端目录（去掉首尾 /）。
  String get dirName {
    var d = remoteDir.trim();
    while (d.startsWith('/')) {
      d = d.substring(1);
    }
    while (d.endsWith('/')) {
      d = d.substring(0, d.length - 1);
    }
    return d;
  }

  /// 远端目录 URL（末尾带 /）。
  String get dirUrl => dirName.isEmpty ? '$baseUrl/' : '$baseUrl/$dirName/';

  /// 远端文件 URL。
  String fileUrl(String fileName) {
    final enc = Uri.encodeComponent(fileName);
    return dirName.isEmpty ? '$baseUrl/$enc' : '$baseUrl/$dirName/$enc';
  }

  Map<String, String> get authHeader {
    if (username.isEmpty && password.isEmpty) return {};
    final token = base64Encode(utf8.encode('$username:$password'));
    return {'Authorization': 'Basic $token'};
  }

  WebdavConfig copyWith({
    String? server,
    String? username,
    String? password,
    String? remoteDir,
  }) =>
      WebdavConfig(
        server: server ?? this.server,
        username: username ?? this.username,
        password: password ?? this.password,
        remoteDir: remoteDir ?? this.remoteDir,
      );

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webdav_server', server.trim());
    await prefs.setString('webdav_username', username);
    await prefs.setString('webdav_password', password);
    await prefs.setString('webdav_remote_dir', remoteDir.trim());
  }

  static Future<WebdavConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return WebdavConfig(
      server: prefs.getString('webdav_server') ?? '',
      username: prefs.getString('webdav_username') ?? '',
      password: prefs.getString('webdav_password') ?? '',
      remoteDir: prefs.getString('webdav_remote_dir') ?? 'zhibing',
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('webdav_server');
    await prefs.remove('webdav_username');
    await prefs.remove('webdav_password');
    await prefs.remove('webdav_remote_dir');
  }
}

/// 远端备份文件条目。
class WebdavFile {
  const WebdavFile({
    required this.name,
    required this.lastModified,
    required this.size,
  });

  final String name;
  final DateTime? lastModified;
  final int size;
}

class WebdavException implements Exception {
  WebdavException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WebdavClient {
  WebdavClient(this.config);

  final WebdavConfig config;

  static const _timeout = Duration(seconds: 20);

  Map<String, String> _headers([Map<String, String>? extra]) => {
        ...config.authHeader,
        ...?extra,
      };

  Never _throwForStatus(int status, String op) {
    switch (status) {
      case 401:
        throw WebdavException('$op失败：用户名或密码错误（401）');
      case 403:
        throw WebdavException('$op失败：没有权限（403）');
      case 404:
        throw WebdavException('$op失败：远端路径不存在（404），请检查服务器地址');
      case 409:
        throw WebdavException('$op失败：父目录不存在（409）');
      default:
        throw WebdavException('$op失败：服务器返回 $status');
    }
  }

  /// 测试连接：向远端目录发 PROPFIND depth 0。
  /// 目录不存在时尝试 MKCOL 自动创建。
  Future<void> testConnection() async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      var res = await _propfind(client, config.dirUrl, depth: '0');
      if (res.statusCode == 404 && config.dirName.isNotEmpty) {
        await _mkdir(client);
        res = await _propfind(client, config.dirUrl, depth: '0');
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _throwForStatus(res.statusCode, '连接测试');
      }
      await res.drain<void>();
    } on SocketException catch (e) {
      throw WebdavException('连接测试失败：无法连接服务器（$e）');
    } on WebdavException {
      rethrow;
    } catch (e) {
      throw WebdavException('连接测试失败：$e');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _mkdir(HttpClient client) async {
    final req = await client.openUrl('MKCOL', Uri.parse(config.dirUrl));
    config.authHeader.forEach(req.headers.set);
    final res = await req.close().timeout(_timeout);
    await res.drain<void>();
    // 201 创建成功、405 已存在都算 OK，其它情况交给后续 PROPFIND 报错。
  }

  Future<HttpClientResponse> _propfind(
    HttpClient client,
    String url, {
    required String depth,
  }) async {
    final req = await client.openUrl('PROPFIND', Uri.parse(url));
    config.authHeader.forEach(req.headers.set);
    req.headers.set('Depth', depth);
    req.headers.set('Content-Type', 'application/xml; charset=utf-8');
    req.write(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<D:propfind xmlns:D="DAV:">'
      '<D:prop><D:displayname/><D:getlastmodified/>'
      '<D:getcontentlength/><D:resourcetype/></D:prop>'
      '</D:propfind>',
    );
    return req.close().timeout(_timeout);
  }

  /// 列出远端目录中的 .db 备份文件（按修改时间倒序）。
  Future<List<WebdavFile>> listBackups() async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final res = await _propfind(client, config.dirUrl, depth: '1');
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _throwForStatus(res.statusCode, '获取云端列表');
      }
      final xml = await res.transform(utf8.decoder).join().timeout(_timeout);
      return _parsePropfind(xml)..sort((a, b) {
          final at = a.lastModified?.millisecondsSinceEpoch ?? 0;
          final bt = b.lastModified?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
        });
    } on WebdavException {
      rethrow;
    } catch (e) {
      throw WebdavException('获取云端列表失败：$e');
    } finally {
      client.close(force: true);
    }
  }

  /// 解析 PROPFIND 多状态响应，只保留目录下一层的 .db 文件。
  List<WebdavFile> _parsePropfind(String xml) {
    final files = <WebdavFile>[];
    // 按 <D:response>…</D:response> 切块，避免引入 XML 解析依赖。
    final respRe = RegExp(
      r'<(?:\w+:)?response>(.*?)</(?:\w+:)?response>',
      dotAll: true,
    );
    for (final m in respRe.allMatches(xml)) {
      final block = m.group(1)!;
      final href = _tag(block, 'href');
      if (href == null || href.isEmpty) continue;
      var decoded = Uri.decodeComponent(href);
      // 去掉查询串与末尾 /。
      decoded = decoded.split('?').first;
      while (decoded.endsWith('/')) {
        decoded = decoded.substring(0, decoded.length - 1);
      }
      final name = decoded.split('/').lastWhere(
            (s) => s.isNotEmpty,
            orElse: () => '',
          );
      if (name.isEmpty || !name.toLowerCase().endsWith('.db')) continue;
      // 排除目录自身的 href（即 dirUrl 本体）。
      if (config.dirName.isNotEmpty &&
          !decoded.contains('/${config.dirName}/') &&
          !decoded.endsWith('/${config.dirName}')) {
        continue;
      }
      final isCollection = block.contains('<D:collection') ||
          block.contains('<d:collection') ||
          block.contains('<collection');
      if (isCollection) continue;
      final lastModRaw = _tag(block, 'getlastmodified');
      DateTime? lastMod;
      if (lastModRaw != null) {
        try {
          lastMod = HttpDate.parse(lastModRaw.trim());
        } catch (_) {
          lastMod = DateTime.tryParse(lastModRaw.trim());
        }
      }
      final sizeRaw = _tag(block, 'getcontentlength');
      final size = int.tryParse((sizeRaw ?? '').trim()) ?? 0;
      if (files.any((f) => f.name == name)) continue;
      files.add(WebdavFile(name: name, lastModified: lastMod, size: size));
    }
    return files;
  }

  String? _tag(String block, String localName) {
    final re = RegExp(
      '<(?:\\w+:)?$localName[^>]*>(.*?)</(?:\\w+:)?$localName>',
      dotAll: true,
    );
    return re.firstMatch(block)?.group(1);
  }

  /// 上传本地数据库文件到云端。
  Future<void> uploadBackup(String localPath, String fileName) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        throw WebdavException('上传失败：本地数据库文件不存在');
      }
      // 先确保远端目录存在（不存在则 MKCOL，失败也不中断，靠 PUT 状态报错）。
      try {
        final probe = await _propfind(client, config.dirUrl, depth: '0');
        await probe.drain<void>();
        if (probe.statusCode == 404 && config.dirName.isNotEmpty) {
          await _mkdir(client);
        }
      } catch (_) {}
      final req = await client.openUrl(
        'PUT',
        Uri.parse(config.fileUrl(fileName)),
      );
      config.authHeader.forEach(req.headers.set);
      req.headers.set('Content-Type', 'application/octet-stream');
      req.contentLength = await file.length();
      await req.addStream(file.openRead()).timeout(_timeout);
      final res = await req.close().timeout(_timeout);
      await res.drain<void>();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _throwForStatus(res.statusCode, '上传');
      }
    } on WebdavException {
      rethrow;
    } catch (e) {
      throw WebdavException('上传失败：$e');
    } finally {
      client.close(force: true);
    }
  }

  /// 从云端下载备份到 [targetPath]。
  Future<void> downloadBackup(String fileName, String targetPath) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(Uri.parse(config.fileUrl(fileName)));
      _headers().forEach(req.headers.set);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        _throwForStatus(res.statusCode, '下载');
      }
      final out = File(targetPath);
      final sink = out.openWrite();
      try {
        await res.pipe(sink).timeout(const Duration(minutes: 5));
      } finally {
        await sink.close();
      }
    } on WebdavException {
      rethrow;
    } catch (e) {
      throw WebdavException('下载失败：$e');
    } finally {
      client.close(force: true);
    }
  }

  /// 删除云端备份。
  Future<void> deleteBackup(String fileName) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.openUrl(
        'DELETE',
        Uri.parse(config.fileUrl(fileName)),
      );
      config.authHeader.forEach(req.headers.set);
      final res = await req.close().timeout(_timeout);
      await res.drain<void>();
      if (res.statusCode != 200 &&
          res.statusCode != 202 &&
          res.statusCode != 204) {
        _throwForStatus(res.statusCode, '删除');
      }
    } on WebdavException {
      rethrow;
    } catch (e) {
      throw WebdavException('删除失败：$e');
    } finally {
      client.close(force: true);
    }
  }
}
