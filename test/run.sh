#!/bin/bash
# Off-car test of mod/seats.sh with a fake hmgapid and sleep. No mksh on the Mac, so
# it runs under bash; the HMG-API script check covers which commands the unit has.
#   test/run.sh                  bash로 실행
#   TEST_SHELL=mksh test/run.sh  헤드유닛과 같은 mksh로 실행
HERE=$(cd "$(dirname "$0")/.." && pwd)
TEST_SHELL=${TEST_SHELL:-bash}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export T PATH="$T/bin:$PATH" HMGAPI_MOD=auto-heat-and-cool-seats UP="$T/uptime"
mkdir "$T/bin"

cat > "$T/bin/hmgapid" <<'EOF'
#!/bin/bash
case "$1" in
setting-get) cat "$T/settings" ;;
vehicle) shift; for n in "$@"; do echo "$n $(cat "$T/r/$n" 2>/dev/null || echo -)"; done ;;
vehicle-do)
    shift; echo "$*" >> "$T/sent"
    if [ -s "$T/refuse" ]; then read -r a < "$T/refuse"; grep -v -x -F "$a" "$T/refuse" > "$T/refuse2"; mv "$T/refuse2" "$T/refuse"; echo "$a"; exit; fi
    [ -f "$T/ignored" ] && { echo "ok"; exit; }
    case "$1:$3" in
    wheel_heat:*) echo 1 > "$T/r/wheel_heat" ;;
    seat_heat:low) echo 6 > "$T/r/seat_state.$2" ;;
    seat_heat:medium) echo 7 > "$T/r/seat_state.$2" ;;
    seat_heat:high) echo 8 > "$T/r/seat_state.$2" ;;
    seat_vent:low) echo 3 > "$T/r/seat_state.$2" ;;
    seat_vent:medium) echo 4 > "$T/r/seat_state.$2" ;;
    seat_vent:high) echo 5 > "$T/r/seat_state.$2" ;;
    esac
    echo "ok" ;;
esac
EOF
# each sleep takes the next hv.ready from seq, after any "up <n>" (/proc/uptime), "moving <n>",
# "temp <n>" (outside_temp, ℃) or "temp_f <n>" (outside_temp_f, ℉) lines; none left ends the run
cat > "$T/bin/sleep" <<'EOF'
#!/bin/bash
off() { for f in "$T"/r/seat_state.*; do echo 2 > "$f"; done; }   # the car off: seats off
while [ -s "$T/seq" ]; do
    read -r line < "$T/seq"
    tail -n +2 "$T/seq" > "$T/seq2"; mv "$T/seq2" "$T/seq"
    case "$line" in
    "up "*) echo "${line#up } 0" > "$UP"; off ;;
    "moving "*) echo "${line#moving }" > "$T/r/moving" ;;
    "temp "*) echo "${line#temp }" > "$T/r/outside_temp" ;;
    "temp_f "*) echo "${line#temp_f }" > "$T/r/outside_temp_f" ;;
    0) echo 0 > "$T/r/hv.ready"; off; exit 0 ;;
    *) echo "$line" > "$T/r/hv.ready"; exit 0 ;;
    esac
done
kill "$PPID"
EOF
chmod +x "$T"/bin/*

pass=0; fail=0
scenario() {  # scenario <name> <settings json> <hv.ready sequence, one per line> <expected sends> [setup...]
    local name=$1 settings=$2 seq=$3 want=$4 got; shift 4
    rm -rf "$T/r" "$T/sent" "$T/refuse" "$T/ignored"; mkdir "$T/r"
    echo "$settings" > "$T/settings"; echo "100.00 0" > "$UP"
    for s in driver passenger rear_left rear_right; do echo 2 > "$T/r/seat_state.$s"; done
    echo 0 > "$T/r/wheel_heat"; echo 0 > "$T/r/moving"; echo 0 > "$T/r/hv.ready"
    echo 5 > "$T/r/outside_temp"; echo 41 > "$T/r/outside_temp_f"   # 5 ℃ = 41 ℉
    for c in "$@"; do eval "$c"; done
    echo "$seq" > "$T/seq"
    $TEST_SHELL "$HERE/mod/seats.sh" > "$T/log" 2>&1 &
    wait $! 2>/dev/null
    got=$(cat "$T/sent" 2>/dev/null)
    if [ "$got" = "$want" ]; then pass=$((pass + 1)); echo "ok   $name"
    else fail=$((fail + 1)); echo "FAIL $name"; echo "  want: ${want//$'\n'/ | }"; echo "  got:  ${got//$'\n'/ | }"; cat "$T/log"; fi
}

ON=$'1\n1\n1\n1\n1\n1'
COLD=$'wheel_heat on\nseat_heat driver medium'
C=$T/r/outside_temp       # 섭씨 값 파일
F=$T/r/outside_temp_f     # 화씨 값 파일

# --- 섭씨(기본) : 기준 10 ℃ 이하 열선, 29 ℃ 이상 통풍
scenario "cold: defaults, once per start" '{}' "$ON" "$COLD"
scenario "not READY yet, then READY" '{}' $'0\n0\n1\n1\n1\n1\n1' "$COLD"
scenario "accessory power only: nothing" '{}' $'0\n0\n0' ""
scenario "hot: seat coolers, no wheel" '{}' "$ON" "seat_vent driver medium" 'echo 32 > $C'
scenario "between the limits: nothing" '{}' "$ON" "" 'echo 20 > $C'
scenario "exactly on the cold limit: heat" '{}' "$ON" "$COLD" 'echo 10 > $C'
scenario "exactly on the hot limit: cool" '{}' "$ON" "seat_vent driver medium" 'echo 29 > $C'
scenario "just over the cold limit: nothing" '{}' "$ON" "" 'echo 10.1 > $C'
scenario "just under the hot limit: nothing" '{}' "$ON" "" 'echo 28.9 > $C'
scenario "exactly on a negative limit: heat" '{"cold_below":-10,"wheel":false}' "$ON" "seat_heat driver medium" 'echo -10 > $C'
scenario "just under a limit (decimal)" '{"wheel":false}' "$ON" "seat_heat driver medium" 'echo 9.9 > $C'
scenario "service restart mid-drive: nothing" '{}' "$ON" "" 'echo 1 > $T/r/moving' 'echo "500.00 0" > $UP'
scenario "just booted, already moving: still on" '{}' "$ON" "$COLD" 'echo 1 > $T/r/moving'
scenario "seat already on: left alone" '{}' "$ON" "wheel_heat on" 'echo 8 > $T/r/seat_state.driver'
scenario "seat already cooling: left alone" '{"wheel":false}' "$ON" "" 'echo 3 > $T/r/seat_state.driver'
scenario "wheel already on: left alone" '{}' "$ON" "seat_heat driver medium" 'echo 1 > $T/r/wheel_heat'
scenario "chosen seats and levels" '{"wheel":false,"heat_driver":"off","heat_passenger":"high","heat_rear_left":"low","heat_rear_right":"high"}' "$ON" \
    $'seat_heat passenger high\nseat_heat rear_left low\nseat_heat rear_right high'
scenario "wheel only" '{"heat_driver":"off"}' "$ON" "wheel_heat on"
scenario "chosen coolers" '{"cool_driver":"high","cool_passenger":"low"}' "$ON" $'seat_vent driver high\nseat_vent passenger low' 'echo 32 > $C'
scenario "Celsius limits, spaced JSON" '{"unit": "c", "cold_below": 5, "hot_above": 30, "wheel": false}' "$ON" "seat_heat driver medium" 'echo -3.5 > $C'
scenario "negative limit" '{"cold_below":-10,"wheel":false}' "$ON" "" 'echo -3 > $C'
scenario "under a negative limit" '{"cold_below":-10,"wheel":false}' "$ON" "seat_heat driver medium" 'echo -10.5 > $C'

# --- 화씨를 고른 경우 : 기본 기준 50 ℉ / 85 ℉
scenario "Fahrenheit: default limits, cold" '{"unit":"f"}' "$ON" "$COLD" 'echo 40 > $F'
scenario "Fahrenheit: default limits, hot" '{"unit":"f"}' "$ON" "seat_vent driver medium" 'echo 90 > $F'
scenario "Fahrenheit: exactly on the cold limit" '{"unit":"f","wheel":false}' "$ON" "seat_heat driver medium" 'echo 50 > $F'
scenario "Fahrenheit: just over the cold limit" '{"unit":"f"}' "$ON" "" 'echo 50.1 > $F'
scenario "Fahrenheit: own limits" '{"unit":"f","cold_below":32,"hot_above":95,"wheel":false}' "$ON" "" 'echo 40 > $F'

# --- 고른 단위의 값이 없을 때 다른 단위 값을 환산
scenario "no ℃ value: ℉ converted, cold" '{"wheel":false}' "$ON" "seat_heat driver medium" 'rm $C' 'echo 40 > $F'
scenario "no ℃ value: 50 ℉ is 10.0 ℃, heat" '{"wheel":false}' "$ON" "seat_heat driver medium" 'rm $C' 'echo 50 > $F'
scenario "no ℃ value: 50.2 ℉ is 10.1 ℃, nothing" '{}' "$ON" "" 'rm $C' 'echo 50.2 > $F'
scenario "no ℃ value: 84.2 ℉ is 29.0 ℃, cool" '{}' "$ON" "seat_vent driver medium" 'rm $C' 'echo 84.2 > $F'
scenario "no ℃ value: -4 ℉ is -20 ℃, heat" '{"wheel":false}' "$ON" "seat_heat driver medium" 'rm $C' 'echo -4 > $F'
scenario "no ℉ value: 10 ℃ is 50 ℉, heat" '{"unit":"f","wheel":false}' "$ON" "seat_heat driver medium" 'rm $F' 'echo 10 > $C'
scenario "no ℉ value: 30 ℃ is 86 ℉, cool" '{"unit":"f"}' "$ON" "seat_vent driver medium" 'rm $F' 'echo 30 > $C'

# --- 값이 없거나 이상할 때
scenario "no temperature: nothing" '{}' "$ON" "" 'rm $C $F'
scenario "nonsense temperature: nothing" '{}' "$ON" "" 'echo 400 > $C' 'echo 752 > $F'
scenario "-40 at startup, then mild: nothing" '{}' $'1\n1\n1\ntemp 25\n1\n1\n1' "" 'echo -40 > $C' 'echo -40 > $F'
scenario "-40.0 at startup, then cold: heat" '{"wheel":false}' $'1\n1\n1\ntemp 4\n1\n1\n1' "seat_heat driver medium" 'echo -40.0 > $C' 'echo -40.0 > $F'
scenario "-40 that never changes: nothing" '{}' "$ON" "" 'echo -40 > $C' 'echo -40 > $F'
scenario "-40 ℉ unit at startup: nothing" '{"unit":"f"}' "$ON" "" 'echo -40 > $C' 'echo -40 > $F'
scenario "-39.9 is still a temperature: heat" '{"wheel":false}' "$ON" "seat_heat driver medium" 'echo -39.9 > $C'

# --- 시동 판단과 재시도
scenario "off, then a new start" '{"wheel":false}' $'1\n1\n1\n0\n0\n0\n0\n0\n1\n1\n1\n1\n1' $'seat_heat driver medium\nseat_heat driver medium'
scenario "off for one read: a new start" '{"wheel":false}' $'1\n1\n1\n0\n1\n1\n1' $'seat_heat driver medium\nseat_heat driver medium'
scenario "stays READY: only once" '{"wheel":false}' "$ON$'\n'$ON" "seat_heat driver medium"
scenario "off while still sending: stops" '{"wheel":false}' $'1\n0\n0\n0' "seat_heat driver medium" 'touch $T/ignored'
scenario "the unit slept: a new start" '{"wheel":false}' $'1\n1\n1\nup 500\n1\n1\n1\n1\n1' $'seat_heat driver medium\nseat_heat driver medium'
scenario "the unit slept, moving at wake: nothing new" '{"wheel":false}' $'1\n1\n1\nmoving 1\nup 500\n1\n1\n1' "seat_heat driver medium"
scenario "temperature comes late: still on" '{"wheel":false}' $'1\n1\n1\n1\n1\n1\n1\n1\n1\n1\ntemp 4\n1\n1\n1' "seat_heat driver medium" 'rm $C $F'
scenario "owner refuses: not sent again" '{"wheel":false}' "$ON" "seat_heat driver medium" \
    'echo "refused: the owner did not allow seat_heat" > $T/refuse'
scenario "owner's question up, then allowed" '{"wheel":false}' "$ON" $'seat_heat driver medium\nseat_heat driver medium' \
    'echo "refused: waiting for the owner" > $T/refuse'

# uptime을 읽지 못할 때
scenario "uptime 못 읽어도 시동 때는 동작" '{}' "$ON" "$COLD" ': > $UP'
scenario "uptime 못 읽고 이미 주행 중이면 동작 안 함" '{}' "$ON" "" ': > $UP' 'echo 1 > $T/r/moving'

# 명령은 ok인데 차량 상태를 읽지 못할 때: 다시 보내지 않고 확인만 기다림
scenario "좌석 상태를 읽지 못해도 한 번만 보냄" '{"wheel":false}' "$ON$'\n'$ON$'\n'$ON$'\n'$ON" "seat_heat driver medium" \
    'rm $T/r/seat_state.driver' 'touch $T/ignored'
grep -q "확인하지 못함: seat_heat:driver:medium" "$T/log" && echo "ok   ...and says it couldn't confirm" || { fail=$((fail + 1)); echo "FAIL no unconfirmed line"; cat "$T/log"; }
scenario "핸들 열선 상태를 읽지 못해도 한 번만 보냄" '{"heat_driver":"off"}' "$ON" "wheel_heat on" 'rm $T/r/wheel_heat' 'touch $T/ignored'
scenario "좌석 상태를 늦게 읽으면 그걸로 확인" '{"wheel":false}' "$ON" "seat_heat driver medium" 'rm $T/r/seat_state.driver'

# a seat that never shows on: sent every pass, then it gives up
want=$(for i in $(seq 20); do echo "seat_heat driver medium"; done)
scenario "car never shows it: stops after 20" '{"wheel":false}' "$ON$'\n'$ON$'\n'$ON$'\n'$ON" "$want" 'touch $T/ignored'
grep -q "차량에 반영되지 않음" "$T/log" && echo "ok   ...and says so" || { fail=$((fail + 1)); echo "FAIL no give-up line"; }

# check 모드: 출력만 하고 명령은 보내지 않음
rm -rf "$T/r" "$T/sent"; mkdir "$T/r"; echo '{}' > "$T/settings"
echo 1 > "$T/r/hv.ready"; echo 0 > "$T/r/moving"; echo 3 > "$T/r/outside_temp"
out=$($TEST_SHELL "$HERE/mod/seats.sh" check 2>&1)
if echo "$out" | grep -q "외기 3.0℃" && echo "$out" | grep -q "보낼 명령: wheel_heat seat_heat:driver:medium" && [ ! -s "$T/sent" ]; then
    pass=$((pass + 1)); echo "ok   check: 섭씨 출력, 명령 안 보냄"
else fail=$((fail + 1)); echo "FAIL check"; echo "$out"; fi
out=$($TEST_SHELL "$HERE/mod/seats.sh" check 30 2>&1)
if echo "$out" | grep -q "보낼 명령: seat_vent:driver:medium"; then pass=$((pass + 1)); echo "ok   check 30: 통풍"
else fail=$((fail + 1)); echo "FAIL check 30"; echo "$out"; fi

echo "$pass passed, $fail failed ($TEST_SHELL)"
[ $fail = 0 ]
