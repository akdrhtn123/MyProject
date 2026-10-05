#!/usr/bin/env bash
# 백엔드(BE-Agent)와 프론트(FE-Agent)를 백그라운드로 띄운다.
# 로그: ./logs/{be,fe}.log   PID: ./.run/{be,fe}.pid   종료: ./stop.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$ROOT/.run"
LOG_DIR="$ROOT/logs"
mkdir -p "$RUN_DIR" "$LOG_DIR"

is_running() {
  local pid_file="$RUN_DIR/$1.pid"
  [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

require() {
  command -v "$1" >/dev/null || { echo "❌ $1 이(가) 없습니다. $2"; exit 1; }
}

require uv   "설치: curl -LsSf https://astral.sh/uv/install.sh | sh"
require pnpm "설치: npm i -g pnpm"

# ---- 백엔드 ----
if is_running be; then
  echo "• 백엔드는 이미 실행 중 (PID $(cat "$RUN_DIR/be.pid"))"
else
  cd "$ROOT/BE-Agent"
  [[ -f .env ]] || { cp .env.example .env; echo "• BE-Agent/.env 생성"; }
  echo "• 백엔드 의존성 확인 (uv sync)"
  uv sync -q
  setsid uv run be-agent >"$LOG_DIR/be.log" 2>&1 < /dev/null &
  echo $! >"$RUN_DIR/be.pid"
  echo "✅ 백엔드 시작 (PID $!) → http://localhost:8000/docs"
fi

# ---- 프론트 ----
if is_running fe; then
  echo "• 프론트는 이미 실행 중 (PID $(cat "$RUN_DIR/fe.pid"))"
else
  cd "$ROOT/FE-Agent"
  [[ -f .env.local ]] || { cp .env.example .env.local; echo "• FE-Agent/.env.local 생성"; }
  if [[ ! -d node_modules ]]; then
    echo "• 프론트 의존성 설치 (pnpm install)"
    pnpm install --silent
  fi
  setsid pnpm dev >"$LOG_DIR/fe.log" 2>&1 < /dev/null &
  echo $! >"$RUN_DIR/fe.pid"
  echo "✅ 프론트 시작 (PID $!) → http://localhost:3000"
fi

echo
echo "로그 보기: tail -f $LOG_DIR/be.log $LOG_DIR/fe.log"
