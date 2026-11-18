package com.remine.server.dto;

import com.remine.server.domain.screenshot.Category;

import java.util.List;

/**
 * analyzed: 이번에 분석한 결과, skipped: 이미 분석돼 있어 건너뛴 localAssetId,
 * failed: 분류에 실패해 미분석으로 남긴 캡처(같은 요청을 다시 보내면 재분석한다).
 * 일부가 실패해도 HTTP 200이고 나머지는 정상 저장된다.
 * olderRemainingToday: 이 요청 뒤 오늘 더 보낼 수 있는 예전 스크린샷 장수(옛 앱은 무시해도 된다).
 */
public record AnalyzeResponse(List<Result> analyzed, List<String> skipped, List<Failure> failed,
                              int olderRemainingToday) {

    public record Result(String localAssetId, Category category, List<String> tags, String summary) {
    }

    /** reason에는 제공사 오류 본문·OCR 원문을 싣지 않고 분류 코드만 둔다. */
    public record Failure(String localAssetId, Reason reason) {
    }

    public enum Reason {
        /** LLM 호출 자체가 실패했다(통신 오류, 쿼터 소진, 인증 오류 등). */
        LLM_CALL_FAILED,
        /** LLM이 해석할 수 없는 응답을 줬다. */
        LLM_INVALID_RESPONSE,
        /** 이미지가 JPEG가 아니거나 읽을 수 없다(손상·픽셀 수 초과). 이미지 없이 다시 보낸다. */
        IMAGE_INVALID,
        /** 이미지가 장당 최대 크기(imageMaxBytes)를 넘는다. 더 줄여서 다시 보낸다. */
        IMAGE_TOO_LARGE,
        /** 같은 기기의 다른 요청이 이 캡처를 분석 중이다. 저장하지 않았으니 나중에 다시 보낸다. */
        IN_PROGRESS,
        /** 요청 마감(remine.analyze.deadline)이 지나 분류를 시작하지 않았다. 저장하지 않았으니 나중에 다시 보낸다. */
        DEADLINE_EXCEEDED,
        /**
         * 예전 스크린샷(기기 등록 전에 찍힘) 하루 한도를 넘었다: 기기 몫(한국 시간 자정 초기화) 또는 서버 전체 호출 예산의
         * 예전 몫. 분류하지 않았고 저장하지 않았으니 내일 다시 보낸다.
         */
        DAILY_LIMIT_EXCEEDED
    }
}
