package com.remine.server.image;

import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageReadParam;
import javax.imageio.ImageReader;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.ImageInputStream;
import javax.imageio.stream.MemoryCacheImageInputStream;
import javax.imageio.stream.MemoryCacheImageOutputStream;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Iterator;

/**
 * 분석용 이미지 정규화: 디코딩 → (긴 변이 maxLongSide보다 크면) 축소 → JPEG 재인코딩. 확대하지 않는다.
 * 운영(analyze의 이미지 입력)과 실험 러너가 같은 코드를 쓴다. JDK 표준(ImageIO)만 쓴다.
 *
 * <p>흔적을 남기지 않는 설계:
 * <ul>
 *   <li>입출력은 모두 <b>메모리 스트림</b>({@code MemoryCacheImage*Stream})이다. {@code ImageIO.read(InputStream)}은
 *       디스크 캐시 파일을 쓸 수 있어 사용하지 않는다.</li>
 *   <li>항상 재인코딩하므로 EXIF·GPS 같은 메타데이터가 출력에 남지 않는다.</li>
 *   <li>예외는 사유 코드와 고정 문구만 담는다({@link InvalidImageException}). 바이트·ImageIO 메시지를 전달하지 않는다.</li>
 *   <li>픽셀 수 상한은 <b>디코딩 전에 헤더로</b> 확인하고, 큰 이미지는 서브샘플링으로 디코딩해 메모리를 줄인다.</li>
 * </ul>
 */
public final class ImageResizer {

    public static final int DEFAULT_MAX_LONG_SIDE = 1024;
    public static final long DEFAULT_MAX_PIXELS = 25_000_000L;
    private static final float JPEG_QUALITY = 0.85f;

    private ImageResizer() {
    }

    /** JPEG 매직 바이트(FF D8 FF)로 시작하는지. 선언된 Content-Type은 믿지 않는다. */
    public static boolean isJpeg(byte[] data) {
        return data != null && data.length >= 3
                && (data[0] & 0xFF) == 0xFF && (data[1] & 0xFF) == 0xD8 && (data[2] & 0xFF) == 0xFF;
    }

    /**
     * JPEG만 받아 긴 변을 maxLongSide 이하로 맞춘 JPEG를 돌려준다(메타데이터 제거).
     *
     * @throws InvalidImageException JPEG가 아니거나, 읽을 수 없거나, 픽셀 수가 maxPixels를 넘는 경우
     */
    public static byte[] normalizeJpeg(byte[] jpeg, int maxLongSide, long maxPixels) {
        if (!isJpeg(jpeg)) {
            throw new InvalidImageException(InvalidImageException.Reason.NOT_JPEG);
        }
        return decodeResizeEncode(jpeg, maxLongSide, maxPixels);
    }

    /** 실험 러너용: 파일을 읽어 정규화한다. 서비스 경로와 달리 PNG 등 ImageIO가 읽는 형식도 받는다. */
    public static byte[] toJpeg(Path file, int maxLongSide) throws IOException {
        byte[] data = Files.readAllBytes(file);
        try {
            return decodeResizeEncode(data, maxLongSide, DEFAULT_MAX_PIXELS);
        } catch (InvalidImageException e) {
            throw new IOException("읽을 수 없는 이미지: " + file.getFileName() + " (" + e.reason() + ")");
        }
    }

    private static byte[] decodeResizeEncode(byte[] data, int maxLongSide, long maxPixels) {
        BufferedImage source = decode(data, maxLongSide, maxPixels);
        try {
            return encodeJpeg(resize(source, maxLongSide));
        } catch (IOException | RuntimeException e) {
            // 원인 예외의 메시지를 전달하지 않는다
            throw new InvalidImageException(InvalidImageException.Reason.UNREADABLE);
        }
    }

    private static BufferedImage decode(byte[] data, int maxLongSide, long maxPixels) {
        try (ImageInputStream in = new MemoryCacheImageInputStream(new ByteArrayInputStream(data))) {
            Iterator<ImageReader> readers = ImageIO.getImageReaders(in);
            if (!readers.hasNext()) {
                throw new InvalidImageException(InvalidImageException.Reason.UNREADABLE);
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(in, true, true);
                int width = reader.getWidth(0);
                int height = reader.getHeight(0);
                if (width <= 0 || height <= 0 || (long) width * height > maxPixels) {
                    throw new InvalidImageException(InvalidImageException.Reason.TOO_MANY_PIXELS);
                }
                ImageReadParam param = reader.getDefaultReadParam();
                // 목표(maxLongSide)의 2배보다 크면 서브샘플링으로 줄여 읽는다 → 디코딩 메모리 절약
                int subsampling = Math.max(1, Math.max(width, height) / (maxLongSide * 2));
                if (subsampling > 1) {
                    param.setSourceSubsampling(subsampling, subsampling, 0, 0);
                }
                return reader.read(0, param);
            } finally {
                reader.dispose();
            }
        } catch (InvalidImageException e) {
            throw e;
        } catch (IOException | RuntimeException e) {
            throw new InvalidImageException(InvalidImageException.Reason.UNREADABLE);
        }
    }

    /** 긴 변이 maxLongSide보다 크면 비율을 유지해 줄이고, 아니면 크기를 그대로 둔다. 알파는 흰 배경에 합성한다. */
    static BufferedImage resize(BufferedImage source, int maxLongSide) {
        int width = source.getWidth();
        int height = source.getHeight();
        double scale = Math.min(1.0, (double) maxLongSide / Math.max(width, height));
        int newWidth = Math.max(1, (int) Math.round(width * scale));
        int newHeight = Math.max(1, (int) Math.round(height * scale));

        BufferedImage target = new BufferedImage(newWidth, newHeight, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = target.createGraphics();
        try {
            g.setColor(Color.WHITE);
            g.fillRect(0, 0, newWidth, newHeight);
            g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
            g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            g.drawImage(source, 0, 0, newWidth, newHeight, null);
        } finally {
            g.dispose();
        }
        return target;
    }

    private static byte[] encodeJpeg(BufferedImage image) throws IOException {
        ImageWriter writer = ImageIO.getImageWritersByFormatName("jpeg").next();
        ImageWriteParam param = writer.getDefaultWriteParam();
        param.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
        param.setCompressionQuality(JPEG_QUALITY);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (MemoryCacheImageOutputStream stream = new MemoryCacheImageOutputStream(out)) {
            writer.setOutput(stream);
            writer.write(null, new IIOImage(image, null, null), param);
        } finally {
            writer.dispose();
        }
        return out.toByteArray();
    }
}
