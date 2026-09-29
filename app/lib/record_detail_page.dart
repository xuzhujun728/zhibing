import 'package:flutter/material.dart';

import 'record.dart';
import 'record_form_page.dart';

/// 病案查看页：全屏展示，用户填写内容用红色字体显示。
class RecordDetailPage extends StatelessWidget {
  final MedicalRecord record;
  const RecordDetailPage({super.key, required this.record});

  static const _red = TextStyle(color: Colors.red, fontSize: 15);
  static const _label = TextStyle(fontSize: 15, color: Colors.black87);
  static const _empty = TextStyle(fontSize: 15, color: Colors.grey);

  Widget _row(String label, String value) {
    final v = value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RichText(
        text: TextSpan(
          style: _label,
          children: [
            TextSpan(text: '$label：'),
            TextSpan(
              text: v.isEmpty ? '（未填）' : v,
              style: v.isEmpty ? _empty : _red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
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
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.name.isEmpty ? '(未命名)' : r.name),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                    builder: (_) => RecordFormPage(record: r)),
              );
              if (changed == true && context.mounted) {
                Navigator.of(context).pop(true);
              }
            },
            icon: const Icon(Icons.edit, color: Colors.white),
            label: const Text('编辑', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              12, 12, 12, 12 + MediaQuery.of(context).padding.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section('基本信息', Icons.person, [
                _row('患者', r.name),
                _row('建档', r.createdAt),
                _row('更新', r.updatedAt),
              ]),
              _section('症状', Icons.sick, [
                _row('头部', r.head),
                _row('颈部', r.neck),
                _row('胸部', r.chest),
                _row('腹部', r.abdomen),
                _row('臀部', r.buttocks),
                _row('手臂', r.arm),
                _row('手', r.hand),
                _row('腿', r.leg),
                _row('脚', r.foot),
                _row('全身', r.wholeBody),
              ]),
              _section('脉象', Icons.favorite, [
                _row('寸部-左', r.pulseCunLeft),
                _row('寸部-右', r.pulseCunRight),
                _row('关部-左', r.pulseGuanLeft),
                _row('关部-右', r.pulseGuanRight),
                _row('尺部-左', r.pulseChiLeft),
                _row('尺部-右', r.pulseChiRight),
              ]),
              _section('舌象', Icons.visibility, [
                _row('舌苔', r.tongueCoating),
                _row('舌边', r.tongueEdge),
              ]),
              _section('按诊记录', Icons.touch_app, [
                _row('左边-手臂', r.palpLeftArm),
                _row('左边-腿脚', r.palpLeftLeg),
                _row('右边-手臂', r.palpRightArm),
                _row('右边-腿脚', r.palpRightLeg),
                _row('补充', r.palpExtra),
              ]),
              _section('确定病经', Icons.gps_fixed, [
                _row('虚证经脉', r.meridian),
              ]),
              _section('治疗方案', Icons.medication, [
                _row('实证-磁疗', r.shiMagnet),
                _row('实证-中药', r.shiHerb),
                _row('虚证', r.xuNote),
              ]),
              _section('治疗记录', Icons.history, [
                _row('记录', r.treatRecord),
              ]),
              _section('分析结论', Icons.analytics, [
                _row('结论', r.analysis),
              ]),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
