package com.remine.server.service;

import com.remine.server.classifier.RemineProperties;
import com.remine.server.domain.device.DeviceRepository;
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
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
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

    static RemineProperties properties(int windowDays, int minCount, int cooldownDays) {
        return new RemineProperties(null, null, null, null, new RemineProperties.Tags(List.of()),
                new RemineProperties.Interest(windowDays, minCount, cooldownDays));
    }

    @BeforeEach
    void setUp() {
        service = new InterestService(deviceRepository, screenshotTagRepository, properties(14, 3, 28),
                Clock.fixed(NOW.atZone(SEOUL).toInstant(), SEOUL));
    }

    private InterestRow row(long tagId, String tag, Category category, int daysAgo) {
        long id = nextScreenshotId++;
        return new InterestRow(tagId, tag, id, "asset-" + id, category, NOW.minusDays(daysAgo).minusMinutes(id));
    }

    // 저장소처럼 최신순으로 돌려준다.
    private void givenRows(InterestRow... rows) {
        List<InterestRow> sorted = new ArrayList<>(List.of(rows));
        sorted.sort(Comparator.comparing(InterestRow::takenAt).reversed());
        when(screenshotTagRepository.findInterestRows(1L, NOW.minusDays(14))).thenReturn(sorted);
    }

    @Test
    void 기간은_지금부터_windowDays_전까지다() {
        when(screenshotTagRepository.findInterestRows(any(), any())).thenReturn(List.of());

        service.detect(1L, NOW);

        verify(screenshotTagRepository).findInterestRows(1L, LocalDateTime.of(2026, 10, 8, 12, 0));
    }

    @Test
    void 같은_태그가_minCount번_이상이어야_관심사다() {
        givenRows(row(1, "가디건", Category.SHOPPING, 1), row(1, "가디건", Category.SHOPPING, 2),
                row(1, "가디건", Category.SHOPPING, 3),
                row(2, "드라마", Category.ENTERTAINMENT, 1), row(2, "드라마", Category.ENTERTAINMENT, 2));

        assertThat(service.detect(1L, NOW)).extracting(InterestService.Detected::tag).containsExactly("가디건");
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
    void 횟수_많은_순_다음_최근_캡처_순_다음_이름순() {
        givenRows(
                row(1, "가", Category.ETC, 5), row(1, "가", Category.ETC, 5), row(1, "가", Category.ETC, 5),
                row(2, "나", Category.ETC, 1), row(2, "나", Category.ETC, 6), row(2, "나", Category.ETC, 6),
                row(3, "다", Category.ETC, 9), row(3, "다", Category.ETC, 9), row(3, "다", Category.ETC, 9),
                row(3, "다", Category.ETC, 9));

        assertThat(service.detect(1L, NOW)).extracting(InterestService.Detected::tag).containsExactly("다", "나", "가");
    }

    @Test
    void 응답은_최근_3장_최신순과_잠든_일수를_담는다() {
        InterestRow newest = row(1, "가디건", Category.SHOPPING, 9);
        InterestRow second = row(1, "가디건", Category.SHOPPING, 10);
        InterestRow third = row(1, "가디건", Category.SHOPPING, 11);
        givenRows(row(1, "가디건", Category.SHOPPING, 12), third, newest, second);
        when(deviceRepository.existsById(1L)).thenReturn(true);

        InterestResponse response = service.list(1L);
        InterestResponse.Item item = response.items().get(0);

        assertThat(response.windowDays()).isEqualTo(14);
        assertThat(response.minCount()).isEqualTo(3);
        assertThat(item.tag()).isEqualTo("가디건");
        assertThat(item.captureCount()).isEqualTo(4);
        assertThat(item.dormantDays()).isEqualTo(9);
        assertThat(item.recent()).extracting(InterestResponse.Capture::id)
                .containsExactly(newest.screenshotId(), second.screenshotId(), third.screenshotId());
        assertThat(item.recent().get(0).localAssetId()).isEqualTo(newest.localAssetId());
    }

    @Test
    void 미등록_기기는_예외() {
        when(deviceRepository.existsById(9L)).thenReturn(false);

        assertThatThrownBy(() -> service.list(9L)).isInstanceOf(DeviceNotFoundException.class);
        verify(screenshotTagRepository, never()).findInterestRows(any(), any());
    }
}
