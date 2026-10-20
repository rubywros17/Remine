import '../models/category.dart';
import '../models/screenshot_item.dart';

/// 가짜 샘플 30개(쇼핑 6 + 나머지 6개 카테고리 각 4). 실제 스크린샷은 쓰지 않는다.
/// 날짜는 [now] 기준 며칠 전으로 만들어 홈 문구("N일째 잠자는 중")가 항상 같게 나온다.
/// "니트가디건" 태그 4개가 잊은 관심사 카드의 재료다(가장 최근 것이 9일 전).
List<ScreenshotItem> buildFakeScreenshots(DateTime now) {
  DateTime ago(int days, int hour, int minute) =>
      DateTime(now.year, now.month, now.day - days, hour, minute);

  // 한 줄 = (카테고리, 출처 앱, 며칠 전, 시, 분, 요약, 태그)
  final rows = <(Category, String, int, int, int, String, List<String>)>[
    (
      Category.shopping,
      'COUPANG',
      9,
      14,
      14,
      '니트 가디건, 장바구니에 담아두고 잊은 그거',
      ['니트가디건', '겨울옷', '39,000원', '무료배송'],
    ),
    (
      Category.shopping,
      'MUSINSA',
      10,
      21,
      3,
      '니트 가디건 색상 비교해 두었던 화면',
      ['니트가디건', '색상비교'],
    ),
    (
      Category.shopping,
      'NAVER',
      12,
      9,
      40,
      '가디건 후기만 모아 본 페이지',
      ['니트가디건', '후기'],
    ),
    (Category.shopping, '29CM', 13, 23, 5, '베이지 가디건 재입고 알림', ['니트가디건', '재입고']),
    (Category.shopping, 'COUPANG', 3, 18, 22, '무선 이어폰 최저가 비교', ['이어폰', '최저가']),
    (Category.shopping, '당근', 5, 12, 8, '캠핑 의자 할인 정보', ['캠핑', '할인']),
    (
      Category.entertainment,
      'Netflix',
      2,
      22,
      30,
      '이번 주 공개된 드라마 시즌2 정리',
      ['드라마', '넷플릭스'],
    ),
    (
      Category.entertainment,
      'Instagram',
      6,
      20,
      15,
      '이번 달 뮤지컬 라인업',
      ['뮤지컬', '공연'],
    ),
    (
      Category.entertainment,
      'Instagram',
      8,
      11,
      50,
      '주말에 가보고 싶은 전시 포스터',
      ['전시', '주말'],
    ),
    (
      Category.entertainment,
      'NAVER',
      15,
      19,
      2,
      '곧 개봉하는 영화 목록',
      ['영화', '개봉예정'],
    ),
    (
      Category.place,
      'Instagram',
      1,
      13,
      25,
      '성수동 브런치 카페 메뉴판',
      ['성수', '카페', '브런치'],
    ),
    (Category.place, 'NAVER', 4, 17, 45, '홍대 맛집 웨이팅 팁', ['맛집', '홍대']),
    (Category.place, 'Instagram', 11, 10, 10, '제주 숙소 후보 세 곳', ['제주', '숙소']),
    (Category.place, 'NAVER', 16, 8, 30, '동네 빵집 영업시간 안내', ['빵집', '영업시간']),
    (Category.info, 'Chrome', 2, 15, 5, '엑셀 단축키 모음', ['엑셀', '꿀팁']),
    (Category.info, 'Instagram', 7, 22, 40, '겨울철 보일러 절약하는 방법', ['꿀팁', '절약']),
    (Category.info, 'Instagram', 14, 7, 55, '자주 틀리는 영어 표현 정리', ['영어', '공부']),
    (Category.info, 'Chrome', 18, 16, 20, '자격증 접수 일정 안내', ['자격증', '공부']),
    (Category.chat, 'KakaoTalk', 0, 12, 12, '친구랑 약속 잡던 대화', ['약속', '친구']),
    (Category.chat, 'KakaoTalk', 5, 20, 33, '엄마가 보내준 레시피', ['레시피', '가족']),
    (Category.chat, 'KakaoTalk', 9, 9, 9, '모임 단톡 공지', ['공지', '모임']),
    (Category.chat, 'KakaoTalk', 17, 21, 47, '선물 고민하던 대화', ['선물', '생일']),
    (Category.schedule, 'Gallery', 3, 10, 0, '치과 예약 확인 문자', ['예약', '병원']),
    (Category.schedule, 'Gmail', 7, 14, 36, '항공권 체크인 안내', ['항공권', '체크인']),
    (Category.schedule, 'Slack', 10, 17, 18, '팀 회식 일정 공지', ['회식', '일정']),
    (Category.schedule, 'Interpark', 19, 11, 11, '콘서트 티켓팅 날짜', ['티켓팅', '콘서트']),
    (Category.etc, 'Twitter', 4, 23, 59, '저장해 둔 웃긴 밈', ['밈', '웃김']),
    (Category.etc, 'Pinterest', 8, 18, 1, '배경화면 후보', ['배경화면', '감성']),
    (Category.etc, 'Keep', 13, 6, 45, '갑자기 떠오른 아이디어 메모', ['메모', '아이디어']),
    (Category.etc, 'Gallery', 20, 13, 13, '영수증 사진', ['영수증']),
  ];

  return [
        for (var i = 0; i < rows.length; i++)
          ScreenshotItem(
            id: i + 1,
            localAssetId: 'fake-${(i + 1).toString().padLeft(3, '0')}',
            takenAt: ago(rows[i].$3, rows[i].$4, rows[i].$5),
            sourceApp: rows[i].$2,
            category: rows[i].$1,
            summary: rows[i].$6,
            tags: rows[i].$7,
            autoCategory: rows[i].$1,
            categorySource: CategorySource.auto,
          ),
      ]
      // 한 건은 사용자가 이미 고친 것으로 둔다(AI는 정보라고 했지만 사용자가 장소로 옮김).
      .map(
        (s) => s.summary == '동네 빵집 영업시간 안내'
            ? ScreenshotItem(
                id: s.id,
                localAssetId: s.localAssetId,
                takenAt: s.takenAt,
                sourceApp: s.sourceApp,
                category: Category.place,
                summary: s.summary,
                tags: s.tags,
                autoCategory: Category.info,
                categorySource: CategorySource.user,
              )
            : s,
      )
      .toList();
}
