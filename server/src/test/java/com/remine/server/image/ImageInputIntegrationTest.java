package com.remine.server.image;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import tools.jackson.databind.JsonNode;

import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * analyze multipart 입력: 정상·하위 호환·검증 오류·분류 규칙·축소/EXIF 제거.
 * "흔적 없음"(로그·응답·DB·임시 파일) 검사는 공통 @AfterEach가 모든 테스트에 적용한다.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
        "remine.image.max-pixels=2000000",
        "logging.level.org.springframework.web=DEBUG",
        "logging.level.com.remine=DEBUG"})
@Import(MultipartTestSupport.Beans.class)
class ImageInputIntegrationTest extends MultipartTestSupport {

    private static final Path MULTIPART_DIR = newDir("multipart");
    private static final Path TOMCAT_DIR = newDir("tomcat");

    @DynamicPropertySource
    static void dirs(DynamicPropertyRegistry registry) {
        dirProperties(registry, MULTIPART_DIR, TOMCAT_DIR);
    }

    private static String shortOcr() {
        return "카페 영업시간 " + OCR_MARKER;
    }

    @Test
    void multipart로_보낸_이미지는_짧은_OCR과_함께_분류기에_전달된다() {
        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("a1|" + shortOcr()))
                .file("image.a1", jpeg(800, 600, false)));

        assertThat(reply.status()).isEqualTo(200);
        JsonNode body = reply.json(json);
        assertThat(body.get("analyzed")).hasSize(1);
        assertThat(body.get("failed")).isEmpty();
        assertThat(provider.imageCalls).hasSize(1);
        assertThat(provider.textCalls).isEmpty();
    }

    @Test
    void 이미지_없는_기존_JSON_요청은_그대로_동작한다() {
        Reply reply = postJson(requestJson("a1|" + shortOcr()));

        assertThat(reply.status()).isEqualTo(200);
        assertThat(reply.json(json).get("analyzed")).hasSize(1);
        assertThat(provider.textCalls).hasSize(1);
        assertThat(provider.imageCalls).isEmpty();
    }

    @Test
    void 이미지가_없는_multipart도_텍스트로_분류한다() {
        Reply reply = postMultipart(new Multipart().text("request", requestJson("a1|" + shortOcr())));

        assertThat(reply.status()).isEqualTo(200);
        assertThat(provider.textCalls).hasSize(1);
    }

    @Test
    void 스무_장과_request까지_스물한_파트도_통과한다() {
        String[] items = IntStream.rangeClosed(1, 20).mapToObj(i -> "c" + i + "|" + shortOcr()).toArray(String[]::new);
        Multipart multipart = new Multipart().text("request", requestJson(items));
        IntStream.rangeClosed(1, 20).forEach(i -> multipart.file("image.c" + i, jpeg(300, 300, false)));

        Reply reply = postMultipart(multipart);

        assertThat(reply.status()).isEqualTo(200);
        assertThat(reply.json(json).get("analyzed")).hasSize(20);
        assertThat(provider.imageCalls).hasSize(20);
    }

    @Test
    void 크기_초과_형식_오류_픽셀_초과는_그_캡처만_실패하고_나머지는_정상이다() {
        byte[] tooLarge = new byte[1_048_577];
        tooLarge[0] = (byte) 0xFF;
        tooLarge[1] = (byte) 0xD8;
        tooLarge[2] = (byte) 0xFF;
        byte[] notJpeg = ("PNG 아님 " + IMAGE_MARKER).getBytes(StandardCharsets.UTF_8);

        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("ok|" + shortOcr(), "big|" + shortOcr(), "fmt|" + shortOcr(), "px|" + shortOcr()))
                .file("image.ok", jpeg(400, 300, false))
                .file("image.big", tooLarge)
                .file("image.fmt", notJpeg)
                .file("image.px", jpeg(2000, 1100, false))); // 2.2M px > 2M

        assertThat(reply.status()).isEqualTo(200);
        JsonNode body = reply.json(json);
        assertThat(body.get("analyzed")).hasSize(1);
        assertThat(body.get("analyzed").get(0).get("localAssetId").asString()).isEqualTo("ok");
        assertThat(body.get("failed")).hasSize(3);
        assertThat(reasonOf(body, "big")).isEqualTo("IMAGE_TOO_LARGE");
        assertThat(reasonOf(body, "fmt")).isEqualTo("IMAGE_INVALID");
        assertThat(reasonOf(body, "px")).isEqualTo("IMAGE_INVALID");
        assertThat(provider.imageCalls).hasSize(1);
        // 실패한 캡처는 미분석 행으로 남는다
        assertThat(jdbc.queryForObject(
                "select count(*) from screenshot where analyzed_at is null", Integer.class)).isEqualTo(3);
    }

    private static String reasonOf(JsonNode body, String assetId) {
        for (JsonNode failure : body.get("failed")) {
            if (failure.get("localAssetId").asString().equals(assetId)) {
                return failure.get("reason").asString();
            }
        }
        throw new AssertionError(assetId + " 실패 항목 없음");
    }

    @Test
    void 요청에_없는_캡처의_이미지_파트는_400이고_아무것도_분류하지_않는다() {
        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("a1|" + shortOcr()))
                .file("image.zzz", jpeg(100, 100, false)));

        assertThat(reply.status()).isEqualTo(400);
        assertThat(provider.imageCalls).isEmpty();
        assertThat(provider.textCalls).isEmpty();
    }

    @Test
    void 같은_이름의_이미지_파트가_둘이면_400() {
        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("a1|" + shortOcr()))
                .file("image.a1", jpeg(100, 100, false))
                .file("image.a1", jpeg(100, 100, false)));

        assertThat(reply.status()).isEqualTo(400);
        assertThat(provider.imageCalls).isEmpty();
    }

    @Test
    void 이름_규칙에_맞지_않는_파일_파트는_400() {
        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("a1|" + shortOcr()))
                .file("photo", jpeg(100, 100, false)));

        assertThat(reply.status()).isEqualTo(400);
    }

    @Test
    void request_파트가_없으면_400() {
        Reply reply = postMultipart(new Multipart().file("image.a1", jpeg(100, 100, false)));

        assertThat(reply.status()).isEqualTo(400);
        assertThat(provider.imageCalls).isEmpty();
    }

    @Test
    void 잘못된_JSON이면_400이고_본문_내용을_되풀이하지_않는다() {
        Reply reply = postMultipart(new Multipart()
                .text("request", "{\"screenshots\":[{\"ocrText\":\"" + OCR_MARKER + "\" 깨진 JSON")
                .file("image.a1", jpeg(100, 100, false)));

        assertThat(reply.status()).isEqualTo(400);
        assertThat(reply.body()).doesNotContain(OCR_MARKER);
    }

    @Test
    void 필드_검증_오류도_400이고_필드_경로만_알려준다() {
        Reply reply = postMultipart(new Multipart().text("request",
                "{\"screenshots\":[{\"localAssetId\":\"\",\"takenAt\":\"2026-10-19T10:00:00\",\"ocrText\":\"" + OCR_MARKER + "\"}]}"));

        assertThat(reply.status()).isEqualTo(400);
        assertThat(reply.body()).contains("localAssetId").doesNotContain(OCR_MARKER);
    }

    @Test
    void 빈_OCR이어도_이미지가_있으면_분류기가_이미지로_분류한다() {
        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("a1|"))
                .file("image.a1", jpeg(300, 300, false)));

        assertThat(reply.status()).isEqualTo(200);
        assertThat(reply.json(json).get("analyzed")).hasSize(1);
        assertThat(provider.imageCalls).hasSize(1);
    }

    @Test
    void 빈_OCR이고_이미지도_없으면_분류기를_부르지_않고_기타다() {
        Reply reply = postMultipart(new Multipart().text("request", requestJson("a1|")));

        assertThat(reply.status()).isEqualTo(200);
        assertThat(reply.json(json).get("analyzed").get(0).get("category").asString()).isEqualTo("ETC");
        assertThat(provider.imageCalls).isEmpty();
        assertThat(provider.textCalls).isEmpty();
    }

    @Test
    void OCR이_기준값_이상이면_이미지가_와도_분류기에_넘기지_않고_디코딩도_하지_않는다() {
        String longOcr = "가".repeat(150) + OCR_MARKER;

        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("a1|" + longOcr))
                .file("image.a1", "JPEG 아님".getBytes(StandardCharsets.UTF_8))); // 검증했다면 IMAGE_INVALID

        assertThat(reply.status()).isEqualTo(200);
        assertThat(reply.json(json).get("failed")).isEmpty();
        assertThat(provider.imageCalls).isEmpty();
        assertThat(provider.textCalls).hasSize(1);
    }

    @Test
    void 전화번호_마스킹_표시가_있으면_짧은_OCR이어도_이미지를_쓰지_않는다() {
        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("a1|연락처 [전화번호] " + OCR_MARKER))
                .file("image.a1", jpeg(300, 300, false)));

        assertThat(reply.status()).isEqualTo(200);
        assertThat(reply.json(json).get("analyzed")).hasSize(1);
        assertThat(provider.imageCalls).isEmpty();
        assertThat(provider.textCalls).hasSize(1);
    }

    @Test
    void 이미_분석된_캡처의_이미지는_무시한다() {
        postMultipart(new Multipart().text("request", requestJson("a1|" + shortOcr())));
        provider.reset();

        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("a1|" + shortOcr()))
                .file("image.a1", jpeg(300, 300, false)));

        assertThat(reply.status()).isEqualTo(200);
        assertThat(reply.json(json).get("skipped")).hasSize(1);
        assertThat(provider.imageCalls).isEmpty();
        assertThat(provider.textCalls).isEmpty();
    }

    @Test
    void 큰_이미지는_긴_변_1024로_줄고_EXIF와_표식은_분류기에도_닿지_않는다() {
        byte[] original = jpeg(1800, 900, true);
        assertThat(contains(original, "Exif")).isTrue();
        assertThat(contains(original, IMAGE_MARKER)).isTrue();

        Reply reply = postMultipart(new Multipart()
                .text("request", requestJson("a1|" + shortOcr()))
                .file("image.a1", original));

        assertThat(reply.status()).isEqualTo(200);
        byte[] delivered = provider.imageCalls.get(0);
        assertThat(decode(delivered).getWidth()).isEqualTo(1024);
        assertThat(decode(delivered).getHeight()).isEqualTo(512);
        assertThat(contains(delivered, "Exif")).isFalse();
        assertThat(contains(delivered, IMAGE_MARKER)).isFalse();
    }
}
