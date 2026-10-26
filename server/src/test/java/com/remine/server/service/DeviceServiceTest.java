package com.remine.server.service;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.dto.DeviceRegisterRequest;
import com.remine.server.dto.DeviceRegisterResponse;
import com.remine.server.exception.DeviceNotFoundException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
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

    @Test
    void 토큰_없이도_등록되고_빈_토큰은_null로_저장한다() {
        when(deviceRepository.save(any(Device.class))).thenAnswer(inv -> inv.getArgument(0));

        service.register(new DeviceRegisterRequest(" "));

        ArgumentCaptor<Device> saved = ArgumentCaptor.forClass(Device.class);
        verify(deviceRepository).save(saved.capture());
        assertThat(saved.getValue().getFcmToken()).isNull();
    }

    @Test
    void 토큰을_갱신한다() {
        Device device = new Device("old");
        when(deviceRepository.findById(7L)).thenReturn(Optional.of(device));

        service.updateFcmToken(7L, "new");

        assertThat(device.getFcmToken()).isEqualTo("new");
    }

    @Test
    void 미등록_기기의_토큰_갱신은_404() {
        when(deviceRepository.findById(7L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.updateFcmToken(7L, "new")).isInstanceOf(DeviceNotFoundException.class);
    }

    @Test
    void 무효_토큰_정리는_보낸_토큰과_같을_때만_지운다() {
        Device device = new Device("old");
        device.updateFcmToken("new"); // 보내는 사이 앱이 새 토큰을 올림
        device.clearFcmToken("old");
        assertThat(device.getFcmToken()).isEqualTo("new");

        device.clearFcmToken("new");
        assertThat(device.getFcmToken()).isNull();
    }
}
