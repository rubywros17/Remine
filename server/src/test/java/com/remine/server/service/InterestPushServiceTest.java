package com.remine.server.service;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.interest.InterestAlert;
import com.remine.server.domain.interest.InterestAlert.Status;
import com.remine.server.domain.interest.InterestAlertRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.exception.NoFcmTokenException;
import com.remine.server.push.PushMessage;
import com.remine.server.push.PushSender;
import com.remine.server.service.InterestAlertServiceTest.MovableClock;
import com.remine.server.service.ScreenshotPersister.Outcome;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

import java.time.LocalDateTime;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

import static com.remine.server.service.InterestAlertServiceTest.THURSDAY;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** 발송을 실제 DB(PostgreSQL) + 가짜 sender로: SENT·재시도·무효 토큰·지난주 정리, 알림 내용에 원문·요약이 없는지. */
@SpringBootTest
class InterestPushServiceTest {

    /** 토큰별로 돌려줄 결과를 차례로 정해 두는 sender. 정해 두지 않았으면 SENT. */
    static class FakeSender implements PushSender {
        record Call(String token, PushMessage message) {
        }

        final List<Call> calls = new CopyOnWriteArrayList<>();
        final Map<String, Deque<Result>> scripted = new ConcurrentHashMap<>();

        void answer(String token, Result... results) {
            scripted.put(token, new ArrayDeque<>(List.of(results)));
        }

        @Override
        public Result send(String token, PushMessage message) {
            calls.add(new Call(token, message));
            Deque<Result> queue = scripted.get(token);
            return queue == null || queue.isEmpty() ? Result.SENT : queue.poll();
        }

        List<Call> callsTo(String token) {
            return calls.stream().filter(c -> c.token().equals(token)).toList();
        }
    }

    @TestConfiguration
    static class Config {
        @Bean
        @Primary
        MovableClock movableClock() {
            return new MovableClock();
        }

        @Bean
        FakeSender fakeSender() {
            return new FakeSender();
        }
    }

    @Autowired MovableClock clock;
    @Autowired FakeSender sender;
    @Autowired InterestPushService service;
    @Autowired InterestAlertService alertService;
    @Autowired InterestAlertRepository alertRepository;
    @Autowired DeviceRepository deviceRepository;
    @Autowired ScreenshotPersister persister;

    private String prefix; // 테스트끼리 태그·토큰이 섞이지 않게
    private String token;
    private Long deviceId;

    @BeforeEach
    void setUp() {
        clock.now = THURSDAY;
        prefix = UUID.randomUUID().toString().substring(0, 8);
        token = "token-" + prefix;
        deviceId = deviceRepository.save(new Device(token)).getId();
    }

    private void captures(Long device, String tag, int count, LocalDateTime at) {
        for (int i = 0; i < count; i++) {
            Item item = new Item(UUID.randomUUID().toString(), at.minusHours(i), "앱", "원문 OCR 내용");
            persister.saveAll(device, List.of(new Outcome(item,
                    new ClassificationResult(Category.SHOPPING, List.of(prefix + tag), "비밀 요약"))));
        }
    }

    private List<InterestAlert> alerts(Long device) {
        return alertRepository.findAll().stream().filter(a -> a.getDevice().getId().equals(device)).toList();
    }

    private InterestAlert alert() {
        return alerts(deviceId).get(0);
    }

    @Test
    void PENDING을_보내고_SENT로_바꾸며_다시_돌려도_재발송하지_않는다() {
        captures(deviceId, "신발", 3, THURSDAY);
        alertService.createWeeklyAlerts();

        service.sendPending();
        service.sendPending();

        assertThat(sender.callsTo(token)).singleElement().satisfies(call -> {
            assertThat(call.message().body()).isEqualTo("요즘 '" + prefix + "신발'을 3번 캡처했어요. 다시 볼까요?");
            assertThat(call.message().data()).containsExactlyInAnyOrderEntriesOf(Map.of(
                    "type", "interest", "tag", prefix + "신발", "category", "SHOPPING"));
            // 알림에는 태그·횟수·카테고리뿐: OCR 원문·요약이 없다
            assertThat(call.message().toString()).doesNotContain("원문", "요약");
        });
        assertThat(alert().getStatus()).isEqualTo(Status.SENT);
        assertThat(alert().getSentAt()).isEqualTo(THURSDAY);
    }

    @Test
    void 실패하면_PENDING으로_남고_다음_실행에_다시_보낸다() {
        sender.answer(token, PushSender.Result.FAILED);
        captures(deviceId, "신발", 3, THURSDAY);
        alertService.createWeeklyAlerts();

        service.sendPending();
        assertThat(alert().getStatus()).isEqualTo(Status.PENDING);
        assertThat(deviceRepository.findById(deviceId).orElseThrow().getFcmToken()).isEqualTo(token); // 토큰은 그대로

        clock.now = THURSDAY.plusHours(1);
        service.sendPending();
        assertThat(sender.callsTo(token)).hasSize(2);
        assertThat(alert().getStatus()).isEqualTo(Status.SENT);
    }

    @Test
    void 무효_토큰이면_기기_토큰만_지우고_새_토큰이_오면_그_주_안에_보낸다() {
        sender.answer(token, PushSender.Result.INVALID_TOKEN);
        captures(deviceId, "신발", 3, THURSDAY);
        alertService.createWeeklyAlerts();

        service.sendPending();
        assertThat(deviceRepository.findById(deviceId).orElseThrow().getFcmToken()).isNull();
        assertThat(alert().getStatus()).isEqualTo(Status.PENDING);

        service.sendPending(); // 토큰이 없으면 보내지 않는다
        assertThat(sender.callsTo(token)).hasSize(1);

        Device device = deviceRepository.findById(deviceId).orElseThrow();
        device.updateFcmToken("new-" + token);
        deviceRepository.save(device);
        service.sendPending();
        assertThat(sender.callsTo("new-" + token)).hasSize(1);
        assertThat(alert().getStatus()).isEqualTo(Status.SENT);
    }

    @Test
    void 지난주_이전_PENDING은_EXPIRED로_정리하고_보내지_않는다() {
        Long sentDevice = deviceRepository.save(new Device("sent-" + token)).getId();
        sender.answer(token, PushSender.Result.FAILED); // 지난주에 끝내 못 보냄
        captures(deviceId, "신발", 3, THURSDAY);
        captures(sentDevice, "가방", 3, THURSDAY);
        alertService.createWeeklyAlerts();
        service.sendPending();

        clock.now = THURSDAY.plusWeeks(1);
        service.sendPending();

        assertThat(alert().getStatus()).isEqualTo(Status.EXPIRED);
        assertThat(sender.callsTo(token)).hasSize(1); // 지난주 시도 한 번뿐
        assertThat(alerts(sentDevice)).singleElement()
                .satisfies(a -> assertThat(a.getStatus()).isEqualTo(Status.SENT)); // 보낸 것은 그대로
    }

    @Test
    void 이번_주_PENDING은_정리하지_않는다() {
        sender.answer(token, PushSender.Result.FAILED, PushSender.Result.FAILED);
        captures(deviceId, "신발", 3, THURSDAY);
        alertService.createWeeklyAlerts();

        service.sendPending();
        clock.now = THURSDAY.plusDays(3); // 같은 주 일요일
        service.sendPending();

        assertThat(alert().getStatus()).isEqualTo(Status.PENDING);
    }

    @Test
    void 토큰이_없는_기기에는_보내지_않는다() {
        Long noToken = deviceRepository.save(new Device(null)).getId();
        captures(noToken, "신발", 3, THURSDAY);
        alertService.createWeeklyAlerts();

        service.sendPending();

        assertThat(alerts(noToken)).singleElement()
                .satisfies(a -> assertThat(a.getStatus()).isEqualTo(Status.PENDING));
    }

    @Test
    void 테스트_알림은_지금_1순위_관심사로_보내고_주간_알림은_건드리지_않는다() {
        captures(deviceId, "드라마", 4, THURSDAY);
        long before = alertRepository.count();

        assertThat(service.sendTest(deviceId)).isEqualTo(PushSender.Result.SENT);

        assertThat(sender.callsTo(token)).singleElement().satisfies(call -> {
            assertThat(call.message().body()).isEqualTo("요즘 '" + prefix + "드라마'를 4번 캡처했어요. 다시 볼까요?");
            assertThat(call.message().data()).containsEntry("tag", prefix + "드라마").containsEntry("category", "SHOPPING");
        });
        assertThat(alertRepository.count()).isEqualTo(before);
        assertThat(alerts(deviceId)).isEmpty();
    }

    @Test
    void 관심사가_없으면_예시_관심사로_보낸다() {
        service.sendTest(deviceId);

        assertThat(sender.callsTo(token)).singleElement().satisfies(call ->
                assertThat(call.message().data()).containsEntry("tag", InterestPushService.EXAMPLE_TAG));
    }

    @Test
    void 알림을_끈_기기에는_테스트_알림도_보내지_않는다() {
        Long noToken = deviceRepository.save(new Device(null)).getId();

        assertThatThrownBy(() -> service.sendTest(noToken)).isInstanceOf(NoFcmTokenException.class);
    }

    @Test
    void 받침에_따라_을_를을_고른다() {
        assertThat(InterestPushService.objectParticle("신발")).isEqualTo("을");
        assertThat(InterestPushService.objectParticle("드라마")).isEqualTo("를");
        assertThat(InterestPushService.objectParticle("Nike")).isEqualTo("을(를)");
    }
}
