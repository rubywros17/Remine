import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/device/gallery_reader.dart';
import '../data/device/older_progress.dart';
import '../data/device/settings_store.dart';
import '../data/remote/remote_services.dart';
import '../widgets/app_button.dart';
import '../widgets/home_widgets.dart' show DashedBorderPainter;
import '../widgets/pressable_scale.dart';
import '../widgets/small_widgets.dart';
import 'older_texts.dart';

/// 첫 실행에서 알림 안내 다음, 첫 분석 전에 한 번 범위를 고르게 한다(사진 권한 → 이미지 동의 → 알림 → **범위** → 첫 분석).
/// 이미 첫 분석을 마친 기기(업데이트)나 범위를 고른 기기는 묻지 않는다 — 그때는 설정·관심사 탭에서 고른다.
class RangeGate extends StatefulWidget {
  const RangeGate({
    super.key,
    required this.remote,
    required this.settings,
    required this.reader,
    required this.child,
  });

  final RemoteServices remote;
  final SettingsStore settings;
  final GalleryReader reader;
  final Widget child;

  @override
  State<RangeGate> createState() => _RangeGateState();
}

class _RangeGateState extends State<RangeGate> {
  bool _loaded = false;
  bool _ask = false;

  @override
  void initState() {
    super.initState();
    () async {
      final ask =
          await widget.settings.olderRangeFrom() == null &&
          !await widget.remote.state.firstSyncDone();
      if (mounted) {
        setState(() {
          _ask = ask;
          _loaded = true;
        });
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (!_ask) return widget.child;
    return OlderRangeScreen(
      settings: widget.settings,
      reader: widget.reader,
      onDone: () => setState(() => _ask = false),
    );
  }
}

/// ① 어디까지 정리할까요? 첫 실행([onDone]이 첫 분석으로) 또는 설정에서([fromSettings], 저장 후 뒤로).
class OlderRangeScreen extends StatefulWidget {
  const OlderRangeScreen({
    super.key,
    required this.settings,
    required this.reader,
    this.onDone,
    this.fromSettings = false,
    this.now,
  });

  final SettingsStore settings;
  final GalleryReader reader;

  /// 저장한 뒤. 없으면 뒤로 간다(설정에서 들어왔을 때).
  final VoidCallback? onDone;
  final bool fromSettings;
  final DateTime Function()? now;

  @override
  State<OlderRangeScreen> createState() => _OlderRangeScreenState();
}

/// 최근 300장을 분석하는 데 드는 시간을 셀 때 장당 초(첫 분석 실측 기준 약 0.8초 → 300장 약 4분).
/// ponytail: 고정 추정값. 서버 호출 간격이 바뀌면 함께 바꾼다.
const _secondsPerShot = 0.8;

class _OlderRangeScreenState extends State<OlderRangeScreen> {
  OlderRangeCounts? _counts;
  OlderRangeKind _kind = OlderRangeKind.year;

  /// 직접 고른 달 수와 그 장수(직접 고르기 카드에 보인다).
  int? _customMonths;
  bool _saving = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = await loadOlderRangeCounts(widget.reader, _now);
    final stored = await widget.settings.olderRangeKind();
    if (!mounted) return;
    setState(() {
      _counts = counts;
      if (stored != null && stored != OlderRangeKind.custom) _kind = stored;
    });
  }

  Future<void> _openCustom() async {
    final counts = _counts;
    if (counts == null) return;
    final months = await showModalBottomSheet<({int? months})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      builder: (_) => OlderCustomRangeSheet(
        counts: counts,
        now: _now,
        initial: _customMonths ?? 9,
      ),
    );
    if (months == null || !mounted) return;
    setState(() {
      if (months.months == null) {
        _kind = OlderRangeKind.all; // 슬라이더 "전부" = 전부 카드
        _customMonths = null;
      } else {
        _kind = OlderRangeKind.custom;
        _customMonths = months.months;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    final from = switch (_kind) {
      OlderRangeKind.year => monthsAgo(_now, 12),
      OlderRangeKind.custom => monthsAgo(_now, _customMonths!),
      _ => null,
    };
    await widget.settings.setOlderRange(_kind, from: from);
    if (!mounted) return;
    final done = widget.onDone;
    if (done != null) {
      done();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _counts;
    final recentShots = c == null ? null : math.min(olderRecentShots, c.all);
    final minutes = recentShots == null
        ? null
        : math.max(1, (recentShots * _secondsPerShot / 60).ceil());
    final year = c?.year;
    final custom = _customMonths == null ? null : c?.byMonths[_customMonths];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  widget.fromSettings ? 8 : AppSpacing.screenPadding,
                  widget.fromSettings ? 4 : AppSpacing.s32,
                  AppSpacing.screenPadding,
                  AppSpacing.s20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.fromSettings) const BackButtonCircle(),
                    Padding(
                      padding: EdgeInsets.only(
                        left: widget.fromSettings ? 14 : 0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(OlderTexts.rangeTitle, style: AppText.display),
                          const SizedBox(height: AppSpacing.s12),
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: OlderTexts.rangeIntroBefore,
                                ),
                                TextSpan(
                                  text: c == null
                                      ? '총 …장'
                                      : OlderTexts.rangeIntroCount(c.all),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const TextSpan(
                                  text:
                                      '${OlderTexts.rangeIntroAfter}\n'
                                      '${OlderTexts.rangeIntroRest}',
                                ),
                              ],
                            ),
                            style: AppText.body.copyWith(
                              color: AppColors.inkSub,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s20),
                          OlderRangeOption(
                            key: const ValueKey('older-option-recent'),
                            title: OlderTexts.recent300,
                            badge: const _Badge(
                              OlderTexts.recent300Badge,
                              background: AppColors.celadonSoft,
                              color: AppColors.celadonDeep,
                            ),
                            sub: c == null
                                ? null
                                : OlderTexts.recentMonths(c.recentMonths),
                            trailingTop: minutes == null
                                ? null
                                : OlderTexts.minutes(minutes),
                            trailingBottom: OlderTexts.todayDone,
                            selected: _kind == OlderRangeKind.recent300,
                            onTap: () => setState(
                              () => _kind = OlderRangeKind.recent300,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s12),
                          OlderRangeOption(
                            key: const ValueKey('older-option-year'),
                            title: OlderTexts.year,
                            badge: const _Badge(
                              OlderTexts.yearBadge,
                              background: AppColors.lemon,
                              color: AppColors.ink,
                            ),
                            sub: year == null ? null : OlderTexts.shots(year),
                            trailingTop: year == null
                                ? null
                                : OlderTexts.days(olderDaysFor(year)),
                            trailingBottom: OlderTexts.perDay,
                            selected: _kind == OlderRangeKind.year,
                            onTap: () =>
                                setState(() => _kind = OlderRangeKind.year),
                          ),
                          const SizedBox(height: AppSpacing.s12),
                          OlderRangeOption(
                            key: const ValueKey('older-option-all'),
                            title: OlderTexts.all,
                            sub: c == null ? null : OlderTexts.shots(c.all),
                            trailingTop: c == null
                                ? null
                                : OlderTexts.days(olderDaysFor(c.all)),
                            trailingBottom: OlderTexts.perDay,
                            selected: _kind == OlderRangeKind.all,
                            onTap: () =>
                                setState(() => _kind = OlderRangeKind.all),
                          ),
                          const SizedBox(height: AppSpacing.s12),
                          _kind == OlderRangeKind.custom && custom != null
                              ? OlderRangeOption(
                                  key: const ValueKey('older-option-custom'),
                                  title: OlderTexts.customChosen(
                                    monthsAgo(_now, _customMonths!),
                                    custom,
                                  ),
                                  trailingTop: OlderTexts.days(
                                    olderDaysFor(custom),
                                  ),
                                  trailingBottom: OlderTexts.perDay,
                                  selected: true,
                                  onTap: _openCustom,
                                )
                              : _CustomCard(onTap: _openCustom),
                          const SizedBox(height: AppSpacing.s16),
                          const _Note(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                0,
                AppSpacing.screenPadding,
                AppSpacing.s16,
              ),
              child: SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: widget.fromSettings
                      ? OlderTexts.confirm
                      : OlderTexts.start,
                  dark: true,
                  onTap: c == null ? null : _save,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 선택지 카드. 고르면 차콜 바탕 + 흰 글자(보조 70%) + 레몬 라디오, 아니면 바탕색 + 연한 테두리 + 회색 라디오.
/// 장수를 세는 동안([sub]·[trailingTop]이 null) 그 자리는 회색 막대(스켈레톤).
class OlderRangeOption extends StatelessWidget {
  const OlderRangeOption({
    super.key,
    required this.title,
    this.badge,
    this.sub,
    this.trailingTop,
    this.trailingBottom,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final Widget? badge;
  final String? sub;
  final String? trailingTop;
  final String? trailingBottom;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final main = selected ? AppColors.white : AppColors.ink;
    final subColor = selected ? AppOlder.onSelectedSub : AppColors.inkSub;
    final label = [
      title,
      ?sub,
      if (trailingBottom != null && trailingTop != null)
        '$trailingBottom $trailingTop'
      else
        ?trailingTop,
      if (selected) '선택됨',
    ].join(', ');
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.duration(context, MotionDuration.fast),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s16,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.darkGray : AppColors.background,
            borderRadius: BorderRadius.circular(AppOlder.optionRadius),
            border: Border.all(
              color: selected ? AppColors.darkGray : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              _Radio(selected: selected),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.s8,
                      runSpacing: AppSpacing.s4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: AppText.label.copyWith(
                            fontSize: 16,
                            color: main,
                          ),
                        ),
                        ?badge,
                      ],
                    ),
                    if (sub != null || trailingTop == null) ...[
                      const SizedBox(height: AppSpacing.s4),
                      sub == null
                          ? const _Skeleton(width: 56)
                          : Text(
                              sub!,
                              style: AppText.caption.copyWith(color: subColor),
                            ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  trailingTop == null
                      ? const _Skeleton(width: 32)
                      : Text(
                          trailingTop!,
                          style: AppText.label.copyWith(color: main),
                        ),
                  if (trailingBottom != null) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      trailingBottom!,
                      style: AppText.caption.copyWith(
                        fontSize: 11,
                        color: subColor,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: AppOlder.radio,
    height: AppOlder.radio,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: selected ? AppColors.lemon : AppColors.border,
        width: 2,
      ),
    ),
    child: selected
        ? Container(
            width: AppOlder.radioDot,
            height: AppOlder.radioDot,
            decoration: const BoxDecoration(
              color: AppColors.lemon,
              shape: BoxShape.circle,
            ),
          )
        : null,
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.background, required this.color});

  final String text;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        text,
        style: AppText.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ),
  );
}

/// 장수를 세는 동안 숫자 자리.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 12,
    decoration: BoxDecoration(
      color: AppColors.chip,
      borderRadius: BorderRadius.circular(6),
    ),
  );
}

class _CustomCard extends StatelessWidget {
  const _CustomCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: OlderTexts.custom,
    excludeSemantics: true,
    child: PressableScale(
      onTap: onTap,
      child: CustomPaint(
        painter: const DashedBorderPainter(radius: AppOlder.optionRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s16,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  OlderTexts.custom,
                  style: AppText.label.copyWith(fontSize: 16),
                ),
              ),
              Text('›', style: AppText.label.copyWith(color: AppColors.inkSub)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppOlder.noteBackground,
      borderRadius: BorderRadius.circular(AppOlder.noteRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Text.rich(
        const TextSpan(
          children: [
            TextSpan(text: OlderTexts.noteBefore),
            TextSpan(
              text: OlderTexts.noteBold,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: OlderTexts.noteAfter),
          ],
        ),
        style: AppText.caption.copyWith(color: AppColors.ink, height: 1.5),
      ),
    ),
  );
}

/// ② 기간 직접 고르기 바텀시트. 고른 달 수를 돌려준다(전부면 months null). 닫으면 null.
class OlderCustomRangeSheet extends StatefulWidget {
  const OlderCustomRangeSheet({
    super.key,
    required this.counts,
    required this.now,
    this.initial = 9,
  });

  final OlderRangeCounts counts;
  final DateTime now;

  /// 처음 놓을 눈금(달 수). 없으면 9달.
  final int initial;

  @override
  State<OlderCustomRangeSheet> createState() => _OlderCustomRangeSheetState();
}

class _OlderCustomRangeSheetState extends State<OlderCustomRangeSheet> {
  late int _index = math.max(0, olderSliderMonths.indexOf(widget.initial));

  int? get _months => olderSliderMonths[_index];
  int get _count => _months == null
      ? widget.counts.all
      : widget.counts.byMonths[_months] ?? widget.counts.all;

  @override
  Widget build(BuildContext context) {
    final months = _months;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.s12,
          AppSpacing.screenPadding,
          AppSpacing.s16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            Text(OlderTexts.sheetTitle, style: AppText.sectionTitle),
            const SizedBox(height: AppSpacing.s20),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: formatThousands(_count),
                    style: AppText.numXL(color: AppColors.celadonDeep),
                  ),
                  TextSpan(
                    text: OlderTexts.shotUnit,
                    style: AppText.label.copyWith(
                      fontSize: 18,
                      color: AppColors.celadonDeep,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              OlderTexts.sheetFrom(
                months == null ? null : monthsAgo(widget.now, months),
                _count,
              ),
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.s20),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: AppOlder.sliderTrackHeight,
                activeTrackColor: AppOlder.sliderFill,
                inactiveTrackColor: AppOlder.sliderTrack,
                thumbShape: const _RingThumb(),
                overlayShape: SliderComponentShape.noOverlay,
                tickMarkShape: SliderTickMarkShape.noTickMark,
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              // 화면 리더: "9달 전부터 1,640장"
              child: Semantics(
                label: OlderTexts.sliderLabel(months, _count),
                child: Slider(
                  value: _index.toDouble(),
                  max: olderSliderMonths.length - 1.0,
                  divisions: olderSliderMonths.length - 1,
                  semanticFormatterCallback: (_) =>
                      OlderTexts.sliderLabel(months, _count),
                  onChanged: (v) => setState(() => _index = v.round()),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final (i, m) in olderSliderMonths.indexed)
                    Text(
                      OlderTexts.tick(m),
                      style: AppText.caption.copyWith(
                        color: i == _index ? AppColors.ink : AppColors.inkSub,
                        fontWeight: i == _index
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            AppButton(
              label: OlderTexts.confirm,
              dark: true,
              onTap: () => Navigator.of(context).pop((months: months)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 흰 원 + 검정 테두리 손잡이.
class _RingThumb extends SliderComponentShape {
  const _RingThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(AppOlder.sliderThumbRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center,
      AppOlder.sliderThumbRadius,
      Paint()..color = AppColors.white,
    );
    canvas.drawCircle(
      center,
      AppOlder.sliderThumbRadius - AppOlder.sliderThumbStroke / 2,
      Paint()
        ..color = AppOlder.sliderThumbBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppOlder.sliderThumbStroke,
    );
  }
}
