import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../data/device/gallery_reader.dart';
import '../data/device/privacy/local_verdict_store.dart';
import '../widgets/gallery_thumb.dart';
import '../widgets/small_widgets.dart';

/// 판정 사유 코드 → 화면에 보이는 말. 코드만 저장돼 있어서 값은 보여 줄 수 없다.
String reasonLabel(String code) => switch (code) {
  'SSN' => '주민등록번호',
  'CARD' => '카드번호',
  'ACCOUNT' => '계좌번호',
  'OTP' => '인증번호',
  'PASSWORD' => '비밀번호',
  'APP_FINANCIAL' => '금융 앱',
  'APP_PRIVATE' => '통화·연락처 앱',
  _ => code,
};

/// "분석 제외": 서버로 보내지 않고 기기에서만 분류한 숨김 캡처(강한 민감 정보, 은행·증권·카드 앱)를 모아 본다.
class ExcludedScreen extends StatelessWidget {
  const ExcludedScreen({
    super.key,
    required this.verdicts,
    required this.reader,
  });

  final LocalVerdictStore verdicts;
  final GalleryReader reader;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                8,
                4,
                AppSpacing.screenPadding,
                0,
              ),
              child: Row(
                children: [
                  const BackButtonCircle(),
                  Expanded(
                    child: Text(
                      '분석 제외',
                      style: AppText.sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.s4,
                AppSpacing.screenPadding,
                AppSpacing.s12,
              ),
              child: Text(
                '서버로 보내지 않고 이 폰 안에서만 분류한 캡처예요.',
                style: AppText.caption,
              ),
            ),
            Expanded(
              child: FutureBuilder<List<StoredVerdict>>(
                future: verdicts.deviceOnly(hidden: true),
                builder: (context, snap) {
                  final items = snap.data;
                  if (items == null) return const SizedBox.shrink();
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.screenPadding),
                        child: Text(
                          '분석에서 제외된 캡처가 없어요.',
                          style: AppText.body,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding,
                      0,
                      AppSpacing.screenPadding,
                      AppSpacing.s24,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 130,
                          mainAxisSpacing: AppSpacing.s12,
                          crossAxisSpacing: 6,
                          childAspectRatio: 0.62,
                        ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _ExcludedTile(
                      reader: reader,
                      verdict: items[i],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExcludedTile extends StatelessWidget {
  const _ExcludedTile({required this.reader, required this.verdict});

  final GalleryReader reader;
  final StoredVerdict verdict;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.tile),
            child: SizedBox.expand(
              child: GalleryThumb(reader: reader, photoId: verdict.assetId),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          verdict.reasons.map(reasonLabel).join(' · '),
          style: AppText.caption,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
