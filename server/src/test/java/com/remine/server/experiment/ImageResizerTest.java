package com.remine.server.experiment;

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

    @Test
    void 이미지가_아니면_예외(@TempDir Path dir) throws IOException {
        Path notImage = dir.resolve("a.jpg");
        Files.writeString(notImage, "이미지 아님");

        assertThatThrownBy(() -> ImageResizer.toJpeg(notImage, 1024)).isInstanceOf(IOException.class);
    }
}
