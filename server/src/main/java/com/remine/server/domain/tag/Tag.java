package com.remine.server.domain.tag;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.text.Normalizer;
import java.util.Locale;

@Entity
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Tag {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // 화면에 보이는 이름. 같은 키의 태그가 처음 들어왔을 때의 표기를 유지한다("니트 가디건").
    @Column(nullable = false)
    private String name;

    // 같은 태그인지 판단하는 키({@link #keyOf}). 키가 같은 태그는 하나만 두고 여러 스크린샷이 공유한다. (관심사 빈도 집계의 기준)
    @Column(nullable = false, unique = true)
    private String normalizedName;

    public Tag(String name) {
        this.name = name;
        this.normalizedName = keyOf(name);
    }

    /** "#니트 가디건", "니트가디건", "NIKE"/"nike"를 같은 태그로 보는 키: '#'·공백 제거, 소문자, NFC. */
    public static String keyOf(String name) {
        String stripped = name.replace("#", "").replaceAll("\\s+", "").toLowerCase(Locale.ROOT);
        return Normalizer.normalize(stripped, Normalizer.Form.NFC);
    }
}
