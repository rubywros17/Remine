package com.remine.server.dto;

import jakarta.validation.constraints.NotBlank;

public record DeviceTokenRequest(@NotBlank String fcmToken) {
}
