package com.remine.server.controller;

import com.remine.server.domain.screenshot.Category;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeResponse;
import com.remine.server.dto.CategoryUpdateRequest;
import com.remine.server.dto.CategoryUpdateResponse;
import com.remine.server.dto.ForgetRequest;
import com.remine.server.dto.TrashRequest;
import com.remine.server.dto.ScreenshotPageResponse;
import com.remine.server.service.ScreenshotCategoryService;
import com.remine.server.service.ScreenshotForgetService;
import com.remine.server.service.ScreenshotTrashService;
import com.remine.server.service.ScreenshotQueryService;
import com.remine.server.service.ScreenshotService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/screenshots")
@RequiredArgsConstructor
public class ScreenshotController {

    private final ScreenshotService screenshotService;
    private final ScreenshotQueryService screenshotQueryService;
    private final AnalyzeMultipartReader multipartReader;
    private final ScreenshotCategoryService categoryService;
    private final ScreenshotForgetService forgetService;
    private final ScreenshotTrashService trashService;

    @PostMapping(value = "/analyze", consumes = MediaType.APPLICATION_JSON_VALUE)
    public AnalyzeResponse analyze(@RequestHeader("X-Device-Id") Long deviceId,
                                   @Valid @RequestBody AnalyzeRequest request) {
        return screenshotService.analyze(deviceId, request);
    }

    /** 이미지를 함께 보내는 형식. 이미지는 요청 처리 중 지역 변수로만 다루고 어디에도 저장하지 않는다. */
    @PostMapping(value = "/analyze", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public AnalyzeResponse analyzeWithImages(@RequestHeader("X-Device-Id") Long deviceId,
                                             @RequestParam(value = "request", required = false) String requestJson,
                                             @RequestParam MultiValueMap<String, MultipartFile> files) {
        AnalyzeRequest request = multipartReader.readRequest(requestJson);
        return screenshotService.analyze(deviceId, request, multipartReader.readImages(files, request));
    }

    @PatchMapping("/{id}/category")
    public CategoryUpdateResponse updateCategory(@RequestHeader("X-Device-Id") Long deviceId,
                                                 @PathVariable("id") Long id,
                                                 @RequestBody CategoryUpdateRequest request) {
        return categoryService.updateCategory(deviceId, id, request.category());
    }

    /** 앱이 보내지 말았어야 할 캡처(Remine 자기 캡처 등)를 서버에서 지운다. 없는 id는 무시 → 204. */
    @PostMapping("/forget")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void forget(@RequestHeader("X-Device-Id") Long deviceId,
                       @Valid @RequestBody ForgetRequest request) {
        forgetService.forget(deviceId, request.assetIds());
    }

    /** 앱 휴지통에 넣은 캡처를 관심사 집계·푸시에서 뺀다. 없는 id는 무시 → 204. */
    @PostMapping("/trash")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void trash(@RequestHeader("X-Device-Id") Long deviceId,
                      @Valid @RequestBody TrashRequest request) {
        trashService.trash(deviceId, request.assetIds());
    }

    /** 앱 휴지통에서 되살린 캡처를 다시 집계에 넣는다. 없는 id는 무시 → 204. */
    @PostMapping("/restore")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void restore(@RequestHeader("X-Device-Id") Long deviceId,
                        @Valid @RequestBody TrashRequest request) {
        trashService.restore(deviceId, request.assetIds());
    }

    @GetMapping
    public ScreenshotPageResponse list(@RequestHeader("X-Device-Id") Long deviceId,
                                       @RequestParam(required = false) Category category,
                                       @RequestParam(required = false) String tag,
                                       @RequestParam(defaultValue = "0") @Min(0) int page,
                                       @RequestParam(defaultValue = "30") @Min(1) @Max(100) int size) {
        return screenshotQueryService.list(deviceId, category, tag, page, size);
    }
}
