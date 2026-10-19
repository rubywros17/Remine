package com.remine.server.image;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 대조군: Spring Boot 기본값(file-size-threshold=0B)에서는 업로드가 디스크 임시 파일로 쓰인다.
 * 이 테스트가 임시 파일을 "감지"하므로, 운영 설정(메모리 전용)의 "임시 파일 없음" 검사가 헛돌지 않는다는 증거다.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
        "spring.servlet.multipart.file-size-threshold=0B"})
@Import(MultipartTestSupport.Beans.class)
class MultipartDiskControlTest extends MultipartTestSupport {

    private static final Path MULTIPART_DIR = newDir("control-multipart");
    private static final Path TOMCAT_DIR = newDir("control-tomcat");

    @DynamicPropertySource
    static void dirs(DynamicPropertyRegistry registry) {
        dirProperties(registry, MULTIPART_DIR, TOMCAT_DIR);
    }

    @Test
    void 기본_설정이면_요청_처리_중_임시_파일이_생긴다() {
        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("a1|카페"))
                .file("image.a1", jpeg(100, 100, false)));

        assertThat(reply.status()).isEqualTo(200);
        assertThat(provider.leakedFiles).isNotEmpty(); // 감지 장치가 동작한다
        provider.leakedFiles.clear(); // 공통 @AfterEach의 "임시 파일 없음" 검사를 이 대조 테스트에서는 건너뛴다
    }

    @AfterEach
    void cleanControlFiles() throws Exception {
        // 요청이 끝난 뒤 Tomcat이 지우는 것이 정상이지만, 대조군이 다음 테스트에 남기지 않도록 정리한다
        provider.newFiles().forEach(f -> new java.io.File(f).delete());
    }
}
