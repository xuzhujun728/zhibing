import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'db.dart';
import 'webdav_backup.dart';

class _LocalBackup {
  final String name;
  final int lastModified;
  _LocalBackup(this.name, this.lastModified);
}

/// 数据备份和还原：将病案数据库备份到 Download/zhibing/（Android）
/// 或工作目录 zhibing/（桌面端），并支持从备份还原、删除备份，
/// 以及 WebDAV 云备份（坚果云 / Nextcloud / 群晖 / Alist）。
class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  static const _channel = MethodChannel('zhibing/native');

  String _status = '';
  Color _statusColor = Colors.grey;
  bool _busy = false;

  // ─── WebDAV 云备份 ───
  WebdavConfig _webdav = const WebdavConfig();
  final TextEditingController _serverCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _dirCtrl = TextEditingController();
  bool _passObscure = true;
  bool _webdavBusy = false;
  bool _webdavExpanded = false;
  String _webdavStatus = '';
  Color _webdavStatusColor = Colors.grey;
  List<WebdavFile> _cloudFiles = [];
  String? _lastTestOkAt;

  @override
  void initState() {
    super.initState();
    _loadWebdav();
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _dirCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWebdav() async {
    final cfg = await WebdavConfig.load();
    if (!mounted) return;
    setState(() {
      _webdav = cfg;
      _serverCtrl.text = cfg.server;
      _userCtrl.text = cfg.username;
      _passCtrl.text = cfg.password;
      _dirCtrl.text = cfg.remoteDir;
      _webdavExpanded = cfg.isConfigured;
    });
  }

  WebdavConfig _editedWebdav() => _webdav.copyWith(
        server: _serverCtrl.text,
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
        remoteDir: _dirCtrl.text.isEmpty ? 'zhibing' : _dirCtrl.text,
      );

  void _setWebdavStatus(String msg, Color color) {
    if (!mounted) return;
    setState(() {
      _webdavStatus = msg;
      _webdavStatusColor = color;
    });
  }

  Future<void> _saveAndTestWebdav() async {
    if (_webdavBusy) return;
    final cfg = _editedWebdav();
    if (cfg.server.trim().isEmpty) {
      _setWebdavStatus('请先填写服务器地址', Colors.orange);
      return;
    }
    setState(() => _webdavBusy = true);
    try {
      await cfg.save();
      await WebdavClient(cfg).testConnection();
      _webdav = cfg;
      _lastTestOkAt = _formatDate(_beijingNow());
      _setWebdavStatus('连接成功（$_lastTestOkAt），配置已保存', Colors.green);
      await _refreshCloudFiles(showStatus: false);
      if (_webdavStatus.isEmpty || _webdavStatusColor == Colors.green) {
        _setWebdavStatus(
          '连接成功（${_lastTestOkAt ?? ''}），配置已保存；云端共 ${_cloudFiles.length} 个备份',
          Colors.green,
        );
      }
    } catch (e) {
      _setWebdavStatus('$e', Colors.red);
    } finally {
      if (mounted) setState(() => _webdavBusy = false);
    }
  }

  Future<void> _refreshCloudFiles({bool showStatus = true}) async {
    final cfg = _editedWebdav();
    if (cfg.server.trim().isEmpty) {
      if (showStatus) _setWebdavStatus('请先填写服务器地址并保存', Colors.orange);
      return;
    }
    setState(() => _webdavBusy = true);
    try {
      final files = await WebdavClient(cfg).listBackups();
      if (!mounted) return;
      setState(() => _cloudFiles = files);
      if (showStatus) {
        _setWebdavStatus(
          files.isEmpty ? '云端暂无备份文件' : '云端共 ${files.length} 个备份',
          Colors.green,
        );
      }
    } catch (e) {
      _setWebdavStatus('$e', Colors.red);
    } finally {
      if (mounted) setState(() => _webdavBusy = false);
    }
  }

  /// 云备份：先关闭数据库，再把 .db 文件 PUT 到 WebDAV。
  Future<void> _uploadToCloud() async {
    if (_busy || _webdavBusy) return;
    final cfg = _editedWebdav();
    if (cfg.server.trim().isEmpty) {
      _setWebdavStatus('请先填写服务器地址并保存', Colors.orange);
      return;
    }
    setState(() {
      _busy = true;
      _webdavBusy = true;
    });
    try {
      final dbPath = await RecordDb.databasePath();
      if (!await File(dbPath).exists()) {
        _setWebdavStatus('数据库文件不存在（还没有保存过病案）', Colors.orange);
        return;
      }
      await WebdavClient(cfg).testConnection().catchError((_) {});
      final fileName = _backupFileName(_beijingNow());
      await RecordDb.close();
      // 用缓存目录做中转，避免备份期间占用数据库文件。
      final tmpDir = Directory.systemTemp;
      final tmpPath = '${tmpDir.path}${Platform.pathSeparator}$fileName';
      await File(dbPath).copy(tmpPath);
      try {
        await WebdavClient(cfg).uploadBackup(tmpPath, fileName);
      } finally {
        try {
          await File(tmpPath).delete();
        } catch (_) {}
      }
      await cfg.save();
      _webdav = cfg;
      _setWebdavStatus('云备份成功：$fileName', Colors.green);
      await _refreshCloudFiles(showStatus: false);
    } catch (e) {
      _setWebdavStatus('$e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _webdavBusy = false;
        });
      }
    }
  }

  /// 云备份方式二：从本地备份文件夹选择一个 .db 文件上传到 WebDAV。
  Future<void> _uploadLocalFileToCloud() async {
    if (_busy || _webdavBusy) return;
    final cfg = _editedWebdav();
    if (cfg.server.trim().isEmpty) {
      _setWebdavStatus('请先填写服务器地址并保存', Colors.orange);
      return;
    }
    try {
      final backups = await _listBackups();
      if (!mounted) return;

      final selected = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择本地备份上传'),
          children: [
            if (backups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text('备份目录中没有备份文件，可先创建备份或点“浏览...”选择文件'),
              )
            else
              ...backups.map(
                (b) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, b.name),
                  child: Text(
                    '${b.name}  (${_formatDate(DateTime.fromMillisecondsSinceEpoch(b.lastModified))})',
                  ),
                ),
              ),
            if (_isAndroid) const Divider(),
            if (_isAndroid)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, '__BROWSE__'),
                child: const Text('浏览...（从本地文件夹选择）'),
              ),
          ],
        ),
      );
      if (selected == null) return;

      String? localPath;
      String uploadName;
      if (selected == '__BROWSE__') {
        localPath = await _pickBackupFile();
        if (localPath == null) return;
        uploadName = localPath.split(Platform.pathSeparator).last;
        if (uploadName.isEmpty) uploadName = _backupFileName(_beijingNow());
        if (!uploadName.toLowerCase().endsWith('.db')) {
          uploadName = '$uploadName.db';
        }
      } else {
        final backup = backups.firstWhere((x) => x.name == selected);
        localPath = await _readBackupToCache(backup);
        if (localPath == null) return;
        uploadName = backup.name;
      }

      final srcFile = File(localPath);
      if (!await srcFile.exists()) {
        _setWebdavStatus('上传失败：所选文件不存在', Colors.red);
        return;
      }
      final validation = await RecordDb.validateDatabaseFile(localPath);
      if (validation != null) {
        _setWebdavStatus('所选文件无效：$validation', Colors.red);
        return;
      }

      setState(() {
        _busy = true;
        _webdavBusy = true;
      });
      try {
        await WebdavClient(cfg).testConnection().catchError((_) {});
        await WebdavClient(cfg).uploadBackup(localPath, uploadName);
        await cfg.save();
        _webdav = cfg;
        _setWebdavStatus('已上传到云端：$uploadName', Colors.green);
        await _refreshCloudFiles(showStatus: false);
      } catch (e) {
        _setWebdavStatus('$e', Colors.red);
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _webdavBusy = false;
          });
        }
      }
    } catch (e) {
      _setWebdavStatus('上传失败：$e', Colors.red);
    }
  }

  Future<void> _restoreFromCloud(WebdavFile f) async {
    if (_busy || _webdavBusy) return;
    final cfg = _editedWebdav();
    setState(() => _webdavBusy = true);
    try {
      final tmpPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}webdav_${f.name}';
      await WebdavClient(cfg).downloadBackup(f.name, tmpPath);
      if (!mounted) return;
      setState(() => _webdavBusy = false);
      await _restoreFromPath(tmpPath);
      try {
        await File(tmpPath).delete();
      } catch (_) {}
    } catch (e) {
      _setWebdavStatus('$e', Colors.red);
      if (mounted) setState(() => _webdavBusy = false);
    }
  }

  Future<void> _deleteCloudFile(WebdavFile f) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这个云端备份？'),
        content: Text(f.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _webdavBusy = true);
    try {
      await WebdavClient(_editedWebdav()).deleteBackup(f.name);
      _setWebdavStatus('云端备份已删除', Colors.green);
      await _refreshCloudFiles(showStatus: false);
    } catch (e) {
      _setWebdavStatus('$e', Colors.red);
    } finally {
      if (mounted) setState(() => _webdavBusy = false);
    }
  }

  Future<void> _clearWebdav() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除云备份配置？'),
        content: const Text('服务器地址、账号与密码将从本机移除，云端文件不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await WebdavConfig.clear();
    if (!mounted) return;
    setState(() {
      _webdav = const WebdavConfig();
      _serverCtrl.clear();
      _userCtrl.clear();
      _passCtrl.clear();
      _dirCtrl.text = 'zhibing';
      _cloudFiles = [];
      _lastTestOkAt = null;
    });
    _setWebdavStatus('已清除本机保存的云备份配置', Colors.grey);
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  /// 北京时间（UTC+8）。云端 WebDAV 返回的 getlastmodified 是 GMT，
  /// 直接显示会比北京时间慢 8 小时，这里统一换算成北京时间展示；
  /// 文件名时间戳同样使用该时间，避免时区偏差。
  DateTime _beijingNow() => DateTime.now().toUtc().add(const Duration(hours: 8));

  DateTime _toBeijing(DateTime dt) => dt.toUtc().add(const Duration(hours: 8));

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  void _setStatus(String msg, Color color) {
    if (!mounted) return;
    setState(() {
      _status = msg;
      _statusColor = color;
    });
  }

  // ─── 平台相关：本地备份文件读写 ───

  String get _localBackupDir {
    try {
      return '${Directory.current.path}${Platform.pathSeparator}zhibing';
    } catch (_) {
      return 'zhibing';
    }
  }

  Future<List<_LocalBackup>> _listBackups() async {
    if (_isAndroid) {
      try {
        final list =
            await _channel.invokeMethod<List<dynamic>>('listBackupFiles') ??
            [];
        return list.map((e) {
          final m = e as Map;
          return _LocalBackup(
            m['name'] as String? ?? '',
            (m['lastModified'] as num?)?.toInt() ?? 0,
          );
        }).toList()
          ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
      } catch (e) {
        _setStatus('读取备份列表失败: $e', Colors.red);
        return [];
      }
    }
    final dir = Directory(_localBackupDir);
    if (!await dir.exists()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files
        .map(
          (f) => _LocalBackup(
            f.path.split(Platform.pathSeparator).last,
            f.lastModifiedSync().millisecondsSinceEpoch,
          ),
        )
        .toList();
  }

  Future<String?> _readBackupToCache(_LocalBackup backup) async {
    if (_isAndroid) {
      try {
        return await _channel.invokeMethod<String>(
          'readBackupFileToCache',
          backup.name,
        );
      } catch (e) {
        _setStatus('读取备份文件失败: $e', Colors.red);
        return null;
      }
    }
    return '${Directory(_localBackupDir).path}${Platform.pathSeparator}${backup.name}';
  }

  Future<bool> _writeBackup(String srcPath, String fileName) async {
    if (_isAndroid) {
      try {
        return await _channel.invokeMethod<bool>('copyDbToBackupFolder', {
              'srcPath': srcPath,
              'fileName': fileName,
            }) ??
            false;
      } catch (e) {
        _setStatus('写入备份文件失败: $e', Colors.red);
        return false;
      }
    }
    final dir = Directory(_localBackupDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    try {
      await File(srcPath).copy('${dir.path}${Platform.pathSeparator}$fileName');
      return true;
    } catch (e) {
      _setStatus('写入备份文件失败: $e', Colors.red);
      return false;
    }
  }

  Future<bool> _deleteBackup(String fileName) async {
    if (_isAndroid) {
      try {
        return await _channel.invokeMethod<bool>(
              'deleteBackupFile',
              fileName,
            ) ??
            false;
      } catch (e) {
        _setStatus('删除备份失败: $e', Colors.red);
        return false;
      }
    }
    try {
      final f = File('${Directory(_localBackupDir).path}/$fileName');
      if (await f.exists()) await f.delete();
      return true;
    } catch (e) {
      _setStatus('删除备份失败: $e', Colors.red);
      return false;
    }
  }

  Future<String?> _pickBackupFile() async {
    if (_isAndroid) {
      try {
        final path = await _channel.invokeMethod<String>('pickBackupFile');
        if (path == null) _setStatus('未选择文件', Colors.grey);
        return path;
      } catch (e) {
        _setStatus('浏览文件失败: $e', Colors.red);
        return null;
      }
    }
    _setStatus('当前平台不支持浏览', Colors.grey);
    return null;
  }

  String _backupFileName(DateTime now) =>
      'zhibing_backup_${now.year}${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}_'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}.db';

  // ─── 备份 ───

  Future<void> _onBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final dbPath = await RecordDb.databasePath();
      if (!await File(dbPath).exists()) {
        _setStatus('数据库文件不存在（还没有保存过病案）', Colors.orange);
        return;
      }
      final fileName = _backupFileName(_beijingNow());
      await RecordDb.close();
      final ok = await _writeBackup(dbPath, fileName);
      _setStatus(
        ok ? '备份成功: $fileName' : '备份失败',
        ok ? Colors.green : Colors.red,
      );
    } catch (e) {
      _setStatus('备份失败: $e', Colors.red);
    } finally {
      setState(() => _busy = false);
    }
  }

  // ─── 还原 ───

  Future<void> _onRestore() async {
    if (_busy) return;
    try {
      final backups = await _listBackups();
      if (!mounted) return;

      final selected = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择备份文件'),
          children: [
            if (backups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text('备份目录中没有备份文件'),
              )
            else
              ...backups.map(
                (b) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, b.name),
                  child: Text(
                    '${b.name}  (${_formatDate(DateTime.fromMillisecondsSinceEpoch(b.lastModified))})',
                  ),
                ),
              ),
            if (_isAndroid && backups.isNotEmpty) const Divider(),
            if (_isAndroid)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, '__BROWSE__'),
                child: const Text('浏览...'),
              ),
          ],
        ),
      );
      if (selected == null) return;

      String? localPath;
      if (selected == '__BROWSE__') {
        localPath = await _pickBackupFile();
      } else {
        localPath = await _readBackupToCache(
          backups.firstWhere((x) => x.name == selected),
        );
      }
      if (localPath == null || !mounted) return;
      await _restoreFromPath(localPath);
    } catch (e) {
      _setStatus('还原失败: $e', Colors.red);
    }
  }

  Future<void> _restoreFromPath(String localPath) async {
    setState(() => _busy = true);
    try {
      final validation = await RecordDb.validateDatabaseFile(localPath);
      if (validation != null) {
        _setStatus('备份文件无效: $validation', Colors.red);
        return;
      }
      if (!mounted) return;

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认还原？'),
          content: const Text('当前所有病案将被备份文件中的内容替换，且无法恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('还原'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      final dbPath = await RecordDb.databasePath();
      await RecordDb.close();
      await Future.delayed(const Duration(milliseconds: 300));

      final dbFile = File(dbPath);
      for (var r = 0; r < 5; r++) {
        for (final f in [dbFile, File('$dbPath-wal'), File('$dbPath-shm')]) {
          try {
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
        if (!await dbFile.exists()) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (await dbFile.exists()) throw Exception('无法删除旧的数据库文件');

      await File(localPath).copy(dbPath);
      for (final f in [File('$dbPath-wal'), File('$dbPath-shm')]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }

      _setStatus('还原成功', Colors.green);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('病案数据还原成功'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      _setStatus('还原失败: $e', Colors.red);
    } finally {
      setState(() => _busy = false);
    }
  }

  // ─── 删除备份 ───

  Future<void> _onDeleteBackup() async {
    final backups = await _listBackups();
    if (!mounted) return;
    if (backups.isEmpty) {
      _setStatus('没有找到备份文件', Colors.grey);
      return;
    }
    final selected = await showDialog<_LocalBackup>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择要删除的备份'),
        children: backups
            .map(
              (b) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, b),
                child: Text(
                  '${b.name}  (${_formatDate(DateTime.fromMillisecondsSinceEpoch(b.lastModified))})',
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null) return;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这个备份？'),
        content: Text(selected.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await _deleteBackup(selected.name);
    _setStatus(ok ? '已删除' : '删除失败', ok ? Colors.green : Colors.red);
  }

  String _formatDate(DateTime dt) {
    final bj = _toBeijing(dt);
    return '${bj.year}-${bj.month.toString().padLeft(2, '0')}-'
        '${bj.day.toString().padLeft(2, '0')} '
        '${bj.hour.toString().padLeft(2, '0')}:${bj.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据备份和还原'),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  '本地备份',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isAndroid
                      ? '备份保存到手机 Download/zhibing/ 目录，可自行拷贝到电脑留存。'
                      : '备份保存到程序运行目录下的 zhibing/ 文件夹。',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _onBackup,
                    icon: const Icon(Icons.backup_rounded),
                    label: const Text('创建备份'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _onRestore,
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('从备份还原'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.brown,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _onDeleteBackup,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('删除备份'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
                if (_status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText(
                      _status,
                      style: TextStyle(fontSize: 13, color: _statusColor),
                    ),
                  ),
                const Divider(height: 40),
                _buildWebdavCard(),
                const Divider(height: 40),
                const Text(
                  '提示：还原会用备份文件替换当前全部病案，请谨慎操作。',
                  style: TextStyle(fontSize: 13, color: Colors.black45, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── WebDAV 云备份 UI ───

  Widget _buildWebdavCard() {
    final busy = _busy || _webdavBusy;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: _webdavExpanded,
        onExpansionChanged: (v) => setState(() => _webdavExpanded = v),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2F1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.cloud_rounded, color: Colors.teal, size: 22),
        ),
        title: const Text(
          'WebDAV 云备份',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.teal,
          ),
        ),
        subtitle: Text(
          _webdav.isConfigured
              ? '已配置：${_webdav.server}'
              : '支持坚果云 / Nextcloud / 群晖 / Alist 等',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        children: [
          const Text(
            '将病案数据库备份到你的 WebDAV 网盘（如坚果云），换手机时一键取回。账号密码仅保存在本机。',
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.6),
          ),
          const SizedBox(height: 12),
          _webdavField(
            controller: _serverCtrl,
            label: '服务器地址',
            hint: '如 https://dav.jianguoyun.com/dav/',
            icon: Icons.dns_rounded,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _webdavField(
                  controller: _userCtrl,
                  label: '账号',
                  hint: '用户名 / 邮箱',
                  icon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _webdavField(
                  controller: _passCtrl,
                  label: '密码',
                  hint: '密码 / 应用专用密码',
                  icon: Icons.lock_outline_rounded,
                  obscure: _passObscure,
                  suffix: IconButton(
                    icon: Icon(
                      _passObscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _passObscure = !_passObscure),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _webdavField(
            controller: _dirCtrl,
            label: '远端目录',
            hint: 'zhibing',
            icon: Icons.folder_outlined,
          ),
          const SizedBox(height: 4),
          const Text(
            '坚果云地址示例：https://dav.jianguoyun.com/dav/，密码请使用「应用密码」（网页端 安全选项 中添加）。',
            style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.6),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _saveAndTestWebdav,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('保存并测试'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '清除本机配置',
                onPressed: busy ? null : _clearWebdav,
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : _uploadToCloud,
              icon: const Icon(Icons.cloud_upload_rounded),
              label: const Text('备份并上传到云端'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2F6F4E),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : _uploadLocalFileToCloud,
              icon: const Icon(Icons.drive_folder_upload_rounded, size: 18),
              label: const Text('选择本地备份上传到云端'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : () => _refreshCloudFiles(),
              icon: const Icon(Icons.cloud_rounded, size: 18),
              label: const Text('刷新云端列表'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ),
          if (_webdavStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(
                _webdavStatus,
                style: TextStyle(fontSize: 13, color: _webdavStatusColor),
              ),
            ),
          if (_webdavBusy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          const SizedBox(height: 6),
          for (final f in _cloudFiles) _cloudFileTile(f, busy),
        ],
      ),
    );
  }

  Widget _webdavField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(color: Colors.red),
      cursorColor: Colors.red,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _cloudFileTile(WebdavFile f, bool busy) {
    final dt = f.lastModified;
    final meta = [
      if (dt != null) '${_formatDate(dt)}（北京时间）',
      if (f.size > 0) _formatSize(f.size),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(
          Icons.cloud_done_outlined,
          color: Color(0xFF2F6F4E),
        ),
        title: Text(
          f.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        subtitle: meta.isEmpty
            ? null
            : Text(meta, style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: busy ? null : () => _restoreFromCloud(f),
              child: const Text('还原'),
            ),
            IconButton(
              tooltip: '删除云端备份',
              onPressed: busy ? null : () => _deleteCloudFile(f),
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
