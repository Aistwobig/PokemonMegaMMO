import { config } from "../config.ts";

// Sliding-window limiter, in memory. Fine for one process; moves to Redis with the transfer tickets.

export class RateLimiter {
  private hits = new Map<string, number[]>();

  constructor(private max: number, private windowMs: number, private enabled = config.authRateLimits) {
    setInterval(() => this.prune(), windowMs).unref();
  }

  /** Records an attempt for key. Returns false if the key is over the limit. */
  allow(key: string): boolean {
    if (this.isLimited(key)) return false;
    this.record(key);
    return true;
  }

  /** True if key is at the limit, without counting this check as an attempt. */
  isLimited(key: string): boolean {
    return this.enabled && this.recent(key).length >= this.max;
  }

  record(key: string): void {
    const recent = this.recent(key);
    recent.push(Date.now());
    this.hits.set(key, recent);
  }

  private recent(key: string): number[] {
    const now = Date.now();
    return (this.hits.get(key) ?? []).filter((t) => now - t < this.windowMs);
  }

  private prune() {
    const now = Date.now();
    for (const [key, times] of this.hits) {
      if (times.every((t) => now - t >= this.windowMs)) this.hits.delete(key);
    }
  }
}
