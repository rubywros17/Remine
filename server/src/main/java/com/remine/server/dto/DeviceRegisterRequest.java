package com.remine.server.dto;

import jakarta.validation.constraints.NotBlank;

public record DeviceRegisterRequest(@NotBlank String fcmToken) {
}
