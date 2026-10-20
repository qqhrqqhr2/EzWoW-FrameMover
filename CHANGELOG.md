# Changelog - EzWoW - Frame Mover

## v2.0.0

### English

- Fixed window dragging offsets and initial jumps at different UI scales.
- Added a resizable, scrollable quest tracker with zone headings, difficulty colours, objective progress and quest-item buttons.
- Added optional Ctrl-only dragging and Alt+drag support for subwindows.
- Added hover-help controls and selectable quick-reset shortcuts.

### 한국어

- UI 배율에 따라 창을 끌 때 위치가 어긋나거나 처음에 튀는 문제를 수정했습니다.
- 지역·난이도·목표 진행도·퀘스트 아이템 버튼을 표시하는 스크롤형 추적기를 추가했습니다.
- Ctrl을 누를 때만 이동하는 옵션과 Alt+드래그 하위 창 분리를 지원합니다.
- 조작 안내 표시 설정과 빠른 위치 초기화 단축키 선택을 추가했습니다.

## v1.1.0
- 드래그 시 마우스 포인터와 아이콘/프레임 좌표가 어긋나거나 벌어지는 스케일 오차(`EffectiveScale`) 및 초기 점프 현상 수정
- **모듈 구조 재구성 (`Core/`, `Data/`, `Modules/`, `UI/`) 및 전용 퀘스트 추적기 통합**:
  - `Core/Init.lua`, `Core/Locales.lua`, `Core/UIKit.lua`
  - `Data/StandardFrames.lua`, `Modules/MoverEngine.lua`
  - `UI/QuestTracker.lua`(스크롤형 퀘스트 추적기 및 퀘스트 아이템 보안 버튼), `UI/OptionsWindow.lua`
- **신규 및 개선 기능**:
  - 전용 스크롤형 퀘스트 추적기(`UI/QuestTracker.lua`) 탑재: 지역 헤더·난이도별 `[Lv]` 색상·목표 진행도 색상·퀘스트 아이템 버튼·마우스 휠 스크롤·모서리 크기 조절 지원
  - `Ctrl` 키를 누른 상태에서만 창 드래그 이동 허용 옵션 및 `Alt + 좌클릭 드래그` 하위 창 분리 이동 지원
  - 창 마우스오버 조작 안내 툴팁 ON/OFF 및 빠른 초기화 단축키(`Ctrl+Alt+우클릭` / `Alt+우클릭` / `Ctrl+우클릭`) 선택 기능 추가

## v1.0.0
- 초기 출시: 블리자드 기본 UI 창 및 지연 로딩(LoD) 창 마우스 드래그 이동, 위치 영구 저장(`EzWoW_FrameMoverDB`), `Ctrl + 마우스 휠` 크기 조절(`50%~150%`), 8개 언어 실시간 전환 지원
