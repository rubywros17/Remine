package com.remine.server.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDateTime;
import java.util.List;

/** 최대 항목 수는 remine.analyze.max-batch-size(기본 20)로 서비스에서 검사한다. */
public record AnalyzeRequest(
        @NotEmpty @Valid List<Item> screenshots) {

    /** ocrText는 글자 없는 스크린샷이면 비어 있거나 null일 수 있다. */
    public record Item(
            @NotBlank String localAssetId,
            @NotNull LocalDateTime takenAt,
            String sourceApp,
            String ocrText) {
    }
}
