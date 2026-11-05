package com.remine.server.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;

/** 앱 휴지통에 넣거나 되살린 캡처의 asset id. 한 번에 최대 500개. */
public record TrashRequest(@NotNull @Size(max = 500) List<String> assetIds) {
}
