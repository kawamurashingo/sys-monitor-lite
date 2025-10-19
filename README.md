# Sys::Monitor::Lite

軽量なシステム監視ツールキット。`script/sys-monitor-lite` スクリプトを使って Linux 上の CPU / メモリ / ディスク / ネットワークなどのメトリクスを JSON 形式で取得できます。Perl のみで完結し、外部依存はありません。

## 特徴

- `/proc` 以下の情報を読み取るだけの軽量実装
- CPU、ロードアベレージ、メモリ、ディスク、ネットワーク、システム情報を収集
- 収集するメトリクスを CLI から選択可能
- JSON / JSON Lines 出力に対応し、`--pretty` オプションで整形も可能
- モジュール (`Sys::Monitor::Lite`) としても利用でき、スクリプトから再利用しやすい

## インストール

CPAN からインストールする場合:

```bash
cpanm Sys::Monitor::Lite
```

リポジトリから直接利用する場合:

```bash
git clone https://github.com/yourname/sys-monitor-lite.git
cd sys-monitor-lite
perl Makefile.PL && make install
```

インストールせずにリポジトリ内のスクリプトを直接実行することもできます。

## 使い方 (コマンドライン)

### 単発でメトリクスを収集

```bash
script/sys-monitor-lite --once
```

### 5 秒間隔で継続的に収集 (デフォルト)

```bash
script/sys-monitor-lite --interval 5
```

### 収集メトリクスを絞り込み、JSON Lines で出力

```bash
script/sys-monitor-lite --interval 10 --collect cpu,mem,disk --output jsonl
```

### 主なオプション

| オプション | 説明 |
| ----------- | ---- |
| `--interval <秒>` | 繰り返し収集する間隔を指定します。デフォルトは 5 秒。0 以下の場合は単発になります。 |
| `--once` | 単発で 1 度だけ収集します。`--interval` が指定されていない場合は同等の挙動になります。 |
| `--collect <リスト>` | `system,cpu,load,mem,disk,net` からカンマ区切りで収集対象を指定します。 |
| `--output <形式>` | `json` (デフォルト) か `jsonl` を指定できます。 |
| `--pretty` | JSON 出力を整形します (`jsonl` の場合は無効)。 |
| `--help` | ヘルプ (POD) を表示します。 |

JSON 出力は `jq` や `jq-lite` などのツールと組み合わせて扱えます。

```bash
script/sys-monitor-lite --once | jq '.mem.used_pct'
```

## Perl モジュールとして利用する

```perl
use Sys::Monitor::Lite qw(collect_all to_json);

my $metrics = collect_all();
print to_json($metrics, pretty => 1);
```

`collect_all` の代わりに `collect(["cpu", "mem"])` のように配列リファレンスでメトリクスを指定することも可能です。

## 取得できるデータ

- `system`: OS 名、カーネルバージョン、ホスト名、アーキテクチャ、稼働時間 (秒)
- `cpu`: コア数と総合 CPU 利用率 (直近 ~100ms の差分)
- `load`: 1/5/15 分ロードアベレージ
- `mem`: メモリの総量・使用量・空き容量、スワップ使用量
- `disk`: マウントポイントごとの総容量・使用容量・使用率
- `net`: インターフェースごとの受信/送信バイト数・パケット数

## ライセンス

MIT License

## 作者

Shingo Kawamura ([@kawamurashingo](https://github.com/kawamurashingo))
