# SK TRADE PREMIUM V8.0

**Advanced Algorithmic Trading Bot for MetaTrader 5**

A sophisticated hybrid trading system combining machine learning (XGBoost, LTC, VAE, TFT+TCN-LSTM, PPO), Smart Money Concepts (SMC), technical analysis, and real-time risk management across multi-timeframe configurations.

---

## ✨ Key Features

### Core Architecture
- **Python Brain** (`PYTHON_BRAIN/`) — 16-step async orchestrator with 17 specialized engines (P1-P17)
- **MQL5 EA** (`MQL5_CODE/SK_V8/`) — Expert Advisor for MetaTrader 5 with 9 core engines (E1-E9, E16-E18)
- **ZMQ Bridge** — 5-port bidirectional data mesh (tick, command, DOM, fill, heartbeat) + WebSocket dashboard
- **FastAPI Dashboard** — Real-time WebSocket monitoring on port 8766

### Trading Logic
| Component | Purpose |
|-----------|---------|
| **P1 Data Pipeline** | Tick ingestion, OHLCV ring buffers, DOM cache |
| **P2 Features** | 52-element feature vector (6 tiers) |
| **P3/M1 Regime** | XGBoost + LTC ensemble classifier (7 classes) |
| **P4 SMC** | Smart Money Concepts (OB/FVG/BOS/CHOCH) |
| **P5 Gate** | 14-rule hard gates (G1-G14 blockers) |
| **P6 Model** | TFT + TCN-LSTM hybrid signal generator |
| **P7 Executor** | Trade command builder (msgpack+CRC-8) |
| **P8 Circuit Breaker** | Risk manager (CB1-CB5) |
| **P9 Retrain** | Weekly walk-forward (Sunday 23:00 UTC) |
| **P10 Online** | Online learning + IsoForest anomaly (M3) |
| **P13 PPO** | Position management agent (10-dim observation) |
| **P14 Risk** | M2 risk classifier (lot multiplier) |
| **P17 Confluence** | Mode-specific AI analysis engine |

### Risk Management
- **Circuit Breakers**: Equity floor, daily drawdown, spread, DOM imbalance, tick velocity, anomaly
- **Dynamic Position Sizing**: Risk-adjusted lot multiplier based on regime + mode
- **Trailing Stop Loss**: Adaptive per-mode ATR scaling
- **Multi-Tier Confidence**: Mode-gated entry thresholds

---

## 📁 Project Structure

```
SK TRADE PREMIUM\
├── PYTHON_BRAIN\                Python brain orchestrator
│   ├── main.py                  Master brain (16-step startup, 14 async tasks)
│   ├── zmq_bridge.py            ZMQ v2 protocol layer
│   ├── dashboard_server.py       FastAPI WebSocket server (port 8766)
│   ├── p1_data.py .. p17_mode_ai.py  Engine implementations
│   ├── models/
│   │   ├── live/                Active models (m1_ltc.pt, m2_vae.pt)
│   │   ├── shadow/              Staging models (P9 retrain)
│   │   └── checkpoints/         Epoch checkpoints
│   ├── sk_trade.db              SQLite WAL database
│   ├── sk_trade.log             Main log
│   ├── brain_state.json         Authority for mode/profile
│   └── .env                     Environment overrides
├── MQL5_CODE\SK_V8\             MQL5 EA source
│   ├── SK_V8_OnInit.mqh         Master init (P01-P32)
│   ├── SK_V8_P29_E16_ZMQ.mqh    ZMQ bridge
│   ├── SK_V8_P33_OnTick.mqh     OnTick handler
│   └── ... (E1-E18 engines)
├── CLAUDE.md                    Authoritative architecture reference
├── CHANGELOG.md                 Version history & fixes
└── README.md                    This file
```

---

## 🚀 Quick Start

### Prerequisites
- MetaTrader 5 (latest build)
- Python 3.10+ with: asyncio, msgpack, zmq, numpy, pandas, torch, xgboost, sklearn, uvicorn
- ZMQ library (libzmq)
- Models trained & staged in `models/live/`

### Installation

1. **Clone repository**
   ```bash
   git clone https://github.com/sohebkhansk11/SK-TRADE-PREMIUM.git
   cd SK-TRADE-PREMIUM
   ```

2. **Set up Python environment**
   ```bash
   cd PYTHON_BRAIN
   python -m venv venv
   venv\Scripts\activate  # Windows
   pip install -r requirements.txt
   ```

3. **Configure environment** (`.env`)
   ```
   SK_ZMQ_HOST=127.0.0.1
   SK_ZMQ_PORT_TICKS=5555
   SK_ZMQ_PORT_CMDS=5556
   SK_DASH_PORT=8766
   SK_MODE=1
   SK_PROFILE=2
   ANTHROPIC_API_KEY=sk-...
   ```

4. **Place MQL5 EA in MetaTrader 5**
   ```
   Copy MQL5_CODE\SK_V8\ → C:\Users\...\AppData\Roaming\MetaQuotes\Terminal\...\MQL5\Experts\
   ```

5. **Run Python Brain**
   ```bash
   python main.py
   ```

6. **Attach EA to chart**
   - Open XAUUSD M1 chart in MT5
   - Drag EA onto chart
   - Set inputs (see section 6 below)
   - Click OK

7. **Monitor dashboard**
   - Open browser: `http://localhost:8766`
   - Watch live ticks, signals, trades

---

## ⚙️ Configuration

### Environment Variables (`.env`)
See [CLAUDE.md § 18](./CLAUDE.md#18-key-env-vars-env-or-os-environment) for full list.

**Critical:**
- `SK_MODE`: 0=HFT, 1=SCALP, 2=MODERATE
- `SK_PROFILE`: 0=APEX, 1=DYNAMIC, 2=BALANCED, 3=GUARDIAN, 4=CUSTOM
- `SK_HB_INTERVAL`: Heartbeat interval (0.4s recommended)
- `SK_CB1_EQUITY_PCT`: Equity floor (0.80 = halt at -20%)

### EA Inputs
Key MT5 EA parameters:
- `InpEnableBot`: Enable trading
- `InpMode`: Trading mode (0/1/2)
- `InpUseZMQ`: Enable ZMQ bridge
- `InpBotRole`: 0=ZMQ, 1=Hybrid, 2=Autonomous
- `InpMagic`: Trade magic number (9090)

---

## 🔗 ZMQ Port Map

| Port | Direction | Type | Purpose |
|------|-----------|------|---------|
| 5555 | MT5→Py | PUSH/PULL | Tick batches (binary) |
| 5556 | Py→MT5 | PUSH/PULL | Trade commands (msgpack+CRC-8) |
| 5557 | MT5→Py | PUSH/PULL | DOM + telemetry (msgpack/JSON) |
| 5558 | MT5→Py | PUSH/PULL | Fill feedback (msgpack+CRC-8) |
| 5559 | Bidirectional | PAIR | Heartbeat (Python 0.4s, EA 500ms) |
| 8766 | Py↔Browser | WebSocket | Dashboard |

**Key:** All ZMQ sockets use `LINGER=0`, `RCVHWM=1000`, `TCP_NODELAY=1` for production-grade latency.

---

## 📊 Dashboard

**Real-time Monitoring:**
- Live tick data (bid, ask, spread)
- P1-P17 engine status & metrics
- Open trades, profit/loss, risk metrics
- Circuit breaker status
- Model confidence & regime classification
- P9 retrain progress

**URL:** `http://localhost:8766`

**WebSocket batching:** Up to 200 messages per frame, max 1s latency.

---

## 🧠 Machine Learning Models

### M1 — Regime Classifier
- **Type**: XGBoost + LTC soft-ensemble
- **Input**: 52-feature vector
- **Output**: 7-class regime (0-6)
- **Path**: `models/live/m1_ltc.pt`
- **Retrain**: Weekly (P9)

### M2 — Risk Classifier  
- **Type**: VAE anomaly + risk score
- **Output**: Risk profile 0-4 (affects lot multiplier)
- **Path**: `models/live/m2_vae.pt`

### M3 — Anomaly Detection
- **Type**: IsoForest
- **Gate**: Triggers emergency halt if score > 0.30
- **Warmup**: 60 ticks before anomaly gates active

### P6 — Signal Generator
- **Type**: TFT (Temporal Fusion) + TCN-LSTM hybrid
- **Output**: {signal ∈ {-1,0,+1}, confidence ∈ [0,1]}
- **Path**: `models/live/p6_signal.pt`
- **Inference**: <14ms (locked via `_p6_sem`)

---

## 🔄 Data Flow

### Tick Ingestion (MT5 → Python)
```
MT5 OnTick()
  ↓
E16_PackTick() → 50-byte binary struct (bid, ask, spread, atr, ofi, cascade, tl_align)
  ↓
ZMQ port 5555 (PUSH) → Python PULL
  ↓
P1DataPipeline.unpack_tick_batch()
  ↓
OHLCV ring buffers (M1, M5, M15, H1, H4, D1)
  ↓
_pipeline_tick() → P2 features → P3 regime → P4 SMC → P5 gates → P6 signal → P7 executor
```

### Trade Execution (Python → MT5 → Fill)
```
P7Executor.send_command()
  ↓
TradeCommandV2 (msgpack 20-field map + CRC-8) → ZMQ port 5556
  ↓
E16_ReceiveCommand() → symbol resolution → E7_PlaceTrade()
  ↓
MT5 OrderSend() → ticket
  ↓
E16_SendFill() → ZMQ port 5558
  ↓
P12Database records trade + lifecycle
```

---

## 🎯 Usage Modes

| Mode | Symbol | Risk Profile | Lot Multiplier | TP Tiers | Use Case |
|------|--------|--------------|----------------|----------|----------|
| **HFT** | XAUUSD, EURUSD, etc. | APEX (1.5×) | Up to 1.50 | 1 tier (full) | 1-5 min scalping |
| **SCALP** | XAUUSD, EURUSD, etc. | DYNAMIC (1.0×) | Standard | 3 tiers (40%/25%/35%) | 5-30 min swings |
| **MODERATE** | XAUUSD (recommended) | BALANCED (0.75×) | Conservative | 3 tiers (40%/25%/35%) | 30m-4h holds |

---

## 📋 Heartbeat Protocol

**Python → EA (every 0.4s)**
- Status flags (AI ready, DOM fresh, models loaded, emergency halt, anomaly, drift)
- Confidence scores

**EA → Python (every 0.5s)**
- Equity, regime, safety lock
- CRC-8 validated

**Miss Tolerance:** 20 misses (8s grace) before autonomous mode triggers.

---

## 🚨 Circuit Breakers

| CB | Trigger | Action | Config |
|----|---------|--------|--------|
| **CB1** | Equity < SK_CB1_EQUITY_PCT × balance | Emergency halt 60min | `SK_CB1_ENABLED`, `SK_CB1_EQUITY_PCT=0.80` |
| **CB2** | Daily drawdown > SK_CB2_MAX_DD_PCT% | Session halt | `SK_CB2_ENABLED`, `SK_CB2_MAX_DD_PCT=5.0` |
| **CB3** | Spread > normal or > threshold | Block entry | `SK_CB3_ENABLED` |
| **CB4** | DOM imbalance > 0.65 | Block entry (grace window) | `SK_CB4_ENABLED` |
| **CB5** | Tick z-score > 3.5 | Spike filter | `SK_CB5_ENABLED` |
| **M3** | Anomaly score > 0.30 | Emergency halt | `SK_M3_HALT_THRESH=0.30` |

**Startup grace:** 90s (CB4/CB5 disabled during warmup).

---

## 📝 Logging

All activity logged to `sk_trade.log` with trace IDs:

```
[TRACE-abc123def456] ZMQ→EA | dir=+1 mode=1 conf=68.5% lot=0.05 sym=XAUUSD
[TRACE-abc123def456] ORDER_OK | ticket=123456789 sym=XAUUSD.
```

**Grep by trace ID:** `grep "TRACE-abc123" sk_trade.log`

---

## 🐛 Troubleshooting

### ZMQ data not flowing
1. Check `sk_trade.log`: Look for `CRC fail`, `Tick parse`, `Recv tick` errors
2. Verify `InpUseZMQ=True` in EA inputs
3. Confirm Python brain running: `netstat -an | grep 555`
4. Check firewall (ports 5555-5559 open)

### Heartbeat misses / autonomous mode
1. Check `sk_trade.log`: `HB#N seq | flags=[...] miss=K`
2. If miss count rising: GIL starvation? Check P17 + P2 executor blocks
3. Verify `gZMQLastHeartbeat` init in EA: must be `TimeCurrent()` in E16_Init

### Indicators tab showing "--"
1. P17 keys must be lowercase (ema9, not EMA9)
2. Verify feature indices in P2 (section 11 in CLAUDE.md)
3. Check P17 cycle throttle < `SK_P17_CYCLE_SECS`

### Trade rejected with ORDER_ERR
1. Grep `[TRACE-<tid>]` in MT5 journal for full lifecycle
2. Common: `INVALID_STOPS` (SL too close to broker min)
3. Common: `SYMBOL_ERR` (broker symbol not in Market Watch)

---

## 📚 Documentation

- **[CLAUDE.md](./CLAUDE.md)** — Authoritative architecture reference (20 sections)
- **[CHANGELOG.md](./CHANGELOG.md)** — Version history, bug fixes, improvements
- **[FAILURE_LOG.md](./FAILURE_LOG.md)** — Known issues, gaps, workarounds
- Inline code comments for non-obvious logic

---

## 🔐 Security Notes

- ZMQ sockets use `LINGER=0` for safe shutdown (no pending data left in sockets)
- CRC-8/SMBUS validation on all inter-process communication
- Trade commands include 12-hex trace IDs for end-to-end audit trail
- EA → Python: binary struct (no pickle/eval vulnerability)
- Python → EA: msgpack (schema-validated, type-safe)

---

## 📦 Dependencies

### Python
- `asyncio` — async event loop
- `msgpack` — binary serialization
- `zmq` (pyzmq) — ZMQ bindings
- `numpy`, `pandas` — data structures
- `torch` — deep learning (M1, M2, P6, P13)
- `xgboost` — regime classifier
- `sklearn` — preprocessing, IsoForest
- `uvicorn` — FastAPI server
- `sqlalchemy` — database ORM

### MQL5
- MQL5 standard library (`Trade.mqh`, `SymbolInfo.mqh`, etc.)
- No external DLLs (pure MQL5)

---

## 🤝 Contributing

For issues, feature requests, or improvements:
1. Document in [FAILURE_LOG.md](./FAILURE_LOG.md)
2. Create a branch: `git checkout -b fix/issue-name`
3. Commit with trace ID: `git commit -m "Fix XYZ [TRACE-abc123]"`
4. Push and create PR
5. Update CHANGELOG.md

---

## 📄 License

Proprietary — SK Trade Premium. All rights reserved.

---

## 📞 Support

For issues or questions:
- Check [CLAUDE.md § 20](./CLAUDE.md#20-quick-reference--common-debugging) for debugging guide
- Review latest entries in `sk_trade.log` with `grep "ERROR\|WARN"`
- Search [FAILURE_LOG.md](./FAILURE_LOG.md) for known issues

---

**Last Updated:** 2026-06-28  
**Status:** Production  
**Version:** 8.0
