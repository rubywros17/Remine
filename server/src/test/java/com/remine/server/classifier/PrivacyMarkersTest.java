package com.remine.server.classifier;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

class PrivacyMarkersTest {

    /** 마스킹 표시 리터럴이 상수 정의 한 곳에만 있는지(다른 곳은 상수를 쓴다). */
    @Test
    void 전화번호_마스킹_표시는_운영_코드에서_상수_한_곳에만_있다() throws IOException {
        assertThat(PrivacyMarkers.PHONE_NUMBER_MASK).isEqualTo("[전화번호]");
        List<Path> offenders;
        try (Stream<Path> files = Files.walk(Path.of("src/main/java"))) {
            offenders = files.filter(f -> f.toString().endsWith(".java"))
                    .filter(f -> !f.getFileName().toString().equals("PrivacyMarkers.java"))
                    .filter(f -> {
                        try {
                            return Files.readString(f).contains(PrivacyMarkers.PHONE_NUMBER_MASK);
                        } catch (IOException e) {
                            throw new java.io.UncheckedIOException(e);
                        }
                    }).toList();
        }
        assertThat(offenders).isEmpty();
    }
}
