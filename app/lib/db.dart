import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'record.dart';

class RecordDb {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final path = await databasePath();
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (d, v) async {
        await d.execute('''CREATE TABLE records(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT, createdAt TEXT, updatedAt TEXT,
          head TEXT, neck TEXT, chest TEXT, abdomen TEXT, buttocks TEXT,
          arm TEXT, hand TEXT, leg TEXT, foot TEXT, wholeBody TEXT,
          pulseCunLeft TEXT, pulseCunRight TEXT,
          pulseGuanLeft TEXT, pulseGuanRight TEXT,
          pulseChiLeft TEXT, pulseChiRight TEXT,
          tongueCoating TEXT, tongueEdge TEXT,
          palpLeftArm TEXT, palpLeftLeg TEXT,
          palpRightArm TEXT, palpRightLeg TEXT, palpExtra TEXT,
          meridian TEXT,
          shiMagnet TEXT, shiHerb TEXT, xuNote TEXT,
          treatStart TEXT, treatDuration TEXT, treatMethod TEXT,
          treatReason TEXT, treatExtra TEXT,
          analysis TEXT
        )''');
      },
    );
    return _db!;
  }

  /// 数据库文件完整路径（供备份还原使用）。
  static Future<String> databasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'zhibing.db');
  }

  /// 关闭数据库连接（备份/还原前调用；下次访问时自动重开）。
  static Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  /// 校验数据库文件是否为本应用的备份数据，无效时返回错误描述。
  static Future<String?> validateDatabaseFile(String path) async {
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true);
      final rows = await db.query(
        'sqlite_master',
        where: "type = 'table' AND name = 'records'",
      );
      if (rows.isEmpty) return '缺少必要的 records 数据表';
      final count =
          (await db.query('records', columns: ['COUNT(*) AS c'])).first['c'];
      if ((count as num).toInt() < 0) return '数据异常';
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  static Future<int> insert(MedicalRecord r) async {
    final d = await db;
    final map = r.toMap()..remove('id');
    return d.insert('records', map);
  }

  static Future<int> update(MedicalRecord r) async {
    final d = await db;
    final map = r.toMap()..remove('id');
    return d.update('records', map, where: 'id=?', whereArgs: [r.id]);
  }

  static Future<int> delete(int id) async {
    final d = await db;
    return d.delete('records', where: 'id=?', whereArgs: [id]);
  }

  static Future<List<MedicalRecord>> search(String keyword) async {
    final d = await db;
    final k = keyword.trim();
    final List<Map<String, dynamic>> rows;
    if (k.isEmpty) {
      rows = await d.query('records', orderBy: 'id DESC');
    } else {
      rows = await d.query(
        'records',
        where: 'name LIKE ? OR meridian LIKE ? OR analysis LIKE ? '
            'OR head LIKE ? OR wholeBody LIKE ? OR treatMethod LIKE ?',
        whereArgs: List.filled(6, '%$k%'),
        orderBy: 'id DESC',
      );
    }
    return rows.map(MedicalRecord.fromMap).toList();
  }
}
