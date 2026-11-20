#!/system/bin/sh
# 자동 열선·통풍 시트 (Auto Heat and Cool Seats)
#
# 시동을 걸 때마다 외기온도를 확인해, 추우면 시트 열선과 핸들 열선을, 더우면 통풍 시트를 켭니다.
# 원작: eclipseempire의 Cold-start Heat → dibble9012의 HMG-API 버전 → 섭씨 우선·한글화(story-sw).
# 차량 값 읽기와 명령은 HMG-API(hmgapid vehicle, hmgapid vehicle-do)를 쓰므로
# 서비스 번호나 logcat 파싱이 필요 없습니다.
#
# 시동 = hv.ready가 1이 되는 순간. 차가 이미 READY인 상태에서 헤드유닛이 부팅되거나,
# 헤드유닛이 슬립에서 깨어난 경우(/proc/uptime이 크게 뛴 경우)도 시동으로 봅니다.
#
# 사용법: seats.sh               모드 서비스로 실행
#         seats.sh check [온도]  지금(또는 지정한 온도에서) 무엇을 보낼지 출력만 함, 명령은 안 보냄
#
# mksh 전용: 헤드유닛에는 sed, cut, expr가 없습니다.

MOD=auto-heat-and-cool-seats
START="hv.ready moving outside_temp outside_temp_f"
UP=${UP:-/proc/uptime}

# 설정을 한 번도 저장하지 않았을 때 쓰는 기본값 (settings.json의 default와 맞춰 둘 것)
DEFAULT_UNIT=c
DEFAULT_COLD_LIMIT_C=10      # 섭씨: 이 온도 이하이면 열선
DEFAULT_HOT_LIMIT_C=29       # 섭씨: 이 온도 이상이면 통풍
DEFAULT_COLD_LIMIT_F=50      # 화씨를 고른 경우
DEFAULT_HOT_LIMIT_F=85

log() { echo "$(date '+%m-%d %H:%M:%S') $*"; }

snapshot() {  # snapshot <name>...: into SNAP, as name=value words
    # hmgapid answers at once, then waits 3 s for a close that doesn't come, holding one of
    # its 8 workers. So: one call for all the names, in the background, taking just the lines.
    local n=$#
    SNAP=$({ hmgapid vehicle "$@" 2>/dev/null & } | {
        while [ $n -gt 0 ] && read a b; do echo "$a=$b"; n=$(( n - 1 )); done
    })
}

seen() {      # seen <name>: its value in SNAP, or -
    local w
    for w in $SNAP; do
        if [ "${w%%=*}" = "$1" ] && [ -n "${w#*=}" ]; then echo "${w#*=}"; return; fi
    done
    echo -
}

load_settings() {
    if [ -n "$HMGAPI_MOD" ]; then S=$(hmgapid setting-get); else S=$(hmgapid setting-get $MOD); fi
}

setting() {   # setting <key> <default>, from settings JSON like {"unit":"c","wheel":false}
    local v
    v=${S#*\"$1\":}
    [ "$v" = "$S" ] && { echo "$2"; return; }
    v=${v# }; v=${v#\"}; v=${v%%[\",\}]*}
    echo "${v:-$2}"
}

limit() {     # limit <key> <default>: a whole-degree setting, in tenths
    tenths "$(setting $1 $2)" || tenths $2
}

cold_limit() {  # 추위 기준(설정 단위의 0.1도 단위)
    if [ "$unit" = f ]; then limit cold_below $DEFAULT_COLD_LIMIT_F
    else limit cold_below $DEFAULT_COLD_LIMIT_C
    fi
}

hot_limit() {   # 더위 기준(설정 단위의 0.1도 단위)
    if [ "$unit" = f ]; then limit hot_above $DEFAULT_HOT_LIMIT_F
    else limit hot_above $DEFAULT_HOT_LIMIT_C
    fi
}

tenths() {    # tenths <reading>: 73 -> 730, -3.5 -> -35; fails on anything else
    local v=$1 s=1 w f
    case "$v" in -*) s=-1; v=${v#-} ;; esac
    case "$v" in *.*) w=${v%%.*}; f=${v#*.} ;; *) w=$v; f=0 ;; esac
    [ -n "$w" ] && [ -n "$f" ] || return 1
    case "$w$f" in *[!0-9]*) return 1 ;; esac
    f=${f%"${f#?}"}
    echo $(( s * (10#$w * 10 + 10#$f) ))
}

divide_rounded() {  # divide_rounded <나눌 수> <나누는 수>: 반올림한 정수 몫 (음수도 대칭)
    local dividend=$1 divisor=$2
    if [ $dividend -lt 0 ]; then echo $(( (dividend - divisor / 2) / divisor ))
    else echo $(( (dividend + divisor / 2) / divisor ))
    fi
}

fahrenheit_to_celsius() {  # 0.1도 단위끼리 변환: 500(50.0℉) -> 100(10.0℃)
    divide_rounded $(( ($1 - 320) * 5 )) 9
}

celsius_to_fahrenheit() {  # 0.1도 단위끼리 변환: 100(10.0℃) -> 500(50.0℉)
    echo $(( $(divide_rounded $(( $1 * 9 )) 5) + 320 ))
}

reading_in() {  # reading_in <c|f>: 그 단위로 차량이 보낸 외기온도(0.1도 단위), 쓸 만한 값이 없으면 실패
    local field lowest highest temp_tenths
    if [ "$1" = c ]; then field=outside_temp;   lowest=-500; highest=600
    else                  field=outside_temp_f; lowest=-580; highest=1400
    fi
    temp_tenths=$(tenths "$(seen $field)") || return 1
    [ $temp_tenths -ge $lowest ] && [ $temp_tenths -le $highest ] || return 1
    [ $temp_tenths = -400 ] && return 1   # -40, the same in F and C: climate control's value before it has a reading
    echo $temp_tenths
}

outside() {   # 설정 단위의 외기온도(0.1도 단위). 둘 다 없으면 실패
    # 원본(1.0.x)이 이 차에서 동작을 확인한 화씨 값(outside_temp_f)을 먼저 쓰고 필요하면 섭씨로 환산.
    # HMG-API의 섭씨 값(outside_temp)은 공조의 섭씨 유효 표시에 기대므로 화씨 값이 없을 때만 씀.
    local temp_tenths
    if temp_tenths=$(reading_in f); then
        if [ "$unit" = f ]; then echo $temp_tenths; else fahrenheit_to_celsius $temp_tenths; fi
        return 0
    fi
    temp_tenths=$(reading_in c) || return 1
    if [ "$unit" = c ]; then echo $temp_tenths; else celsius_to_fahrenheit $temp_tenths; fi
}

unit_symbol() { if [ "$unit" = f ]; then echo ℉; else echo ℃; fi; }

deg() {       # deg <tenths>: 로그용 표기 (예: -3.5℃)
    local a=$1 s=
    [ $a -lt 0 ] && { s=-; a=$(( -a )); }
    echo "$s$(( a / 10 )).$(( a % 10 ))$(unit_symbol)"
}

seat_name() { # seat_name <좌석 키>: 로그용 좌석 이름
    case $1 in
    driver)     echo 운전석 ;;
    passenger)  echo 조수석 ;;
    rear_left)  echo 뒷좌석 왼쪽 ;;
    rear_right) echo 뒷좌석 오른쪽 ;;
    *)          echo "$1" ;;
    esac
}

jobs_for() {  # jobs_for <temp in tenths>: what this temperature asks for, or nothing
    local s l j=
    if [ $1 -le $(cold_limit) ]; then
        [ "$(setting wheel true)" = true ] && j=wheel_heat
        for s in driver passenger rear_left rear_right; do
            case $s in driver) l=$(setting heat_$s medium) ;; *) l=$(setting heat_$s off) ;; esac
            [ "$l" = off ] || j="$j seat_heat:$s:$l"
        done
    elif [ $1 -ge $(hot_limit) ]; then
        for s in driver passenger; do
            case $s in driver) l=$(setting cool_$s medium) ;; *) l=$(setting cool_$s off) ;; esac
            [ "$l" = off ] || j="$j seat_vent:$s:$l"
        done
    fi
    echo $j
}

result() {    # result <what> <answer> <state before>: 0 when it's done with, 1 to look again
    # hmgapid의 응답 문구(ok, refused...)는 HMG-API가 정한 영어이므로 번역하지 않습니다.
    case "$2" in
    "refused: waiting"*) return 1 ;;   # the owner's question is on the screen
    refused*) log "$1: 거부됨 ($2)"; return 0 ;;
    ok*) ;;
    *) return 1 ;;                     # no answer from the vehicle service
    esac
    # 꺼져 있었거나(0, 2), 아직 보고 전(15), 상태를 읽지 못함(-): 다음 판에서 반영됐는지 확인
    [ "$3" = 0 ] || [ "$3" = 2 ] || [ "$3" = 15 ] || [ "$3" = - ] && return 1
    return 0
}

awaiting_state() {  # awaiting_state <job>: ok를 받았지만 차량 상태를 아직 읽지 못한 작업인가
    case " $UNCONFIRMED " in *" $1 "*) return 0 ;; esac
    return 1
}

remember_unconfirmed() {  # remember_unconfirmed <job> <answer> <state before>: 상태를 모르는 채 ok를 받았으면 기록
    case "$2" in ok*) [ "$3" = - ] && UNCONFIRMED="$UNCONFIRMED $1" ;; esac
}

send() {      # send <job>: wheel_heat or seat_heat:driver:low
    local cmd=${1%%:*} rest=${1#*:} seat state answer
    if [ "$cmd" = wheel_heat ]; then
        state=$(seen wheel_heat)
        [ "$state" = 1 ] && { log "핸들 열선이 켜져 있음"; return 0; }
        # 이미 ok를 받았고 상태만 못 읽는 중이면 다시 보내지 않고 기다림
        [ "$state" = - ] && awaiting_state "$1" && return 1
        answer=$(hmgapid vehicle-do wheel_heat on 2>&1)
        result "핸들 열선" "$answer" "$state" && return 0
        remember_unconfirmed "$1" "$answer" "$state"
        return 1
    fi
    seat=${rest%:*}
    state=$(seen seat_state.$seat)
    if [ "$state" != - ] && [ "$state" -ge 3 ] && [ "$state" -le 8 ]; then
        log "$(seat_name $seat) 좌석이 이미 $state 단계로 켜져 있음"   # 운전자가 켰거나 이 모드가 켠 것
        return 0
    fi
    [ "$state" = - ] && awaiting_state "$1" && return 1
    answer=$(hmgapid vehicle-do $cmd $seat ${rest#*:} 2>&1)
    result "$(seat_name $seat) 좌석" "$answer" "$state" && return 0
    remember_unconfirmed "$1" "$answer" "$state"
    return 1
}

apply() {     # apply <jobs>: send each, again until the car shows it (a minute at most)
    local jobs=$1 left j n=0 unshown= unconfirmed=
    UNCONFIRMED=
    while [ -n "$jobs" ] && [ $n -lt 20 ]; do
        snapshot hv.ready wheel_heat seat_state.driver seat_state.passenger seat_state.rear_left seat_state.rear_right
        [ "$(seen hv.ready)" = 0 ] && return
        left=
        for j in $jobs; do
            send $j || left="$left $j"
        done
        jobs=$left
        n=$(( n + 1 ))
        [ -n "$jobs" ] && sleep 3
    done
    [ -z "$jobs" ] && return
    for j in $jobs; do
        if awaiting_state "$j"; then unconfirmed="$unconfirmed $j"; else unshown="$unshown $j"; fi
    done
    [ -z "$unshown" ] || log "1분 동안 차량에 반영되지 않음:$unshown"
    [ -z "$unconfirmed" ] || log "명령은 받아들여졌지만 차량 상태를 읽지 못해 반영 여부를 확인하지 못함:$unconfirmed"
}

on_start() {  # SNAP holds START's readings
    local t waited= jobs booted_seconds
    # a service restart mid-drive isn't a start; right after the unit boots it may be one
    # (uptime을 읽지 못하면 부팅 직후인지 알 수 없으므로 주행 중이면 동작하지 않음)
    booted_seconds=$(uptime_s)
    if [ "$(seen moving)" = 1 ] && { [ $booted_seconds -lt 0 ] || [ $booted_seconds -ge 180 ]; }; then
        log "READY지만 이미 주행 중(서비스 재시작이거나 부팅 시점을 알 수 없음), 동작 안 함"
        return
    fi
    load_settings
    unit=$(setting unit $DEFAULT_UNIT)
    until t=$(outside); do
        [ "$(seen hv.ready)" = 0 ] && { log "시동이 꺼짐, 동작 안 함"; return; }
        [ -n "$waited" ] || { log "외기온도를 기다리는 중"; waited=1; }
        sleep 3
        snapshot $START
    done
    jobs=$(jobs_for $t)
    log "외기 $(deg $t), 기준 $(deg $(cold_limit)) 이하 열선 / $(deg $(hot_limit)) 이상 통풍: ${jobs:-동작 안 함}"
    apply "$jobs"
}

uptime_s() {  # 부팅 후 지난 초(정수). 읽지 못하면 -1
    local u x
    read u x 2>/dev/null < "$UP"
    u=${u%.*}
    case "$u" in ''|*[!0-9]*) echo -1 ;; *) echo "$u" ;; esac
}

if [ "$1" = check ]; then
    load_settings
    unit=$(setting unit $DEFAULT_UNIT)
    snapshot $START
    if [ -n "$2" ]; then t=$(tenths "$2"); else t=$(outside); fi || { echo "외기온도 값이 없음"; exit 1; }
    echo "hv.ready $(seen hv.ready), 주행 중 $(seen moving), 외기 $(deg $t)"
    echo "기준: $(deg $(cold_limit)) 이하 열선 / $(deg $(hot_limit)) 이상 통풍"
    echo "보낼 명령: $(jobs_for $t)"
    exit 0
fi

log "서비스 시작"
armed=1; last=$(uptime_s)
while :; do
    now=$(uptime_s)
    # the unit slept: this is a new start (uptime을 읽지 못한 동안은 판단하지 않음)
    [ $now -ge 0 ] && [ $last -ge 0 ] && [ $(( now - last )) -gt 20 ] && armed=1
    last=$now
    snapshot $START
    ready=$(seen hv.ready)
    if [ "$ready" = 1 ]; then
        if [ $armed = 1 ]; then
            armed=0
            on_start
            last=$(uptime_s)
        fi
    elif [ "$ready" != - ]; then
        armed=1                        # any read of off: the next READY is a new start
    fi
    sleep 3
done
