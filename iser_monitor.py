'''
iser_monitor — iSER/RoCEv2 async polling daemon

	python3 iser_monitor.py                        # start daemon
	python3 iser_monitor.py --once                 # single poll, print to stdout (debug)
	python3 iser_monitor.py --once --interval 1

Log format (consumed by Zabbix log[] item):
	2025-03-08T10:00:05 ERROR   RDMA_ERROR         counter=rnr_nak_retry_err delta=3 total=15
	2025-03-08T10:00:05 ERROR   NIC_DROP           stat=rx_discards_phy delta=1 total=4
	2025-03-08T10:00:05 WARNING RDMA_RATE_HIGH     counter=np_cnp_sent rate=12.3/s threshold=10.0/s
	2025-03-08T10:00:05 WARNING RDMA_RATE_HIGH     counter=rp_cnp_ignored rate=2.0/s threshold=1.0/s
	2025-03-08T10:00:05 WARNING NIC_RATE_HIGH      stat=rx_pause_ctrl_phy rate=150.0/s threshold=100.0/s
	2025-03-08T10:00:05 WARNING NO_SESSIONS        active=0
	2025-03-08T10:00:05 WARNING SESSIONS_RESTORED  active=2
	2025-03-08T10:00:05 WARNING COUNTER_RESET      type=rdma name=rnr_nak_retry_err prev=10 curr=0
	2025-03-08T10:00:05 WARNING COUNTER_RESET      type=nic  name=rx_discards_phy prev=4 curr=0
	2025-03-08T10:00:05 WARNING COUNTER_RESET      type=net  name=rx_bytes prev=1000 curr=0
	2025-03-08T10:00:05 WARNING CONFIGFS_MISSING   path=/sys/kernel/config/target/iscsi/...
	2025-03-08T10:00:05 WARNING SKIPPED_ANALYSIS   reason=prev_stale
	2025-03-08T10:00:05 INFO    THROUGHPUT         rx_mbps=820.30 tx_mbps=95.10 sessions=2
	2025-03-08T10:00:05 INFO    HEALTH             status=OK      sessions=2 ...
	2025-03-08T10:00:05 WARNING HEALTH             status=DEGRADED sessions=2 ...
	2025-03-08T10:00:05 ERROR   HEALTH             status=CRITICAL sessions=0 ...
	2025-03-08T10:00:05 INFO    START              iface=enp59s0f0np0 interval=5s
	2025-03-08T10:00:05 INFO    STOPPED

Zabbix log[] item keys and regex patterns:
	errors:   RDMA_ERROR|NIC_DROP
	warnings: RDMA_RATE_HIGH|NIC_RATE_HIGH|NO_SESSIONS|COUNTER_RESET
	health:   HEALTH
	thruput:  THROUGHPUT

	Trigger find() expressions use "." (match-any) against the pre-filtered
	log[] item rather than repeating the filter pattern. This avoids silent
	mismatch if item filter and trigger expression drift out of sync.

HEALTH summary (emitted every health_log_interval seconds, default 60s):
	Synthesises all counters accumulated across the window into a single
	line with level matching the worst condition seen:
		INFO    status=OK       — clean window, no anomalies
		WARNING status=DEGRADED — rate thresholds exceeded, counter resets,
		                          cycles skipped, or rp_cnp_ignored > 0
		ERROR   status=CRITICAL — any RDMA error, NIC drop, or zero sessions
		                          (suppressed during startup_grace_period)

	HEALTH is the primary Zabbix trigger source for dashboard-level alerting.
	Granular events (RDMA_ERROR, NIC_RATE_HIGH, …) remain for drill-down.

	Fields:
		sessions            — session count at emission time
		rx_avg_mbps         — mean RX throughput over the window
		tx_avg_mbps         — mean TX throughput over the window
		cnp_avg_rate        — mean np_cnp_sent/s over the window
		cnp_ignored_avg     — mean rp_cnp_ignored/s over the window;
		                      any value > 0 indicates DCQCN is not throttling
		                      the sender — elevates status to DEGRADED
		pause_rx_avg        — mean pause-RX frames/s over the window
		pause_tx_avg        — mean pause-TX frames/s over the window
		rdma_errors         — total RDMA strict-counter increments in the window
		nic_drops           — total NIC strict-counter increments in the window
		counter_resets      — total COUNTER_RESET events (all types) in the window
		skipped             — cycles skipped due to snapshot timeout
		window              — actual elapsed seconds

	Status precedence (highest wins):
		CRITICAL  — rdma_errors > 0, or nic_drops > 0, or sessions == 0
		            (sessions == 0 only after startup_grace_period)
		DEGRADED  — cnp_avg_rate > thr_cnp_rate,
		            or cnp_ignored_avg > 0 (DCQCN ineffective),
		            or pause_rx/tx_avg > thr_pause_rate,
		            or counter_resets > 0, or skipped > 0,
		            or sessions == 0 within grace period
		OK        — none of the above

HealthWindow mutability:
	HealthWindow is a mutable accumulator. It is created fresh after each
	HEALTH emission and updated only from the main async loop (analyze()),
	so there is no concurrent access. The surrounding PollState uses
	dataclasses.replace() for its own fields; HealthWindow is intentionally
	mutated in place to avoid allocating a new object on every counter
	increment. This is consistent with its role as a rolling aggregator.

Sessions counter:
	_read_sessions() counts active sessions via the kernel configfs target path:
		/sys/kernel/config/target/iscsi/<iqn>/tpgt_1/sessions/

	When the sessions path does not exist, _read_sessions() returns (0, False).
	The caller in analyze() handles CONFIGFS_MISSING emission with the same
	throttle as NO_SESSIONS (no_sessions_relog_interval).

	SESSIONS_RESTORED is intentionally suppressed on the first analysis cycle
	(state.first_cycle == True). On that cycle, prev is the bootstrap snapshot
	taken before PollState is initialised; if prev.sessions == 0 and
	curr.sessions > 0 the transition would be logged as SESSIONS_RESTORED even
	though no actual disconnect/reconnect occurred — it is simply the daemon
	seeing the already-active session for the first time. Suppressing it on
	first_cycle prevents this false event. After first_cycle, all subsequent
	0 → N transitions are logged normally.

ethtool availability tracking:
	_ethtool_seen is stored in PollState (not as a module-level global) so
	that it is only read and written from the main async loop, eliminating
	any race with the thread pool worker that executes _read_ethtool.

	_check_ethtool_availability() is called from analyze() (main loop) after
	the ethtool result has been awaited and merged into the current Snapshot.
	It receives and returns PollState so the flag update is part of the normal
	immutable-state dataflow.

rp_cnp_ignored monitoring:
	rp_cnp_ignored is included in RDMA_RATE with a threshold of 1.0/s.
	Any positive rate means the Reaction Point is receiving CNP notifications
	from the Notification Point but not acting on them — DCQCN congestion
	control is not throttling the sender. This condition elevates HEALTH
	status to at least DEGRADED even when no hard errors or drops are present.

	cnp_ignored_rates is accumulated in HealthWindow alongside cnp_rates.
	_health_status checks _avg(hw.cnp_ignored_rates) > 0 as a DEGRADED
	condition, independent of the thr_cnp_rate threshold.

Constraints:
	POLL_INTERVAL >= 4s — enforced at startup. Required so that sub_timeout
	(interval * 0.6) and wait_timeout (interval * 0.85) have sufficient
	separation for the ethtool subprocess + asyncio.wait_for layers.

	startup_grace_period should be >= health_log_interval to guarantee
	coverage of the first HEALTH emission.

	NO_SESSIONS and CONFIGFS_MISSING share no_sessions_relog_interval.
	Both are suppressed for the first no_sessions_relog_interval seconds
	after daemon start.

	COUNTER_RESET for rx_bytes and tx_bytes are evaluated independently.
	A simultaneous reset of both increments counter_resets twice.

	next_deadline resets to loop.time() + interval after a snapshot timeout
	to prevent back-to-back snapshots with no idle gap.
'''

ENV = {
"DEVICE_NAME": "iser_monitor",
"LOG_DIR": "/var/log/zabbix",
"IFACE": "enp59s0f0np0",
"ISCSI_TARGET": "iqn.2025-01.local.storage:iser-target1",
"IB_BASE": "/sys/class/infiniband/mlx5_0",
"ETHTOOL_BIN": "/usr/sbin/ethtool",
"ETHTOOL_SUDO": True,
"POLL_INTERVAL": 5,
"thr_cnp_rate": 10.0,
"thr_pause_rate": 100.0,
"throughput_log_interval": 30.0,
"no_sessions_relog_interval": 30.0,
"thr_throughput_mbps": 1.0,
"health_log_interval": 60.0
}

import asyncio, dataclasses, logging, signal, subprocess, sys, time
from dataclasses import dataclass, field
from logging.handlers import WatchedFileHandler
from pathlib import Path

import click, uvloop

_HERE = Path(__file__).parent

# import orjson
# ENV   = orjson.loads((_HERE / 'env.json').read_bytes())

ENV['IB_BASE'] = Path(ENV['IB_BASE'])

POLL_INTERVAL:              float = float(ENV.get('POLL_INTERVAL',                 5))
THR_CNP_RATE:               float = float(ENV.get('thr_cnp_rate',               10.0))
THR_PAUSE_RATE:             float = float(ENV.get('thr_pause_rate',             100.0))
THROUGHPUT_LOG_INTERVAL:    float = float(ENV.get('throughput_log_interval',     30.0))
NO_SESSIONS_RELOG_INTERVAL: float = float(ENV.get('no_sessions_relog_interval',  30.0))
THR_THROUGHPUT_MBPS:        float = float(ENV.get('thr_throughput_mbps',          1.0))
HEALTH_LOG_INTERVAL:        float = float(ENV.get('health_log_interval',         60.0))
STARTUP_GRACE_PERIOD:       float = float(ENV.get('startup_grace_period',       120.0))
ETHTOOL_SUDO:               bool  = bool(ENV.get('ETHTOOL_SUDO',                True))

RDMA_STRICT: list[str] = [
	'rnr_nak_retry_err',
	'out_of_sequence',
	'local_ack_timeout_err',
	'duplicate_request',
]
RDMA_RATE: dict[str, float] = {
	'np_cnp_sent':    THR_CNP_RATE,
	# Any ignored CNP means the Reaction Point is not throttling despite
	# congestion signals from the Notification Point — DCQCN ineffective.
	'rp_cnp_ignored': 1.0,
}
NIC_STRICT: list[str] = [
	'rx_discards_phy',
	'rx_out_of_buffer',
]
NIC_RATE: dict[str, float] = {
	'rx_pause_ctrl_phy': THR_PAUSE_RATE,
	'tx_pause_ctrl_phy': THR_PAUSE_RATE,
}

LOG_FILE = Path(ENV['LOG_DIR']) / f"{ENV['DEVICE_NAME']}.log"
_fmt = logging.Formatter(
	'%(asctime)s %(levelname)-7s %(message)s',
	datefmt='%Y-%m-%dT%H:%M:%S',
)

_log = logging.getLogger('iser_monitor')
_log.setLevel(logging.INFO)

_fh = WatchedFileHandler(LOG_FILE)
_fh.setFormatter(_fmt)
_log.addHandler(_fh)

_sh = logging.StreamHandler(sys.stderr)
_sh.setFormatter(_fmt)
_sh.setLevel(logging.WARNING)
_log.addHandler(_sh)


# ---------------------------------------------------------------------------
# Low-level readers
# ---------------------------------------------------------------------------

def _sysfs_int(path: Path) -> int | None:
	try: return int(path.read_text().strip())
	except (OSError, ValueError): return None


def _read_rdma_counters(names: list[str]) -> dict[str, int]:
	result: dict[str, int] = {}
	for name in names:
		for sub in ('ports/1/hw_counters', 'hw_counters'):
			v = _sysfs_int(ENV['IB_BASE'] / sub / name)
			if v is not None:
				result[name] = v
				break
	return result


def _read_ethtool(names: list[str], timeout: float) -> dict[str, int]:
	'''
	Invoke ethtool -S and parse per-queue / per-port statistics.

	The sudo prefix is controlled by ETHTOOL_SUDO in env.json (default true).
	Set to false when the process has CAP_NET_ADMIN or runs as root.

	Returns an empty dict on timeout, exec failure, or non-zero exit.

	After proc.kill() on TimeoutExpired, proc.wait() is called with a 2s
	hard deadline to prevent the thread from leaking a zombie process. If
	the process still does not exit within that window (kernel bug / hung
	syscall), the wait is abandoned and an empty dict is returned — the
	thread itself will eventually unblock when the OS reaps the child.
	'''
	cmd = (
		(['sudo'] if ETHTOOL_SUDO else [])
		+ [ENV['ETHTOOL_BIN'], '-S', ENV['IFACE']]
	)
	proc = subprocess.Popen(
		cmd,
		stdout=subprocess.PIPE,
		stderr=subprocess.DEVNULL,
		text=True,
	)
	try:
		out, _ = proc.communicate(timeout=timeout)
	except subprocess.TimeoutExpired:
		proc.kill()
		try:
			proc.wait(timeout=2)
		except subprocess.TimeoutExpired:
			pass  # process did not exit; OS will reap eventually
		_log.error('ETHTOOL_TIMEOUT iface=%s', ENV['IFACE'])
		return {}
	except OSError as e:
		_log.error('ETHTOOL_FAIL error=%s', e)
		return {}
	if proc.returncode != 0:
		_log.error('ETHTOOL_FAIL rc=%d', proc.returncode)
		return {}
	raw: dict[str, int] = {}
	for line in out.splitlines():
		if ':' not in line:
			continue
		k, _, v = line.strip().partition(':')
		try:
			raw[k.strip()] = int(v.strip())
		except ValueError:
			pass
	return {n: raw[n] for n in names if n in raw}


def _read_sessions() -> tuple[int, bool]:
	'''
	Count active iSER sessions via kernel configfs target path.

	Returns (count, configfs_present):
		configfs_present=False  — sessions directory absent
		configfs_present=True   — directory exists; count may be zero

	The tpgt_1 path suffix is fixed by LIO for the first TPG created by
	targetcli. If multiple TPGs are configured, adjust the path accordingly.
	'''
	iqn          = ENV['ISCSI_TARGET']
	sessions_dir = Path(f'/sys/kernel/config/target/iscsi/{iqn}/tpgt_1/sessions')
	if not sessions_dir.is_dir():
		return 0, False
	return sum(1 for s in sessions_dir.iterdir() if s.is_dir()), True


def _read_net_bytes() -> tuple[int, int]:
	iface = ENV['IFACE']
	rx = _sysfs_int(Path(f'/sys/class/net/{iface}/statistics/rx_bytes')) or 0
	tx = _sysfs_int(Path(f'/sys/class/net/{iface}/statistics/tx_bytes')) or 0
	return rx, tx


# ---------------------------------------------------------------------------
# Snapshot — pure point-in-time data, no monitoring state
# ---------------------------------------------------------------------------

@dataclass
class Snapshot:
	ts:               float
	rdma:             dict[str, int] = field(default_factory=dict)
	nic:              dict[str, int] = field(default_factory=dict)
	sessions:         int  = 0
	configfs_present: bool = True
	rx_bytes:         int  = 0
	tx_bytes:         int  = 0
	stale:            bool = False


async def take_snapshot(interval: float) -> Snapshot:
	rdma               = _read_rdma_counters([*RDMA_STRICT, *RDMA_RATE])
	sessions, cf_ok    = _read_sessions()
	rx, tx             = _read_net_bytes()
	sub_timeout        = interval * 0.60
	wait_timeout       = interval * 0.85
	try:
		nic = await asyncio.wait_for(
			asyncio.to_thread(_read_ethtool, [*NIC_STRICT, *NIC_RATE], sub_timeout),
			timeout=wait_timeout,
		)
	except asyncio.TimeoutError:
		_log.error('SNAPSHOT_TIMEOUT interval=%.0f', interval)
		raise

	return Snapshot(
		ts               = time.monotonic(),
		rdma             = rdma,
		nic              = nic,
		sessions         = sessions,
		configfs_present = cf_ok,
		rx_bytes         = rx,
		tx_bytes         = tx,
	)


# ---------------------------------------------------------------------------
# HealthWindow — rolling metrics accumulator for HEALTH summary
#
# Intentionally mutable: updated in-place from the main async loop only.
# A new instance is created after each HEALTH emission. See module docstring
# section "HealthWindow mutability" for rationale.
# ---------------------------------------------------------------------------

@dataclass
class HealthWindow:
	'''
	Accumulates per-cycle metrics across health_log_interval seconds.

	cnp_ignored_rates accumulates rp_cnp_ignored/s per cycle. Any average
	above zero means DCQCN is not throttling the sender — status DEGRADED.

	counter_resets counts every COUNTER_RESET event (rdma, nic, net types).
	Both rx_bytes and tx_bytes resets are evaluated independently; a
	simultaneous reset of both increments counter_resets twice.

	The window is replaced after each HEALTH emission; the old instance is
	discarded. All mutation happens only in analyze() on the main async loop.
	'''
	started_at:         float
	rdma_errors:        int         = 0
	nic_drops:          int         = 0
	counter_resets:     int         = 0
	skipped_cycles:     int         = 0
	cnp_rates:          list[float] = field(default_factory=list)
	cnp_ignored_rates:  list[float] = field(default_factory=list)
	pause_rx_rates:     list[float] = field(default_factory=list)
	pause_tx_rates:     list[float] = field(default_factory=list)
	rx_mbps:            list[float] = field(default_factory=list)
	tx_mbps:            list[float] = field(default_factory=list)


def _avg(samples: list[float]) -> float:
	return sum(samples) / len(samples) if samples else 0.0


def _health_status(hw: HealthWindow, sessions: int, daemon_start: float, now: float) -> str:
	'''
	Determine the HEALTH status for the current window.

	CRITICAL conditions (always, regardless of grace period):
		- rdma_errors > 0
		- nic_drops > 0

	CRITICAL after startup_grace_period:
		- sessions == 0

	DEGRADED conditions:
		- cnp_avg_rate > thr_cnp_rate
		- cnp_ignored_avg > 0  (DCQCN ineffective — any ignored CNP is notable)
		- pause_rx/tx_avg > thr_pause_rate
		- counter_resets > 0
		- skipped_cycles > 0
		- sessions == 0 within grace period (daemon just started)

	Note: sessions==0 within grace period raises DEGRADED, not CRITICAL.
	The corresponding NO_SESSIONS granular event is emitted separately on
	the same poll cycle. The Zabbix "iSER fabric — DEGRADED" trigger has
	a declared dependency on "RDMA/NIC rate high or no sessions" so that
	both are visible without double-paging.
	'''
	if hw.rdma_errors > 0 or hw.nic_drops > 0:
		return 'CRITICAL'

	grace_expired = (now - daemon_start) >= STARTUP_GRACE_PERIOD
	if sessions == 0 and grace_expired:
		return 'CRITICAL'

	if (
		_avg(hw.cnp_rates)          > THR_CNP_RATE
		or _avg(hw.cnp_ignored_rates) > 0
		or _avg(hw.pause_rx_rates)  > THR_PAUSE_RATE
		or _avg(hw.pause_tx_rates)  > THR_PAUSE_RATE
		or hw.counter_resets        > 0
		or hw.skipped_cycles        > 0
		or (sessions == 0 and not grace_expired)
	):
		return 'DEGRADED'

	return 'OK'


def _emit_health(hw: HealthWindow, sessions: int, daemon_start: float, now: float) -> None:
	status          = _health_status(hw, sessions, daemon_start, now)
	window_s        = now - hw.started_at
	rx_avg          = _avg(hw.rx_mbps)
	tx_avg          = _avg(hw.tx_mbps)
	cnp_avg         = _avg(hw.cnp_rates)
	cnp_ignored_avg = _avg(hw.cnp_ignored_rates)
	prx_avg         = _avg(hw.pause_rx_rates)
	ptx_avg         = _avg(hw.pause_tx_rates)

	msg = (
		f'HEALTH  status={status:<8} '
		f'sessions={sessions} '
		f'rx_avg_mbps={rx_avg:.2f} '
		f'tx_avg_mbps={tx_avg:.2f} '
		f'cnp_avg_rate={cnp_avg:.1f}/s '
		f'cnp_ignored_avg={cnp_ignored_avg:.1f}/s '
		f'pause_rx_avg={prx_avg:.1f}/s '
		f'pause_tx_avg={ptx_avg:.1f}/s '
		f'rdma_errors={hw.rdma_errors} '
		f'nic_drops={hw.nic_drops} '
		f'counter_resets={hw.counter_resets} '
		f'skipped={hw.skipped_cycles} '
		f'window={window_s:.0f}s'
	)

	if status == 'CRITICAL':
		_log.error(msg)
	elif status == 'DEGRADED':
		_log.warning(msg)
	else:
		_log.info(msg)


# ---------------------------------------------------------------------------
# PollState — monitoring continuity across cycles
# ---------------------------------------------------------------------------

@dataclass
class PollState:
	'''
	All mutable monitoring state. Updated only from the main async loop so
	that no field is ever accessed concurrently with the ethtool thread pool
	worker.

	ethtool_seen tracks whether ethtool has ever returned a non-empty result:
		False  — not yet seen; ETHTOOL_UNAVAILABLE has not been emitted
		True   — at least one successful read; no further action needed
		None   — permanently unavailable; ETHTOOL_UNAVAILABLE already emitted

	daemon_start is set at PollState construction time, which is after the
	bootstrap snapshot is taken. The gap is a few milliseconds and does not
	meaningfully affect startup_grace_period behaviour.
	'''
	daemon_start:         float        = field(default_factory=time.monotonic)
	first_cycle:          bool         = True
	ethtool_seen:         bool | None  = False
	last_throughput_log:  float        = field(default_factory=time.monotonic)
	last_no_sessions_log: float        = field(default_factory=time.monotonic)
	last_configfs_log:    float        = field(default_factory=time.monotonic)
	last_health_log:      float        = field(default_factory=time.monotonic)
	health:               HealthWindow = field(
		default_factory=lambda: HealthWindow(started_at=time.monotonic())
	)


# ---------------------------------------------------------------------------
# ethtool availability check — called from analyze() in the main loop
# ---------------------------------------------------------------------------

def _check_ethtool_availability(nic: dict[str, int], state: PollState) -> PollState:
	'''
	Emit ETHTOOL_UNAVAILABLE once if ethtool has never returned any of the
	expected NIC counters after the first poll cycle completes.

	Called from analyze() (main async loop) after the Snapshot is available,
	so ethtool_seen is read and written only from the main loop — no race
	with the _read_ethtool thread pool worker.

	Transitions:
		False → True   first successful ethtool read
		False → None   first cycle complete, still no data; log once
		True  → True   normal operation; no-op
		None  → None   already logged; no-op
	'''
	if state.ethtool_seen is True or state.ethtool_seen is None:
		return state

	# ethtool_seen is False here
	if nic:
		return dataclasses.replace(state, ethtool_seen=True)

	# nic is empty after first cycle — log once, then silence
	_log.warning(
		'ETHTOOL_UNAVAILABLE iface=%s counters=%s — NIC-layer monitoring inactive',
		ENV['IFACE'],
		','.join([*NIC_STRICT, *NIC_RATE]),
	)
	return dataclasses.replace(state, ethtool_seen=None)


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

def analyze(prev: Snapshot, curr: Snapshot, state: PollState, *, once: bool = False) -> PollState:
	'''
	Compare two snapshots, emit granular log events, accumulate metrics into
	the HEALTH window, and return an updated PollState.

	HealthWindow (state.health) is mutated in place — see module docstring
	"HealthWindow mutability". All other state changes use dataclasses.replace().

	rp_cnp_ignored is treated as a RDMA_RATE counter with threshold 1.0/s.
	Its per-cycle rate is accumulated into hw.cnp_ignored_rates. Any average
	above zero in the window elevates HEALTH to DEGRADED, indicating that
	DCQCN congestion notifications are being received but not acted upon.

	ethtool availability is checked via _check_ethtool_availability() which
	reads and updates state.ethtool_seen. This keeps all access to that flag
	within the main async loop, avoiding any concurrent access with the
	_read_ethtool thread pool worker.

	SESSIONS_RESTORED is suppressed on first_cycle. See PollState docstring
	and module-level docstring for rationale.

	COUNTER_RESET for rx_bytes and tx_bytes are evaluated with independent
	if-blocks. A simultaneous reset of both increments counter_resets twice.

	When prev is stale:
		- RDMA/NIC counter deltas, rates, and throughput are skipped.
		- Session transitions and CONFIGFS_MISSING are still evaluated.
		- health.skipped_cycles is incremented.
	'''
	dt  = curr.ts - prev.ts
	now = curr.ts
	if dt <= 0:
		return state

	# hw is mutated in place throughout this function.
	# It is replaced with a fresh HealthWindow only at HEALTH emission.
	hw = state.health

	# -------------------------------------------------------------------
	# Per-cycle analysis (skipped when prev is stale)
	# -------------------------------------------------------------------
	if not prev.stale:

		# RDMA strict — any positive delta is an error
		for counter in RDMA_STRICT:
			pv = prev.rdma.get(counter)
			cv = curr.rdma.get(counter)
			if pv is None or cv is None:
				continue
			delta = cv - pv
			if delta < 0:
				_log.warning('COUNTER_RESET type=rdma name=%s prev=%d curr=%d', counter, pv, cv)
				hw.counter_resets += 1
			elif delta > 0:
				_log.error('RDMA_ERROR counter=%s delta=%d total=%d', counter, delta, cv)
				hw.rdma_errors += delta

		# RDMA rate — warn when rate exceeds threshold, accumulate for HEALTH.
		# np_cnp_sent    → cnp_rates          (CNP generation rate)
		# rp_cnp_ignored → cnp_ignored_rates  (DCQCN effectiveness)
		for counter, thr in RDMA_RATE.items():
			pv = prev.rdma.get(counter)
			cv = curr.rdma.get(counter)
			if pv is None or cv is None:
				continue
			delta = cv - pv
			if delta < 0:
				_log.warning('COUNTER_RESET type=rdma name=%s prev=%d curr=%d', counter, pv, cv)
				hw.counter_resets += 1
				continue
			rate = delta / dt
			if counter == 'np_cnp_sent':
				hw.cnp_rates.append(rate)
			elif counter == 'rp_cnp_ignored':
				hw.cnp_ignored_rates.append(rate)
			if rate > thr:
				_log.warning(
					'RDMA_RATE_HIGH counter=%s rate=%.1f/s threshold=%.1f/s',
					counter, rate, thr,
				)

		# NIC strict — any positive delta is an error
		for stat in NIC_STRICT:
			pv = prev.nic.get(stat)
			cv = curr.nic.get(stat)
			if pv is None or cv is None:
				continue
			delta = cv - pv
			if delta < 0:
				_log.warning('COUNTER_RESET type=nic name=%s prev=%d curr=%d', stat, pv, cv)
				hw.counter_resets += 1
			elif delta > 0:
				_log.error('NIC_DROP stat=%s delta=%d total=%d', stat, delta, cv)
				hw.nic_drops += delta

		# NIC rate — warn and accumulate for HEALTH
		for stat, thr in NIC_RATE.items():
			pv = prev.nic.get(stat)
			cv = curr.nic.get(stat)
			if pv is None or cv is None:
				continue
			delta = cv - pv
			if delta < 0:
				_log.warning('COUNTER_RESET type=nic name=%s prev=%d curr=%d', stat, pv, cv)
				hw.counter_resets += 1
				continue
			rate = delta / dt
			if stat == 'rx_pause_ctrl_phy':
				hw.pause_rx_rates.append(rate)
			elif stat == 'tx_pause_ctrl_phy':
				hw.pause_tx_rates.append(rate)
			if rate > thr:
				_log.warning(
					'NIC_RATE_HIGH stat=%s rate=%.1f/s threshold=%.1f/s',
					stat, rate, thr,
				)

		# Throughput — rx and tx evaluated with independent if-blocks so that
		# a simultaneous reset of both is fully logged and counted.
		rx_delta = curr.rx_bytes - prev.rx_bytes
		tx_delta = curr.tx_bytes - prev.tx_bytes

		rx_reset = rx_delta < 0
		tx_reset = tx_delta < 0

		if rx_reset:
			_log.warning(
				'COUNTER_RESET type=net name=rx_bytes prev=%d curr=%d',
				prev.rx_bytes, curr.rx_bytes,
			)
			hw.counter_resets += 1

		if tx_reset:
			_log.warning(
				'COUNTER_RESET type=net name=tx_bytes prev=%d curr=%d',
				prev.tx_bytes, curr.tx_bytes,
			)
			hw.counter_resets += 1

		if not rx_reset and not tx_reset:
			rx_mbps = rx_delta / dt / 1e6
			tx_mbps = tx_delta / dt / 1e6
			hw.rx_mbps.append(rx_mbps)
			hw.tx_mbps.append(tx_mbps)

			should_log_tp = once or (
				(curr.sessions > 0 or (rx_mbps + tx_mbps) >= THR_THROUGHPUT_MBPS)
				and (now - state.last_throughput_log) >= THROUGHPUT_LOG_INTERVAL
			)
			if should_log_tp:
				_log.info(
					'THROUGHPUT rx_mbps=%.2f tx_mbps=%.2f sessions=%d',
					rx_mbps, tx_mbps, curr.sessions,
				)
				state = dataclasses.replace(state, last_throughput_log=now)

		# ethtool availability — checked once after first non-stale cycle.
		# Reads and updates state.ethtool_seen in the main loop only.
		state = _check_ethtool_availability(curr.nic, state)

	else:
		_log.warning('SKIPPED_ANALYSIS reason=prev_stale')
		hw.skipped_cycles += 1

	# -------------------------------------------------------------------
	# Session transitions — evaluated regardless of stale
	# -------------------------------------------------------------------
	if not curr.configfs_present:
		if (now - state.last_configfs_log) >= NO_SESSIONS_RELOG_INTERVAL:
			_log.warning(
				'CONFIGFS_MISSING path=/sys/kernel/config/target/iscsi/%s/tpgt_1/sessions',
				ENV['ISCSI_TARGET'],
			)
			state = dataclasses.replace(state, last_configfs_log=now)
	elif curr.sessions == 0:
		if prev.sessions > 0:
			_log.warning('NO_SESSIONS active=0')
			state = dataclasses.replace(state, last_no_sessions_log=now)
		elif (now - state.last_no_sessions_log) >= NO_SESSIONS_RELOG_INTERVAL:
			_log.warning('NO_SESSIONS active=0')
			state = dataclasses.replace(state, last_no_sessions_log=now)
	elif curr.sessions > 0 and prev.sessions == 0 and not state.first_cycle:
		# Suppressed on first_cycle: prev is the bootstrap snapshot taken
		# before PollState was initialised. A 0→N transition there is not a
		# real reconnect event — the session was already active when the daemon
		# started. See module docstring for full rationale.
		_log.warning('SESSIONS_RESTORED active=%d', curr.sessions)
		state = dataclasses.replace(
			state,
			last_no_sessions_log=now - NO_SESSIONS_RELOG_INTERVAL,
			last_configfs_log=now - NO_SESSIONS_RELOG_INTERVAL,
		)

	# -------------------------------------------------------------------
	# HEALTH summary — emit when window is full, then reset
	# -------------------------------------------------------------------
	should_health = once or (now - state.last_health_log) >= HEALTH_LOG_INTERVAL
	if should_health:
		_emit_health(hw, curr.sessions, state.daemon_start, now)
		state = dataclasses.replace(
			state,
			last_health_log=now,
			health=HealthWindow(started_at=now),
		)

	return dataclasses.replace(state, first_cycle=False)


# ---------------------------------------------------------------------------
# Poll loop
# ---------------------------------------------------------------------------

async def poll_loop(once: bool, interval: float) -> None:
	loop = asyncio.get_running_loop()
	stop = asyncio.Event()
	for sig in (signal.SIGTERM, signal.SIGINT):
		loop.add_signal_handler(sig, stop.set)

	_log.info('START iface=%s interval=%.0fs', ENV['IFACE'], interval)
	prev  = await take_snapshot(interval)
	state = PollState()

	if once:
		try:
			await asyncio.sleep(interval)
			curr  = await take_snapshot(interval)
			state = analyze(prev, curr, state, once=True)
		except asyncio.CancelledError:
			pass
		except asyncio.TimeoutError:
			_log.error('SNAPSHOT_TIMEOUT_ONCE interval=%.0f', interval)
		_log.info('STOPPED once=true')
		logging.shutdown()
		return

	next_deadline = loop.time() + interval

	while not stop.is_set():
		remaining = next_deadline - loop.time()
		if remaining > 0:
			try:
				await asyncio.wait_for(stop.wait(), timeout=remaining)
				break
			except asyncio.TimeoutError:
				pass

		next_deadline += interval

		try:
			curr  = await take_snapshot(interval)
			state = analyze(prev, curr, state)
			prev  = curr
		except asyncio.TimeoutError:
			prev          = dataclasses.replace(prev, stale=True)
			next_deadline = loop.time() + interval
		except Exception as e:
			_log.exception('POLL_ERROR error=%s', e)

	_log.info('STOPPED')
	logging.shutdown()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

@click.command()
@click.option('--once',     is_flag=True, default=False, help='Single poll cycle then exit (debug).')
@click.option('--interval', default=None, type=float,    help='Override POLL_INTERVAL from env.json.')
def cli(once: bool, interval: float | None) -> None:
	effective = interval if interval is not None else POLL_INTERVAL
	if effective < 4:
		raise click.BadParameter(
			f'got {effective} — must be >= 4s so that ethtool sub_timeout '
			f'(interval*0.6) and wait_timeout (interval*0.85) have sufficient separation.',
			param_hint='--interval / POLL_INTERVAL',
		)
	asyncio.run(
		poll_loop(once=once, interval=effective),
		loop_factory=uvloop.new_event_loop,
	)


if __name__ == '__main__':
	cli()