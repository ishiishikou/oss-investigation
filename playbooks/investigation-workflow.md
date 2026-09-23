# OSS調査 Playbook

この文書は、個別OSSの不具合や配布問題を調査するときの標準手順です。個別案件で改善点が見つかったら更新します。

## 1. 調査対象を固定する

最低限、次を記録します。

- 上流リポジトリURL
- 調査対象branch / tag
- good commit
- bad commit
- 関連Issue / PR
- ユーザー影響
- 再現環境

「最新版」のような可変表現だけで記録しないことを原則とします。

## 2. IssueをSSOTにする

親Issueには次を維持します。

- 現在のステータス
- 確認済み事実
- 未確認事項
- 仮説
- 実験履歴
- 否定された仮説
- 次の作業
- 上流への報告候補

大きな検証は子Issueへ切り出します。

## 3. 上流コードは一時cloneする

上流コードはこのリポジトリへvendorしません。

例:

```bash
mkdir -p /workspace/upstream/<owner>
git clone https://github.com/<owner>/<repo>.git /workspace/upstream/<owner>/<repo>
cd /workspace/upstream/<owner>/<repo>
git checkout <commit-sha>
```

再現スクリプトからcloneする場合も、clone先はGit管理外にします。

## 4. 最後の成功と最初の失敗を探す

CI/CD、リリース、配布問題では特に次を優先します。

1. 最後に正常だったrevisionを特定
2. 最初に異常になったrevisionを特定
3. 差分commit数を数える
4. 小さければ順番に検証
5. 大きければgit bisectまたは同等手法を使う

## 5. 公開境界とprivate境界を分離する

外部サービスやprivate CIが含まれる場合、

- 公開コードで再現できる範囲
- 公開ログで確認できる範囲
- private環境がないと確認できない範囲

を分けます。

private部分を推測で断定しません。

## 6. 証拠を残す

残すもの:

- commit SHA
- PR / Issue番号
- Check Run名と結果
- 実行コマンド
- 再現結果
- 日時
- 必要なら最小再現コード

残さないもの:

- token
- cookie
- device code
- private key
- 公開権限のないログ

## 7. 上流へ報告する

報告時は次の順序を推奨します。

1. Expected
2. Actual
3. Reproduction
4. Impact
5. Last known good / first known bad
6. Evidence
7. 仮説（断定と分離）
8. 修正案（原因が十分確認できた場合のみ）

既存Issue / PRとの重複を事前に確認します。

## 8. 調査終了時

個別Issueから再利用可能な知見を抽出し、

- `playbooks/`
- `scripts/`
- `templates/`

へ昇格します。

個別案件固有の情報と一般的な調査手法を混在させないことを原則とします。
