package com.remine.server.classifier.llm;

import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.time.Duration;
import java.util.Map;

/** 제공사 구현이 공유하는 "JSON POST → JSON 응답" 부분. 4xx/5xx는 예외로 올려 재시도 대상이 된다. */
abstract class JsonHttpProvider implements LlmProvider {

    protected final JsonMapper mapper;
    private final RestClient client;

    protected JsonHttpProvider(JsonMapper mapper) {
        this.mapper = mapper;
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(10));
        factory.setReadTimeout(Duration.ofSeconds(60));
        this.client = RestClient.builder().requestFactory(factory).build();
    }

    protected JsonNode post(String url, Map<String, String> headers, Object body) {
        String response = client.post()
                .uri(url)
                .contentType(MediaType.APPLICATION_JSON)
                .headers(h -> headers.forEach(h::set))
                .body(mapper.writeValueAsString(body))
                .retrieve()
                .body(String.class);
        return mapper.readTree(response);
    }
}
