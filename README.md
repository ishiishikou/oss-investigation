# oss-investigation

OSSの不具合・配布・CI/CD・設計上の挙動を、再現可能な形で継続調査するためのリポジトリです。

## 目的

このリポジトリでは、特定のOSSのソースコードそのものを管理しません。調査対象の上流リポジトリは、必要なときにコンテナ等の一時作業領域へcloneし、対象commitを明示して調査します。

このリポジトリに残すのは、主に次の内容です。

- 調査Issue（調査のSSOT）
- 再現条件、対象リポジトリ、commit SHA
- 仮説と検証結果
- 再利用可能な調査スクリプト
- 調査で確立したPlaybook
- 上流Issue / PRへつなげるための根拠・証跡

## 基本原則

1. **Issueを調査のSSOTにする**
   - 長期調査は親Issueを作成し、既知事実・未確認事項・仮説・実験結果・次の作業を更新します。
   - 大きな実験は子Issueへ分割します。

2. **上流OSSコードをこのリポジトリへコピーしない**
   - 調査対象は一時領域へcloneします。
   - 再現に必要な情報はURL、branch、tag、commit SHAで記録します。

3. **事実・推測・結論を分離する**
   - 「確認済み」「仮説」「未確認」を明示します。
   - 上流へ報告する前に、再現条件をできる限り固定します。

4. **調査方法を再利用可能にする**
   - 個別案件から得た一般化可能な手順は `playbooks/` に昇格します。
   - 汎用スクリプトは `scripts/` に置きます。

5. **公開して問題ない情報だけを保存する**
   - token、cookie、device code、秘密鍵、内部URL、個人情報などは登録しません。
   - privateログを引用する場合は公開可能性を確認します。

## 推奨作業領域

例:

```text
/workspace/
├─ oss-investigation/          # このリポジトリ
└─ upstream/                   # Git管理外の一時clone
   ├─ docker/
   │  └─ mcp-registry/
   └─ wonderwhy-er/
      └─ DesktopCommanderMCP/
```

調査対象は必要に応じて作り直せることを前提にします。

## ディレクトリ

```text
.
├─ README.md
├─ investigations/             # 個別調査の確定情報・再現情報
├─ playbooks/                  # 一般化した調査手順
├─ scripts/                    # 再利用可能な補助スクリプト
├─ templates/                  # 調査記録テンプレート
└─ .github/ISSUE_TEMPLATE/     # Issueテンプレート
```

## 現在の調査

最初の調査対象として、Desktop CommanderのDocker公式イメージが上流より古い状態で固定されている件を扱います。

詳細は `investigations/2026-09-desktop-commander-docker-stale/` と対応するGitHub Issueで管理します。
