#!/usr/bin/env bash
# 로컬 kind 클러스터에 전체 스택을 띄운다 (없으면 클러스터부터 만든다). 다시 실행하면 이미지를 새로 빌드해 재배포한다.
#   ./k8s/up.sh        → http://localhost
#   ./k8s/down.sh      클러스터 삭제
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K8S="$ROOT/k8s"
CLUSTER=myproject
CTX="kind-$CLUSTER"
NS=myproject
SECRET_ENV="$K8S/overlays/local/secret.env"
kc() { kubectl --context "$CTX" -n "$NS" "$@"; }

for t in docker kind kubectl openssl; do
  command -v "$t" >/dev/null || { echo "❌ $t 이(가) 없습니다."; exit 1; }
done

# ---- 클러스터 ----
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "• 클러스터 $CLUSTER 사용"
else
  for port in 80 8000; do
    if ss -ltn "sport = :$port" | grep -q LISTEN; then
      echo "❌ $port 포트를 이미 쓰고 있습니다. ./stop.sh 또는 docker compose down 으로 먼저 내려 주세요."
      exit 1
    fi
  done
  echo "• 클러스터 생성 (control-plane 1 + worker 2)"
  kind create cluster --config "$K8S/kind-cluster.yaml"
fi

# ---- 비밀값 (처음 한 번 무작위 생성) ----
if [[ ! -f "$SECRET_ENV" ]]; then
  {
    echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)"
    echo "JWT_SECRET=$(openssl rand -hex 32)"
    echo "ENCRYPTION_KEY=$(openssl rand -hex 32)"
    echo "ANTHROPIC_API_KEY="
    echo "OPENAI_API_KEY="
  } >"$SECRET_ENV"
  echo "• $SECRET_ENV 생성"
fi

# ---- 이미지 빌드 → 클러스터 노드에 직접 넣기 (레지스트리 없이) ----
echo "• 이미지 빌드"
docker build -q --provenance=false -t myproject/be:dev "$ROOT/BE-Agent" >/dev/null
docker build -q --provenance=false -t myproject/fe:dev "$ROOT/FE-Agent" >/dev/null
echo "• kind 노드로 이미지 반입"
kind load docker-image myproject/be:dev myproject/fe:dev --name "$CLUSTER" >/dev/null 2>&1

# ---- 배포 ----
FIRST_DEPLOY=true
kc get deployment/be >/dev/null 2>&1 && FIRST_DEPLOY=false
echo "• 매니페스트 적용"
kubectl --context "$CTX" apply -k "$K8S/overlays/local"
# 재배포: 같은 태그(dev)로 이미지만 바뀐 경우에도 새 이미지로 다시 뜨게 한다.
# 첫 배포에 하면 be 가 두 개 겹쳐 떠서 DB 마이그레이션을 동시에 돌리다 하나가 죽는다
$FIRST_DEPLOY || kc rollout restart deployment/be deployment/fe >/dev/null

echo "• 준비될 때까지 대기"
kc rollout status statefulset/postgres --timeout=180s
kc rollout status deployment/be --timeout=240s
kc rollout status deployment/fe --timeout=180s

cat <<MSG

✅ 배포 완료
   화면     http://localhost
   백엔드   http://localhost:8000/docs
   상태     kubectl --context $CTX -n $NS get pods -o wide
   로그     kubectl --context $CTX -n $NS logs -f deploy/be
MSG
