# MyProject 워크스페이스

소스를 담지 않는 우산 저장소. 하위 프로젝트는 각자 독립 git 저장소이고, 이 저장소는 공통 스크립트·문서만 관리한다.

전체 구성도·개발 환경·실행 방식 비교: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

| 폴더 | 내용 | 저장소 |
| --- | --- | --- |
| `BE-Agent/` | 백엔드 (uv · FastAPI · LangGraph), :8000 | https://github.com/akdrhtn123/BE-Agent |
| `FE-Agent/` | 프론트 (Next.js · pnpm), :3000 | https://github.com/akdrhtn123/FE-Agent |

## 셋업

```bash
git clone https://github.com/akdrhtn123/BE-Agent.git
git clone https://github.com/akdrhtn123/FE-Agent.git
```

필요 도구: [uv](https://docs.astral.sh/uv/) (`curl -LsSf https://astral.sh/uv/install.sh | sh`), Node 22+, pnpm

## 실행

```bash
./start.sh   # 백엔드 + 프론트 백그라운드 실행 (첫 실행 시 .env 복사·의존성 설치)
./stop.sh    # 둘 다 종료
tail -f logs/be.log logs/fe.log
```

기본 모델이 `fake:echo` 라서 API 키 없이 동작한다. 실제 모델 키는 화면의 설정 → API 키, 또는 `BE-Agent/.env` 에 넣는다.

## Docker (운영과 같은 이미지로 전체 실행)

```bash
cp .env.example .env          # POSTGRES_PASSWORD, JWT_SECRET 채우기 (openssl rand -hex 32)
docker compose up -d --build  # Postgres + 백엔드 + 프론트 → http://localhost:3000
docker compose logs -f be
docker compose down           # 종료 (데이터는 postgres-data 볼륨에 남는다. 지우려면 down -v)
```

- 이미지는 각 저장소의 `Dockerfile` 로 만든다 (`BE-Agent/Dockerfile`, `FE-Agent/Dockerfile`).
- 백엔드는 시작할 때 DB 마이그레이션을 적용한다. 프론트는 내부망(`http://be:8000`)으로 백엔드를 부른다.
- `./start.sh` 개발 서버와 동시에 띄우면 포트가 겹친다. `.env` 의 `BE_PORT`·`FE_PORT` 를 바꾼다.
- 로그인 쿠키는 운영 모드에서 `Secure` 라서, localhost 가 아닌 서버에 올릴 때는 HTTPS 가 필요하다.

## 쿠버네티스 (로컬 kind 클러스터, 학습용)

내 PC 의 Docker 위에 노드 3대(control-plane 1 + worker 2)짜리 클러스터를 띄운다. 외부 서버·레지스트리는 쓰지 않는다.

```bash
./k8s/up.sh     # 클러스터 생성(없으면) → 이미지 빌드·반입 → 배포 → http://localhost
./k8s/up.sh     # 코드를 고친 뒤 다시 실행하면 새 이미지로 롤링 재배포
./k8s/down.sh   # 클러스터 삭제 (DB 데이터 포함)
```

필요 도구: [kind](https://kind.sigs.k8s.io/), kubectl, docker buildx

```
k8s/
├── kind-cluster.yaml     클러스터 정의 (NodePort 30080→localhost:80, 30081→localhost:8000)
├── base/                 namespace, postgres(StatefulSet+PVC), be·fe(Deployment+Service)
└── overlays/local/       ConfigMap·Secret 생성, 이미지 태그, NodePort 노출
                          secret.env 는 up.sh 가 무작위 값으로 만든다 (커밋 금지)
```

자주 쓰는 명령 (`--context` 를 항상 붙여 다른 클러스터에 실수로 적용하지 않는다):

```bash
alias k='kubectl --context kind-myproject -n myproject'
k get pods -o wide                 # 어느 노드에 떴는지
k logs -f deploy/be                # 로그
k describe pod <이름>              # 안 뜰 때 이벤트 확인
k rollout undo deploy/be           # 직전 버전으로 되돌리기
k delete pod postgres-0            # 지워도 같은 이름·같은 디스크로 다시 뜬다 (StatefulSet)
```

- `./start.sh`, `docker compose`, kind 는 같은 포트(80/8000/3000)를 쓰니 하나만 켠다.
- 백엔드는 시작할 때 DB 마이그레이션을 돌리므로 처음 배포는 1개로 띄운다. 늘리는 건 배포가 끝난 뒤에 (`k scale deploy/be --replicas=2`).

## 규칙 — 반드시 준수 (사람·AI 도구 공통)

이 저장소와 BE-Agent·FE-Agent 는 **공개 저장소**다.

- **이 개인 프로젝트만 push 한다.** 이 워크스페이스 밖의 다른 프로젝트 소스·문서·설정·스크립트는 커밋하거나 올리지 않는다.
- **다른 프로젝트의 이름·내용을 언급하지 않는다.** 코드, 주석, 문서, 커밋 메시지, PR·이슈 어디에도 남기지 않는다. 참고했더라도 일반적인 표현으로만 쓴다.
- **push 전에 확인한다.** `git diff --cached` 로 올라갈 내용에 다른 프로젝트 내용·내부 주소·비밀값(`.env`, API 키)이 없는지 본다.
- **개인 git 계정으로 커밋한다.** 전역 git 설정이 다른 계정이면 저장소마다 로컬로 지정한다:
  `git config user.name akdrhtn1 && git config user.email 184370766+ParkRhtn@users.noreply.github.com`
