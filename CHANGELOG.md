# CHANGELOG — SK TRADE PREMIUM

All notable changes to this project are documented here.

---

## [8.0] - 2026-06-28

### Architecture ✨

#### ZMQ Protocol Stabilization (V2 → V2 with extended validation)
- Completed CRC-8/SMBUS validation framework on all ports (5555-5559)
- Implemented socket timeout handling via `asyncio.wait_for()` (100-250ms per port)
- Added graceful reconnect on EA restart detection (`tel_seq` wraparound > 0x7FFFFFFF)
- **CRITICAL FIX**: `gZMQLastHeartbeat = TimeCurrent()` init (was 0, causing instant autonomous trigger)

#### Data Pipeline (P1)
- Ring buffers for M1, M5, M15, H1, H4, D1 OHLCV
- DOM cache with 20-level depth snapshot
- Telemetry absorption from E16 (`equity`, `spread`, `margin_level`, `tel_seq`)
- Volume scaling: `iVolume(M1,0) × 100` → unpacked as `uint32 / 100`

#### Feature Engine (P2)
- **52-element locked vector** with fixed indices (see section 11, CLAUDE.md)
- 6-tier hierarchy: price action, trend, momentum, volatility, volume, market structure
- Batch compute via `run_in_executor` (100-500ms)
- Feature staleness: never older than 60s; cold-start buffering for first 2 minutes

#### Regime Classifier (P3/M1)
- XGBoost primary (7-class: ranging, bull_trend, bear_trend, reversal_up, reversal_down, weak_volatility, high_volatility)
- LTC soft-ensemble for temporal consistency
- Confidence: per-class probabilities + aggregate confidence score
- Retrain: weekly walk-forward (P9, Sunday 23:00 UTC, 12 phases)

#### Smart Money Concepts (P4)
- Order Block (OB): High-volume rejection zones
- Fair Value Gap (FVG): Unfinished liquidity sweeps
- Break of Structure (BOS): Trend confirmation
- Change of Character (CHOCH): Reversal signals
- **Integration**: P5 gates check SMC zone overlap; P7 executor weights by zone priority

#### Hard Gate System (P5)
- **14 rules** (G1-G14) blocking entry when confidence insufficient or risk extreme
- Rules include: minimum confidence threshold, spread excess, DOM imbalance, equity floor, daily DD, circuit breaker status
- Veto evaluation: sequential short-circuit on first blocked gate
- Gate telemetry: which rule blocked + reason → trace ID logging

#### Signal Generation (P6)
- Temporal Fusion Transformer (TFT) + TCN-LSTM hybrid
- Input: 52-feature vector (P2) + regime (P3) + SMC zones (P4)
- Output: `{signal ∈ {-1, 0, +1}, confidence ∈ [0, 1]}`
- Inference: <14ms per call (locked via `_p6_sem(1)` semaphore)
- Model retraining: P9 walk-forward validation + staged promotion

#### Trade Executor (P7)
- Command builder: direction, lot size, SL (pips), TP1/TP2/TP3 (pips), confidence, regime, risk profile
- Mode-specific TP scaling:
  - HFT: single TP tier (full position at TP1)
  - SCALP: 3 tiers (40% @ TP1, 25% @ TP2, 35% @ TP3)
  - MODERATE: 3 tiers (40% @ TP1, 25% @ TP2, 35% @ TP3)
- Lot clamping: enforces risk % of equity + margin rules
- **Trace ID**: 12-hex uuid fragment for end-to-end audit (Python→MT5→fill)

#### Circuit Breakers (P8/CB1-CB5)
- **CB1** Equity Floor: If equity < SK_CB1_EQUITY_PCT (default 80%) of balance → 60min halt + FLAG_EMERGENCY_HALT
- **CB2** Daily Drawdown: If session DD > SK_CB2_MAX_DD_PCT% (default 5%) → session halt
- **CB3** Spread: If spread > normal or > SK_CB3_SPREAD_PIPS_MAX → entry blocked
- **CB4** DOM Imbalance: If bid/ask ratio > SK_CB4_IMBALANCE_THRESH (default 0.65) → entry blocked (grace 90s startup)
- **CB5** Tick Velocity: If tick z-score > SK_CB5_TICK_ZSCORE (default 3.5) → spike filter entry block

#### Weekly Retrain (P9)
- **Schedule**: Sunday 23:00 UTC (configurable via env)
- **12 phases**: data pull → feature eng → M1 XGBoost train → M1 LTC train → M2 VAE → P6 TFT → P6 TCN → P13 PPO → walk-forward validation → staged → model swap → cleanup
- **Staging path**: `models/shadow/` → walk-forward → `models/live/` (atomic swap)
- **Gates**: `_ltc_swap_event` and `_vae_swap_event` asyncio.Events block other loops during swap
- **Progress broadcast**: Dashboard ML Engine tab shows pct, msg, phase

#### Online Learning (P10)
- Real-time loss aggregation per trade
- IsoForest anomaly detection on feature drift
- M3 anomaly score triggers emergency halt if > SK_M3_HALT_THRESH (0.30)
- Model staleness: if no updates in 12 hours → trigger manual retrain alert

#### Position Management (P13)
- Proximal Policy Optimization (PPO) agent
- 10-dim observation: `[equity, margin_level, open_pnl, num_trades, avg_win, avg_loss, consecutive_wins, consecutive_losses, regime, mode]`
- Actions: `{hold, tighten_sl, loosen_sl, close_partial, close_full}`
- ~1s cadence per trade

#### Risk Classifier (P14)
- Lot multiplier assignment: 0=APEX(1.50×), 1=DYNAMIC(1.00×), 2=BALANCED(0.75×), 3=GUARDIAN(0.40×), 4=CUSTOM
- Input: regime + market conditions + recent equity changes
- Output: risk score 0-4 → applied to base lot calculation

#### Macro Correlation (P15)
- DXY, XAG, VIX, US10Y fetch (~15min cadence)
- Correlation matrix recomputed: each asset vs current chart symbol
- Weight multipliers on S/R levels: if DXY strong, gold weighting adjusted
- Dashboard ML tab displays correlation heatmap

#### Sentiment Engine (P16)
- Anthropic Claude API integration (Anthropic SDK `anthropic.Anthropic(api_key=...)`)
- 5min cadence sentiment poll
- Input: last 20 trades (entry reason, exit reason, pnl)
- Output: market sentiment label (bullish, neutral, bearish) + confidence
- Used by P17 as context for confluence analysis

#### Mode-Specific AI (P17)
- Confluence analysis: 8-32s compute (run_in_executor, `_p17_sem(1)` semaphore)
- **Input**: indicator snapshot (ema9-800, sma20, rsi, stoch, vwap) + regime + sentiment + macro
- **Output**: `{"ema9": value, "ema21": value, ..., "rsi_14": value, "vwap": value}` (lowercase keys)
- **Integration**: P6 confidence boosted if P17 analysis confirms direction
- **Throttle**: 60s minimum between cycles (SK_P17_CYCLE_SECS)

#### Dashboard (FastAPI + WebSocket)
- Server: `http://127.0.0.1:8766` (port: SK_DASH_PORT in .env)
- **Endpoints**:
  - `/ws` — WebSocket real-time push (full state snapshot on connect)
  - `/api/state` — Current system state (read-only)
  - `/api/trades` — Open/closed trades list
  - `/api/logs` — Recent log entries
  - `/static/` — dashboard.html + assets
- **Throttle policy**: tick (0.25s), indicators (0.5s), engine_status (0.5s), mode_ai (1.0s)
- **Batch mode**: Wait 1s for first message, collect 199 more → single JSON frame (prevents DOM flooding)
- **Ping/Pong**: 10s interval, 5s timeout → zombie detection within 15s

#### Database (P12/SQLite)
- **Path**: `sk_trade.db` (WAL mode for concurrent read/write)
- **Tables**: trades, fills, daily_pnl, feature_snapshots, alerts
- **Lifecycle**: every trade → row insert; every hour → PnL snapshot; weekly → vacuum
- **Atomicity**: PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL

#### Autonomous Mode (E15 Shadow Engine)
- **Trigger**: `gZMQMissedHeartbeats >= InpHBMissedThreshold` (default 20 over 10s) OR `InpBotRole == 2`
- **Engine**: Pre-computed E6 feature vector (gPackedFeatures) → shadow signal generation
- **Confidence threshold**: lower than full Python pipeline (conservative fallback)
- **Deactivation**: 3-ACK debounce on heartbeat recovery

### Fixes 🔧

#### Critical
1. **gZMQLastHeartbeat initialization** — Was 0 (Unix epoch 1970), causing `TimeCurrent() - 0 ≈ 177M seconds` → instant autonomous trigger on startup. Now initialized to `TimeCurrent()` in E16_Init().
2. **EA restart detection** — `tel_seq` wraparound (delta > 0x7FFFFFFF) triggers `_ea_restarted=True` → heartbeat loop calls socket-only reconnect (no `ctx.term()`, avoiding TIME_WAIT)
3. **asyncio.wait_for timeout on ZMQ recv** — `zmq.asyncio` sockets ignore `RCVTIMEO`; all recv paths now wrapped: `await asyncio.wait_for(sock.recv(), timeout=X)`

#### High
4. **CRC-8 polynomial** — Locked to SMBUS (0x07). Self-test at import: `assert crc8(b"123456789") == 0xF4`
5. **Binary tick frame schema** — Standard (50B) vs Extended (67B with trendlines). CRC at end (byte [49] for standard, byte [66] for extended). OFI/cascade/tl_align: signed int32 (use `struct.unpack_from('<i', ...)`), NOT unsigned.
6. **Trade command staleness** — E16 rejects if `age_us > 5,000,000 µs` (5s); Python also drops stale event-loop commands >2s

#### Medium
7. **Feature vector indexing** — P2 has FIXED indices; P2.17 uses correct offsets (e.g., rsi_14=feats[5], NOT [0])
8. **P17 indicator keys** — Dashboard JS expects lowercase (ema9, not EMA9); all 8 keys mapped
9. **Mode/profile authority** — `brain_state.json` (Python) overrides `ea_config.json` (MT5); EA's `InpBotMode` only affects E15 shadow
10. **Dashboard HTML encoding** — UTF-8 with \r\n (Windows CRLF); file: 379,407 bytes. Use Edit tool directly, not batch patch scripts.

#### Low
11. **Heartbeat miss debounce** — 3-ACK streak required before clearing `_autonomous` flag (prevents log spam on transient misses)
12. **PAIR socket after EA restart** — Reconnect called within 2 HB cycles (~0.8s) to re-establish peer connection
13. **Symbol resolution** — Python sends clean base ('XAUUSD'); EA calls `GetBrokerSymbol()` to resolve broker variant. If not found: SYMERR message on port 5557 → Python logs `[TRACE-<tid>]`

### Known Issues ⚠️

1. **P17 long blocks (8-32s)** — Runs in executor with `_p17_sem(1)`. HB still fires every 0.4s, but GIL contention can spike latency >1s on slow hardware. Monitor `sk_trade.log` for HB gaps >3s; reduce P17 cycle via SK_P17_CYCLE_SECS if needed.

2. **Infrastructure gaps (not code-fixable)**:
   - B-Book emulation latency (GAP 101/241)
   - Last Look LP rejections (GAP 347)
   - BGP route flaps (GAP 305/392)
   - Thermal throttling (GAP 315/389)
   - NUMA misalignment (GAP 251)

3. **Windows scheduler resolution** — Locked to 1ms via `timeBeginPeriod(1)`, but system load can cause jitter. SSD placement of `sk_trade.db` recommended.

### Added 📝

- Full 20-section CLAUDE.md architecture reference (174 pivot levels, 3510 swing levels, 84,309 total S/R concepts locked)
- Comprehensive README with quick start, config, troubleshooting
- CHANGELOG (this file) tracking all changes session-by-session
- FAILURE_LOG.md documenting 395+ audit gaps and resolutions

### Improved 🚀

- ZMQ protocol now fully schema-validated (no backward-incompatible changes)
- Dashboard batching reduced browser DOM flooding (200 msgs/frame, 1s max)
- P9 retrain progress broadcast to dashboard in real-time
- Trace ID pipeline fully bidirectional (Python→MT5→fill→Python)
- Log output structured with `[TRACE-<id>]` for grep-able lifecycle audit

### Deprecated ⛔

- Old zmq_bridge.py message parsing (msgpack-first tick attempt) — removed in favor of binary-struct-only
- Manual model loading — now automated via P9 walk-forward

---

## [7.0] - 2026-05-22

### Major Features
- Introduced TFT+TCN-LSTM hybrid signal generator (P6)
- Added multi-timeframe cascade alignment (E3)
- Implemented weekly retrain scheduler (P9) with walk-forward validation
- Launched FastAPI dashboard (port 8766) with WebSocket

### Architecture Changes
- Migrated from pub/sub to full ZMQ port mesh (5555-5559)
- Introduced heartbeat protocol (port 5559 PAIR)
- Moved all indicator computation to async executors (GIL contention fix)

### Bug Fixes
- Fixed ZMQ socket linger behavior (LINGER=0 → immediate close)
- Corrected ATR scaling in EA (was uint32 / 1e6, now scaled correctly)
- Fixed OFI sign handling (use signed int32, NOT unsigned)

---

## [6.0] - 2026-04-15

### Initial Release
- Core EA architecture (E1-E9, E16-E18)
- Python Brain with P1-P14 engines
- XGBoost regime classifier (M1)
- VAE anomaly detection (M2)
- IsoForest online anomaly (M3)
- Basic dashboard prototype

---

## Version Legend

- **Major** (X.0): Architecture redesign or protocol breaking change
- **Minor** (X.Y): New feature or significant fix
- **Patch** (X.Y.Z): Bug fix or minor improvement

---

**Last Updated:** 2026-06-28  
**Status:** Production Ready  
**Next Session Focus:** P2 scoring refinements, TSL logic review, failure case mitigation
