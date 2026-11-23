package com.remine.server.controller;

import com.remine.server.domain.device.DeviceToken;
import com.remine.server.dto.DeviceRegisterResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.time.OffsetDateTime;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * [임시] 토큰 도입(V7) 전에 등록된 기기가 기존 기록을 이어 가도록 토큰을 한 번만 받는 이전 창구.
 * 이전이 끝나면 이 파일·{@code LegacyDeviceClaimTest}·설정 {@code remine.legacy.*}(compose의 REMINE_LEGACY_*)만 지우면 된다.
 *
 * <p>설정 {@code remine.legacy.ids}(허용 기기 id, 쉼표 구분)가 비어 있으면 빈이 없어 경로 자체가 404다(기본).
 * 다음을 모두 만족할 때만 토큰을 준다:
 * <ol>
 *   <li>허용 목록에 있는 id (운영자가 EC2 환경변수로 지정)</li>
 *   <li>{@code remine.legacy.until} 전 (필수, 예: 2026-11-27T00:00+09:00)</li>
 *   <li>서버에 저장된 FCM 토큰과 보낸 값이 같다 — FCM 토큰은 어떤 응답에도 나간 적이 없어 앱만 안다.
 *       FCM 토큰이 없는 기기는 이전하지 않는다(앱이 새로 등록한다).</li>
 *   <li>아직 토큰이 없다 — {@code where token_hash is null}로 원자적으로 한 번만. 그 뒤로는 토큰으로만 접근한다.</li>
 * </ol>
 * 거절 이유는 응답에서 구분하지 않고(모두 같은 403) 로그에 사유 코드로만 남긴다. 기기 id·토큰·FCM 토큰 값은 남기지 않는다.
 */
@RestController
@ConditionalOnExpression("!'${remine.legacy.ids:}'.isBlank()")
public class LegacyDeviceClaim {

    private static final Logger log = LoggerFactory.getLogger(LegacyDeviceClaim.class);

    enum Reason { ALLOWED, NOT_LISTED, EXPIRED, NOT_FOUND, NO_FCM, FCM_MISMATCH, ALREADY_CLAIMED }

    public record Request(@NotNull Long deviceId, String fcmToken) {
    }

    private final JdbcTemplate jdbc;
    private final Clock clock;
    private final Set<Long> ids;
    private final OffsetDateTime until;

    public LegacyDeviceClaim(JdbcTemplate jdbc, Clock clock,
                             @Value("${remine.legacy.ids}") String ids,
                             @Value("${remine.legacy.until:}") String until) {
        this.jdbc = jdbc;
        this.clock = clock;
        this.ids = Arrays.stream(ids.split(",")).map(String::strip).map(Long::valueOf).collect(Collectors.toSet());
        if (until.isBlank()) {
            throw new IllegalStateException("remine.legacy.ids를 쓰려면 remine.legacy.until(예: 2026-11-27T00:00+09:00)도 필요합니다");
        }
        this.until = OffsetDateTime.parse(until.strip());
    }

    @PostMapping("/api/devices/legacy-claim")
    public ResponseEntity<?> claim(@Valid @RequestBody Request request) {
        String token = DeviceToken.generate();
        Reason reason = decide(request, DeviceToken.hash(token));
        log.info("legacy claim → {}", reason);
        if (reason == Reason.ALLOWED) {
            return ResponseEntity.ok(new DeviceRegisterResponse(token));
        }
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.FORBIDDEN,
                "기존 기기를 이전할 수 없습니다. 기기를 새로 등록해 주세요.");
        problem.setProperty("code", "LEGACY_CLAIM_REJECTED");
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(problem);
    }

    Reason decide(Request request, byte[] tokenHash) {
        if (!ids.contains(request.deviceId())) {
            return Reason.NOT_LISTED;
        }
        if (!OffsetDateTime.now(clock).isBefore(until)) {
            return Reason.EXPIRED;
        }
        List<Map<String, Object>> rows = jdbc.queryForList(
                "select fcm_token, token_hash is not null as claimed from device where id = ?", request.deviceId());
        if (rows.isEmpty()) {
            return Reason.NOT_FOUND;
        }
        if ((Boolean) rows.getFirst().get("claimed")) {
            return Reason.ALREADY_CLAIMED;
        }
        String stored = (String) rows.getFirst().get("fcm_token");
        if (stored == null) {
            return Reason.NO_FCM;
        }
        if (request.fcmToken() == null || !MessageDigest.isEqual(
                stored.getBytes(StandardCharsets.UTF_8), request.fcmToken().getBytes(StandardCharsets.UTF_8))) {
            return Reason.FCM_MISMATCH;
        }
        // 두 요청이 동시에 와도 하나만 바꾼다.
        int updated = jdbc.update("update device set token_hash = ? where id = ? and token_hash is null",
                tokenHash, request.deviceId());
        return updated == 1 ? Reason.ALLOWED : Reason.ALREADY_CLAIMED;
    }
}
