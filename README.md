
# 📘 README Structure

## 1. Title & Tagline

```markdown
# Sys::Monitor::Lite
*A lightweight system monitoring toolkit for Linux, written in pure Perl.*

Collect CPU, memory, disk, network, and process metrics — all in clean JSON.  
Perfect for automation, DevOps pipelines, and integration with [jq-lite](https://metacpan.org/pod/JQ::Lite).
```

---

## 2. Motivation / Why It Exists

```markdown
## 🌍 Why Sys::Monitor::Lite?

Modern observability tools like Prometheus or Datadog are powerful — but heavy.  
In small-scale environments, embedded systems, and private datacenters,  
administrators still need **a fast, dependency-free way to monitor system health**.

`Sys::Monitor::Lite` was created for that world:
- Works on any Linux system (no root required)
- Outputs structured **JSON telemetry**
- Easily combined with `jq-lite`, shell pipelines, or custom scripts
- Zero external dependencies (uses `/proc` and core Perl only)

It's **lightweight observability for everyone**, from IoT to HPC.
```

---

## 3. Features

```markdown
## ✨ Features

- 🧠 **Simple & Fast** — no agents, daemons, or daemons needed.
- ⚙️ **Collects Key Metrics**
  - CPU usage, load average
  - Memory, swap
  - Disk usage and filesystem stats
  - Network I/O per interface
  - Process and system uptime info
- 🧾 **JSON Output** — perfect for data pipelines and automation.
- 🧩 **Integrates with jq-lite** — filter and analyze metrics directly.
- 🧱 **Modular Design** — extend collectors easily (`Sys::Monitor::Lite::Collector::*`).
- 🧰 **CLI or Perl API** — run as command or import as a module.
```

---

## 4. Installation

````markdown
## 📦 Installation

From CPAN:
```bash
cpanm Sys::Monitor::Lite
````

Or from GitHub:

```bash
git clone https://github.com/yourname/sys-monitor-lite.git
cd sys-monitor-lite
perl Makefile.PL && make install
```

````

---

## 5. Usage Examples
```markdown
## 🚀 Examples

### Basic one-shot collection
```bash
sys-monitor-lite --once
````

### Filter with jq-lite

```bash
sys-monitor-lite --once | jq-lite '.disk[] | select(.used_pct > 80)'
```

### Continuous monitoring (JSON Lines output)

```bash
sys-monitor-lite --interval 5 --collect cpu,mem,disk --output jsonl
```

### Nagios-compatible check

```bash
sys-monitor-lite --nagios mem --threshold 'mem.used_pct > 90'
```

### As a Perl module

```perl
use Sys::Monitor::Lite 'collect_all';
my $data = collect_all();
print $data->{cpu}->{usage_pct}->{total}, "%\n";
```

````

---

## 6. Example Output
```markdown
## 📊 Example JSON Output

```json
{
  "timestamp": "2025-10-19T12:34:56Z",
  "system": { "os": "Linux", "kernel": "5.15.0", "uptime_sec": 123456 },
  "cpu": { "cores": 8, "usage_pct": { "total": 7.3 } },
  "mem": { "total_bytes": 33554432000, "used_bytes": 1234567890 },
  "disk": [
    { "mount": "/", "used_pct": 23.0 }
  ],
  "net": [
    { "iface": "eth0", "rx_bytes": 123456789, "tx_bytes": 987654321 }
  ]
}
````

````

---

## 7. Integration & Ecosystem
```markdown
## 🔗 Integration

`Sys::Monitor::Lite` speaks JSON, so it works with anything:

| Tool | Example |
|------|----------|
| **jq-lite** | `sys-monitor-lite | jq-lite '.cpu.usage_pct.total'` |
| **Fluent Bit / Logstash** | Stream JSON directly to a collector |
| **Prometheus** | Use `--prometheus` mode to export metrics |
| **Nagios** | Use `--nagios` mode for simple threshold checks |
| **AI Ops** | Feed the JSON into LLMs for automated health summaries |

````

---

## 8. Philosophy

```markdown
## 🧭 Philosophy

> “Observability should be simple, open, and scriptable.”

`Sys::Monitor::Lite` promotes **Open Observability**:
- No vendor lock-in
- No heavy daemons or hidden telemetry
- 100% open source, readable, and hackable
```

---

## 9. Roadmap

```markdown
## 🗺️ Roadmap

| Version | Focus |
|----------|-------|
| v0.1 | Basic metrics (CPU, mem, disk, net, system) |
| v0.2 | Prometheus & Nagios output, `jq-lite` filter integration |
| v0.3 | macOS / BSD fallback support |
| v0.4 | Process & inode metrics, extended schema |
```

---

## 10. License & Author

```markdown
## 📄 License

MIT License

## 👤 Author

**Shingo Kawamura**  
GitHub: [@kawamurashingo](https://github.com/kawamurashingo)
```

---

## 🔥 Tagline for Reddit / Hacker News Post

> “Perl isn’t dead — it’s monitoring your system.”
> Introducing **Sys::Monitor::Lite**, a zero-dependency JSON system monitor that pairs perfectly with `jq-lite`.

