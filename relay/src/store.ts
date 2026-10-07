/**
 * Delivery records and the rate limit.
 *
 * A delivery record answers one question: does the relay know what happened to
 * this report id? `created` is used only after the destination confirmed it.
 * Every other state keeps the app honest.
 */

/** The state of one report at the relay. */
export type DeliveryStatus = 'pending' | 'preflight_unknown' | 'created' | 'unknown' | 'failed';

/** What the relay knows about one report id. */
export interface DeliveryRecord {
  report_id: string;
  product_id: string;
  status: DeliveryStatus;
  issue_url?: string;
  note?: string;
  updated_at: string;
}

/** Keeps the delivery record of each report id. */
export interface DeliveryStore {
  get(reportId: string): Promise<DeliveryRecord | null>;
  /** Claims a report id. Returns false when a record already exists. */
  claim(record: DeliveryRecord): Promise<boolean>;
  /** Writes the current record of a claimed report id. */
  put(record: DeliveryRecord): Promise<void>;
}

/** A minimal key value store shape, as Cloudflare KV provides it. */
export interface KeyValueStore {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

const RECORD_PREFIX = 'report:';

/** Delivery records in Cloudflare KV. */
export class KvDeliveryStore implements DeliveryStore {
  private readonly kv: KeyValueStore;

  constructor(kv: KeyValueStore) {
    this.kv = kv;
  }

  async get(reportId: string): Promise<DeliveryRecord | null> {
    const raw = await this.kv.get(recordKey(reportId));
    if (!raw) {
      return null;
    }
    try {
      return JSON.parse(raw) as DeliveryRecord;
    } catch {
      return null;
    }
  }

  async claim(record: DeliveryRecord): Promise<boolean> {
    // KV cannot compare and swap. The relay also searches the backlog before
    // it creates an issue, so a lost claim cannot create a second issue in one
    // product. The read-then-write window stays small.
    const existing = await this.get(record.report_id);
    if (existing) {
      return false;
    }
    await this.put(record);
    return true;
  }

  async put(record: DeliveryRecord): Promise<void> {
    await this.kv.put(recordKey(record.report_id), JSON.stringify(record), { expirationTtl: 60 * 60 * 24 * 30 });
  }
}

/** Delivery records in memory. Used by tests and the local server. */
export class MemoryDeliveryStore implements DeliveryStore {
  private readonly records = new Map<string, DeliveryRecord>();

  async get(reportId: string): Promise<DeliveryRecord | null> {
    return this.records.get(reportId) ?? null;
  }

  async claim(record: DeliveryRecord): Promise<boolean> {
    if (this.records.has(record.report_id)) {
      return false;
    }
    this.records.set(record.report_id, record);
    return true;
  }

  async put(record: DeliveryRecord): Promise<void> {
    this.records.set(record.report_id, record);
  }

  /** Every record, for tests that read the final state. */
  all(): DeliveryRecord[] {
    return [...this.records.values()];
  }
}

/** A small fixed window rate limit. */
export interface RateLimiter {
  /** Counts one request under [key]. Returns false when the window is full. */
  allow(key: string): Promise<boolean>;
}

/** A rate limit that keeps counters in memory. */
export class MemoryRateLimiter implements RateLimiter {
  private readonly counters = new Map<string, { count: number; resetAt: number }>();
  private readonly max: number;
  private readonly windowSeconds: number;
  private readonly now: () => number;

  constructor(max = 10, windowSeconds = 60, now: () => number = () => Date.now()) {
    this.max = max;
    this.windowSeconds = windowSeconds;
    this.now = now;
  }

  async allow(key: string): Promise<boolean> {
    const now = this.now();
    const current = this.counters.get(key);
    if (!current || current.resetAt <= now) {
      this.counters.set(key, { count: 1, resetAt: now + this.windowSeconds * 1000 });
      return true;
    }
    if (current.count >= this.max) {
      return false;
    }
    current.count += 1;
    return true;
  }
}

/** A rate limit that keeps counters in Cloudflare KV. */
export class KvRateLimiter implements RateLimiter {
  private readonly kv: KeyValueStore;
  private readonly max: number;
  private readonly windowSeconds: number;

  constructor(kv: KeyValueStore, max = 10, windowSeconds = 60) {
    this.kv = kv;
    this.max = max;
    this.windowSeconds = windowSeconds;
  }

  async allow(key: string): Promise<boolean> {
    const name = `rate:${key}`;
    const raw = await this.kv.get(name);
    const count = raw ? Number.parseInt(raw, 10) : 0;
    if (count >= this.max) {
      return false;
    }
    await this.kv.put(name, String(count + 1), { expirationTtl: this.windowSeconds });
    return true;
  }
}

function recordKey(reportId: string): string {
  return `${RECORD_PREFIX}${reportId}`;
}
