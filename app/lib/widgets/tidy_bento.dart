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
/// │ 있는 캡처 ├────────┤
/// │ (2칸)    │ 석 달째 │
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
                        title: '쌍둥이 캡처',
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
                        title: '석 달째 안 봄',
                        count: bundles.stale.length,
                        note: '3개월 넘은 캡처',
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
                  title: '갈 곳 없는 캡처',
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
          ? '비울 수 있는 캡처. 지금은 정리할 게 없어요'
          : '비울 수 있는 캡처 ${shots.length}장${size == null ? '' : ', $size 가벼워져요'}',
      onTap: empty ? null : onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '비울 수 있는 캡처',
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

/// "이번 주 비운 캡처 N장" + 요일별 막대 7개(월~일, 오늘만 진한 셀라돈).
class TidyWeek extends StatelessWidget {
  const TidyWeek({super.key, required this.counts, required this.todayIndex});

  final List<int> counts;
  final int todayIndex;

  @override
  Widget build(BuildContext context) {
    final total = counts.fold(0, (a, b) => a + b);
    final most = counts.fold(1, (a, b) => b > a ? b : a);
    return Semantics(
      label: '이번 주 비운 캡처 $total장',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('이번 주 비운 캡처', style: AppText.label),
                const SizedBox(height: AppSpacing.s4),
                // 숫자 글꼴에는 한글이 없어 "장"은 본문 글꼴로.
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$total',
                        style: AppText.numHero(size: 24),
                      ),
                      TextSpan(text: '장', style: AppText.label),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          for (final (i, c) in counts.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Container(
              key: ValueKey('week-$i'),
              width: AppTidy.weekBarWidth,
              height: c == 0
                  ? AppTidy.weekBarMin
                  : AppTidy.weekBarMin +
                        (AppTidy.weekBarHeight - AppTidy.weekBarMin) * c / most,
              decoration: BoxDecoration(
                color: i == todayIndex ? AppTidy.weekToday : AppTidy.weekOther,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
