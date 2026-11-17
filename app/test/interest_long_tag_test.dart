import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/interest.dart';
import 'package:remine/widgets/home_widgets.dart';
import 'package:remine/widgets/small_widgets.dart';

/// 긴 태그는 실제 글자 폭이 중요해서 앱 폰트(Pretendard)를 불러와 잰다.
/// (테스트 기본 폰트는 한글 한 글자가 글자 크기만큼 넓어 실제보다 훨씬 길다.)
Interest _interest(String tag, {required int dormantDays}) => Interest(
  tag: tag,
  category: Category.etc,
  forgotten: dormantDays > Interest.defaultRecentDays,
  captureCount: 12,
  dormantDays: dormantDays,
  peakMonth: 9,
  peakMonthCount: 12,
  latestMonth: 11,
  latestMonthCount: 12,
  recent: [
    for (var i = 0; i < 3; i++) InterestCapture(id: i + 1, localAssetId: 'a$i'),
  ],
);

Widget _card(
  Interest i, {
  double width = 360,
  double scale = 1.0,
  InterestCardVariant variant = InterestCardVariant.list,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: width - 2 * AppSpacing.screenPadding,
          child: InterestCard(interest: i, onTap: () {}, variant: variant),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final f in [
      'assets/fonts/Pretendard-Regular.otf',
      'assets/fonts/Pretendard-SemiBold.otf',
      'assets/fonts/Pretendard-Bold.otf',
    ]) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
      );
    }
    await loader.load();
  });

  group('긴 태그 한 줄', () {
    for (final tag in ['데스크테리어', '프로필사진', '홈카페인테리어']) {
      for (final (width, scale) in const [
        (360.0, 1.0),
        (412.0, 1.0),
        (360.0, 1.3),
      ]) {
        testWidgets(
          '#$tag · 폭 $width 글자 $scale: 한 줄, 줄여서 맞추고(최소 60%) 말줄임은 최소 크기에서만',
          (tester) async {
            for (final (dormant, variant) in [
              for (final d in const [52, 1])
                for (final v in InterestCardVariant.values) (d, v),
            ]) {
              await tester.pumpWidget(
                _card(
                  _interest(tag, dormantDays: dormant),
                  width: width,
                  scale: scale,
                  variant: variant,
                ),
              );
              final finder = find.text('#$tag');
              final paragraph = tester.renderObject<RenderParagraph>(finder);
              final size = tester.widget<Text>(finder).style!.fontSize!;
              expect(size, inInclusiveRange(30 * 0.6, 30));
              expect(
                tester.getSize(finder).height,
                lessThan(30 * scale * 1.15 * 1.5),
                reason: '한 줄',
              );
              // 기본 글자 크기에서는 세 태그 모두 줄여서 들어간다. 큰 글꼴에서는 최소 크기일 때만 말줄임.
              if (scale == 1.0 || size > 30 * 0.6) {
                expect(paragraph.didExceedMaxLines, isFalse, reason: '말줄임 없음');
              }
            }
          },
        );
      }
    }

    testWidgets('최소 크기로도 넘치면 그때만 말줄임', (tester) async {
      await tester.pumpWidget(
        _card(_interest('아주아주긴관심사이름이라한줄에절대안들어가는태그', dormantDays: 1)),
      );
      final finder = find.text('#아주아주긴관심사이름이라한줄에절대안들어가는태그');
      expect(tester.widget<Text>(finder).style!.fontSize, 30 * 0.6);
      expect(
        tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
        isTrue,
      );
    });
  });

  // 폭 360(360×800)에서 홈 상태 스티커가 글자 1.0·1.3배 모두 한 줄로 글자 영역(콜라주 앞) 안에 들어간다.
  for (final scale in const [1.0, 1.3]) {
    testWidgets('360×800 ×$scale: 홈 "잊었던 관심사" 스티커가 한 줄, 글자 영역 안, SHOTS와 안 겹침', (
      tester,
    ) async {
      await tester.pumpWidget(
        _card(
          _interest('뜨개질', dormantDays: 52),
          scale: scale,
          variant: InterestCardVariant.home,
        ),
      );
      final label = find.text('잊었던 관심사');
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse,
      );
      expect(
        tester.getSize(label).height,
        lessThan(13 * scale * 1.6),
        reason: '한 줄',
      );
      final sticker = tester.getRect(find.byType(Sticker));
      final card = tester.getRect(find.byType(InterestCard));
      final shots = tester.getRect(find.byKey(const ValueKey('shots-sticker')));
      expect(sticker.overlaps(shots), isFalse);
      expect(
        sticker.right,
        lessThanOrEqualTo(card.right - card.width * 0.36 - 16),
        reason: '콜라주 앞',
      );
    });
  }
}
