package com.remine.server.service;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.device.DeviceToken;
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

import java.util.Arrays;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DeviceServiceTest {

    @Mock DeviceRepository deviceRepository;
    @InjectMocks DeviceService service;

    @Test
    void 등록하면_무작위_토큰을_한_번만_주고_해시만_저장한다() {
        when(deviceRepository.save(any(Device.class))).thenAnswer(inv -> inv.getArgument(0));

        DeviceRegisterResponse first = service.register(new DeviceRegisterRequest("fcm-token"));
        DeviceRegisterResponse second = service.register(new DeviceRegisterRequest("fcm-token"));

        // 256비트 → URL-safe Base64(패딩 없음) 43자
        assertThat(first.token()).matches("[A-Za-z0-9_-]{43}").isNotEqualTo(second.token());
        ArgumentCaptor<Device> saved = ArgumentCaptor.forClass(Device.class);
        verify(deviceRepository, times(2)).save(saved.capture());
        assertThat(saved.getAllValues().getFirst().getTokenHash()).isEqualTo(DeviceToken.hash(first.token()));
    }

    @Test
    void 토큰으로_기기를_찾고_없거나_틀리면_빈_값() {
        Device device = new Device("fcm");
        String token = device.issueToken();
        ReflectionTestUtils.setField(device, "id", 7L);
        when(deviceRepository.findByTokenHash(any())).thenAnswer(inv ->
                Arrays.equals(inv.getArgument(0), DeviceToken.hash(token)) ? Optional.of(device) : Optional.empty());

        assertThat(service.authenticate(token)).contains(7L);
        assertThat(service.authenticate(DeviceToken.generate())).isEmpty();
        assertThat(service.authenticate("7")).isEmpty(); // 숫자 id는 토큰이 아니다
        assertThat(service.authenticate("")).isEmpty();
        assertThat(service.authenticate(null)).isEmpty();
        assertThat(service.authenticate("x".repeat(129))).isEmpty();
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
    void 알림을_끄면_토큰을_지우고_미등록_기기는_404() {
        Device device = new Device("token");
        when(deviceRepository.findById(7L)).thenReturn(Optional.of(device));
        when(deviceRepository.findById(8L)).thenReturn(Optional.empty());

        service.deleteFcmToken(7L);
        service.deleteFcmToken(7L); // 이미 없어도 그대로(멱등)

        assertThat(device.getFcmToken()).isNull();
        assertThatThrownBy(() -> service.deleteFcmToken(8L)).isInstanceOf(DeviceNotFoundException.class);
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
