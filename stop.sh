#!/usr/bin/env bash
# start.sh 로 띄운 백엔드·프론트를 종료한다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$ROOT/.run"

stop() {
  local name="$1" label="$2" pid_file="$RUN_DIR/$1.pid"
  if [[ ! -f "$pid_file" ]]; then
    echo "• $label: 실행 기록 없음"
    return
  fi
  local pid; pid="$(cat "$pid_file")"
  if kill -0 "$pid" 2>/dev/null; then
    # setsid 로 띄웠으므로 프로세스 그룹 전체(자식 포함)를 종료
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid"
    for _ in {1..10}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
    kill -0 "$pid" 2>/dev/null && kill -KILL -- "-$pid" 2>/dev/null
    echo "✅ $label 종료 (PID $pid)"
  else
    echo "• $label: 이미 종료됨"
  fi
  rm -f "$pid_file"
}

stop fe "프론트"
stop be "백엔드"
