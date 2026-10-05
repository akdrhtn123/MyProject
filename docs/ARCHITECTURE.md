# 구성도

이 워크스페이스의 전체 구조와 실행 방식 세 가지(개발 서버 · docker compose · kind)를 그림으로 정리한다.

## 0. 개발 환경

WSL2 (Ubuntu) 기준. 확인한 버전 (2026-10).

| 구분 | 도구 | 버전 | 설치 |
| --- | --- | --- | --- |
| 백엔드 | uv | 0.12 | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| | Python | 3.13 | `uv sync` 가 알아서 받는다 (`BE-Agent/.python-version`) |
| 프론트 | Node.js | 22 | |
| | pnpm | 10 | `npm i -g pnpm` |
| 컨테이너 | Docker Engine | 29 | |
| | docker compose | 2.40 | |
| | docker buildx | 0.37 | `~/.docker/cli-plugins/docker-buildx` (Dockerfile 의 캐시 마운트에 필요) |
| 쿠버네티스 | kind | 0.33 (노드 k8s 1.37) | `~/.local/bin/kind` |
| | kubectl | 1.37 | `~/.local/bin/kubectl` |
| GitHub | gh | 2.102 | `~/.local/bin/gh` (`gh auth login` 으로 git push 인증) |

주요 라이브러리: FastAPI · LangGraph · SQLAlchemy 2 · Alembic / Next.js 16 · React 19

| 포트 | 쓰는 곳 |
| --- | --- |
| 3000 | 프론트 (개발 서버 · compose) |
| 8000 | 백엔드 (세 방식 모두) |
| 80 | 프론트 (kind) |

| 설정 파일 | 쓰는 곳 | 커밋 |
| --- | --- | --- |
| `BE-Agent/.env` | 개발 서버 (백엔드) | ✗ (`.env.example` 만) |
| `FE-Agent/.env.local` | 개발 서버 (프론트) | ✗ (`.env.example` 만) |
| `.env` (루트) | docker compose | ✗ (`.env.example` 만) |
| `k8s/overlays/local/secret.env` | kind | ✗ (`secret.env.example` 만) |

## 1. 앱 구조

브라우저는 프론트(Next.js)만 부른다. 프론트 서버가 BFF 로서 로그인 쿠키의 토큰을 붙여 백엔드를 대신 호출한다.
외부 서비스는 API 키로 백엔드를 직접 부른다.

```mermaid
flowchart LR
    user([브라우저])
    ext([외부 서비스<br/>API 키])
    embed([다른 사이트<br/>iframe])

    subgraph FE["FE-Agent · Next.js :3000"]
        proxy["proxy.ts<br/>로그인 쿠키 확인 · iframe 허용 사이트"]
        pages["화면<br/>chat · agents · workflows<br/>settings · usage"]
        bff["/api/backend/*<br/>BFF 프록시"]
        actions["로그인 server action"]
    end

    subgraph BE["BE-Agent · FastAPI :8000"]
        api["/api/v1/*<br/>REST · SSE 스트리밍"]
        agent["에이전트<br/>LangGraph"]
        wf["워크플로우 엔진<br/>+ 예약 실행 스케줄러"]
        tools["도구<br/>기본 · MCP · 텔레그램"]
    end

    db[("DB<br/>SQLite / Postgres")]
    ckpt[("대화 체크포인트<br/>SQLite 파일 / 같은 Postgres")]
    llm["LLM<br/>Anthropic · OpenAI · fake:echo"]
    obs["Langfuse (선택)"]

    user --> proxy --> pages
    pages --> bff --> api
    pages --> actions --> api
    embed --> pages
    ext -->|/api/v1/ext| api
    api --> agent & wf
    wf --> agent
    agent --> tools
    agent --> llm
    api --> db
    agent --> ckpt
    agent -.-> obs
```

| 저장소 | 스택 | 주요 폴더 |
| --- | --- | --- |
| BE-Agent | uv · FastAPI · LangGraph · SQLAlchemy · Alembic | `core/` 설정·LLM, `agent/`, `workflow/`, `tools/`, `api/v1/`, `db/`, `migrations/` |
| FE-Agent | Next.js · pnpm · shadcn/ui · React Flow · AI SDK | `app/(main)/` 화면, `app/api/backend/` BFF, `components/`, `lib/api/` |

## 2. 실행 방식 세 가지

세 방식 모두 같은 소스, 그리고 compose·kind 는 **같은 Docker 이미지**를 쓴다. 바뀌는 건 "어떻게 실행하느냐" 뿐이다.

```mermaid
flowchart TB
    src["소스<br/>BE-Agent · FE-Agent"]
    df["Dockerfile<br/>BE-Agent/Dockerfile · FE-Agent/Dockerfile"]
    img[["이미지<br/>be · fe"]]

    src -->|./start.sh| dev["개발 서버<br/>uv run · pnpm dev<br/>자동 리로드, SQLite"]
    src --> df -->|docker build| img
    img -->|docker compose up| compose["docker compose<br/>서버 1대, Postgres"]
    img -->|kind load| kind["kind 클러스터<br/>노드 3대, Postgres"]
```

| | 개발 서버 | docker compose | kind (쿠버네티스) |
| --- | --- | --- | --- |
| 용도 | 평소 개발 | 이미지 확인 · 서버 1대 배포 | 쿠버네티스 배포 (로컬 kind, 같은 base 로 실제 클러스터) |
| 켜기 | `./start.sh` | `docker compose up -d --build` | `./k8s/up.sh` |
| 끄기 | `./stop.sh` | `docker compose down` | `./k8s/down.sh` (삭제) |
| 잠깐 멈춤 | — | `docker compose stop` | `docker stop myproject-control-plane myproject-worker myproject-worker2` |
| 화면 | http://localhost:3000 | http://localhost:3000 | http://localhost |
| 백엔드 | http://localhost:8000 | http://localhost:8000 | http://localhost:8000 |
| DB | SQLite (`BE-Agent/data/`) | Postgres (볼륨 `postgres-data`) | Postgres (StatefulSet + PVC) |
| 설정 | `BE-Agent/.env`, `FE-Agent/.env.local` | 루트 `.env` | `k8s/overlays/local/` (`secret.env`) |

> 세 방식은 같은 포트를 쓰므로 **한 번에 하나만** 켠다. 끌 때는 켠 방식의 명령을 쓴다
> (`docker compose down` 은 kind 노드를 내리지 않는다).

## 3. docker compose 구성

```mermaid
flowchart LR
    user([브라우저]) -->|:3000| fe
    ext([외부 서비스]) -->|:8000| be

    subgraph host["Docker (서버 1대)"]
        fe["fe<br/>Next.js standalone"]
        be["be<br/>uvicorn"]
        pg[("postgres:17")]
        vol[/"볼륨 postgres-data"/]
    end

    fe -->|"BACKEND_URL=http://be:8000"| be
    be -->|"postgres:5432<br/>시작 시 마이그레이션"| pg
    pg --- vol
```

- 시작 순서: postgres 가 healthy → be 가 healthy(`/health`) → fe (`depends_on`)
- 비밀값은 루트 `.env` (커밋 제외). 포트는 `BE_PORT` · `FE_PORT` 로 바꿀 수 있다.

## 4. kind (쿠버네티스) 구성

kind 는 Docker 컨테이너를 쿠버네티스 노드로 쓴다. `docker ps` 에는 노드 3개만 보이고, 앱은 그 안의 Pod 로 돈다.

```mermaid
flowchart TB
    user([브라우저]) -->|localhost:80| np1
    ext([외부 서비스]) -->|localhost:8000| np2

    subgraph docker["Docker (내 PC)"]
        subgraph cluster["kind 클러스터 myproject · 네임스페이스 myproject"]
            subgraph cp["myproject-control-plane"]
                np1["NodePort 30080"]
                np2["NodePort 30081"]
            end

            svcfe["Service fe :3000"]
            svcbe["Service be :8000"]
            svcpg["Service postgres :5432<br/>headless"]

            subgraph workers["worker 노드 2대 (스케줄러가 배치)"]
                fe["Deployment fe<br/>Pod"]
                be["Deployment be<br/>Pod<br/>initContainer: DB 대기"]
                pg[("StatefulSet postgres<br/>Pod postgres-0")]
                pvc[/"PVC data-postgres-0 · 1Gi"/]
            end

            cm["ConfigMap be-config"]
            sec["Secret app-secrets"]
        end
    end

    np1 --> svcfe --> fe
    np2 --> svcbe --> be
    fe -->|"http://be:8000"| svcbe
    be --> svcpg --> pg
    pg --- pvc
    cm -.-> be
    sec -.-> be & pg
```

| 리소스 | 하는 일 |
| --- | --- |
| Deployment (be, fe) | 지정한 개수의 Pod 를 유지. 죽으면 다시 띄우고, 이미지가 바뀌면 롤링 업데이트 |
| StatefulSet (postgres) | Pod 이름(`postgres-0`)과 디스크(PVC)를 고정. Pod 를 지워도 같은 데이터로 다시 뜬다 |
| Service | Pod 앞의 고정 주소 · DNS 이름(`be`, `fe`, `postgres`). NodePort 는 노드 포트로 외부에 연다 |
| ConfigMap / Secret | 설정과 비밀값을 환경변수로 넣는다. 이름에 내용 해시가 붙어 값이 바뀌면 Pod 가 새로 뜬다 |
| readiness / liveness | 준비 안 된 Pod 는 트래픽에서 빼고, 응답 없는 컨테이너는 재시작 |

`./k8s/up.sh` 가 하는 일:

```mermaid
flowchart LR
    a["클러스터 생성<br/>(없을 때만)"] --> b["secret.env 생성<br/>(없을 때만)"] --> c["docker build<br/>be · fe"] --> d["kind load<br/>노드로 이미지 반입"] --> e["kubectl apply -k<br/>overlays/local"] --> f["rollout status<br/>준비될 때까지 대기"]
```

```
k8s/
├── kind-cluster.yaml        노드 3대, NodePort ↔ localhost 포트 연결
├── base/                    namespace · postgres · be · fe
├── overlays/local/          ConfigMap·Secret 생성, 이미지 태그(dev), NodePort 노출
├── up.sh                    생성 · 빌드 · 반입 · 배포 (다시 실행하면 재배포)
└── down.sh                  클러스터 삭제
```

## 5. CPU · 메모리 권장치

실사용 전이라 2026-10-05 에 docker compose 로 띄워 잰 값(대기, 화면·API 요청 60회 직후)을 기준으로 잡았다.
LLM 은 외부 API 라 CPU 는 거의 안 쓰고, 메모리는 동시 대화(SSE) 수와 MCP 도구에 따라 늘어난다.

| 컨테이너 | 측정 · 대기 | 측정 · 요청 직후 | 권장 requests | 권장 limits |
| --- | --- | --- | --- | --- |
| be | 163 MiB · CPU 0.2% | 168 MiB | CPU 100m · 256Mi | 메모리 1Gi |
| fe | 34 MiB · CPU 0% | 88 MiB | CPU 50m · 128Mi | 메모리 512Mi |
| postgres | 40 MiB · CPU 0.1% | 47 MiB | CPU 100m · 256Mi | 메모리 512Mi |

| 실행 환경 | 최소 | 권장 | 근거 |
| --- | --- | --- | --- |
| docker compose 서버 | 1 vCPU · 2GB | 2 vCPU · 4GB | 앱 3개 합계 약 300MB + OS. 이미지 빌드(Next.js)는 CI·로컬에서 |
| Kubernetes (kind 로컬) | 2 코어 · 4GB | 4 코어 · 8GB | 노드 3대의 쿠버네티스 구성요소가 앱보다 더 쓴다 |
| 실제 클러스터 | — | — | 노드 크기는 클러스터 정책을 따르고, 위 requests · limits 를 그대로 쓴다 |

CPU limit 은 두지 않는다 (순간 부하에 스로틀링 방지). 메모리 limit 만 둬서 누수가 노드 전체로 번지지 않게 한다.
실사용이 쌓이면 `kubectl top pod` · `docker stats` 로 다시 재서 `k8s/base/*.yaml` 의 값을 고친다.

## 6. 다음 단계

- **Gateway API**: `localhost` 하나에서 `/api/v1` → be, 나머지 → fe 로 나눠 보내기 (ingress-nginx 는 2026-03 개발 종료)
- **마이그레이션 Job**: be 를 여러 개로 늘려도 마이그레이션이 한 번만 돌게 분리
- **Skaffold**: 코드 수정 → 빌드 → 재배포 자동화
