package com.remine.server.service;

import com.remine.server.classifier.RemineProperties;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.interest.InterestStatus;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.InterestRow;
import com.remine.server.domain.screenshot.ScreenshotTagRepository;
import com.remine.server.dto.InterestResponse;
import com.remine.server.exception.DeviceNotFoundException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Clock;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.tuple;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class InterestServiceTest {

    static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");
    static final LocalDateTime NOW = LocalDateTime.of(2026, 10, 22, 12, 0);

    @Mock DeviceRepository deviceRepository;
    @Mock ScreenshotTagRepository screenshotTagRepository;

    private InterestService service;
    private long nextScreenshotId = 1;

    static RemineProperties properties(int recentDays, int minCount, int cooldownDays, String... broadTags) {
        return new RemineProperties(null, null, null, null, new RemineProperties.Tags(List.of()),
                new RemineProperties.Interest(recentDays, minCount, cooldownDays, List.of(broadTags)));
    }

    @BeforeEach
    void setUp() {
        service = new InterestService(deviceRepository, screenshotTagRepository, properties(30, 3, 28, "#패션"),
                Clock.fixed(NOW.atZone(SEOUL).toInstant(), SEOUL));
    }

    private InterestRow row(long tagId, String tag, Category category, int daysAgo) {
        long id = nextScreenshotId++;
        return new InterestRow(tagId, tag, id, "asset-" + id, category, NOW.minusDays(daysAgo).minusMinutes(id));
    }

    private InterestRow[] rows(long tagId, String tag, int... daysAgo) {
        InterestRow[] rows = new InterestRow[daysAgo.length];
        for (int i = 0; i < daysAgo.length; i++) {
            rows[i] = row(tagId, tag, Category.ETC, daysAgo[i]);
        }
        return rows;
    }

    // 저장소처럼 최신순으로 돌려준다.
    private void givenRows(InterestRow... rows) {
        List<InterestRow> sorted = new ArrayList<>(List.of(rows));
        sorted.sort(Comparator.comparing(InterestRow::takenAt).reversed());
        when(screenshotTagRepository.findInterestRows(1L)).thenReturn(sorted);
    }

    private static InterestRow[] concat(InterestRow[]... groups) {
        return java.util.Arrays.stream(groups).flatMap(java.util.Arrays::stream).toArray(InterestRow[]::new);
    }

    @Test
    void 기간_제한_없이_오래된_캡처도_센다_쿼리는_한_번() {
        givenRows(rows(1, "집들이선물", 34, 40, 200));

        assertThat(service.detect(1L, NOW)).singleElement().satisfies(d -> {
            assertThat(d.captureCount()).isEqualTo(3);
            assertThat(d.status()).isEqualTo(InterestStatus.FORGOTTEN);
            assertThat(d.dormantDays()).isEqualTo(34);
        });
        verify(screenshotTagRepository, times(1)).findInterestRows(1L);
    }

    @Test
    void 마지막_캡처가_30일_이내면_RECENT_넘으면_FORGOTTEN() {
        givenRows(concat(rows(1, "경계안", 30, 31, 32), rows(2, "경계밖", 31, 32, 33)));

        assertThat(service.detect(1L, NOW)).extracting(InterestService.Detected::tag, InterestService.Detected::status)
                .containsExactly(tuple("경계밖", InterestStatus.FORGOTTEN), tuple("경계안", InterestStatus.RECENT));
    }

    @Test
    void 같은_태그가_minCount번_이상이어야_관심사다() {
        givenRows(concat(rows(1, "가디건", 1, 2, 3), rows(2, "드라마", 1, 2)));

        assertThat(service.detect(1L, NOW)).extracting(InterestService.Detected::tag).containsExactly("가디건");
    }

    @Test
    void 넓은_태그는_관심사에서_뺀다_표기만_달라도() {
        givenRows(concat(rows(1, "패 션", 1, 2, 3, 4), rows(2, "가디건", 1, 2, 3)));

        assertThat(service.detect(1L, NOW)).extracting(InterestService.Detected::tag).containsExactly("가디건");
    }

    @Test
    void 가장_많이_캡처한_달과_그_장수_마지막_달_장수() {
        // NOW = 10/22. 9월 3장(9/1·9/10·9/20), 8월 1장, 10월 1장(10/2) → peak 9월 3장, 마지막 달(10월) 1장.
        givenRows(rows(1, "코바늘도안", 20, 42, 32, 51, 60));

        InterestService.Detected d = service.detect(1L, NOW).get(0);

        assertThat(d.peakMonth()).isEqualTo(YearMonth.of(2026, 9));
        assertThat(d.peakMonthCount()).isEqualTo(3);
        assertThat(d.latestMonthCount()).isEqualTo(1);
    }

    @Test
    void 가장_많은_달이_동점이면_최근_달() {
        // 8월 2장(8/10·8/20), 9월 2장(9/10·9/20)
        givenRows(rows(1, "코바늘도안", 32, 42, 63, 73));

        assertThat(service.detect(1L, NOW).get(0).peakMonth()).isEqualTo(YearMonth.of(2026, 9));
    }

    @Test
    void 대표_카테고리는_현재_카테고리의_최빈값이다_사용자_수정_반영() {
        // 모델은 SHOPPING이라 했지만 사용자가 두 장을 INFO로 고쳤다(행의 category는 현재 값).
        givenRows(row(1, "가디건", Category.INFO, 1), row(1, "가디건", Category.SHOPPING, 2),
                row(1, "가디건", Category.INFO, 3));

        assertThat(service.detect(1L, NOW).get(0).category()).isEqualTo(Category.INFO);
    }

    @Test
    void 카테고리_동점이면_가장_최근_캡처의_카테고리() {
        givenRows(row(1, "가디건", Category.PLACE, 1), row(1, "가디건", Category.SHOPPING, 2),
                row(1, "가디건", Category.SHOPPING, 3), row(1, "가디건", Category.PLACE, 4));

        assertThat(service.detect(1L, NOW).get(0).category()).isEqualTo(Category.PLACE);
    }

    @Test
    void FORGOTTEN_장수순_오래된순_다음_RECENT_장수순_최근순() {
        givenRows(concat(
                rows(1, "잊은셋_40일", 40, 41, 42),
                rows(2, "잊은셋_90일", 90, 91, 92),
                rows(3, "잊은넷", 35, 36, 37, 38),
                rows(4, "요즘셋_5일", 5, 6, 7),
                rows(5, "요즘셋_1일", 1, 6, 7),
                rows(6, "요즘다섯", 9, 9, 9, 9, 9)));

        assertThat(service.detect(1L, NOW)).extracting(InterestService.Detected::tag).containsExactly(
                "잊은넷", "잊은셋_90일", "잊은셋_40일", "요즘다섯", "요즘셋_1일", "요즘셋_5일");
    }

    @Test
    void 응답은_상태_전체_장수_달_정보와_최근_3장_최신순을_담는다() {
        InterestRow newest = row(1, "가디건", Category.SHOPPING, 9);
        InterestRow second = row(1, "가디건", Category.SHOPPING, 10);
        InterestRow third = row(1, "가디건", Category.SHOPPING, 11);
        givenRows(row(1, "가디건", Category.SHOPPING, 40), third, newest, second);
        when(deviceRepository.existsById(1L)).thenReturn(true);

        InterestResponse response = service.list(1L);
        InterestResponse.Item item = response.items().get(0);

        assertThat(response.recentDays()).isEqualTo(30);
        assertThat(response.minCount()).isEqualTo(3);
        assertThat(item.tag()).isEqualTo("가디건");
        assertThat(item.status()).isEqualTo(InterestStatus.RECENT);
        assertThat(item.captureCount()).isEqualTo(4);
        assertThat(item.dormantDays()).isEqualTo(9);
        assertThat(item.peakMonth()).isEqualTo(10);
        assertThat(item.peakMonthCount()).isEqualTo(3);
        assertThat(item.latestMonth()).isEqualTo(10);
        assertThat(item.latestMonthCount()).isEqualTo(3);
        assertThat(item.recent()).extracting(InterestResponse.Capture::id)
                .containsExactly(newest.screenshotId(), second.screenshotId(), third.screenshotId());
        assertThat(item.recent().get(0).localAssetId()).isEqualTo(newest.localAssetId());
        assertThat(item.recent().get(0).takenAt()).isEqualTo(newest.takenAt());
    }

    @Test
    void 같은_캡처에_함께_붙은_관심사끼리_linkedTags로_잇는다() {
        // 뜨개질·도안은 캡처 101·102를 공유, 코스터는 따로. 한 번뿐인 "실"은 관심사가 아니라 연결에서 빠진다.
        givenRows(
                on(101, 1, "뜨개질", 1), on(102, 1, "뜨개질", 2), on(103, 1, "뜨개질", 3), on(104, 1, "뜨개질", 4),
                on(101, 2, "도안", 1), on(102, 2, "도안", 2), on(105, 2, "도안", 5),
                on(106, 3, "코스터", 6), on(107, 3, "코스터", 7), on(108, 3, "코스터", 8),
                on(106, 4, "실", 6));

        assertThat(service.detect(1L, NOW)).extracting(InterestService.Detected::tag, InterestService.Detected::linkedTags)
                .containsExactly(
                        tuple("뜨개질", List.of("도안")),
                        tuple("도안", List.of("뜨개질")),
                        tuple("코스터", List.of()));
    }

    private InterestRow on(long screenshotId, long tagId, String tag, int daysAgo) {
        return new InterestRow(tagId, tag, screenshotId, "asset-" + screenshotId, Category.ETC,
                NOW.minusDays(daysAgo).minusMinutes(screenshotId));
    }

    @Test
    void 미등록_기기는_예외() {
        when(deviceRepository.existsById(9L)).thenReturn(false);

        assertThatThrownBy(() -> service.list(9L)).isInstanceOf(DeviceNotFoundException.class);
        verify(screenshotTagRepository, never()).findInterestRows(any());
    }
}
