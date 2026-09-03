# NotiEcho 프로젝트 현황 (인수인계 문서)

> 새 대화/새 모델에서 이 프로젝트를 이어받을 때 이 문서를 먼저 읽으세요.
> 최종 업데이트: 2026-09-03

## 1. 앱 개요
- **앱 이름**: Noti Echo (NotiEcho) — "노티" 시리즈
- **패키지명**: `com.notiecho.vocab`
- **컨셉**: 논문/페이퍼를 읽다가 새 단어를 **음성으로 캡처**하고, **입 밖으로 소리 내어 반복**(에코)하며 암기하는 앱
- **핵심 철학**: 반복이 가장 중요. 단기기억(반복 청취) → 시험(능동적 회상) → 장기기억 창고 승격
- **사용자**: 한국인 (UI 한국어, 단어는 영어, 뜻은 한글 우선)
- **디자인**: 사용자가 3개 시안 중 **Style 1 (모던 Material Design 3, 딥 인디고 #303F9F + 틸 #26A69A)** 선택

## 2. 구현 완료된 기능 (v1.0.0)

### 녹음 탭 (lib/screens/record_screen.dart)
- 큰 녹음 버튼 + 에코 링 애니메이션 → STT(speech_to_text, en_US) 인식 + 동시에 내 목소리 녹음(record 패키지)
- 인식 결과 텍스트필드에서 **오리지널 단어로 정정** 가능, 직접 입력 모드도 있음
- 뜻 자동 조회: 한글 번역(MyMemory API) + 영어 정의(dictionaryapi.dev) 합쳐서 표시
- "표준 발음(원어민 발음)" / "내 녹음" 버튼 2개
- 태그 선택/새 태그 생성 → 저장 시 발음 1회 자동 재생

### 플레이 탭 (lib/screens/play_screen.dart)
- 필터: 태그별 / 날짜별 / 기억단계별(단기/장기/전체)
- 체크박스로 재생 목록 선택 (미선택 시 전체)
- 단일 재생 / 전체 반복(루프) 재생
- 재생 옵션: 단어당 반복 횟수(1-5), 단어 간격(0.5-5초), 목소리(AI/내 목소리/둘 다)
- 재생 횟수(playCount) 기록

### 시험 탭 (lib/screens/test_screen.dart)
- 모드 A: 발음 듣고 뜻 말하기 / 모드 B: 뜻 보고 단어 말하기
- 자가 판정(몰랐어요/말했어요) → **연속 3회 정답 시 장기기억(stage='long') 승격**
- 틀리면 연속 기록 리셋. 세션 결과 다이얼로그

### 관리 탭 (lib/screens/manage_screen.dart)
- 통계(전체/오늘/단기/장기), 태그 수정·삭제, 단어 수정·삭제·단기↔장기 수동 이동

## 3. 발음 시스템 (중요! 사용자가 가장 신경쓰는 부분)
사용자가 "구글 검색 발음 수준"을 강력히 요구함. 현재 우선순위:
1. **구글 번역 TTS mp3** (`translate.google.com/translate_tts?client=tw-ob`) — 구글 검색과 동급 품질
   - ⚠️ **웹에서는 브라우저 Referer 때문에 구글이 404 차단** → `web_server.py`의 `/tts?q=word` 프록시 경유
   - 모바일(APK)은 직접 호출 OK (audio_service.dart에서 kIsWeb 분기)
2. 사전 API 원어민 녹음 mp3 (nativeAudioUrl, 미국 발음 우선)
3. 기기 TTS 폴백 (고품질 보이스 점수제 자동 선택)

## 4. 기술 스택
- Flutter 3.35.4 / Dart 3.9.2 (버전 고정, 업데이트 금지)
- 상태관리: provider / 저장소: Hive (words_box, tags_box)
- 주요 패키지: speech_to_text, flutter_tts, record, audioplayers, http, intl, permission_handler
- 데이터 모델: lib/models/word_entry.dart (word, meaning, tags, myVoicePath, nativeAudioUrl, stage, correctStreak, playCount...)

## 5. 빌드/배포 상태
- **웹 프리뷰**: `flutter build web --release` 후 `python3 web_server.py 5060` (build/web에서 실행, TTS 프록시 포함 커스텀 서버 필수!)
- **APK**: v1.0.0 릴리즈 빌드 성공, 서명 완료 (android/release-key.jks + key.properties, build.gradle.kts에 release signingConfig 설정됨)
- 웹 매니페스트/아이콘 NotiEcho 브랜딩 적용 완료 (에코 마이크 아이콘, /home/user/assets/icons/app_icon.png)
- Android 권한: RECORD_AUDIO, INTERNET + 음성인식/TTS 서비스 쿼리 (AndroidManifest.xml)

## 6. 알려진 이슈 / 주의사항
- 첫 APK 빌드 시 flutter build가 일시 오류 낼 수 있음 → `cd android && ./gradlew assembleRelease --no-daemon`으로 재시도하면 성공
- ProjectBackup 도구가 gradle 데몬의 .kotlin 임시파일 때문에 실패할 수 있음 → `rm -rf android/.kotlin android/.gradle` 후 재시도
- 웹에서 발음 테스트할 때는 반드시 web_server.py 커스텀 서버 사용 (일반 http.server는 /tts 프록시 없어서 발음 저품질로 폴백됨)

## 7. 향후 로드맵 (사용자와 논의된 것)
- [ ] 발음 속도 "느림" 토글 (구글처럼) — web_server.py에 slow=1 파라미터 이미 구현되어 있음, UI만 붙이면 됨
- [ ] 망각곡선 기반 복습 알림
- [ ] 발음 기호(IPA) 표시
- [ ] AI 목소리 추가 녹음/선택 기능 고도화
