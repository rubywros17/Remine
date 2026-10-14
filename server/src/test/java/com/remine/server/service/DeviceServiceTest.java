package com.remine.server.service;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.dto.DeviceRegisterRequest;
import com.remine.server.dto.DeviceRegisterResponse;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DeviceServiceTest {

    @Mock DeviceRepository deviceRepository;
    @InjectMocks DeviceService service;

    @Test
    void 기기를_저장하고_deviceId를_반환한다() {
        when(deviceRepository.save(any(Device.class))).thenAnswer(inv -> {
            Device device = inv.getArgument(0);
            ReflectionTestUtils.setField(device, "id", 7L);
            return device;
        });

        DeviceRegisterResponse response = service.register(new DeviceRegisterRequest("fcm-token"));

        assertThat(response.deviceId()).isEqualTo(7L);
    }
}
