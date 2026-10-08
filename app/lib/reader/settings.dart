import 'package:flutter/material.dart';

import 'style.dart';

class ReaderSettings extends StatefulWidget {
  final ReaderStyle style;
  final bool perBook;
  final ValueChanged<ReaderStyle> onChanged;
  final ValueChanged<bool>? onPerBook;
  final Widget? orientationSetting;
  const ReaderSettings({
    super.key,
    required this.style,
    required this.onChanged,
    this.perBook = false,
    this.onPerBook,
    this.orientationSetting,
  });
  @override
  State<ReaderSettings> createState() => _ReaderSettingsState();
}

class _ReaderSettingsState extends State<ReaderSettings> {
  late ReaderStyle style = widget.style;
  late bool perBook = widget.perBook;
  void update(String key, dynamic value) {
    setState(() => style = style.withValue(key, value));
    widget.onChanged(style);
  }

  Widget slider(
    String label,
    String key,
    double value,
    double min,
    double max,
    int divisions,
    String suffix,
  ) => Column(
    children: [
      Row(
        children: [
          Text(label),
          const Spacer(),
          Text(
            '${value.toStringAsFixed(suffix == '倍' ? 2 : 0)}$suffix',
            style: const TextStyle(color: Color(0xFF888888)),
          ),
        ],
      ),
      Slider(
        key: ValueKey(key),
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: (v) => update(key, v),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final wide = ReaderStyle.isWideLandscape(MediaQuery.sizeOf(context));
    final fonts = <String, String>{
      'platform': isIOS ? 'Iowan Old Style · 默认' : 'Literata · 默认',
      if (isIOS) ...{
        'Charter': 'Charter',
        'Georgia': 'Georgia',
        'Palatino': 'Palatino',
        'Athelas': 'Athelas',
        'Seravek': 'Seravek',
      },
      'Literata': 'Literata',
      'SourceSerif4': 'Source Serif 4',
      'EBGaramond': 'EB Garamond',
      'AtkinsonHyperlegible': 'Atkinson Hyperlegible',
      'system': isIOS ? 'San Francisco · 系统' : '系统字体',
    };
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .78,
      maxChildSize: .94,
      minChildSize: .4,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
        children: [
          Row(
            children: [
              const Text(
                '阅读设置',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                tooltip: '关闭设置',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (widget.onPerBook != null)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('仅应用于这本书'),
              subtitle: const Text('关闭时，此样式也会作为其他书的默认值'),
              value: perBook,
              onChanged: (v) {
                setState(() => perBook = v);
                widget.onPerBook!(v);
              },
            ),
          const SizedBox(height: 12),
          if (wide)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('横屏宽窗口阅读方式（与竖屏分别保存）'),
            ),
          SegmentedButton<bool>(
            segments: [
              const ButtonSegment(value: false, label: Text('上下滚动')),
              ButtonSegment(value: true, label: Text(wide ? '双页翻阅' : '左右翻页')),
            ],
            selected: {wide ? style.landscapePaged : style.paged},
            onSelectionChanged: (value) =>
                update(wide ? 'landscapePaged' : 'paged', value.first),
          ),
          const SizedBox(height: 16),
          if (widget.orientationSetting != null) widget.orientationSetting!,
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey('font-${style.font}'),
            initialValue: fonts.containsKey(style.font)
                ? style.font
                : 'platform',
            decoration: const InputDecoration(
              labelText: '正文字体',
              border: OutlineInputBorder(),
            ),
            items: fonts.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) => update('font', v),
          ),
          const SizedBox(height: 24),
          slider('字号', 'size', style.size, 14, 34, 20, ''),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('粗体'),
            value: style.bold,
            onChanged: (v) => update('bold', v),
          ),
          slider('行间距', 'lineHeight', style.lineHeight, 1.1, 2.4, 26, '倍'),
          slider(
            '字间距',
            'letterSpacing',
            style.letterSpacing,
            -.02,
            .15,
            17,
            '倍',
          ),
          slider(
            '段间距',
            'paragraphSpacing',
            style.paragraphSpacing,
            0,
            2,
            20,
            '倍',
          ),
          slider('页边距', 'margin', style.margin, 12, 60, 24, ''),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('两端对齐'),
            value: style.justify,
            onChanged: (v) => update('justify', v),
          ),
          const Divider(height: 40),
          const Text('阅读主题', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: ReaderTheme.values.map((t) {
              final p = ReaderPalette.palettes[t]!;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Semantics(
                    selected: style.theme == t,
                    button: true,
                    child: InkWell(
                      onTap: () {
                        update('followSystem', false);
                        update('theme', t.name);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: p.background,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: style.theme == t
                                ? const Color(0xFFAF754A)
                                : const Color(0x33888888),
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          ['白色', '纸色', '安静', '夜间'][t.index],
                          style: TextStyle(color: p.ink),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('跟随系统深色模式'),
            value: style.followSystem,
            onChanged: (v) => update('followSystem', v),
          ),
          const Divider(height: 40),
          const Text('点词释义', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          SegmentedButton<GlossTier>(
            segments: const [
              ButtonSegment(value: GlossTier.minimal, label: Text('极简')),
              ButtonSegment(value: GlossTier.brief, label: Text('简洁')),
              ButtonSegment(value: GlossTier.full, label: Text('完整')),
            ],
            selected: {style.tier},
            onSelectionChanged: (v) => update('tier', v.first.name),
          ),
          const SizedBox(height: 18),
          const Text('主释义'),
          const SizedBox(height: 8),
          SegmentedButton<GlossLanguage>(
            key: const ValueKey('gloss-language-setting'),
            segments: const [
              ButtonSegment(value: GlossLanguage.enZh, label: Text('英汉')),
              ButtonSegment(value: GlossLanguage.enEn, label: Text('英英')),
            ],
            selected: {style.glossLanguage},
            onSelectionChanged: (v) => update('glossLanguage', v.first.name),
          ),
          const SizedBox(height: 18),
          const Text('点击气泡展开'),
          RadioGroup<GlossExpansion>(
            groupValue: style.glossExpansion,
            onChanged: (v) {
              if (v != null) update('glossExpansion', v.name);
            },
            child: Column(
              children: [
                for (final option in GlossExpansion.values)
                  RadioListTile<GlossExpansion>(
                    key: ValueKey('gloss-expansion-${option.name}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    enabled: style.tier != GlossTier.full,
                    value: option,
                    title: Text(
                      option == GlossExpansion.current ? '保持当前方式' : '查看另一种语言',
                    ),
                  ),
              ],
            ),
          ),
          if (style.tier == GlossTier.full)
            const Text(
              '完整档直接显示主释义；切回极简或简洁后恢复展开设置。',
              style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Text('极简显示释义数'),
              const Spacer(),
              SegmentedButton<int>(
                segments: [1, 2, 3]
                    .map((n) => ButtonSegment(value: n, label: Text('$n')))
                    .toList(),
                selected: {style.senses},
                onSelectionChanged: (v) => update('senses', v.first),
              ),
            ],
          ),
          const SizedBox(height: 16),
          slider('气泡字号', 'bubbleSize', style.bubbleSize, 12, 24, 12, ''),
          const Text(
            '释义按词典顺序显示。长按正文可以选句并复制。',
            style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
          ),
        ],
      ),
    );
  }
}
