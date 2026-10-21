package com.remine.server.experiment;

import com.remine.server.classifier.llm.LlmOutcome.Status;
import com.remine.server.classifier.llm.PromptVersion;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.experiment.RunCsv.Row;
import com.remine.server.experiment.RunCsv.Run;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import tools.jackson.databind.json.JsonMapper;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class MlKitRemeasureTest {

    private static Row row(String name, Category predicted, int chars) {
        return new Row(name, Category.PLACE, null, predicted, Status.OK, true, chars);
    }

    private static Run run(Row... rows) {
        return new Run("c", PromptVersion.V1, "t", List.of(rows));
    }

    @Test
    void 기준값을_가로지르는_장만_골라_엔진별_하이브리드_선택을_비교한다() {
        // a: Tesseract 200자(텍스트 실행, 오답) → ML Kit 100자(이미지 실행, 정답)
        // b: 둘 다 100자 미만(변화 없음)
        var tess = new MlKitRemeasure.Engine(
                run(row("a", Category.ETC, 200), row("b", Category.PLACE, 50)),
                run(row("a", Category.PLACE, 200), row("b", Category.PLACE, 50)));
        var mlkit = new MlKitRemeasure.Engine(
                run(row("a", Category.ETC, 100), row("b", Category.PLACE, 60)),
                run(row("a", Category.PLACE, 100), row("b", Category.PLACE, 60)));

        var flips = MlKitRemeasure.flips(tess, mlkit, 150);

        assertThat(flips).hasSize(1);
        assertThat(flips.get(0).filename()).isEqualTo("a");
        assertThat(flips.get(0).tesseract().strictCorrect()).isFalse();
        assertThat(flips.get(0).mlkit().strictCorrect()).isTrue();
        assertThat(mlkit.hybrid(150).correct()).isEqualTo(2);
        assertThat(tess.hybrid(150).correct()).isEqualTo(1);
    }

    @Test
    void 내보낸_JSON을_확장자_뺀_파일명으로_읽는다(@TempDir Path tmp) throws Exception {
        Path json = tmp.resolve("e.json");
        Files.writeString(json, "{\"items\":[{\"fileName\":\"S_1.jpg\",\"charCount\":3,\"text\":\" 안녕 \"}]}");

        assertThat(MlKitOcr.load(json, JsonMapper.builder().build())).containsEntry("S_1", "안녕");
    }
}
