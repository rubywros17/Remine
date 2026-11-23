package com.remine.server.service;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.device.DeviceToken;
import com.remine.server.dto.DeviceRegisterRequest;
import com.remine.server.dto.DeviceRegisterResponse;
import com.remine.server.exception.DeviceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.MessageDigest;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class DeviceService {

    private final DeviceRepository deviceRepository;

    @Transactional
    public DeviceRegisterResponse register(DeviceRegisterRequest request) {
        Device device = new Device(request.fcmToken());
        String token = device.issueToken();
        deviceRepository.save(device);
        return new DeviceRegisterResponse(token);
    }

    /**
     * 토큰 → 기기 id. 없거나 틀리면 빈 값(이유는 구분하지 않는다).
     * 해시로 찾으므로 DB 비교 시간이 원문 추측에 단서가 되지 않는다(해시의 앞자리를 골라 맞출 수 없다).
     * 찾은 뒤 상수 시간 비교를 한 번 더 둔다.
     */
    @Transactional(readOnly = true)
    public Optional<Long> authenticate(String token) {
        if (token == null || token.isEmpty() || token.length() > 128) {
            return Optional.empty();
        }
        byte[] hash = DeviceToken.hash(token);
        return deviceRepository.findByTokenHash(hash)
                .filter(d -> MessageDigest.isEqual(d.getTokenHash(), hash))
                .map(Device::getId);
    }

    /** 앱이 시작할 때·FCM이 토큰을 바꿀 때 올린다. 같은 값이어도 그대로 덮어쓴다(멱등). */
    @Transactional
    public void updateFcmToken(Long deviceId, String fcmToken) {
        deviceRepository.findById(deviceId)
                .orElseThrow(() -> new DeviceNotFoundException(deviceId))
                .updateFcmToken(fcmToken);
    }

    /** 사용자가 앱 설정에서 알림을 껐다 → 토큰을 지워 발송 대상에서 뺀다. 이미 없어도 204(멱등). */
    @Transactional
    public void deleteFcmToken(Long deviceId) {
        deviceRepository.findById(deviceId)
                .orElseThrow(() -> new DeviceNotFoundException(deviceId))
                .updateFcmToken(null);
    }
}
