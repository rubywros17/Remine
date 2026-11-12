import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import '../data/tidy_bundles.dart';
import '../models/screenshot_item.dart';
import 'app_button.dart';
import 'capture_thumb.dart';

/// 정리 탭 묶음 종류. 타일을 누르면 이 묶음의 그리드 화면이 열린다.
enum TidyKind { twins, stale, etc }

/// 정리 탭 벤토 그리드(디자인 캔버스 20안 O). 2열(왼쪽 1.1 : 오른쪽 1).
///
/// ```
/// ┌──────────┬────────┐
/// │ 비울 수   │ 쌍둥이  │
/// │ 있는 스크린샷 ├────────┤
/// │ (2칸)    │ 3달째 │
/// ├──────────┼────────┤
/// │ 갈 곳 없는│ 휴지통  │
/// └──────────┴────────┘
/// ```
/// 숫자가 0인 묶음 타일은 흐리고 누를 수 없다. [trashCount]가 null(가짜 데이터 모드)이면 휴지통 타일이 없다.
///
/// [Flutter 메모] IntrinsicHeight는 한 줄의 높이를 "가장 키가 큰 칸"에 맞춘다. 글자가 커져도 칸끼리 높이가
/// 같이 늘어 넘치지 않는다(대신 레이아웃을 두 번 재서 조금 비싸다 — 타일 몇 개라 괜찮다).
class TidyBento extends StatelessWidget {
  const TidyBento({
    super.key,
    required this.bundles,
    required this.onOpen,
    this.size,
    this.trashCount,
    this.onTrash,
  });

  final TidyBundles bundles;

  /// 묶음 화면 열기. null이면 "한 번에 보기"(세 묶음 전부).
  final void Function(TidyKind? kind) onOpen;

  /// "약 1.2GB". null이면 용량 줄을 숨긴다.
  final String? size;
  final int? trashCount;
  final VoidCallback? onTrash;

  @override
  Widget build(BuildContext context) {
    final all = bundles.all;
    final twins = bundles.twinExtras;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: AppTidy.leftFlex,
                child: _BigTile(
                  shots: all,
                  size: size,
                  onOpen: () => onOpen(null),
                ),
              ),
              const SizedBox(width: AppTidy.gap),
              Expanded(
                flex: AppTidy.rightFlex,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _CountTile(
                        key: const ValueKey('tidy-twins'),
                        color: AppTidy.twins,
                        title: '비슷한 스크린샷',
                        count: bundles.twinsReady ? twins.length : null,
                        note: bundles.twinsReady ? '거의 똑같아요' : '곧 찾아 드릴게요',
                        peek: twins.take(2).toList(),
                        onTap: () => onOpen(TidyKind.twins),
                      ),
                    ),
                    const SizedBox(height: AppTidy.gap),
                    Expanded(
                      child: _CountTile(
                        key: const ValueKey('tidy-stale'),
                        color: AppTidy.stale,
                        title: '3달째 안 봄',
                        count: bundles.stale.length,
                        note: '3개월 넘은 스크린샷',
                        onTap: () => onOpen(TidyKind.stale),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTidy.gap),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: AppTidy.leftFlex,
                child: _CountTile(
                  key: const ValueKey('tidy-etc'),
                  color: AppTidy.etc,
                  outlined: true,
                  title: '갈 곳 없는 스크린샷',
                  count: bundles.etc.length,
                  note: '기타 서랍',
                  onTap: () => onOpen(TidyKind.etc),
                ),
              ),
              if (trashCount != null) ...[
                const SizedBox(width: AppTidy.gap),
                Expanded(
                  flex: AppTidy.rightFlex,
                  child: _TrashTile(count: trashCount!, onTap: onTrash),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 모서리 26 타일. [enabled]가 false면 흐리고 누를 수 없다.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.color,
    required this.label,
    required this.child,
    this.outlined = false,
    this.onTap,
    this.enabled = true,
  });

  final Color color;
  final String label;
  final Widget child;

  /// 흰 타일의 1px 테두리(#E3E3DE).
  final bool outlined;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTidy.radius);
    return Opacity(
      opacity: enabled ? 1 : AppTidy.emptyOpacity,
      child: Semantics(
        button: enabled,
        enabled: enabled,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: color,
          shape: !outlined
              ? RoundedRectangleBorder(borderRadius: radius)
              : RoundedRectangleBorder(
                  borderRadius: radius,
                  side: const BorderSide(
                    color: AppTidy.etcBorder,
                    width: AppTidy.etcBorderWidth,
                  ),
                ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            highlightColor: AppColors.pressHighlight,
            splashColor: AppColors.pressSplash,
            child: Padding(
              padding: const EdgeInsets.all(AppTidy.padding),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle get _tileTitle =>
    AppText.label.copyWith(fontSize: AppTidy.tileLabel, color: AppColors.ink);
TextStyle get _tileNote => AppText.caption.copyWith(color: AppColors.ink);

/// 차콜 큰 타일: "비울 수 있는 캡처" / 레몬 큰 숫자 / 용량 / 썸네일 3장 / [한 번에 보기 →].
/// 세 묶음이 다 비면 숫자 대신 "지금은 정리할 게 없어요", 버튼 없음.
class _BigTile extends StatelessWidget {
  const _BigTile({
    required this.shots,
    required this.size,
    required this.onOpen,
  });

  final List<ScreenshotItem> shots;
  final String? size;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final empty = shots.isEmpty;
    final onDark = AppText.caption.copyWith(color: AppColors.onDarkSub);
    return _Tile(
      key: const ValueKey('tidy-all'),
      color: AppTidy.big,
      label: empty
          ? '비울 수 있는 스크린샷. 지금은 정리할 게 없어요'
          : '비울 수 있는 스크린샷 ${shots.length}장${size == null ? '' : ', $size 가벼워져요'}',
      onTap: empty ? null : onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '비울 수 있는 스크린샷',
            style: _tileTitle.copyWith(color: AppColors.white),
          ),
          const SizedBox(height: AppSpacing.s8),
          if (empty)
            Text(
              '지금은 정리할 게 없어요',
              style: AppText.sectionTitle.copyWith(color: AppColors.white),
            )
          else ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${shots.length}',
                style: AppText.numHero(
                  color: AppColors.lemon,
                  size: AppTidy.bigNumber,
                ),
              ),
            ),
            if (size != null) ...[
              const SizedBox(height: AppSpacing.s4),
              Text('$size 가벼워져요', style: onDark),
            ],
            const SizedBox(height: AppSpacing.s16),
            _Thumbs(shots: shots.take(3).toList()),
          ],
          const Spacer(),
          if (!empty) ...[
            const SizedBox(height: AppSpacing.s16),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AppButton(label: '한 번에 보기 →', onTap: onOpen),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 썸네일 몇 장을 살짝 겹치고 기울여 놓는다. 폭이 모자라면 통째로 줄어든다.
class _Thumbs extends StatelessWidget {
  const _Thumbs({required this.shots, this.scale = 1});

  final List<ScreenshotItem> shots;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (shots.isEmpty) return const SizedBox.shrink();
    const w = AppTidy.thumbWidth;
    const h = AppTidy.thumbHeight;
    const step = w - AppTidy.thumbOverlap;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: (w + step * (shots.length - 1)) * scale,
        height: h * scale,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (i, s) in shots.indexed)
              Positioned(
                left: step * i * scale,
                top: 0,
                width: w * scale,
                height: h * scale,
                child: Transform.rotate(
                  angle: AppTidy.thumbTilts[i % AppTidy.thumbTilts.length],
                  child: CaptureThumb(
                    assetId: s.localAssetId,
                    seed: s.id,
                    radius: 10,
                    size: 160,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 묶음 타일: 제목 / 숫자 / 설명. [count]가 null이면 숫자 없이 설명만(아직 준비 중). 0이거나 null이면 흐리고 못 누른다.
/// [peek]이 있으면 오른쪽 아래에 썸네일이 타일 밖으로 걸친다(잘린다).
class _CountTile extends StatelessWidget {
  const _CountTile({
    super.key,
    required this.color,
    required this.title,
    required this.count,
    required this.note,
    required this.onTap,
    this.outlined = false,
    this.peek = const [],
  });

  final Color color;
  final String title;
  final int? count;
  final String note;
  final VoidCallback onTap;
  final bool outlined;
  final List<ScreenshotItem> peek;

  @override
  Widget build(BuildContext context) {
    final n = count;
    final enabled = n != null && n > 0;
    return _Tile(
      color: color,
      outlined: outlined,
      label: n == null ? '$title. $note' : '$title $n장. $note',
      enabled: enabled,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (peek.isNotEmpty)
            Positioned(
              right: -AppTidy.padding - 6,
              bottom: -AppTidy.padding - 18,
              child: _Thumbs(shots: peek, scale: 0.8),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: _tileTitle),
              if (n != null) ...[
                const SizedBox(height: AppSpacing.s4),
                Text('$n', style: AppText.numHero(size: AppTidy.tileNumber)),
              ],
              const SizedBox(height: AppSpacing.s4),
              Text(note, style: _tileNote),
            ],
          ),
        ],
      ),
    );
  }
}

/// 연회색 휴지통 타일: 아이콘 + "휴지통" + "N장"(0이면 "0장 · 비어 있어요"). 0이어도 누를 수 있다.
class _TrashTile extends StatelessWidget {
  const _TrashTile({required this.count, required this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = count == 0 ? '0장 · 비어 있어요' : '$count장';
    return _Tile(
      key: const ValueKey('tidy-trash'),
      color: AppTidy.trash,
      label: '휴지통 $text',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.trash2, size: 22, color: AppColors.ink),
          const SizedBox(height: AppSpacing.s8),
          Text('휴지통', style: _tileTitle),
          const SizedBox(height: AppSpacing.s4),
          Text(text, style: _tileNote),
        ],
      ),
    );
  }
}

/// "이번 주 비운 스크린샷"(디자인 캔버스 D3 점선 도장).
///
/// ```
/// 이번 주 비운 스크린샷              18MB   ← 레몬 형광펜 밑줄
///                                 확보했어요
/// [■■■■■■■■■■■■■■■ 차콜 ][▨ 점선 ]   ← 남은 : 비운 (비운 쪽은 최소 9%)
/// 남은 120장                        비운 7장
///  ◌   ◍   ●   ◍   ○   ○   ○         ← 요일 도장
///  월  화  수  목  금  토  일
/// ```
/// 요일 도장: 지운 날은 점선 동그라미 + 장수, 오늘은 진한 점선 + 빗금, 안 지운 날은 연회색 원, 아직 안 온 요일은 흐리게.
class TidyWeekStamps extends StatelessWidget {
  const TidyWeekStamps({super.key, required this.week});

  final TidyWeek week;

  static const _days = ['월', '화', '수', '목', '금', '토', '일'];

  String get _semantics {
    final days = [
      for (final (i, c) in week.counts.indexed)
        if (c > 0) '${_days[i]}요일 $c장',
    ];
    return [
      '이번 주 ${week.cleared}장 비움',
      if (_freedText(week) case final freed?) '$freed 확보',
      if (days.isNotEmpty) days.join(' '),
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semantics,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '이번 주 비운 스크린샷',
                  style: AppText.label.copyWith(
                    fontSize: AppTidy.weekTitleSize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              _Freed(week: week),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          _RatioBar(cleared: week.cleared, remaining: week.remaining),
          const SizedBox(height: AppSpacing.s8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '남은 ${week.remaining}장',
                  style: AppText.caption.copyWith(color: AppColors.ink),
                ),
              ),
              Text(
                '비운 ${week.cleared}장',
                style: AppText.caption.copyWith(
                  color: AppTidy.dash,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s20),
          // 일곱 칸으로 나누고, 칸이 도장보다 좁은 아주 작은 화면에서만 도장이 줄어든다.
          Row(
            children: [
              for (final (i, c) in week.counts.indexed)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _DayStamp(
                      key: ValueKey('stamp-$i'),
                      day: _days[i],
                      count: c,
                      today: i == week.todayIndex,
                      future: i > week.todayIndex,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 확보한 용량 문구: 전부 알면 "18MB", 추정이면 "약 18MB", 0장이거나 추정할 수 없으면 null.
String? _freedText(TidyWeek week) {
  final bytes = week.estimatedBytes;
  if (week.cleared == 0 || bytes == null) return null;
  return week.sizeComplete ? freedLabel(bytes) : '약 ${freedLabel(bytes)}';
}

/// 오른쪽 위 확보한 용량(형광펜) + "확보했어요".
/// - 크기를 전부 알면 "18MB", 모르는 장이 있으면 평균으로 추정해 "약 18MB"
/// - 평균조차 낼 수 없으면 "7장" + "비웠어요"
/// - 0장이면 "아직 0MB"(회색, 형광펜 없음)
class _Freed extends StatelessWidget {
  const _Freed({required this.week});

  final TidyWeek week;

  @override
  Widget build(BuildContext context) {
    final bytes = week.estimatedBytes;
    final big = AppText.numHero(size: AppTidy.weekSizeFont);
    // 숫자 글꼴에는 한글이 없어 "장"·"아직"·"약"은 본문 글꼴로.
    final kr = AppText.label.copyWith(fontSize: AppTidy.weekSizeFont * 0.6);
    final Widget value;
    if (week.cleared == 0) {
      value = Text.rich(
        key: const ValueKey('week-freed'),
        TextSpan(
          children: [
            TextSpan(
              text: '아직 ',
              style: kr.copyWith(color: AppTidy.weekSub),
            ),
            TextSpan(
              text: '0MB',
              style: big.copyWith(color: AppTidy.weekSub),
            ),
          ],
        ),
      );
    } else {
      value = _Highlighted(
        child: Text.rich(
          key: const ValueKey('week-freed'),
          bytes == null
              ? TextSpan(
                  children: [
                    TextSpan(text: '${week.cleared}', style: big),
                    TextSpan(text: '장', style: kr),
                  ],
                )
              : TextSpan(
                  children: [
                    if (!week.sizeComplete) TextSpan(text: '약 ', style: kr),
                    TextSpan(text: freedLabel(bytes), style: big),
                  ],
                ),
        ),
      );
    }
    final counted = week.cleared > 0 && bytes == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        value,
        const SizedBox(height: 2),
        Text(
          counted ? '비웠어요' : '확보했어요',
          style: AppText.caption.copyWith(
            fontSize: AppTidy.weekSubSize,
            color: AppTidy.weekSub,
          ),
        ),
      ],
    );
  }
}

/// 글자 아래쪽에 레몬 형광펜 띠.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      const Positioned(
        key: ValueKey('week-highlight'),
        left: -2,
        right: -2,
        bottom: 0,
        height: AppTidy.weekSizeHighlight,
        child: ColoredBox(color: AppColors.lemon),
      ),
      child,
    ],
  );
}

/// 남은(차콜) : 비운(점선 + 빗금) 비율 막대. 비운 쪽은 실제 비율이 작아도 최소 [AppTidy.barMinCleared].
class _RatioBar extends StatelessWidget {
  const _RatioBar({required this.cleared, required this.remaining});

  final int cleared;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final double share;
    if (cleared == 0) {
      share = 0;
    } else if (remaining == 0) {
      share = 1;
    } else {
      share = (cleared / (cleared + remaining)).clamp(
        AppTidy.barMinCleared,
        1 - AppTidy.barMinCleared,
      );
    }
    return SizedBox(
      height: AppTidy.barHeight,
      child: LayoutBuilder(
        builder: (context, box) {
          final gap = share > 0 && share < 1 ? AppTidy.barGap : 0.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, // 막대 높이를 꽉 채운다
            children: [
              if (share < 1)
                Expanded(
                  child: DecoratedBox(
                    key: const ValueKey('bar-remaining'),
                    decoration: BoxDecoration(
                      color: AppTidy.barRemaining,
                      borderRadius: BorderRadius.circular(
                        AppTidy.barHeight / 2,
                      ),
                    ),
                  ),
                ),
              if (gap > 0) SizedBox(width: gap),
              if (share > 0)
                SizedBox(
                  key: const ValueKey('bar-cleared'),
                  width: (box.maxWidth - gap) * share,
                  child: const CustomPaint(
                    painter: _DashedPainter(
                      circle: false,
                      dash: AppTidy.dash,
                      strokeWidth: AppTidy.barDashWidth,
                      hatch: true,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 요일 도장 하나(지름 [AppTidy.stampSize]) + 아래 요일 글자.
class _DayStamp extends StatelessWidget {
  const _DayStamp({
    super.key,
    required this.day,
    required this.count,
    required this.today,
    required this.future,
  });

  final String day;
  final int count;
  final bool today;
  final bool future;

  @override
  Widget build(BuildContext context) {
    final Widget circle;
    if (today || count > 0) {
      circle = CustomPaint(
        painter: _DashedPainter(
          circle: true,
          dash: today ? AppTidy.dash : AppTidy.stampDash,
          strokeWidth: AppTidy.stampDashWidth,
          hatch: today,
        ),
        child: Center(
          child: count > 0
              ? Text(
                  '$count',
                  style: AppText.numHero(
                    size: 13,
                    color: today ? AppTidy.dash : AppColors.ink,
                  ),
                )
              : null,
        ),
      );
    } else {
      circle = const DecoratedBox(
        decoration: BoxDecoration(
          color: AppTidy.stampEmpty,
          shape: BoxShape.circle,
        ),
      );
    }
    return Opacity(
      opacity: future ? AppTidy.futureOpacity : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(dimension: AppTidy.stampSize, child: circle),
          const SizedBox(height: AppSpacing.s4),
          Text(
            day,
            style: AppText.caption.copyWith(
              fontSize: AppTidy.dayLabelSize,
              color: today ? AppTidy.dash : AppTidy.weekSub,
              fontWeight: today ? FontWeight.w800 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// 점선 테두리(동그라미 또는 둥근 막대) + 선택적으로 안쪽 셀라돈 빗금.
class _DashedPainter extends CustomPainter {
  const _DashedPainter({
    required this.circle,
    required this.dash,
    required this.strokeWidth,
    required this.hatch,
  });

  final bool circle;
  final Color dash;
  final double strokeWidth;
  final bool hatch;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = (Offset.zero & size).deflate(strokeWidth / 2);
    final shape = Path();
    if (circle) {
      shape.addOval(inset);
    } else {
      shape.addRRect(
        RRect.fromRectAndRadius(inset, Radius.circular(inset.height / 2)),
      );
    }
    if (hatch) {
      canvas
        ..save()
        ..clipPath(shape);
      final paint = Paint()
        ..color = AppTidy.hatch
        ..strokeWidth = 1.2;
      // 45° 빗금: 왼쪽 아래 → 오른쪽 위.
      for (var x = -size.height; x < size.width; x += AppTidy.hatchGap) {
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x + size.height, 0),
          paint,
        );
      }
      canvas.restore();
    }
    final stroke = Paint()
      ..color = dash
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    const step = AppTidy.dashLength + AppTidy.dashGap;
    for (final m in shape.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += step) {
        canvas.drawPath(m.extractPath(d, d + AppTidy.dashLength), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.circle != circle ||
      old.dash != dash ||
      old.strokeWidth != strokeWidth ||
      old.hatch != hatch;
}
