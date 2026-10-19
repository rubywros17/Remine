package com.remine.server.controller;

import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.exception.InvalidAnalyzeRequestException;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validator;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.util.MultiValueMap;
import org.springframework.web.multipart.MultipartFile;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * analyze multipart 요청을 읽는다: {@code request} 텍스트 파트(JSON) + {@code image.<localAssetId>} 파일 파트.
 * 구조가 잘못되면 분류를 시작하기 전에 {@link InvalidAnalyzeRequestException}(400)으로 거절한다.
 * 오류 메시지에는 고정 문구와 필드 경로만 쓰고 요청 내용은 되풀이하지 않는다.
 */
@Component
@RequiredArgsConstructor
class AnalyzeMultipartReader {

    static final String REQUEST_PART = "request";
    static final String IMAGE_PART_PREFIX = "image.";

    private final JsonMapper mapper;
    private final Validator validator;

    AnalyzeRequest readRequest(String json) {
        if (json == null || json.isBlank()) {
            throw new InvalidAnalyzeRequestException("multipart 요청에 '" + REQUEST_PART + "' 파트가 필요합니다.");
        }
        AnalyzeRequest request;
        try {
            request = mapper.readValue(json, AnalyzeRequest.class);
        } catch (JacksonException e) {
            // 파싱 오류 메시지에는 입력 일부가 들어갈 수 있으므로 쓰지 않는다
            throw new InvalidAnalyzeRequestException("'" + REQUEST_PART + "' 파트가 올바른 JSON이 아닙니다.");
        }
        if (request == null) {
            throw new InvalidAnalyzeRequestException("'" + REQUEST_PART + "' 파트가 비어 있습니다.");
        }
        Set<ConstraintViolation<AnalyzeRequest>> violations = validator.validate(request);
        if (!violations.isEmpty()) {
            String paths = violations.stream().map(v -> v.getPropertyPath().toString()).sorted()
                    .collect(Collectors.joining(", "));
            throw new InvalidAnalyzeRequestException("'" + REQUEST_PART + "' 파트의 값이 올바르지 않습니다: " + paths);
        }
        return request;
    }

    /** image.&lt;localAssetId&gt; 파트를 localAssetId → 바이트로 읽는다. 짝이 없거나 중복·알 수 없는 파트면 400. */
    Map<String, byte[]> readImages(MultiValueMap<String, MultipartFile> files, AnalyzeRequest request) {
        Set<String> knownIds = new HashSet<>();
        request.screenshots().forEach(item -> knownIds.add(item.localAssetId()));

        // 바이트를 읽기 전에 구조부터 전부 검사한다
        Map<String, MultipartFile> byAssetId = new HashMap<>();
        for (Map.Entry<String, List<MultipartFile>> part : files.entrySet()) {
            String name = part.getKey();
            if (!name.startsWith(IMAGE_PART_PREFIX)) {
                throw new InvalidAnalyzeRequestException(
                        "알 수 없는 파일 파트입니다. 이미지 파트 이름은 'image.<localAssetId>' 형식이어야 합니다.");
            }
            if (part.getValue().size() != 1) {
                throw new InvalidAnalyzeRequestException(
                        "같은 이름의 이미지 파트가 여러 개입니다. 캡처마다 이미지는 하나만 보낼 수 있습니다.");
            }
            String assetId = name.substring(IMAGE_PART_PREFIX.length());
            if (!knownIds.contains(assetId)) {
                throw new InvalidAnalyzeRequestException("요청에 없는 캡처의 이미지 파트가 있습니다.");
            }
            byAssetId.put(assetId, part.getValue().get(0));
        }

        Map<String, byte[]> images = new HashMap<>();
        for (Map.Entry<String, MultipartFile> entry : byAssetId.entrySet()) {
            try {
                images.put(entry.getKey(), entry.getValue().getBytes());
            } catch (IOException e) {
                throw new InvalidAnalyzeRequestException("이미지 파트를 읽을 수 없습니다.");
            }
        }
        return images;
    }
}
