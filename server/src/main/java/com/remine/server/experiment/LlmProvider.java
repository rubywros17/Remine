package com.remine.server.experiment;

/** 제공사별 HTTP 호출만 담당한다. 프롬프트·파싱은 모든 후보가 공통으로 쓴다. */
public interface LlmProvider {

    LlmReply call(String model, String systemPrompt, String userText);
}
