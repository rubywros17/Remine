package com.remine.server.classifier;

import com.remine.server.domain.screenshot.Category;

import java.util.List;

public record ClassificationResult(Category category, List<String> tags, String summary) {
}
