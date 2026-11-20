# 자동 열선·통풍 시트 (Auto Heat and Cool Seats, HMG-API 모드)

시동을 걸면 외기온도를 확인해서, 설정해 둔 장치를 켭니다.

- **추위 기준 이하:** 시트 열선과 핸들 열선
- **더위 기준 이상:** 통풍 시트

이 저장소는 [dibble9012/auto-heat-and-cool-seats](https://github.com/dibble9012/auto-heat-and-cool-seats)
v1.0.1을 포크해 **섭씨 우선**과 **한글화**를 적용한 버전입니다. 원본은 eclipseempire의
[Cold-start Heat](https://github.com/eclipseempire/hkmc-coldstart-heat)를 HMG-API용으로 옮기고
통풍과 뒷좌석을 더한 모드입니다.

## 원본과 달라진 점 (v1.1.0)

- 기본 단위가 **섭씨(℃)**이고, 설정 화면에서도 섭씨가 먼저 나옵니다. 기본 기준은 10℃ 이하 열선, 29℃ 이상 통풍입니다.
- 설정 화면, 모드 설명, 로그, `check` 출력이 한국어입니다.
- 고른 단위의 외기온도 값이 없으면 다른 단위 값을 환산해서 씁니다.
- NEMESIS 패키지의 호환 차종을 **쏘나타 하이브리드(DN8 HEV) 국내형, 펌웨어 260902**로 바꿨습니다.

## 대상 차량

- 현대 쏘나타 하이브리드(DN8 HEV) 국내형, 펌웨어 260902 (`DN823HEV.KOR`), HMG-API 1.0.2
  : HMG-API 차량 리포트로 필요한 차량 기능(READY, 외기온도, 시트 상태·단계, 핸들 열선)이
  매핑된 것을 확인했습니다. **실차 동작은 아직 검증 전**입니다.

원본이 시험된 차량: 2023 기아 EV6 GT-Line(미국, 260507), 2023 기아 니로 EV(미국, 260507).

## 알려진 문제 (원본 기준)

**2023 기아 니로 EV(미국, 260507, HMG-API 1.0.2)에서 시동 후 약 30초 안에 헤드유닛이 한 번
재시작됩니다.** 원인은 이 모드가 아니라 HMG-API 차량 서비스의 디지털 키 콜백 처리 버그이며,
디지털 키가 있는 다른 차량도 영향을 받을 수 있습니다. 수정은 HMG-API
[PR #101](https://github.com/VysseCodes/HMG-API/pull/101)에 올라가 있습니다.

## 설치

차량에 HMG-API 1.0.0 이상이 먼저 설치돼 있어야 합니다. 두 방법 모두 USB 메모리를 씁니다.
USB 디버깅(ADB over USB)이 켜져 있으면 USB 메모리를 읽지 못하므로 꺼 두세요.

### HMG-API 앱으로 설치

1. `auto-heat-and-cool-seats-v1.1.0-hmgapi-usb.zip`을 FAT32 USB 메모리 최상위에 압축 해제합니다.
   `HMGAPI/updates/auto-heat-and-cool-seats-v1.1.0.zip`이 생기면 됩니다.
2. 차량에 꽂고 HMG-API 앱의 업데이트 화면에서 모드를 설치합니다.
3. 앱에서 **Apply changes**를 누릅니다.

삭제도 HMG-API 앱에서 합니다.

### NEMESIS로 설치

1. `auto-heat-and-cool-seats-v1.1.0-nemesis-usb.zip`을 FAT32 또는 exFAT USB 메모리 최상위에
   압축 해제합니다. `NEMESIS.data`와 `packages` 폴더가 최상위에 있어야 하며, USB에는 NEMESIS
   패키지를 하나만 두세요.
2. Android가 다 켜진 뒤 USB를 꽂고 설치를 확인합니다.
3. 재시작하라고 하면 헤드유닛을 재시작하고 USB를 뺍니다.

삭제는 NEMESIS Manager에서 패키지를 제거합니다.

> **서명 키 주의:** 업데이트는 처음 설치한 모드와 같은 키로 서명돼야 합니다. 원본(dibble9012)
> 모드가 이미 설치돼 있다면 먼저 삭제한 뒤 이 버전을 설치하세요.

## 설정 (HMG-API 앱)

| 설정 | 기본값 |
|---|---|
| 기준 온도 단위 (섭씨/화씨) | 섭씨 |
| 추위 기준: 이 온도 이하이면 열선 켜기 | 10 |
| 더위 기준: 이 온도 이상이면 통풍 켜기 | 29 |
| 추울 때 핸들 열선 켜기 | 켬 |
| 추울 때 운전석 / 조수석 열선 (켜지 않음, 1~3단) | 운전석 2단, 조수석 켜지 않음 |
| 추울 때 뒷좌석 왼쪽 / 오른쪽 열선 (켜지 않음, 1~2단) | 켜지 않음 |
| 더울 때 운전석 / 조수석 통풍 (켜지 않음, 1~3단) | 운전석 2단, 조수석 켜지 않음 |

- 단위를 바꿔도 기준 온도는 자동으로 바뀌지 않으니 함께 고쳐 주세요.
- **통풍 시트가 없는 차량이면 통풍 항목을 모두 '켜지 않음'으로 두세요.**
- 모드가 처음 명령을 보낼 때 HMG-API가 화면에 허용 여부를 묻습니다(시트 열선, 시트 통풍,
  핸들 열선 각각 한 번). 질문이 떠 있는 동안 모드는 1분까지 다시 시도하므로 첫 시동은 느려
  보일 수 있습니다.

## 동작 방식

- 시동은 `hv.ready`가 1이 되는 순간이며, 3초마다 확인합니다. ACC(액세서리 전원)만으로는
  동작하지 않습니다. 시동이 꺼진 값을 한 번이라도 읽으면 다음 READY를 새 시동으로 봅니다.
  READY 상태에서 헤드유닛이 부팅되거나 슬립에서 깨어난 경우(`/proc/uptime`이 크게 뛴 경우)도
  시동으로 봅니다.
- 설정 단위의 외기온도(`outside_temp` 또는 `outside_temp_f`)를 쓰고, 그 값이 없으면 다른 단위
  값을 환산합니다. 시동이 켜져 있는 동안 첫 값을 기다리며, 쓸 만한 값이 없으면 아무것도 하지
  않습니다. 시동 직후 공조가 실제 값 대신 -40을 보낼 수 있어, 정확히 -40(℃/℉ 동일)은 아직
  값이 없는 것으로 보고 계속 기다립니다. 실제 -40도 무시됩니다.
- 명령은 `hmgapid vehicle-do`로 `seat_heat`, `seat_vent`, `wheel_heat`을 보냅니다.
- 이미 열선이나 통풍이 켜진 좌석, 이미 켜진 핸들 열선은 건드리지 않습니다.
- 차량에 반영된 게 보이지 않으면 3초마다 최대 1분 동안 다시 보냅니다.
- READY 시점에 이미 주행 중이고 헤드유닛이 켜진 지 3분이 넘었으면, 서비스가 재시작된 것으로
  보고 아무것도 하지 않습니다.

로그는 `/data/hmgapi/logs/auto-heat-and-cool-seats/seats.log`에 남습니다. 차량에서
`sh seats.sh check [온도]`를 실행하면 실제로 명령을 보내지 않고 무엇을 할지만 출력합니다.

## 빌드

[HMG-API](https://github.com/VysseCodes/HMG-API) 소스 체크아웃이 필요합니다
(`tools/mknemesismod.sh`로 NEMESIS 패키지를 만듭니다). openssl, zip, unzip이 필요합니다.

```bash
./build.py keygen ~/.hmgapi/author.key      # 처음 한 번: 본인 서명 키 생성
./build.py ~/.hmgapi/author.key ../HMG-API
```

`dist/`에 설치용 파일 두 개(`-hmgapi-usb.zip`, `-nemesis-usb.zip`)와 서명된 모드
(`.hmgapi.zip`), NEMESIS 패키지 스토어용 파일(`-nemesis-package.zip`)이 만들어집니다.

## 테스트

```bash
test/run.sh
```

가짜 `hmgapid`와 `sleep`으로 차량 없이 bash에서 스크립트를 돌립니다.

## 라이선스

AGPL-3.0. [LICENSE](LICENSE)를 참고하세요. 이 버전은 원본을 수정한 것이며,
수정 내용은 위 "원본과 달라진 점"과 Git 이력에 있습니다.
