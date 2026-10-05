# MyProject 워크스페이스

소스를 담지 않는 우산 저장소. 하위 프로젝트는 각자 독립 git 저장소이고, 이 저장소는 공통 스크립트·문서만 관리한다.

| 폴더 | 내용 | 저장소 |
| --- | --- | --- |
| `BE-Agent/` | 백엔드 (uv · FastAPI · LangGraph), :8000 | https://github.com/ParkRhtn/BE-Agent |
| `FE-Agent/` | 프론트 (Next.js · pnpm), :3000 | https://github.com/ParkRhtn/FE-Agent |

## 셋업

```bash
git clone https://github.com/ParkRhtn/BE-Agent.git
git clone https://github.com/ParkRhtn/FE-Agent.git
```

필요 도구: [uv](https://docs.astral.sh/uv/) (`curl -LsSf https://astral.sh/uv/install.sh | sh`), Node 22+, pnpm

## 실행

```bash
./start.sh   # 백엔드 + 프론트 백그라운드 실행 (첫 실행 시 .env 복사·의존성 설치)
./stop.sh    # 둘 다 종료
tail -f logs/be.log logs/fe.log
```

기본 모델이 `fake:echo` 라서 API 키 없이 동작한다. 실제 모델 키는 화면의 설정 → API 키, 또는 `BE-Agent/.env` 에 넣는다.
