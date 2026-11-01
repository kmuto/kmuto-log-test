# nginxログ・メトリック検証用セット

このディレクトリは、ダミーの nginx アクセスログを生成し、OpenTelemetry Collector でログ/メトリックを処理するためのサンプルです。

## ファイル構成

- [config.yaml](config.yaml)  
  Mackerel OpenTelemetry Collector 向けのプレインログ（nginx combined 風）設定。  
  `regex_parser` でログを解析し、属性整形・severity設定を実施します。  
- [config-json.yaml](config-json.yaml)  
  Mackerel OpenTelemetry Collector 向けの JSON ログ設定。  
  JSONL を `json_parser` で読み、属性整形・severity設定を実施してログを送ります。

- [config-json-contrib.yaml](config-json-contrib.yaml)  
  `opentelemetry-collector-contrib` 向けの JSON ログ設定。  
  `count` connector で `http.server.request.count` を作り、メトリックを出力します（OTLP exporter + debug exporter）。

- [generate_access_log.sh](generate_access_log.sh)  
  ダミーアクセスログを継続生成するスクリプト。  
  通常トラフィックと攻撃風トラフィックを混ぜて出力します。

## 事前準備

- 実行権限を付与:

```bash
chmod +x ./generate_access_log.sh
```

## generate_access_log.sh の使い方

基本:

```bash
./generate_access_log.sh ./access.log
```

主な環境変数:

- `INTERVAL_SECONDS`（デフォルト: `1`）  
  生成間隔の基準秒数
- `INTERVAL_JITTER_RATIO`（デフォルト: `0.20`）  
  生成間隔の揺らぎ（±比率）
- `LOG_FORMAT`（`combined` or `jsonl`、デフォルト: `combined`）  
  出力フォーマット

例（JSONLで0.5秒間隔、揺らぎなし）:

```bash
LOG_FORMAT=jsonl INTERVAL_SECONDS=0.5 INTERVAL_JITTER_RATIO=0 ./generate_access_log.sh ./access.log
```

## 設定ファイルごとの実行例

### 1) contrib版（JSONログ + メトリック）

1. JSONLでログ生成:

```bash
LOG_FORMAT=jsonl ./generate_access_log.sh ./access.log
```

2. 別ターミナルで Collector 起動:

```bash
MACKEREL_APIKEY='YOUR_API_KEY' otelcol-contrib --config ./config-json-contrib.yaml
```

### 2) Mackerel版（JSONログ）

1. JSONLでログ生成:

```bash
LOG_FORMAT=jsonl ./generate_access_log.sh ./access.log
```

2. 別ターミナルで Collector 起動:

```bash
MACKEREL_APIKEY='YOUR_API_KEY' otelcol-mackerel --config ./config-json.yaml
```

### 3) Mackerel版（プレインログ）

1. combined形式でログ生成:

```bash
LOG_FORMAT=combined ./generate_access_log.sh ./access.log
```

2. 別ターミナルで Collector 起動:

```bash
MACKEREL_APIKEY='YOUR_API_KEY' otelcol-mackerel --config ./config.yaml
```

## 補足

- `config-json-contrib.yaml` ではメトリクスは 1 分バッチ（`batch/metrics_1m`）で送信する想定です。
- `url.path` はクエリ除去・末尾スラッシュ正規化（`/` を除く）を行います。
- severity は `status >= 500` を `ERROR/17`、それ以外を `INFO/9` に設定します。
