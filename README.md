# TransToWebp PowerShell Script

폴더별 이미지 시퀀스를 애니메이션 WebP로 일괄 변환하는 PowerShell 스크립트입니다. 파이썬/닷넷 미설치 환경에서도 동작하며, libwebp 도구가 없으면 자동으로 내려받아 사용합니다.

## 개요
- 입력: `Before/` 하위 폴더의 `.png/.jpg/.jpeg` 시퀀스
- 출력: `Webp/<폴더이름>.webp` (루트에만 이미지가 있으면 `Webp/root.webp`)
- 도구: libwebp (`img2webp.exe`, `cwebp.exe`) 자동 다운로드 → `tools/` 캐시

## 실행
- 'Before' 폴더와 'Webp' 폴더를 생성
```powershell
powershell -ExecutionPolicy Bypass -File .\convert_to_webp.ps1
```
- 루프 없는 버전은 _noLoop 스크립트를 실행하면 됩니다.

- 인터넷 차단 환경에서는 `tools/`에 `img2webp.exe`, `cwebp.exe`를 미리 넣어 두면 됩니다.

## 조정 가능한 옵션 (스크립트 상단 변수)
- ** `$frameDurationMs` ** : 프레임 딜레이(ms) — 83(≈12fps), 63(≈16fps), 41(≈24fps), 33(≈30fps) 
- `$quality` : 0~100 품질 (높을수록 용량 증가)
- `$method` : 0~6 속도/품질 트레이드오프 (높을수록 품질↑, 속도↓)
- `$exts` : 입력 확장자 목록

## 동작 방식
1) `Before/` 및 모든 하위 폴더를 스캔해 입력 시퀀스를 정렬된 파일명 기준으로 수집  
2) 각 폴더별로 애니메이션 WebP를 생성해 `Webp/`에 저장  
3) 명령줄 길이 제한을 피하기 위해 임시 작업 디렉터리에서 짧은 이름(하드링크/복사)으로 변환 후 정리

## 주의 및 트러블슈팅
- 경로 길이: 워크스페이스 경로가 너무 길면 여전히 영향 받을 수 있으니 가능하면 짧은 경로에서 실행
- 다운로드 실패: 프록시/방화벽으로 libwebp를 받지 못하면 수동으로 `tools/`에 두기
- 품질/용량 튜닝: `$quality`와 `$method` 값을 조정
- FPS 변경: `$frameDurationMs` 값 조정