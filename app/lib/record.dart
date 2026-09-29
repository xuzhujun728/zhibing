/// 诊疗记录数据模型，对应《治病模板.md》全部字段。
class MedicalRecord {
  int? id;
  String name; // 患者姓名（列表检索用，模板之外附加）
  String createdAt; // 建档时间
  String updatedAt; // 更新时间

  // 症状
  String head;
  String neck;
  String chest;
  String abdomen;
  String buttocks;
  String arm;
  String hand;
  String leg;
  String foot;
  String wholeBody;

  // 脉象
  String pulseCunLeft;
  String pulseCunRight;
  String pulseGuanLeft;
  String pulseGuanRight;
  String pulseChiLeft;
  String pulseChiRight;

  // 舌象
  String tongueCoating;
  String tongueEdge;

  // 按诊记录
  String palpLeftArm;
  String palpLeftLeg;
  String palpRightArm;
  String palpRightLeg;
  String palpExtra;

  // 确定病经
  String meridian;

  // 治疗方案
  String shiMagnet; // 实证-磁疗法
  String shiHerb; // 实证-中药法
  String xuNote; // 虚证

  // 治疗记录（单个文本框自由填写）
  String treatRecord;

  // 分析结论
  String analysis;

  MedicalRecord({
    this.id,
    this.name = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.head = '',
    this.neck = '',
    this.chest = '',
    this.abdomen = '',
    this.buttocks = '',
    this.arm = '',
    this.hand = '',
    this.leg = '',
    this.foot = '',
    this.wholeBody = '',
    this.pulseCunLeft = '',
    this.pulseCunRight = '',
    this.pulseGuanLeft = '',
    this.pulseGuanRight = '',
    this.pulseChiLeft = '',
    this.pulseChiRight = '',
    this.tongueCoating = '',
    this.tongueEdge = '',
    this.palpLeftArm = '',
    this.palpLeftLeg = '',
    this.palpRightArm = '',
    this.palpRightLeg = '',
    this.palpExtra = '',
    this.meridian = '',
    this.shiMagnet = '',
    this.shiHerb = '',
    this.xuNote = '',
    this.treatRecord = '',
    this.analysis = '',
  });

  factory MedicalRecord.fromMap(Map<String, dynamic> m) => MedicalRecord(
        id: m['id'] as int?,
        name: '${m['name'] ?? ''}',
        createdAt: '${m['createdAt'] ?? ''}',
        updatedAt: '${m['updatedAt'] ?? ''}',
        head: '${m['head'] ?? ''}',
        neck: '${m['neck'] ?? ''}',
        chest: '${m['chest'] ?? ''}',
        abdomen: '${m['abdomen'] ?? ''}',
        buttocks: '${m['buttocks'] ?? ''}',
        arm: '${m['arm'] ?? ''}',
        hand: '${m['hand'] ?? ''}',
        leg: '${m['leg'] ?? ''}',
        foot: '${m['foot'] ?? ''}',
        wholeBody: '${m['wholeBody'] ?? ''}',
        pulseCunLeft: '${m['pulseCunLeft'] ?? ''}',
        pulseCunRight: '${m['pulseCunRight'] ?? ''}',
        pulseGuanLeft: '${m['pulseGuanLeft'] ?? ''}',
        pulseGuanRight: '${m['pulseGuanRight'] ?? ''}',
        pulseChiLeft: '${m['pulseChiLeft'] ?? ''}',
        pulseChiRight: '${m['pulseChiRight'] ?? ''}',
        tongueCoating: '${m['tongueCoating'] ?? ''}',
        tongueEdge: '${m['tongueEdge'] ?? ''}',
        palpLeftArm: '${m['palpLeftArm'] ?? ''}',
        palpLeftLeg: '${m['palpLeftLeg'] ?? ''}',
        palpRightArm: '${m['palpRightArm'] ?? ''}',
        palpRightLeg: '${m['palpRightLeg'] ?? ''}',
        palpExtra: '${m['palpExtra'] ?? ''}',
        meridian: '${m['meridian'] ?? ''}',
        shiMagnet: '${m['shiMagnet'] ?? ''}',
        shiHerb: '${m['shiHerb'] ?? ''}',
        xuNote: '${m['xuNote'] ?? ''}',
        treatRecord: '${m['treatRecord'] ?? ''}',
        analysis: '${m['analysis'] ?? ''}',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'head': head,
        'neck': neck,
        'chest': chest,
        'abdomen': abdomen,
        'buttocks': buttocks,
        'arm': arm,
        'hand': hand,
        'leg': leg,
        'foot': foot,
        'wholeBody': wholeBody,
        'pulseCunLeft': pulseCunLeft,
        'pulseCunRight': pulseCunRight,
        'pulseGuanLeft': pulseGuanLeft,
        'pulseGuanRight': pulseGuanRight,
        'pulseChiLeft': pulseChiLeft,
        'pulseChiRight': pulseChiRight,
        'tongueCoating': tongueCoating,
        'tongueEdge': tongueEdge,
        'palpLeftArm': palpLeftArm,
        'palpLeftLeg': palpLeftLeg,
        'palpRightArm': palpRightArm,
        'palpRightLeg': palpRightLeg,
        'palpExtra': palpExtra,
        'meridian': meridian,
        'shiMagnet': shiMagnet,
        'shiHerb': shiHerb,
        'xuNote': xuNote,
        'treatRecord': treatRecord,
        'analysis': analysis,
      };

  /// 汇总成 Markdown 文本（与治病模板同结构），用于详情展示。
  String toMarkdown() {
    final b = StringBuffer();
    b.writeln('患者：$name');
    b.writeln('建档：$createdAt　更新：$updatedAt');
    b.writeln('\n症状');
    b.writeln('- 头部：$head');
    b.writeln('- 颈部：$neck');
    b.writeln('- 胸部：$chest');
    b.writeln('- 腹部：$abdomen');
    b.writeln('- 臀部：$buttocks');
    b.writeln('- 手臂：$arm');
    b.writeln('- 手：$hand');
    b.writeln('- 腿：$leg');
    b.writeln('- 脚：$foot');
    b.writeln('- 全身：$wholeBody');
    b.writeln('\n脉象');
    b.writeln('- 寸部');
    b.writeln('  - 左：$pulseCunLeft');
    b.writeln('  - 右：$pulseCunRight');
    b.writeln('- 关部');
    b.writeln('  - 左：$pulseGuanLeft');
    b.writeln('  - 右：$pulseGuanRight');
    b.writeln('- 尺部');
    b.writeln('  - 左：$pulseChiLeft');
    b.writeln('  - 右：$pulseChiRight');
    b.writeln('\n舌象');
    b.writeln('- 舌苔：$tongueCoating');
    b.writeln('- 舌边：$tongueEdge');
    b.writeln('\n按诊记录');
    b.writeln('- 左边');
    b.writeln('  - 手臂：$palpLeftArm');
    b.writeln('  - 腿脚：$palpLeftLeg');
    b.writeln('- 右边');
    b.writeln('  - 手臂：$palpRightArm');
    b.writeln('  - 腿脚：$palpRightLeg');
    b.writeln('- 补充：$palpExtra');
    b.writeln('\n确定病经');
    b.writeln('- $meridian');
    b.writeln('\n治疗方案');
    b.writeln('- 实证-磁疗：$shiMagnet');
    b.writeln('- 实证-中药：$shiHerb');
    b.writeln('- 虚证：$xuNote');
    b.writeln('\n治疗记录');
    b.writeln(treatRecord.isEmpty ? '（未填）' : treatRecord);
    b.writeln('\n分析结论');
    b.writeln(analysis.isEmpty ? '（暂无）' : analysis);
    return b.toString();
  }
}

/// 本地规则分析：统计填写项，给出辨证提示（非诊断，仅整理提示）。
String analyzeRecord(MedicalRecord r) {
  int count(List<String> xs) =>
      xs.where((e) => e.trim().isNotEmpty).length;
  final symptomCount = count([
    r.head, r.neck, r.chest, r.abdomen, r.buttocks,
    r.arm, r.hand, r.leg, r.foot, r.wholeBody,
  ]);
  final pulseCount = count([
    r.pulseCunLeft, r.pulseCunRight, r.pulseGuanLeft,
    r.pulseGuanRight, r.pulseChiLeft, r.pulseChiRight,
  ]);
  final tongueCount = count([r.tongueCoating, r.tongueEdge]);
  final palpCount = count([
    r.palpLeftArm, r.palpLeftLeg, r.palpRightArm, r.palpRightLeg, r.palpExtra,
  ]);
  final filled = symptomCount + pulseCount + tongueCount + palpCount;

  final tips = <String>[];
  if (r.meridian.trim().isEmpty) tips.add('尚未确定虚证经脉，建议结合脉象/按诊补填“确定病经”。');
  if (r.shiMagnet.trim().isEmpty && r.shiHerb.trim().isEmpty && r.xuNote.trim().isEmpty) {
    tips.add('治疗方案为空：实证磁疗可用补/泻、实证中药用泻法；虚证磁疗与中药均用补法。');
  }
  if (r.treatRecord.trim().isEmpty) tips.add('治疗记录为空，建议记录治疗时间、治法与缘由。');
  if (r.tongueCoating.trim().isEmpty && r.tongueEdge.trim().isEmpty) {
    tips.add('舌象未填，舌苔/舌边有助于辨虚实。');
  }
  if (tips.isEmpty) tips.add('四诊与方案记录完整，可复核虚实与补泻方向是否一致。');

  return '【自动分析】共填写 $filled 项：症状 $symptomCount/10，脉象 $pulseCount/6，'
      '舌象 $tongueCount/2，按诊 $palpCount/5。\n'
      '提示：\n${tips.map((t) => '- $t').join('\n')}';
}
