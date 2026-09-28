import 'package:flutter/material.dart';

import 'db.dart';
import 'record.dart';
import 'record_detail_page.dart';
import 'record_form_page.dart';

void main() {
  runApp(const ZhibingApp());
}

class ZhibingApp extends StatelessWidget {
  const ZhibingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '治病诊疗记录',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _kw = TextEditingController();
  List<MedicalRecord> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _kw.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final items = await RecordDb.search(_kw.text);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _openForm({MedicalRecord? record}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RecordFormPage(record: record)),
    );
    if (changed == true) _reload();
  }

  Future<void> _confirmDelete(MedicalRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定删除「${r.name.isEmpty ? '(未命名)' : r.name}」的记录吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await RecordDb.delete(r.id!);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已删除')));
        _reload();
      }
    }
  }

  Future<void> _showDetail(MedicalRecord r) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RecordDetailPage(record: r)),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('治病诊疗记录'), centerTitle: true),
      body: SafeArea(
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _kw,
                    style: const TextStyle(color: Colors.red),
                    cursorColor: Colors.red,
                    decoration: const InputDecoration(
                      hintText: '搜索：姓名 / 病经 / 症状 / 治法…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _reload(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _reload, child: const Text('查询')),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('暂无记录，点击右下角 + 新建'))
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (context, _) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final r = _items[index];
                          return ListTile(
                            title: Text(
                                '${r.name.isEmpty ? '(未命名)' : r.name}　${r.updatedAt}'),
                            subtitle: Text(
                              '病经：${r.meridian.isEmpty ? '未定' : r.meridian}｜'
                              '治法：${r.treatMethod.isEmpty ? '未填' : r.treatMethod}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _showDetail(r),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  tooltip: '编辑',
                                  onPressed: () => _openForm(record: r),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  tooltip: '删除',
                                  onPressed: () => _confirmDelete(r),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('新建病案'),
      ),
    );
  }
}
