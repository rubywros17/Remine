package com.remine.server.experiment;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

/**
 * 앱의 디버그 OCR 측정 화면이 내보낸 ML Kit 결과 JSON({"items":[{"fileName","text"}]})을 읽는다.
 * Tesseract의 ocr/{이름}.txt 대신 쓰며, labels.csv의 파일명과 확장자를 뺀 이름으로 맞춘다.
 */
final class MlKitOcr {

    private MlKitOcr() {
    }

    static Map<String, String> load(Path json, JsonMapper mapper) throws IOException {
        Map<String, String> byStem = new HashMap<>();
        for (JsonNode item : mapper.readTree(Files.readString(json, StandardCharsets.UTF_8)).path("items")) {
            byStem.put(stem(item.path("fileName").asString()), item.path("text").asString("").trim());
        }
        return byStem;
    }

    static String stem(String filename) {
        return filename.replaceFirst("[.][^.]+$", "");
    }
}
