/**
 * The Cloudflare Worker entry of the feedback relay.
 *
 * Every destination secret lives in the Worker settings. The app ships only a
 * relay URL, a public product id, and a tester token. See
 * `docs/OPERATOR_RUNBOOK.md` for provisioning.
 */

import { GitHubBacklog } from './backlog.ts';
import { readDestinations } from './destinations.ts';
import { DisabledImageHost, ImgbbImageHost } from './images.ts';
import { createRelay } from './relay.ts';
import { KvDeliveryStore, KvRateLimiter, type KeyValueStore } from './store.ts';

/** The Worker settings. */
export interface Env {
  FEEDBACK_STORE: KeyValueStore;
  [key: string]: unknown;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    let relay;
    try {
      const settings: Record<string, string | undefined> = {};
      for (const [key, value] of Object.entries(env)) {
        settings[key] = typeof value === 'string' ? value : undefined;
      }
      relay = createRelay({
        destinations: readDestinations(settings),
        backlog: new GitHubBacklog(),
        imgbb: new ImgbbImageHost(),
        disabledImages: new DisabledImageHost(),
        store: new KvDeliveryStore(env.FEEDBACK_STORE),
        limiter: new KvRateLimiter(env.FEEDBACK_STORE),
        log: (event, fields) => console.log(JSON.stringify({ event, ...fields })),
      });
    } catch {
      // A broken destination setting must not serve reports.
      return new Response(JSON.stringify({ ok: false, error: 'Relay configuration error.' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    return relay(request);
  },
};
