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
SECRET_ENV="$K8S/secret.env"
RELEASE=myproject
kc() { kubectl --context "$CTX" -n "$NS" "$@"; }

for t in docker kind kubectl helm openssl; do
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
# 네임스페이스와 Secret 은 차트 밖에서 만든다 (비밀값을 values 나 Helm 릴리스 기록에 남기지 않는다)
kubectl --context "$CTX" create namespace "$NS" --dry-run=client -o yaml | kubectl --context "$CTX" apply -f - >/dev/null
kc create secret generic app-secrets --from-env-file="$SECRET_ENV" --dry-run=client -o yaml | kc apply -f - >/dev/null
echo "• helm upgrade --install $RELEASE"
helm upgrade --install "$RELEASE" "$K8S/chart" --kube-context "$CTX" -n "$NS" -f "$K8S/values-local.yaml"
# 재배포: 같은 태그(dev)로 이미지만 바뀌면 helm 은 바뀐 게 없다고 보고 Pod 를 그대로 둔다.
# Secret 도 차트 밖이라 값이 바뀌어도 Pod 가 모른다. 그래서 매번 다시 띄운다 (첫 배포는 이미 새로 뜨므로 건너뛴다)
$FIRST_DEPLOY || kc rollout restart deployment/be deployment/fe >/dev/null

echo "• 준비될 때까지 대기"
kc rollout status statefulset/postgres --timeout=180s
# be 는 마이그레이션 Job 이 끝나야 뜬다. Job 이 실패하면 be 가 기다리기만 하므로 여기서 로그를 보여 주고 멈춘다
MIGRATE_JOB="job/be-migrate-$(helm --kube-context "$CTX" -n "$NS" history "$RELEASE" --max 1 | awk 'END{print $1}')"
if ! kc wait --for=condition=complete "$MIGRATE_JOB" --timeout=240s; then
  echo "❌ DB 마이그레이션 실패. 로그:"
  kc logs "$MIGRATE_JOB" --all-containers --tail=50 || true
  exit 1
fi
kc rollout status deployment/be --timeout=240s
kc rollout status deployment/fe --timeout=180s

cat <<MSG

✅ 배포 완료
   화면     http://localhost
   백엔드   http://localhost:8000/docs
   상태     kubectl --context $CTX -n $NS get pods -o wide
   로그     kubectl --context $CTX -n $NS logs -f deploy/be
   이력     helm --kube-context $CTX -n $NS history $RELEASE
MSG
