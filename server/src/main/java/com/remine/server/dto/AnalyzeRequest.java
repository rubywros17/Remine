package com.remine.server.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.LocalDateTime;
import java.util.List;

public record AnalyzeRequest(
        @NotEmpty @Size(max = 300) @Valid List<Item> screenshots) {

    /** ocrText는 글자 없는 스크린샷이면 비어 있거나 null일 수 있다. */
    public record Item(
            @NotBlank String localAssetId,
            @NotNull LocalDateTime takenAt,
            String sourceApp,
            String ocrText) {
    }
}
