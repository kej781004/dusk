# Dusk

**뚜껑을 닫아도 안 자는** 맥을 만드는 메뉴바 앱. [Awayke](https://github.com/daemonphantom/Awayke)를
그대로 옮겨 오고, 화면 어둡게 · 저전력 모드 두 스위치를 얹었다.

## 쓰는 법

| 동작 | 결과 |
|---|---|
| 아이콘 **좌클릭** | Dusk 켜기 / 끄기 — **이것만이** 켜고 끈다. 켤 땐 **20분 타이머 모드**로 켜진다 (무기한은 메뉴의 「계속」) |
| 아이콘 **우클릭** (트랙패드 두 손가락) | 메뉴 — 딸려 올 것 고르기, 타이머, 배터리 자동 끄기 |

아이콘은 뚜껑 스위치만 따라간다. 꺼짐은 흰 `∠`, 켜짐은 주황 `∠` — 모양은 같고 색만 바뀐다.
(저전력 모드는 사람이 시스템 설정에서 켜 두기도 하는 값이라, 그걸 아이콘에 반영하면
Dusk가 한 적 없는 일을 켜진 것처럼 보여 준다.)

### 켜면 일어나는 일

| | 실제로 하는 일 |
|---|---|
| 뚜껑 닫아도 안 자기 | `pmset -a disablesleep 1` |
| 저전력 모드 | `pmset -a lowpowermode 1` |
| 화면 어둡게 | 백라이트를 3초에 걸쳐 0으로 (끌 땐 0.8초) |

**뚜껑은 메뉴에 없다.** 그게 이 앱 자체라서, 아이콘을 켜면 같이 켜지고 끄면 같이 꺼진다.

메뉴의 **저전력 모드 · 화면 어둡게는 스위치가 아니라 설정이다.** "좌클릭으로 켤 때 이것도
같이 켤까"를 정할 뿐, 그걸 뒤집는다고 Dusk가 켜지거나 꺼지지 않는다. 켜져 있는 동안 뒤집으면
그 자리에서 바로 반영되고, 꺼져 있는 동안 뒤집으면 다음에 켤 때부터 적용된다.

맥은 뚜껑 닫힘 전용 잠자기 경로가 따로 있어서, 흔한 "잠자기 방지" 방법
(`caffeinate`, 디스플레이 어서션)으로는 못 막는다.
덮어쓸 수 있는 건 `pmset disablesleep` 하나뿐이다.

`lowpowermode`는 이것과 **아무 상관이 없다.** 그냥 배터리 절약이다.
(Dusk 첫 판이 `disablesleep` 대신 이걸 켜 놓고 "뚜껑 닫아도 안 잔다"고 믿었다가
검은 화면에 무지개 커서로 끝난 적이 있다.)

### 화면이 캄캄해졌는데 아이콘이 안 보일 때

**밝기 올리기 키(F2)를 누르면 된다.** Dusk가 그걸 알아채고 스위치를 알아서 내린다.
페이드 도중에 눌러도 즉시 손을 뗀다 — 키와 싸우지 않는다.

## 잠자기·깨어남을 왜 따로 다루나

macOS는 잠들기 직전의 밝기를 기억했다가 깰 때 그대로 되돌린다.
**밝기 0으로 잠들면 밝기 0으로 깬다.** 그런데 탈출구(F2 감시)는 밝기가 *올라올 때만*
발동하므로, 저절로 올라올 일이 없어서 영원히 검은 화면에 갇힌다.

게다가 감시 타이머가 잠자기·깨어남 구간 내내 0.4초마다 `DisplayServices`를
메인 스레드에서 호출하는데, 디스플레이가 붙었다 떨어지는 그 순간엔 이 비공개 호출이
블로킹될 수 있다. **메뉴바 앱의 메인 스레드가 막히면 그게 무지개 커서다.**

그래서 `DuskController`가 `NSWorkspace`의 네 알림을 듣는다:

- `willSleep` / `screensDidSleep` → 타이머 전부 정지, 밝기를 사람이 볼 수 있는 값으로 **되돌려 놓고** 잠든다
- `didWake` / `screensDidWake` → 1초 기다렸다가(패널이 돌아올 시간) 다시 어둡게

`displayAsleep` 플래그가 켜져 있는 동안엔 어떤 코드도 `DisplayServices`를 건드리지 않는다.

## 죽어도 되돌린다

`pmset` 설정과 밝기는 **프로세스보다 오래 산다.** 앱이 강제 종료되면
맥이 영영 잠을 못 자거나, 화면이 0인 채로 되살릴 주체가 사라진다. 그래서:

- **켤 때마다** `disablesleep 0`을 한 번 때리고, 밝기가 0이면 저장해 둔 값으로 되돌린다
- **끝낼 때** `applicationWillTerminate`에서 전부 되돌린다
- 저전력 모드는 되돌리지 **않는다** — 그건 사람이 시스템 설정에서 직접 켜기도 하는 값이라 뺏으면 안 된다

## 암호를 왜 한 번 묻나

`disablesleep`도 `lowpowermode`도 root만 바꿀 수 있다. 우회로가 없다 —
`IOPMSetValueInt`는 성공을 리턴하면서 실제로는 아무것도 안 바꾼다(확인함).

그래서 처음 켤 때 한 번만 암호를 묻고, 아래 네 명령**만** 허용하는 규칙을 넣는다:

```
parkchanbin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0
parkchanbin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1
parkchanbin ALL=(root) NOPASSWD: /usr/bin/pmset -a lowpowermode 0
parkchanbin ALL=(root) NOPASSWD: /usr/bin/pmset -a lowpowermode 1
```

와일드카드가 없어서 다른 명령으로 늘려 쓸 수 없다.

되돌리려면: `sudo rm /etc/sudoers.d/dusk`

### `sudo -l`로는 권한을 확인할 수 없다

"암호 없이 이 명령 되나?"를 sudo에 물어볼 방법이 없다. `sudo -l`은 *애초에 실행이
허용되는가*만 답하는데, 관리자 계정에겐 전부 예스다 — 규칙이 하나도 없어도 통과한다.
**실제로 실행해서 종료 코드를 보는 것**이 유일하게 정직한 검사다.

모든 호출에 `-n -k`를 붙인다. `-n`은 절대 암호를 묻지 않고(메뉴바 앱엔 답할 터미널이 없다),
`-k`는 캐시된 sudo 타임스탬프를 무시한다. `-k`가 없으면 다른 데서 암호를 친 직후
몇 분 동안은 그냥 성공하다가 만료되면 갑자기 실패한다 — 테스트할 땐 되고 나중에 깨진다.

## 배터리 자동 끄기 · 타이머

뚜껑 닫고 돌려 놓는 앱이라 배터리가 방전되는 걸 못 본다. Awayke에서 그대로 가져왔다.

- **이만큼 켜두기**: 15 / 30 / 60 / 120분, 또는 계속. 벽시계 기준이라 중간에 잠들었다 깨도 안 틀어진다.
- **배터리 낮으면 자동 끄기**: 0~100%를 5단위로 끄는 슬라이더. 0은 이 기능 자체를 끔.
  아래로 떨어지면 끄고 알림. 충전해서 임계값 **+5%p**를 넘겨야 다시 켠다
  (히스테리시스 — 경계에서 깜빡이지 말라고). 다만 +5%p는 100%를 넘지 않게 자른다.
  안 그러면 기준을 100 근처로 둔 순간 105% 같은 존재하지 않는 충전량을 기다리게 되고,
  한 번 꺼지면 영영 안 돌아온다.
- 이미 임계값 아래인 상태에서 사람이 직접 켰으면 그건 **의도적 오버라이드**로 보고 자동 끄기가 물러선다.
  충전기에 꽂으면 오버라이드가 풀리고 다음 방전 때 다시 무장한다.

## 빌드

이 맥에는 Xcode가 없다. SwiftPM으로 빌드하고 `.app` 번들은 Makefile이 손으로 조립한다.

```sh
make check     # 검증 (XCTest가 Xcode에만 있어서 실행파일로 돌린다)
make install   # 검증 → 빌드 → 서명 → /Applications
make run       # 위 전부 + 실행
make stop
```

TCC 권한이 하나도 필요 없어서 ad-hoc 서명으로 충분하다. 인증서를 관리할 필요가 없다.
(Awayke는 SMAppService 권한 헬퍼를 쓰지만 그건 정식 Developer ID 서명이 있어야 등록된다.
이 맥엔 없어서 sudoers 방식으로 갈아탔다.)

## 구조

```
Sources/DuskCore/     순수 로직. AppKit·IOKit 없음 → 전부 테스트 대상
  BrightnessRamp      경과 시간 → 밝기. 타이머가 밀려도 도착점은 안 틀어진다
  PowerSettings       pmset 출력 파싱 (disablesleep + lowpowermode)
  AutoOffPolicy       배터리 자동 끄기 판단 (Awayke에서)
  DarkGracePolicy     밝기 키를 누른 뒤 화면을 얼마나 빌려줄지 판단
  DuskState           스위치 세 개와 클릭 규칙
Sources/Dusk/         앱
  DisplayBrightness   DisplayServices (비공개 API라 dlopen, 없으면 기능만 끔)
  DisplayWakeKeeper   IOPMAssertion — 밝기 0을 붙들고 있는 동안 패널이 잠들지 않게
  BatteryMonitor      IOKit 전원 소스 (폴링 아님, 이벤트)
  AutoOffTimer        벽시계 카운트다운
  PowerCommands       pmset을 sudo로, 전부 백그라운드 큐에서
  DuskController      상태 + 페이드 + 엿보기 감시 + 잠자기/깨어남
  StatusIcon          메뉴바 글리프
  SwitchMenuItemView  NSSwitch를 얹은 메뉴 줄 (체크표시 대신)
  AppDelegate         클릭 분기, 메뉴, 배터리·타이머 조정
Sources/DuskCheck/    검증 실행파일
```

### 알아둘 것

- **`pmset`은 구분자가 일정하지 않다.** 전원별 설정(`pmset -g custom`)은 공백으로 줄을 맞추는데
  시스템 전역 블록(`pmset -g`)은 **탭**을 쓴다. 공백으로만 쪼개면 `SleepDisabled`를
  조용히 "없음"으로 읽는다. DuskCheck가 **실제 pmset 출력**으로도 파서를 검사하는 이유.
- `SleepDisabled`는 `pmset -g`에만 있다. `pmset -g custom`엔 없다.
- `Process.waitUntilExit()`를 메인 스레드에서 부르면 그동안 메뉴바가 통째로 언다. 전부 백그라운드로.
- 파이프는 `waitUntilExit()` **전에** 다 읽어야 한다. 안 그러면 출력이 파이프를 채우는 순간 영영 멈춘다.
- 페이드 타이머는 `.common` 런루프 모드에 넣는다. 기본 모드면 **메뉴가 열려 있는 동안 페이드가 멈춘다.**
- 메뉴 스위치를 뒤집으면 **메뉴를 먼저 닫고** 다음 런루프에서 적용한다. 메뉴 추적 중에는
  권한 프롬프트나 실패 알림 같은 모달이 제대로 못 뜬다.
- 메뉴 항목에 붙인 커스텀 뷰는 하이라이트를 스스로 그려야 한다. `NSMenuItem.isHighlighted`는
  뷰를 다시 그려 준다는 보장이 없어서 `NSTrackingArea`로 직접 본다.
- `NSApplication.delegate`는 weak다. 전역에 붙들어 두지 않으면 사라진다.
- `UNUserNotificationCenter.current()`는 번들 아이덴티티가 없으면 죽는다.
  `.build`에서 바로 실행하면 번들이 아니므로 `Bundle.main.bundleIdentifier`로 먼저 거른다.
- 외부 모니터는 DisplayServices로 안 되는 경우가 많다(DDC가 필요). 실패는 무시하고 내장 화면만 따른다.
