package com.remine.server.classifier;

import org.springframework.boot.diagnostics.AbstractFailureAnalyzer;
import org.springframework.boot.diagnostics.FailureAnalysis;

/** 키가 없을 때 긴 빈 생성 스택 트레이스 대신 "무엇이 문제이고 어떻게 고치는지"만 보여 준다. */
public class MissingApiKeyFailureAnalyzer extends AbstractFailureAnalyzer<MissingApiKeyException> {

    @Override
    protected FailureAnalysis analyze(Throwable rootFailure, MissingApiKeyException cause) {
        String name = cause.propertyName();
        return new FailureAnalysis(
                "remine.classifier=gemini 로 실행했지만 API 키(" + name + ")가 설정되어 있지 않습니다.",
                "다음 중 하나를 하세요.\n"
                        + "  1) 환경변수 " + name + " 를 설정한다.\n"
                        + "  2) 사용자 홈의 ~/.remine.env 파일에 한 줄을 적는다: " + name + "=키값 (따옴표 없이, BOM 없는 UTF-8)\n"
                        + "  3) 키 없이 쓰려면 remine.classifier=fake (기본값)로 실행한다.",
                cause);
    }
}
