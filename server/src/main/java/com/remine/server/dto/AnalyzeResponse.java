package com.remine.server.dto;

import com.remine.server.domain.screenshot.Category;

import java.util.List;

/**
 * analyzed: 이번에 분석한 결과, skipped: 이미 분석돼 있어 건너뛴 localAssetId,
 * failed: 분류에 실패해 미분석으로 남긴 캡처(같은 요청을 다시 보내면 재분석한다).
 * 일부가 실패해도 HTTP 200이고 나머지는 정상 저장된다.
 */
public record AnalyzeResponse(List<Result> analyzed, List<String> skipped, List<Failure> failed) {

    public record Result(String localAssetId, Category category, List<String> tags, String summary) {
    }

    /** reason에는 제공사 오류 본문·OCR 원문을 싣지 않고 분류 코드만 둔다. */
    public record Failure(String localAssetId, Reason reason) {
    }

    public enum Reason {
        /** LLM 호출 자체가 실패했다(통신 오류, 쿼터 소진, 인증 오류 등). */
        LLM_CALL_FAILED,
        /** LLM이 해석할 수 없는 응답을 줬다. */
        LLM_INVALID_RESPONSE
    }
}
