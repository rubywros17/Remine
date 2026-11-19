import 'package:flutter/material.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/device/gallery_reader.dart';
import '../data/device/older_progress.dart';
import '../data/device/settings_store.dart';
import '../data/remote/remote_services.dart';
import '../widgets/settings_rows.dart';
import '../widgets/small_widgets.dart';
import 'older_range_screen.dart';
import 'older_texts.dart';

/// ⑤ 예전 스크린샷: 진행률, 오늘 남은 몫, 이어서 정리하기·Wi-Fi·충전 스위치, 분석 범위, "더 빨리 정리하기(준비 중)".
/// 남은 몫은 서버 값(저장된 older_quota)을 먼저 보이고, 들어올 때 /api/config로 한 번 갱신한다([remote]가 있을 때).
class OlderShotsScreen extends StatefulWidget {
  const OlderShotsScreen({
    super.key,
    required this.settings,
    required this.reader,
    this.remote,
  });

  final SettingsStore settings;
  final GalleryReader reader;
  final RemoteServices? remote;

  @override
  State<OlderShotsScreen> createState() => _OlderShotsScreenState();
}

class _OlderShotsScreenState extends State<OlderShotsScreen> {
  OlderOverview? _overview;
  int? _remaining;
  int _limit = olderDailyLimit;
  bool _enabled = true;
  bool _wifiOnly = true;
  bool _chargingOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshQuota();
  }

  Future<void> _load() async {
    final s = widget.settings;
    final overview = await loadOlderOverview(widget.reader, s);
    final quota = await s.olderQuota();
    final enabled = await s.olderEnabled();
    final wifi = await s.olderWifiOnly();
    final charging = await s.olderChargingOnly();
    if (!mounted) return;
    setState(() {
      _overview = overview;
      _remaining ??= quota?.remaining;
      _enabled = enabled;
      _wifiOnly = wifi;
      _chargingOnly = charging;
    });
  }

  Future<void> _refreshQuota() async {
    try {
      final q = await widget.remote?.sync.refreshOlderQuota();
      if (q == null || !mounted) return;
      setState(() {
        _remaining = q.remaining;
        if (q.limit > 0) _limit = q.limit;
      });
    } catch (_) {
      // 서버에 닿지 못하면 저장된 값 그대로(다음에 들어올 때 다시)
    }
  }

  Future<void> _openRange() async {
    final changed = await Navigator.of(context).push<bool>(
      appRoute(
        context,
        (_) => OlderRangeScreen(
          settings: widget.settings,
          reader: widget.reader,
          fromSettings: true,
        ),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final o = _overview;
    final s = widget.settings;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            8,
            4,
            AppSpacing.screenPadding,
            AppSpacing.s24,
          ),
          children: [
            Row(
              children: [
                const BackButtonCircle(),
                Expanded(
                  child: Text(
                    OlderTexts.shotsTitle,
                    style: AppText.sectionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (o != null) ...[
                    _ProgressCard(overview: o),
                    const SizedBox(height: AppSpacing.s12),
                    if (o.done || !o.scanning)
                      const _DoneCard()
                    else if (_remaining == 0)
                      _QuotaDoneCard(left: o.unseen)
                    else
                      _QuotaCard(remaining: _remaining, limit: _limit),
                  ] else
                    const SizedBox(height: 160),
                  const SizedBox(height: AppSpacing.s8),
                ],
              ),
            ),
            SwitchSettingsRow(
              title: OlderTexts.continueTitle,
              body: OlderTexts.continueBody,
              value: _enabled,
              onChanged: (v) {
                setState(() => _enabled = v);
                s.setOlderEnabled(v);
              },
            ),
            SwitchSettingsRow(
              title: OlderTexts.wifiOnly,
              value: _wifiOnly,
              onChanged: (v) {
                setState(() => _wifiOnly = v);
                s.setOlderWifiOnly(v);
              },
            ),
            SwitchSettingsRow(
              title: OlderTexts.chargingOnly,
              value: _chargingOnly,
              onChanged: (v) {
                setState(() => _chargingOnly = v);
                s.setOlderChargingOnly(v);
              },
            ),
            SettingsRow(
              title: OlderTexts.rangeRow,
              body: o == null
                  ? null
                  : '${OlderTexts.rangeName(o.kind, o.from)} · '
                        '${OlderTexts.shots(o.total)}',
              onTap: _openRange,
              trailing: const SettingsChevron(),
            ),
            const SizedBox(height: AppSpacing.s12),
            const Padding(
              padding: EdgeInsets.only(left: 14),
              child: _FasterCard(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 흰 바탕 · 연한 테두리 카드.
class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppOlder.optionRadius),
      border: Border.all(color: AppColors.border),
    ),
    child: Padding(padding: const EdgeInsets.all(AppSpacing.s16), child: child),
  );
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.overview});

  final OlderOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final percent = (o.progress * 100).floor();
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  OlderTexts.rangeName(o.kind, o.from),
                  style: AppText.label,
                ),
              ),
              Text('$percent%', style: AppText.brand()),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Semantics(
            label: '진행 $percent%',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: LinearProgressIndicator(
                value: o.progress,
                minHeight: AppOlder.barHeight,
                color: AppColors.darkGray,
                backgroundColor: AppColors.border,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            OlderTexts.progressLine(o.seen, o.total, o.seenUntil),
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

/// 오늘 몫: 연한 레몬 바탕, 테두리 없음.
class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.remaining, required this.limit});

  /// 서버에서 받은 적 없으면 null(숫자 자리 "–").
  final int? remaining;
  final int limit;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppOlder.quotaBackground,
      borderRadius: BorderRadius.circular(AppOlder.optionRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(OlderTexts.quotaLabel, style: AppText.caption),
                const SizedBox(height: AppSpacing.s4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: remaining == null
                            ? '–'
                            : formatThousands(remaining!),
                        style: AppText.brand().copyWith(fontSize: 26),
                      ),
                      TextSpan(
                        text: ' / ${formatThousands(limit)}',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            child: Text(
              OlderTexts.quotaAside,
              textAlign: TextAlign.right,
              style: AppText.caption.copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );
}

class _QuotaDoneCard extends StatelessWidget {
  const _QuotaDoneCard({required this.left});

  final int left;

  @override
  Widget build(BuildContext context) => _WhiteCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(OlderTexts.quotaDoneTitle, style: AppText.label),
        const SizedBox(height: AppSpacing.s4),
        Text(OlderTexts.quotaDoneBody, style: AppText.caption),
        const SizedBox(height: AppSpacing.s4),
        Text(OlderTexts.quotaDoneLeft(left), style: AppText.caption),
      ],
    ),
  );
}

class _DoneCard extends StatelessWidget {
  const _DoneCard();

  @override
  Widget build(BuildContext context) =>
      _WhiteCard(child: Text(OlderTexts.allDone, style: AppText.label));
}

/// 유료(준비 중): 누를 수 없다.
class _FasterCard extends StatelessWidget {
  const _FasterCard();

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${OlderTexts.faster}, ${OlderTexts.fasterBody}, ${OlderTexts.comingSoon}',
    enabled: false,
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppOlder.optionRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(OlderTexts.faster, style: AppText.label),
                  const SizedBox(height: AppSpacing.s4),
                  Text(OlderTexts.fasterBody, style: AppText.caption),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            DecoratedBox(
              key: const ValueKey('older-coming-soon'),
              decoration: BoxDecoration(
                color: AppColors.chip,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Text(OlderTexts.comingSoon, style: AppText.caption),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
