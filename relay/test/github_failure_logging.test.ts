import assert from 'node:assert/strict';
import { test } from 'node:test';

import { GitHubBacklog } from '../src/backlog.ts';
import { MapDestinations, sha256Hex, type ProductBundle } from '../src/destinations.ts';
import { DisabledImageHost } from '../src/images.ts';
import { createRelay } from '../src/relay.ts';
import { MemoryDeliveryStore, MemoryRateLimiter, type DeliveryRecord } from '../src/store.ts';

const token = 'local-test-token';
const githubToken = 'local-github-token';
const reportId = '11111111-2222-4333-8444-555555555555';

async function makeRelay(fetchImpl: typeof fetch, store = new MemoryDeliveryStore()) {
  const bundle: ProductBundle = {
    product_id: 'ohridskiprolog2',
    github_repo: 'zarkob/ohridskiprolog2',
    github_token: githubToken,
    testers: [{ name: 'tester', token_sha256: await sha256Hex(token) }],
  };
  const logs: Array<{ event: string; fields: Record<string, string> }> = [];
  const relay = createRelay({
    destinations: new MapDestinations([bundle]),
    backlog: new GitHubBacklog(fetchImpl),
    imgbb: new DisabledImageHost(),
    disabledImages: new DisabledImageHost(),
    store,
    limiter: new MemoryRateLimiter(100, 60),
    log: (event, fields) => logs.push({ event, fields }),
  });
  const request = new Request('https://relay.test/reports', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Tester-Token': token },
    body: JSON.stringify({
      schema: 'avensora-report/1',
      report_id: reportId,
      created_at: '2026-10-07T10:00:00.000Z',
      text: 'A test report.',
      expected: '',
      steps: '',
      screenshot_b64: null,
      context: {
        product_id: 'ohridskiprolog2',
        app_version: '1.2.4',
        build_number: '77',
        build_mode: 'test',
        screen: 'test',
        source_revision: 'Unknown',
        captured_at: '2026-10-07T10:00:00.000Z',
        device: { model: 'Unknown', platform: 'test', os_version: 'Unknown', locale: 'en' },
      },
    }),
  });
  return { relay, request, store, logs };
}

test('a failed GitHub search keeps the report unknown and does not create an issue', async () => {
  let calls = 0;
  const { relay, request, store, logs } = await makeRelay(async () => {
    calls += 1;
    return new Response('private response body', { status: 422 });
  });

  const response = await relay(request);
  const body = (await response.json()) as Record<string, unknown>;

  assert.equal(response.status, 502);
  assert.equal(body.delivery, 'unknown');
  assert.equal(calls, 1);
  assert.equal(store.all()[0].status, 'preflight_unknown');
  assert.deepEqual(logs[0], {
    event: 'github_search_failed',
    fields: { product: 'ohridskiprolog2', report: reportId, http_status: '422' },
  });
  assert.doesNotMatch(JSON.stringify(logs), /private response body|Authorization|local-github-token/);
});

test('a GitHub create failure logs only its safe status', async () => {
  const { relay, request, logs } = await makeRelay(async (input, init) => {
    if (init?.method === 'POST') {
      return new Response('private response body', { status: 403 });
    }
    assert.match(String(input), /is%3Aissue/);
    return new Response(JSON.stringify({ items: [] }), { status: 200 });
  });

  const response = await relay(request);
  assert.equal(response.status, 502);
  assert.deepEqual(logs.find((item) => item.event === 'github_create_failed'), {
    event: 'github_create_failed',
    fields: { product: 'ohridskiprolog2', report: reportId, http_status: '403' },
  });
  assert.doesNotMatch(JSON.stringify(logs), /private response body|Authorization|local-github-token/);
});

test('a final delivery-store failure is logged apart from GitHub failure', async () => {
  class FailingCreatedStore extends MemoryDeliveryStore {
    override async put(record: DeliveryRecord): Promise<void> {
      if (record.status === 'created') {
        throw new Error('private store failure');
      }
      await super.put(record);
    }
  }

  const store = new FailingCreatedStore();
  const { relay, request, logs } = await makeRelay(async (_input, init) => init?.method === 'POST'
    ? new Response(JSON.stringify({ html_url: 'https://github.com/zarkob/ohridskiprolog2/issues/30' }), { status: 201 })
    : new Response(JSON.stringify({ items: [] }), { status: 200 }), store);

  const response = await relay(request);
  const body = (await response.json()) as Record<string, unknown>;

  assert.equal(response.status, 502);
  assert.equal(body.delivery, 'unknown');
  assert.equal(logs.some((item) => item.event === 'github_create_failed'), false);
  assert.deepEqual(logs.find((item) => item.event === 'delivery_store_failed'), {
    event: 'delivery_store_failed',
    fields: { product: 'ohridskiprolog2', report: reportId, stage: 'after_create' },
  });
  assert.doesNotMatch(JSON.stringify(logs), /private store failure|local-github-token/);
});
