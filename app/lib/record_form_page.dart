import 'package:flutter/material.dart';

import 'db.dart';
import 'record.dart';

/// 新增 / 编辑表单页：按《治病模板.md》分组填写，一键分析，保存入库。
class RecordFormPage extends StatefulWidget {
  final MedicalRecord? record;
  const RecordFormPage({super.key, this.record});

  @override
  State<RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends State<RecordFormPage> {
  late MedicalRecord _r;
  final _ctrls = <String, TextEditingController>{};
  bool _saving = false;

  TextEditingController c(String key, String init) =>
      _ctrls.putIfAbsent(key, () => TextEditingController(text: init));

  @override
  void initState() {
    super.initState();
    _r = widget.record ?? MedicalRecord();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncFromUi() {
    String v(String k) => _ctrls[k]?.text ?? '';
    _r
      ..name = v('name')
      ..head = v('head')
      ..neck = v('neck')
      ..chest = v('chest')
      ..abdomen = v('abdomen')
      ..buttocks = v('buttocks')
      ..arm = v('arm')
      ..hand = v('hand')
      ..leg = v('leg')
      ..foot = v('foot')
      ..wholeBody = v('wholeBody')
      ..pulseCunLeft = v('pulseCunLeft')
      ..pulseCunRight = v('pulseCunRight')
      ..pulseGuanLeft = v('pulseGuanLeft')
      ..pulseGuanRight = v('pulseGuanRight')
      ..pulseChiLeft = v('pulseChiLeft')
      ..pulseChiRight = v('pulseChiRight')
      ..tongueCoating = v('tongueCoating')
      ..tongueEdge = v('tongueEdge')
      ..palpLeftArm = v('palpLeftArm')
      ..palpLeftLeg = v('palpLeftLeg')
      ..palpRightArm = v('palpRightArm')
      ..palpRightLeg = v('palpRightLeg')
      ..palpExtra = v('palpExtra')
      ..meridian = v('meridian')
      ..shiMagnet = v('shiMagnet')
      ..shiHerb = v('shiHerb')
      ..xuNote = v('xuNote')
      ..treatStart = v('treatStart')
      ..treatDuration = v('treatDuration')
      ..treatMethod = v('treatMethod')
      ..treatReason = v('treatReason')
      ..treatExtra = v('treatExtra')
      ..analysis = v('analysis');
  }

  void _doAnalyze() {
    _syncFromUi();
    final a = analyzeRecord(_r);
    setState(() => c('analysis', _r.analysis).text = a);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已生成分析结论，可修改后保存')));
  }

  String _now() {
    final t = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}';
  }

  Future<void> _save() async {
    _syncFromUi();
    if (_r.name.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先填写患者姓名')));
      return;
    }
    setState(() => _saving = true);
    try {
      final now = _now();
      if (_r.id == null) {
        _r.createdAt = now;
        _r.updatedAt = now;
        await RecordDb.insert(_r);
      } else {
        _r.updatedAt = now;
        await RecordDb.update(_r);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存成功')));
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label, String init,
      {int lines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c(key, init),
        style: const TextStyle(color: Colors.red),
        cursorColor: Colors.red,
        maxLines: lines,
        minLines: lines > 1 ? lines : 1,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.record == null ? '新建病案' : '编辑病案'),
        actions: [
          TextButton.icon(
            onPressed: _doAnalyze,
            icon: const Icon(Icons.analytics_outlined, color: Colors.white),
            label:
                const Text('分析', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              12, 12, 12, 12 + MediaQuery.of(context).padding.bottom),
          child: Column(
            children: [
            _section('基本信息', [
              _field('name', '患者姓名 *', r.name),
            ], Icons.person),
            _section('症状', [
              _field('head', '头部', r.head),
              _field('neck', '颈部', r.neck),
              _field('chest', '胸部', r.chest),
              _field('abdomen', '腹部', r.abdomen),
              _field('buttocks', '臀部', r.buttocks),
              _field('arm', '手臂', r.arm),
              _field('hand', '手', r.hand),
              _field('leg', '腿', r.leg),
              _field('foot', '脚', r.foot),
              _field('wholeBody', '全身', r.wholeBody),
            ], Icons.sick),
            _section('脉象', [
              _field('pulseCunLeft', '寸部-左', r.pulseCunLeft),
              _field('pulseCunRight', '寸部-右', r.pulseCunRight),
              _field('pulseGuanLeft', '关部-左', r.pulseGuanLeft),
              _field('pulseGuanRight', '关部-右', r.pulseGuanRight),
              _field('pulseChiLeft', '尺部-左', r.pulseChiLeft),
              _field('pulseChiRight', '尺部-右', r.pulseChiRight),
            ], Icons.favorite),
            _section('舌象', [
              _field('tongueCoating', '舌苔', r.tongueCoating),
              _field('tongueEdge', '舌边', r.tongueEdge),
            ], Icons.visibility),
            _section('按诊记录', [
              _field('palpLeftArm', '左边-手臂', r.palpLeftArm),
              _field('palpLeftLeg', '左边-腿脚', r.palpLeftLeg),
              _field('palpRightArm', '右边-手臂', r.palpRightArm),
              _field('palpRightLeg', '右边-腿脚', r.palpRightLeg),
              _field('palpExtra', '补充', r.palpExtra, lines: 2),
            ], Icons.touch_app),
            _section('确定病经', [
              _field('meridian', '虚证经脉是哪条', r.meridian,
                  lines: 2, hint: '如：足太阴脾经虚证'),
            ], Icons.gps_fixed),
            _section('治疗方案', [
              _field('shiMagnet', '实证-磁疗（补法/泻法）', r.shiMagnet,
                  lines: 2, hint: '磁疗法用补法或泻法'),
              _field('shiHerb', '实证-中药（泻法）', r.shiHerb,
                  lines: 2, hint: '中药法用泻法'),
              _field('xuNote', '虚证（磁疗/中药均用补法）', r.xuNote, lines: 2),
            ], Icons.medication),
            _section('治疗记录', [
              _field('treatStart', '开始时间', r.treatStart,
                  hint: '如 2026-09-28 09:00'),
              _field('treatDuration', '持续时间', r.treatDuration,
                  hint: '如 30分钟'),
              _field('treatMethod', '治法', r.treatMethod, lines: 2),
              _field('treatReason', '治法缘由', r.treatReason, lines: 2),
              _field('treatExtra', '补充记录', r.treatExtra, lines: 2),
            ], Icons.history),
            _section('分析结论', [
              _field('analysis', '分析结论', r.analysis,
                  lines: 5, hint: '点击右上角“分析”自动生成，可再手动修改'),
            ], Icons.analytics),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _doAnalyze,
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('分析'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(_saving ? '保存中…' : '保存'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
