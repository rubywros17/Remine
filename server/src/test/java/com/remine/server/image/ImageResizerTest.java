package com.remine.server.image;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ImageResizerTest {

    private Path writePng(Path dir, int width, int height) throws IOException {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        Path file = dir.resolve("img.png");
        ImageIO.write(image, "png", file.toFile());
        return file;
    }

    private BufferedImage decode(byte[] jpeg) throws IOException {
        return ImageIO.read(new ByteArrayInputStream(jpeg));
    }

    @Test
    void 긴_변이_1024를_넘으면_비율을_유지해_줄인다(@TempDir Path dir) throws IOException {
        Path file = writePng(dir, 1080, 2400); // 갤럭시 스크린샷 비율

        BufferedImage result = decode(ImageResizer.toJpeg(file, 1024));

        assertThat(result.getHeight()).isEqualTo(1024);
        assertThat(result.getWidth()).isEqualTo(461); // 1080 * 1024 / 2400
    }

    @Test
    void 가로가_긴_이미지도_긴_변을_기준으로_줄인다(@TempDir Path dir) throws IOException {
        Path file = writePng(dir, 3000, 1500);

        BufferedImage result = decode(ImageResizer.toJpeg(file, 1024));

        assertThat(result.getWidth()).isEqualTo(1024);
        assertThat(result.getHeight()).isEqualTo(512);
    }

    @Test
    void 이미_작은_이미지는_확대하지_않는다(@TempDir Path dir) throws IOException {
        Path file = writePng(dir, 400, 300);

        BufferedImage result = decode(ImageResizer.toJpeg(file, 1024));

        assertThat(result.getWidth()).isEqualTo(400);
        assertThat(result.getHeight()).isEqualTo(300);
    }

    @Test
    void 결과는_JPEG이다(@TempDir Path dir) throws IOException {
        byte[] jpeg = ImageResizer.toJpeg(writePng(dir, 100, 100), 1024);

        assertThat(jpeg[0] & 0xFF).isEqualTo(0xFF);
        assertThat(jpeg[1] & 0xFF).isEqualTo(0xD8); // JPEG SOI 마커
    }

    private byte[] jpeg(int width, int height) throws IOException {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        ImageIO.write(image, "jpeg", out);
        return out.toByteArray();
    }

    @Test
    void 바이트_API는_JPEG를_줄여_재인코딩한다() throws IOException {
        byte[] result = ImageResizer.normalizeJpeg(jpeg(3000, 1500), 1024, 25_000_000L);

        BufferedImage image = decode(result);
        assertThat(image.getWidth()).isEqualTo(1024);
        assertThat(image.getHeight()).isEqualTo(512);
    }

    @Test
    void JPEG가_아니면_사유_코드만_담은_예외() throws IOException {
        BufferedImage image = new BufferedImage(10, 10, BufferedImage.TYPE_INT_RGB);
        java.io.ByteArrayOutputStream png = new java.io.ByteArrayOutputStream();
        ImageIO.write(image, "png", png);

        assertThatThrownBy(() -> ImageResizer.normalizeJpeg(png.toByteArray(), 1024, 25_000_000L))
                .isInstanceOfSatisfying(InvalidImageException.class,
                        e -> assertThat(e.reason()).isEqualTo(InvalidImageException.Reason.NOT_JPEG));
    }

    @Test
    void 헤더만_JPEG인_손상_파일은_읽을_수_없음() {
        byte[] broken = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 0, 1, 2, 3};

        assertThatThrownBy(() -> ImageResizer.normalizeJpeg(broken, 1024, 25_000_000L))
                .isInstanceOfSatisfying(InvalidImageException.class,
                        e -> assertThat(e.reason()).isEqualTo(InvalidImageException.Reason.UNREADABLE));
    }

    @Test
    void 픽셀_수가_상한을_넘으면_디코딩_전에_거부한다() throws IOException {
        byte[] big = jpeg(2000, 1000); // 2,000,000px

        assertThatThrownBy(() -> ImageResizer.normalizeJpeg(big, 1024, 1_000_000L))
                .isInstanceOfSatisfying(InvalidImageException.class,
                        e -> assertThat(e.reason()).isEqualTo(InvalidImageException.Reason.TOO_MANY_PIXELS));
    }

    @Test
    void 이미지가_아니면_예외(@TempDir Path dir) throws IOException {
        Path notImage = dir.resolve("a.jpg");
        Files.writeString(notImage, "이미지 아님");

        assertThatThrownBy(() -> ImageResizer.toJpeg(notImage, 1024)).isInstanceOf(IOException.class);
    }
}
