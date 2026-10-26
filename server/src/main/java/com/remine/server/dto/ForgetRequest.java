package com.remine.server.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;

/** 서버에서 지울 캡처의 기기 asset id. 한 번에 최대 500개. */
public record ForgetRequest(@NotNull @Size(max = 500) List<String> assetIds) {
}
