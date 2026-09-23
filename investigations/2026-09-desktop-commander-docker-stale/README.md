# Desktop Commander Docker配布停滞の調査

## 概要

Desktop Commander本体は更新されている一方、Docker公式MCP Registry経由の `mcp/desktop-commander:latest` が古いrevisionに固定され、Remote Desktop Commander利用時に旧版として拒否される現象を調査します。

調査の進行状況はGitHubの親IssueをSSOTとし、このディレクトリには再現に必要な固定情報や、確定した調査結果を残します。

## 対象

- Desktop Commander: `wonderwhy-er/DesktopCommanderMCP`
- Docker MCP Registry: `docker/mcp-registry`
- Docker側更新PR: `docker/mcp-registry#4362`

## 現時点の固定情報

### 最後にDocker Security Reviewが成功したDesktop Commander pin

- Desktop Commander commit: `0ad919bc188947fc55b1bf269df62f4b14b3880c`
- package version: `0.2.43`
- Docker MCP Registry PR: `#4183`
- Security Review: success

### 最初に失敗を確認している更新

- base: `0ad919bc188947fc55b1bf269df62f4b14b3880c`
- head: `d627e1baf8b51c5e0c64bf8e3da78c148743e44a`
- package version: `0.2.43`
- Security Review: `Security review failed to complete`

このため、「0.2.51へのversion更新そのものが原因」という仮説は支持されません。

### 現在Docker側が取り込もうとしているrevision

- Desktop Commander commit: `75048278f4866f0d8bde26f6f9aa3b8d39dca870`
- package version: `0.2.51`
- Docker MCP Registry PR: `#4362`

## 現時点の主要な問い

1. Docker公開security reviewerをローカル再現した場合も同じ失敗になるか。
2. `0ad919bc` から `d627e1ba` の間のどのcommitで初めて失敗するか。
3. 公開security reviewerでは成功し、Docker private orchestrationだけ失敗するのか。
4. Desktop Commander側に修正すべき実質的な問題があるのか。
5. Docker側のreview pipelineに一般化可能な不具合があるのか。

## 調査原則

原因が確定するまでは、Docker側・Desktop Commander側のどちらかに責任を固定しません。

また、上流コードはこのリポジトリへコピーせず、一時作業領域へcloneして検証します。
