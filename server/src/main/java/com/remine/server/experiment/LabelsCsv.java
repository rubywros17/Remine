package com.remine.server.experiment;

import com.remine.server.domain.screenshot.Category;

import java.util.Arrays;

/**
 * labels.csv 한 줄 파싱. 형식은 {@code filename,category,alt}이고 alt는 선택이다.
 * 2칸({@code filename,category}) 형식도 그대로 읽는다. 파일명에 쉼표가 없다고 가정한다.
 */
final class LabelsCsv {

    private LabelsCsv() {
    }

    /** category·alt는 비어 있을 수 있다(공백 제거됨). */
    record Row(String filename, String category, String alt) {
    }

    /** 쉼표가 없는 줄(빈 줄 등)은 null. */
    static Row parseLine(String line) {
        String text = line.startsWith("﻿") ? line.substring(1) : line; // 엑셀 저장 BOM
        if (!text.contains(",")) {
            return null;
        }
        String[] parts = text.split(",", -1);
        if (parts.length == 2) {
            return new Row(parts[0].trim(), parts[1].trim(), "");
        }
        String filename = String.join(",", Arrays.copyOfRange(parts, 0, parts.length - 2)).trim();
        return new Row(filename, parts[parts.length - 2].trim(), parts[parts.length - 1].trim());
    }

    /** 빈 값이면 null, 알 수 없는 값이면 IllegalArgumentException. */
    static Category parseCategory(String raw) {
        return raw.isBlank() ? null : Category.valueOf(raw.trim().toUpperCase());
    }
}
