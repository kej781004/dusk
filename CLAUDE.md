# Dusk — AI 컨텍스트

## 한 줄 정체
Awayke(https://github.com/daemonphantom/Awayke)를 대신하는 자작 메뉴바 앱. 뚜껑을 닫아도
맥이 잠들지 않게 한다. `/Applications/Dusk.app`에 설치돼 있다. 2026-08-14 시작, 같은 날 전면 재작성.

## 현재 상태
본체 기능(뚜껑 열림 유지) + 딸린 스위치 둘(저전력 모드, 화면 어둡게) + 타이머/배터리 자동 끄기까지
구현 완료. 지뢰 5개 전부 실측·수정됨. **미확인**: 실제 뚜껑 닫기 end-to-end 테스트(sudoers 4줄
재설치 후에나 가능), 배터리 임계값 자동 끄기 → 충전 후 되살아나는 전체 사이클.

## 핵심 구조
- **본체는 `pmset -a disablesleep`이다.** 뚜껑 닫힘 전용 잠자기 경로는 이것만 듣는다 —
  `caffeinate`나 디스플레이 어서션으로는 못 막는다. `lowpowermode`는 **이것과 무관**(그냥 배터리 절약).
- 좌클릭 = 켜기/끄기(아이콘이 그 자체), 우클릭 = 메뉴(저전력 모드·화면 어둡게 스위치, 타이머, 배터리 자동 끄기).
- 밝기 제어는 `DisplayServices` 비공개 프레임워크(dlopen) — 권한 불필요, ad-hoc 서명으로 충분.
  Awayke의 SMAppService 헬퍼는 정식 Developer ID가 필요해서 이 맥에선 못 씀.
- 진단 로그: `Sources/Dusk/Log.swift`, subsystem `parkchanbin.Dusk`.
  `log show --predicate 'subsystem == "parkchanbin.Dusk"' --last 1d --info`

## 절대 반복하면 안 되는 지뢰
1. **잠자기/깨어남을 안 다루면 검은 화면 + 무지개 커서에 갇힌다.** macOS는 잠들기 직전 밝기를 기억했다가 그대로 복원한다 → 밝기 0으로 자면 0으로 깬다. F2 탈출구는 밝기가 *올라갈 때만* 발동해서 영영 못 나온다. 게다가 감시 타이머가 그 구간에 메인 스레드에서 `DisplayServices`를 계속 두드려 블로킹된다. **해법**: willSleep/screensDidSleep에서 타이머 전부 끄고 밝기 복원 후 자고, didWake/screensDidWake에서 1초 뒤 다시 어둡게.
2. **`sudo -l`로는 "암호 없이 되나"를 알 수 없다.** 관리자 계정이면 규칙이 없어도 통과한다. 실행해서 종료 코드로 확인. **모든 sudo 호출에 `-n -k`** — `-k` 없으면 다른 데서 암호 친 직후엔 되다가 만료되면 갑자기 깨지는 함정.
3. **`pmset`은 구분자가 일정하지 않다.** `-g custom`은 공백, `-g`의 시스템 전역 블록은 **탭**. 공백으로만 쪼개면 `SleepDisabled`를 조용히 "없음"으로 읽는다.
4. **pmset 설정·밝기는 프로세스보다 오래 산다.** 강제 종료되면 영영 못 자거나 화면 0인 채 남는다. 켤 때 `disablesleep 0`+밝기 복구, 끌 때 되돌리기 — 단 **저전력 모드는 안 되돌린다**(사람이 시스템 설정에서 직접 켤 수도 있음).
5. **이벤트만 믿는 배터리 감시는 조용히 멈춘다.** `IOPSNotificationCreateRunLoopSource`는 전원이 *변할 때만* 부름 — 100%로 충전 끝나고 가만있으면 알림이 아예 안 온다. `handleBattery`에 결정 없이 빠져나가는 출구가 있으면 재개가 한 번 실패하고 영영 안 켜진다. **해법**: `intent` 참인 동안 60초마다 `currentSnapshot()`으로 재검사하는 타이머.

**Dusk가 켜졌는지 확실히 판별하는 법**: `pmset -g assertions` — 켜져 있으면 `kIOPMAssertPreventUserIdleDisplaySleep`를 잡는다. 그러니 "잠금화면이 떴다 = 그 시점 Dusk는 꺼져 있었다"가 성립. `pmset -g log`엔 disablesleep 변경이 안 남으므로 사후 추적은 assertions 쪽으로.

**틀렸던 진단, 반복 금지**: (1) `com.apple.ncprefs.plist`에 없다고 "알림 권한 없음" 단정 — 틀림, 그 파일은 갱신이 밀릴 뿐. `requestAuthorization` 결과를 로그로 확인할 것. (2) 사람 기억("알림 왔었나?")만으로 정상 작동 결론 — 검증은 시스템 기록으로만.

메뉴 스위치는 커스텀 뷰 필수(AppKit엔 스위치형 메뉴 항목이 없음), 스위치 뒤집으면 메뉴를 먼저 닫고 다음 런루프에서 적용해야 한다(메뉴 추적 중엔 모달이 제대로 안 뜸).

## 남은 일
- 실제 뚜껑 닫기 end-to-end 확인
- 배터리 자동 끄기 → 충전 후 재개 전체 사이클 확인

관련: [[parrot]], [[beacon]] (`.accessory` 앱 공통 지뢰)
