#!/usr/bin/env python3
"""앱(디버그 OCR 측정 화면)이 내보낸 ML Kit 결과 JSON과 Tesseract 결과(ocr/*.txt)를 파일명 기준으로 비교한다.

실행 (Git Bash):  python experiment/compare_mlkit.py [experiment/mlkit/ocr-export-....json]
- JSON을 안 주면 experiment/mlkit/ 의 가장 최근 파일을 쓴다.
- 출력: experiment/compare.local.mlkit-vs-tesseract.md  (글자 수 비교 + 기준값 경계 변화)
- --show-text 를 주면 파일마다 두 엔진의 앞 60자를 같이 적는다.

주의: 입력 JSON과 출력 파일에는 OCR 원문(개인 데이터)이 들어 있을 수 있다. 둘 다 .gitignore 대상이며 커밋하지 않는다.
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
THRESHOLD = 150  # spec의 OCR 글자 수 기준값(공백 제외)


def count(text: str) -> int:
    return len(re.sub(r"\s", "", text))


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    show_text = "--show-text" in sys.argv
    if args:
        src = Path(args[0])
    else:
        files = sorted((HERE / "mlkit").glob("ocr-export-*.json"))
        if not files:
            sys.exit("experiment/mlkit/ 에 내보낸 JSON이 없습니다. (adb pull 로 가져오세요)")
        src = files[-1]

    data = json.loads(src.read_text(encoding="utf-8"))
    tess = {p.stem: p.read_text(encoding="utf-8", errors="replace") for p in (HERE / "ocr").glob("*.txt")}

    rows, missing = [], []
    for item in data["items"]:
        stem = Path(item["fileName"]).stem
        if stem not in tess:
            missing.append(item["fileName"])
            continue
        rows.append((stem, count(tess[stem]), item["charCount"], tess[stem], item["text"]))

    lines = [
        "# ML Kit vs Tesseract (개인 데이터 포함 — 커밋 금지)",
        "",
        f"- 입력: `{src.name}` · 엔진 `{data.get('engine')}` · 비교 {len(rows)}장 · 짝 없음 {len(missing)}장",
        "",
        "| 파일 | Tesseract 글자 수 | ML Kit 글자 수 | 150자 기준 |",
        "|---|---:|---:|---|",
    ]
    flips = 0
    for stem, t, m, tt, mt in rows:
        side = lambda n: "이상" if n >= THRESHOLD else "미만"
        flip = side(t) != side(m)
        flips += flip
        lines.append(f"| {stem} | {t} | {m} | {side(t)}→{side(m)}{' ⚠' if flip else ''} |")
        if show_text:
            lines.append(f"|  | `{tt[:60]!r}` | `{mt[:60]!r}` | |")
    if rows:
        lines += [
            "",
            f"- 평균 글자 수: Tesseract {sum(r[1] for r in rows) / len(rows):.0f} / ML Kit {sum(r[2] for r in rows) / len(rows):.0f}",
            f"- {THRESHOLD}자 기준을 가로지르는 장: {flips}장 (하이브리드 분류에서 텍스트만/이미지 동봉이 바뀌는 장)",
        ]
    if missing:
        lines += ["", "짝이 없는 파일: " + ", ".join(missing)]

    out = HERE / "compare.local.mlkit-vs-tesseract.md"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(rows)}장 비교 → {out.name}")


if __name__ == "__main__":
    main()
