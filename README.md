# AstroRAG

Multi-tenant, hybrid retrieval-augmented generation over astronomy and astrophysics papers
(arXiv astro-ph + NASA ADS). Answers cite the exact page and section, and tenants only see
documents they are allowed to read.

**Stack:** FastAPI · PostgreSQL · Elasticsearch (BM25 + vectors) · Neo4j · Redis + Celery ·
Docling · BGE-M3 + cross-encoder (local GPU) · DeepSeek via LangChain/LangGraph · Vite ·
Docker Compose · AWS · Kubernetes.

This is a learning project built the way a professional team works: every change starts as a
Linear issue, lands through a squash-merged pull request with green CI, and decisions are recorded
as ADRs in `docs/adr/`.

## Status
Phase 01 — engineering foundation.

## How work flows
1. Pick an issue from the current Linear cycle (team `AST`).
2. Create a branch whose name contains the issue ID, e.g. `rsalehin/ast-9-init-backend`.
3. Open a PR using the template; CI must pass; squash-merge with a Conventional Commits title.

## Getting started
Setup instructions arrive with issues AST-7 (WSL/Docker) and AST-9 (backend).
