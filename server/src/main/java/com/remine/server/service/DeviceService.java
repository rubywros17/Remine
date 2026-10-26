package com.remine.server.service;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.dto.DeviceRegisterRequest;
import com.remine.server.dto.DeviceRegisterResponse;
import com.remine.server.exception.DeviceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class DeviceService {

    private final DeviceRepository deviceRepository;

    @Transactional
    public DeviceRegisterResponse register(DeviceRegisterRequest request) {
        Device device = deviceRepository.save(new Device(request.fcmToken()));
        return new DeviceRegisterResponse(device.getId());
    }

    /** 앱이 시작할 때·FCM이 토큰을 바꿀 때 올린다. 같은 값이어도 그대로 덮어쓴다(멱등). */
    @Transactional
    public void updateFcmToken(Long deviceId, String fcmToken) {
        deviceRepository.findById(deviceId)
                .orElseThrow(() -> new DeviceNotFoundException(deviceId))
                .updateFcmToken(fcmToken);
    }
}
