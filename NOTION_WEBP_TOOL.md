# TransToWebp 변환 스크립트 (디자인팀용)

- 디자인팀 산출물(PNG/JPG 시퀀스)을 외주 개발 요청 사양에 맞춰 애니메이션 WebP로 일괄 변환
- 비개발자도 PowerShell 한 번 실행으로 처리

## 동작 개요
- `Before/` 하위 각 폴더의 이미지 시퀀스 → 단일 애니메이션 WebP(`Webp/<폴더>.webp`)
- 루트에 이미지만 있는 경우 `Webp/root.webp` 생성
- libwebp(`img2webp.exe`, `cwebp.exe`) 없으면 자동 다운로드 후 사용

## 폴더/파일 구조
- `Before/` : 입력 이미지 폴더들 (png/jpg/jpeg)
- `Webp/` : 결과 WebP
- `tools/` : libwebp 도구 캐시(`img2webp.exe`, `cwebp.exe`)
- `convert_to_webp.ps1` : 실행 스크립트

## 실행 방법
```powershell
powershell -ExecutionPolicy Bypass -File .\convert_to_webp.ps1
```
- 인터넷 차단 환경: 미리 `tools/`에 `img2webp.exe`, `cwebp.exe` 넣어두면 다운로드 없이 실행

## 주요 옵션(스크립트 상단 변수)
- `$frameDurationMs` : 프레임 딜레이(ms) (예: 33 ≈ 30fps, 41 ≈ 24fps)
- `$quality` : 품질 0~100 (높을수록 용량↑)
- `$method` : 0~6 (낮을수록 빠름, 높을수록 품질↑)
- `$exts` : 입력 확장자 목록

## 대용량·다프레임 대응 (다프레임은 도중에 비정상종료되는 이슈 해결)
- 문제: 900+ 프레임, 긴 경로로 인해 Windows 명령줄 길이 제한 초과 → `img2webp` 호출 실패
- 해결: 임시 작업 디렉터리에서 짧은 파일명으로 하드링크(안되면 복사) 생성 후 변환, 완료 후 정리
- 결과: 900+ 프레임 시퀀스도 정상 변환 (`Webp/infographic2.webp`)

## 장점
- 파이썬/닷넷 미의존, PowerShell만으로 실행
- 폴더 구조 자동 감지, 추가 설정 없이 일괄 변환
- 실패 지점 로그로 바로 확인

## 트러블슈팅
- 도구 다운로드 실패: 프록시/방화벽 확인 후 `tools/`에 수동 배치
- 용량/품질 조정: `$quality` 낮추기, `$method` 낮추기
- 속도 조정: `$method` 낮추면 빠르나 품질 감소
- 프레임 속도: `$frameDurationMs` 조정
- 경로 길이: 가능한 짧은 루트 경로에서 실행

## 변경 이력
- v1: 폴더별 프레임 → 단일 애니메이션 WebP 생성
- v2: 대용량·긴 경로 대응(임시 짧은 경로 하드링크/복사) 추가

## 향후 가능 개선
- 폴더별 커스텀 FPS/품질 설정 지원
- 변환 요약 리포트(성공/실패, 용량 변화) 출력
- 환경에 ffmpeg가 있을 경우 대체 경로 제공 옵션
