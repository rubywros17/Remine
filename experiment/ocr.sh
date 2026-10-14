#!/usr/bin/env bash
# images/*.{jpg,jpeg,png} -> ocr/*.txt (Tesseract kor+eng), 그리고 labels.csv 템플릿 생성.
# 실행 (Git Bash):  bash experiment/ocr.sh
# 주의: 앱은 ML Kit을 쓰므로 Tesseract 결과는 실제 앱 OCR의 근사치다.
set -euo pipefail

cd "$(dirname "$0")"

TESSERACT="$(command -v tesseract || true)"
if [ -z "$TESSERACT" ] && [ -x "/c/Program Files/Tesseract-OCR/tesseract.exe" ]; then
  TESSERACT="/c/Program Files/Tesseract-OCR/tesseract.exe"
fi
if [ -z "$TESSERACT" ]; then
  echo "tesseract를 찾을 수 없습니다."
  echo "  설치: https://github.com/UB-Mannheim/tesseract/wiki (설치 중 'Korean' 언어 데이터 체크)"
  echo "  설치 후 Git Bash를 다시 열거나 PATH에 설치 폴더를 추가하세요."
  exit 1
fi
if ! "$TESSERACT" --list-langs | grep -qx "kor"; then
  echo "tesseract에 kor 언어 데이터가 없습니다. 설치 프로그램을 다시 실행해 'Korean'을 추가하세요."
  exit 1
fi

mkdir -p ocr
shopt -s nullglob nocaseglob
images=(images/*.jpg images/*.jpeg images/*.png)
if [ ${#images[@]} -eq 0 ]; then
  echo "images/ 에 이미지가 없습니다."
  exit 1
fi

done_count=0; skip_count=0
for img in "${images[@]}"; do
  name="$(basename "$img")"
  base="${name%.*}"
  if [ -s "ocr/$base.txt" ]; then
    skip_count=$((skip_count + 1))
    continue
  fi
  "$TESSERACT" "$img" "ocr/$base" -l kor+eng >/dev/null 2>&1
  done_count=$((done_count + 1))
  echo "OCR: $name"
done
echo "완료: 새로 ${done_count}장, 건너뜀 ${skip_count}장"

# labels.csv: 이미 있으면 덮어쓰지 않는다 (정답을 입력한 뒤 다시 실행해도 안전).
if [ -e labels.csv ]; then
  echo "labels.csv가 이미 있어 건드리지 않았습니다."
else
  {
    echo "filename,category"
    for img in "${images[@]}"; do
      basename "$img"
      done | sed 's/$/,/'
  } > labels.csv
  echo "labels.csv 템플릿 생성: category 칸을 채워주세요 (SHOPPING ENTERTAINMENT PLACE INFO CHAT SCHEDULE ETC)"
fi
