package com.remine.server.image;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

/** 컨테이너 하드 상한(파트·요청 전체) 초과 → 요청 전체 413. 상한을 작게 낮춘 설정으로 확인한다. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
        "remine.image.max-part-bytes=20000",
        "remine.image.max-request-bytes=50000"})
@Import(MultipartTestSupport.Beans.class)
class ImageInputLimitsIntegrationTest extends MultipartTestSupport {

    private static final Path MULTIPART_DIR = newDir("limits-multipart");
    private static final Path TOMCAT_DIR = newDir("limits-tomcat");

    @DynamicPropertySource
    static void dirs(DynamicPropertyRegistry registry) {
        dirProperties(registry, MULTIPART_DIR, TOMCAT_DIR);
    }

    private static byte[] filler(int size) {
        byte[] data = new byte[size];
        data[0] = (byte) 0xFF;
        data[1] = (byte) 0xD8;
        data[2] = (byte) 0xFF;
        return data;
    }

    @Test
    void 파트_하나가_상한을_넘으면_413이고_읽을_수_있는_메시지를_준다() {
        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("a1|카페 " + OCR_MARKER))
                .file("image.a1", filler(30_000)));

        assertThat(reply.status()).isEqualTo(413);
        assertThat(reply.body()).contains("너무 큽니다").doesNotContain(OCR_MARKER);
        assertThat(provider.textCalls).isEmpty();
        assertThat(provider.imageCalls).isEmpty();
    }

    @Test
    void 요청_전체가_상한을_넘으면_413() {
        Multipart multipart = new Multipart().text("request", requestJson("a1|카페", "a2|카페", "a3|카페"));
        multipart.file("image.a1", filler(18_000)).file("image.a2", filler(18_000)).file("image.a3", filler(18_000));

        Reply reply = postMultipart(multipart);

        assertThat(reply.status()).isEqualTo(413);
        assertThat(provider.textCalls).isEmpty();
        assertThat(provider.imageCalls).isEmpty();
    }

    @Test
    void 상한_이내의_요청은_정상이다() {
        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("a1|카페 " + OCR_MARKER))
                .file("image.a1", jpeg(100, 100, false)));

        assertThat(reply.status()).isEqualTo(200);
    }
}
