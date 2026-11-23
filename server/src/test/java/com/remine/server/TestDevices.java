package com.remine.server;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.device.DeviceToken;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 테스트용: 토큰을 가진 기기를 저장하고, 기기 id로 Authorization 헤더 값을 만든다.
 * 저장하지 않은 id(987654321 등 "남의/없는 기기")는 아무 기기에도 맞지 않는 무작위 토큰이 된다 → 401.
 */
public final class TestDevices {

    private static final Map<Long, String> TOKENS = new ConcurrentHashMap<>();

    private TestDevices() {
    }

    public static Long save(DeviceRepository repository, String fcmToken) {
        Device device = new Device(fcmToken);
        String token = device.issueToken();
        Long id = repository.save(device).getId();
        TOKENS.put(id, token);
        return id;
    }

    public static String token(Long deviceId) {
        return TOKENS.getOrDefault(deviceId, DeviceToken.generate());
    }

    /** {@code Authorization} 헤더 값. */
    public static String auth(Object deviceId) {
        return "Bearer " + token(Long.valueOf(String.valueOf(deviceId)));
    }
}
