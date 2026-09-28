import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'record.dart';

class RecordDb {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'zhibing.db');
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
