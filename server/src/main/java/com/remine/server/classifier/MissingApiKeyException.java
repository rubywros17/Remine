package com.remine.server.classifier;

/**
 * remine.classifier=gemini 인데 API 키가 없다. 키 값이나 길이는 담지 않는다.
 * {@link MissingApiKeyFailureAnalyzer}가 기동 실패 화면을 읽기 쉬운 안내로 바꾼다.
 */
public class MissingApiKeyException extends IllegalStateException {

    private final String propertyName;

    public MissingApiKeyException(String propertyName) {
        super("remine.classifier=gemini 인데 " + propertyName + " 가 설정되어 있지 않습니다. 환경변수 " + propertyName
                + " 또는 키 파일(REMINE_ENV_FILE, 기본 ~/.remine.env)에 " + propertyName + "=키값 을 설정하거나, remine.classifier=fake 로 실행하세요.");
        this.propertyName = propertyName;
    }

    public String propertyName() {
        return propertyName;
    }
}
