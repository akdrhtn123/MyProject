#!/usr/bin/env bash
# 로컬 kind 클러스터를 통째로 지운다 (DB 데이터 포함). 비밀값(overlays/local/secret.env)은 남긴다.
set -euo pipefail
kind delete cluster --name myproject
