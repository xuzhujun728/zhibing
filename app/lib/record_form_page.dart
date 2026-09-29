import 'package:flutter/material.dart';

import 'db.dart';
import 'record.dart';

/// 新增 / 编辑表单页：按《治病模板.md》分组填写，一键分析，保存入库。
///
/// 性能说明：键盘弹出/收起动画期间，框架会因视图衬区（viewInsets）
/// 变化而频繁触发布局。以前 build() 内直接调用
/// `MediaQuery.of(context)`，导致整个含 30+ 输入框的表单在动画的
/// 每一帧都执行完整重建（ jedynie 输入框越多越卡）。现在 build()
/// 不再订阅 MediaQuery：内边距改为常量、输入框分组部件在 initState
/// 中一次性构建并缓存，动画期间只做布局不再重建 Widget，因此键盘
/// 开合恢复流畅。
class RecordFormPage extends StatefulWidget {
  final MedicalRecord? record;
  const RecordFormPage({super.key, this.record});

  @override
  State<RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends State<RecordFormPage>
    with WidgetsBindingObserver {
  late MedicalRecord _r;
  final _ctrls = <String, TextEditingController>{};
  bool _saving = false;
  bool _handlingBack = false;

  /// 当前键盘是否可见（经窗口衬区判断，不订阅 MediaQuery）。
  bool _keyboardVisible = false;

  /// 上次自动保存成功的时间，用于过滤重复触发（如主动 unfocus 后
  /// 紧跟着的 metrics 回调），避免短时间内重复写库。
  DateTime? _lastAutoSavedAt;

  /// 表单缓存：输入框分组只构建一次，键盘动画/ setState 重建时复用。
  late final List<Widget> _cachedSections;

  /// 全部表单 key（与 _r 字段一一对应）。
  static const _keys = <String>[
    'name',
    'head', 'neck', 'chest', 'abdomen', 'buttocks',
    'arm', 'hand', 'leg', 'foot', 'wholeBody',
    'pulseCunLeft', 'pulseCunRight',
    'pulseGuanLeft', 'pulseGuanRight',
    'pulseChiLeft', 'pulseChiRight',
    'tongueCoating', 'tongueEdge',
    'palpLeftArm', 'palpLeftLeg',
    'palpRightArm', 'palpRightLeg', 'palpExtra',
    'meridian',
    'shiMagnet', 'shiHerb', 'xuNote',
    'treatRecord',
    'analysis',
  ];

  String _initialFor(String key) {
    switch (key) {
      case 'name': return _r.name;
      case 'head': return _r.head;
      case 'neck': return _r.neck;
      case 'chest': return _r.chest;
      case 'abdomen': return _r.abdomen;
      case 'buttocks': return _r.buttocks;
      case 'arm': return _r.arm;
      case 'hand': return _r.hand;
      case 'leg': return _r.leg;
      case 'foot': return _r.foot;
      case 'wholeBody': return _r.wholeBody;
      case 'pulseCunLeft': return _r.pulseCunLeft;
      case 'pulseCunRight': return _r.pulseCunRight;
      case 'pulseGuanLeft': return _r.pulseGuanLeft;
      case 'pulseGuanRight': return _r.pulseGuanRight;
      case 'pulseChiLeft': return _r.pulseChiLeft;
      case 'pulseChiRight': return _r.pulseChiRight;
      case 'tongueCoating': return _r.tongueCoating;
      case 'tongueEdge': return _r.tongueEdge;
      case 'palpLeftArm': return _r.palpLeftArm;
      case 'palpLeftLeg': return _r.palpLeftLeg;
      case 'palpRightArm': return _r.palpRightArm;
      case 'palpRightLeg': return _r.palpRightLeg;
      case 'palpExtra': return _r.palpExtra;
      case 'meridian': return _r.meridian;
      case 'shiMagnet': return _r.shiMagnet;
      case 'shiHerb': return _r.shiHerb;
      case 'xuNote': return _r.xuNote;
      case 'treatRecord': return _r.treatRecord;
      case 'analysis': return _r.analysis;
      default: return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _r = widget.record ?? MedicalRecord();
    // 控制器在 initState 一次性建好：build() 为纯函数，不再边构建边创建。
    for (final k in _keys) {
      _ctrls[k] = TextEditingController(text: _initialFor(k));
    }
    _cachedSections = _buildSections();
    WidgetsBinding.instance.addObserver(this);
    // 首帧结束后记录初始键盘状态，避免首次回调误判。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keyboardVisible = _isKeyboardVisible();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 不订阅 MediaQuery、只读一次窗口衬区高度，判断键盘是否可见。
  /// （用 View.of 而不是 MediaQuery.of，因此不会引入 rebuild 依赖。）
  bool _isKeyboardVisible() {
    final view = View.of(context);
    final insets = view.viewInsets.bottom / view.devicePixelRatio;
    return insets > 0;
  }

  /// 系统键盘/窗口衬区变化时触发：第一次返回键被系统消费为"收键盘"时，
  /// 走到这里，此时直接把当前内容保存入库。
  @override
  void didChangeMetrics() {
    if (!mounted || _saving) return;
    final visible = _isKeyboardVisible();
    final wasVisible = _keyboardVisible;
    _keyboardVisible = visible;
    // 键盘 展开->收起 的边沿：先让文本框彻底失焦（系统只收键盘不丢焦点，
    // 不手动 unfocus 的话焦点还留在文本框里），再保存，人留在页面。
    if (wasVisible && !visible) {
      if (FocusScope.of(context).hasFocus) {
        FocusScope.of(context).unfocus();
      }
      // 距上次自动保存不足 3 秒则跳过（主动 unfocus/重复回调的去重）。
      final last = _lastAutoSavedAt;
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 3)) {
        return;
      }
      _autoSave(popAfter: false);
    }
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
      ..treatRecord = v('treatRecord')
      ..analysis = v('analysis');
  }

  /// 是否填写了任何实质内容（用于判断空表单直接退出、无需入库）。
  bool _hasContent() =>
      _ctrls.values.any((c) => c.text.trim().isNotEmpty);

  void _doAnalyze() {
    _syncFromUi();
    final a = analyzeRecord(_r);
    setState(() => _ctrls['analysis']!.text = a);
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

  /// 返回键自动保存：不校验姓名（避免草稿丢失），空表单则直接退出。
  /// [popAfter] 为 true 表示键盘已收起，保存后退出页面；
  /// 为 false 表示本次返回只收起键盘，保存在后台完成，人留在页面。
  Future<void> _autoSave({required bool popAfter}) async {
    if (_saving) return;
    _syncFromUi();
    if (_r.id == null && !_hasContent()) {
      if (popAfter && mounted) Navigator.of(context).pop(false);
      return;
    }
    if (mounted) setState(() => _saving = true);
    try {
      final now = _now();
      if (_r.id == null) {
        _r.createdAt = now;
        _r.updatedAt = now;
        _r.id = await RecordDb.insert(_r);
      } else {
        _r.updatedAt = now;
        await RecordDb.update(_r);
      }
      if (!mounted) return;
      _lastAutoSavedAt = DateTime.now();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(popAfter ? '已自动保存' : '键盘已收起，草稿已自动保存')),
      );
      if (popAfter) Navigator.of(context).pop(true);
    } catch (e) {
      // 保存失败时留在页面，避免数据丢失。
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('自动保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 拦截返回（系统返回键 / 顶部返回箭头）。
  /// 注意：键盘展开时按返回，第 1 次返回会被系统消费为"收键盘"，
  /// 根本到不了这里，保存由 didChangeMetrics() 完成（收拢且保存）。
  /// 能走到这里时键盘已收起：保存后退出（第 2 次返回即退出）。
  void _handleBack() {
    if (_handlingBack || _saving) return;
    _handlingBack = true;
    try {
      if (_keyboardVisible || FocusScope.of(context).hasFocus) {
        // 顶部返回箭头等未被系统消费为收键盘的情况：先收键盘，
        // 保存交给 didChangeMetrics 的键盘收起边沿，避免重复写库。
        FocusScope.of(context).unfocus();
        _handlingBack = false;
      } else {
        _autoSave(popAfter: true).whenComplete(() {
          // 保存失败时会留在页面，需重置标记；成功退出则页面已销毁，无影响。
          _handlingBack = false;
        });
      }
    } catch (_) {
      _handlingBack = false;
    }
  }

  Widget _field(String key, String label, {int lines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _ctrls[key],
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

  /// 分组部件只构建一次并缓存，供 build() 复用。
  List<Widget> _buildSections() {
    return [
      _section('基本信息', [
        _field('name', '患者姓名 *'),
      ], Icons.person),
      _section('症状', [
        _field('head', '头部'),
        _field('neck', '颈部'),
        _field('chest', '胸部'),
        _field('abdomen', '腹部'),
        _field('buttocks', '臀部'),
        _field('arm', '手臂'),
        _field('hand', '手'),
        _field('leg', '腿'),
        _field('foot', '脚'),
        _field('wholeBody', '全身'),
      ], Icons.sick),
      _section('脉象', [
        _field('pulseCunLeft', '寸部-左'),
        _field('pulseCunRight', '寸部-右'),
        _field('pulseGuanLeft', '关部-左'),
        _field('pulseGuanRight', '关部-右'),
        _field('pulseChiLeft', '尺部-左'),
        _field('pulseChiRight', '尺部-右'),
      ], Icons.favorite),
      _section('舌象', [
        _field('tongueCoating', '舌苔'),
        _field('tongueEdge', '舌边'),
      ], Icons.visibility),
      _section('按诊记录', [
        _field('palpLeftArm', '左边-手臂'),
        _field('palpLeftLeg', '左边-腿脚'),
        _field('palpRightArm', '右边-手臂'),
        _field('palpRightLeg', '右边-腿脚'),
        _field('palpExtra', '补充', lines: 2),
      ], Icons.touch_app),
      _section('确定病经', [
        _field('meridian', '虚证经脉是哪条', lines: 2, hint: '如：足太阴脾经虚证'),
      ], Icons.gps_fixed),
      _section('治疗方案', [
        _field('shiMagnet', '实证-磁疗（补法/泻法）', lines: 2, hint: '磁疗法用补法或泻法'),
        _field('shiHerb', '实证-中药（泻法）', lines: 2, hint: '中药法用泻法'),
        _field('xuNote', '虚证（磁疗/中药均用补法）', lines: 2),
      ], Icons.medication),
      _section('治疗记录', [
        _field('treatRecord', '治疗记录', lines: 5,
            hint: '如：2026-09-28 09:00，30分钟，治法与缘由…'),
      ], Icons.history),
      _section('分析结论', [
        _field('analysis', '分析结论', lines: 5, hint: '点击右上角“分析”自动生成，可再手动修改'),
      ], Icons.analytics),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 注意：此处刻意不用 MediaQuery.of(context)。之前底部内边距依赖
    // MediaQuery，导致键盘动画每一帧都重建整个表单（30+ 输入框），
    // 是键盘开合卡顿的根因。现在只用常量内边距 + SafeArea，
    // 键盘动画只触发布局，不再触发 Widget 重建。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              children: [
                ..._cachedSections,
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
      ),
    );
  }
}
