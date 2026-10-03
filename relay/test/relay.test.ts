/**
 * Local checks for the relay. Every external service is a fake in memory.
 * No issue is filed and no image is uploaded to a real service.
 */

import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { MapDestinations, sha256Hex, type ProductBundle } from '../src/destinations.ts';
import { DisabledImageHost } from '../src/images.ts';
import { createRelay } from '../src/relay.ts';
import { MemoryDeliveryStore, MemoryRateLimiter } from '../src/store.ts';
import { FakeBacklog, FakeImageHost } from '../src/local_server.ts';

const TESTER_TOKEN = 'tester-token-value';
const IMAGE_KEY = 'image-key-value';
const GITHUB_TOKEN = 'gh-token-value';

interface Harness {
  relay: (request: Request) => Promise<Response>;
  backlog: FakeBacklog;
  images: FakeImageHost;
  store: MemoryDeliveryStore;
}

async function harness(options: { imageHost?: boolean; rateLimit?: number } = {}): Promise<Harness> {
  const bundle: ProductBundle = {
    product_id: 'alpha-notes',
    github_repo: 'example/alpha-notes',
    github_token: GITHUB_TOKEN,
    testers: [{ name: 'zarko', token_sha256: await sha256Hex(TESTER_TOKEN) }],
  };
  if (options.imageHost !== false) {
    bundle.image_api_key = IMAGE_KEY;
  }
  const backlog = new FakeBacklog();
  const images = new FakeImageHost();
  const store = new MemoryDeliveryStore();
  const relay = createRelay({
    destinations: new MapDestinations([bundle]),
    backlog,
    store,
    imgbb: images,
    disabledImages: new DisabledImageHost(),
    limiter: new MemoryRateLimiter(options.rateLimit ?? 1000, 60),
  });
  return { relay, backlog, images, store };
}

function reportBody(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    schema: 'avensora-report/1',
    report_id: '11111111-2222-4333-8444-555555555555',
    created_at: '2026-10-03T10:00:00.000Z',
    text: 'The list is empty after a restart.',
    expected: 'The saved items stay visible.',
    steps: '1. Add one item\n2. Restart the app',
    screenshot_b64: null,
    context: {
      product_id: 'alpha-notes',
      app_version: '1.2.4',
      build_number: '77',
      build_mode: 'test',
      screen: 'notes_list',
      source_revision: 'Unknown',
      captured_at: '2026-10-03T10:00:00.000Z',
      device: { model: 'Pixel 7', platform: 'android', os_version: 'Android 15', locale: 'en_US' },
    },
    ...overrides,
  };
}

function post(body: unknown, token: string | null = TESTER_TOKEN): Request {
  const headers = new Headers({ 'Content-Type': 'application/json' });
  if (token) {
    headers.set('X-Tester-Token', token);
  }
  return new Request('https://relay.test/reports', { method: 'POST', headers, body: JSON.stringify(body) });
}

function check(reportId: string, token: string | null = TESTER_TOKEN): Request {
  const headers = new Headers();
  if (token) {
    headers.set('X-Tester-Token', token);
  }
  return new Request(`https://relay.test/reports/${reportId}`, { method: 'GET', headers });
}

describe('destination limits', () => {
  test('an unknown product is refused and files nothing', async () => {
    const { relay, backlog } = await harness();
    const body = reportBody();
    (body.context as Record<string, unknown>).product_id = 'other-product';

    const response = await relay(post(body));

    assert.equal(response.status, 404);
    assert.equal(backlog.createCalls, 0);
    assert.match(await response.text(), /Unknown product/);
  });

  test('the app cannot name a repository', async () => {
    const { relay, backlog } = await harness();
    const body = reportBody({ github_repo: 'attacker/repo' });

    const response = await relay(post(body));

    assert.equal(response.status, 400);
    assert.match(await response.text(), /Unknown report field .*github_repo/);
    assert.equal(backlog.createCalls, 0);
  });

  test('the app cannot name a web address or a label', async () => {
    const { relay } = await harness();
    for (const extra of [{ labels: ['bug'] }, { issue_url: 'https://evil.test' }, { image_url: 'https://evil.test/a.png' }]) {
      const response = await relay(post(reportBody(extra)));
      assert.equal(response.status, 400);
    }
  });

  test('the app cannot add fields to the report context or the device facts', async () => {
    const { relay } = await harness();
    const context = reportBody().context as Record<string, unknown>;
    context.repository = 'attacker/repo';
    assert.equal((await relay(post(reportBody({ context })))).status, 400);

    const clean = reportBody().context as Record<string, unknown>;
    (clean.device as Record<string, unknown>).serial = 'ABC123';
    assert.equal((await relay(post(reportBody({ context: clean })))).status, 400);
  });

  test('the issue goes to the destination of the server settings', async () => {
    const { relay, backlog } = await harness();

    await relay(post(reportBody({ screenshot_b64: 'AA==' })));

    assert.equal(backlog.issues.length, 1);
    assert.match(backlog.issues[0].body, /avensora-report-id: 11111111-2222-4333-8444-555555555555/);
  });
});

describe('tester access', () => {
  test('a missing token is refused', async () => {
    const { relay, backlog } = await harness();
    const response = await relay(post(reportBody(), null));
    assert.equal(response.status, 403);
    assert.equal(backlog.createCalls, 0);
  });

  test('a wrong token is refused', async () => {
    const { relay, backlog } = await harness();
    const response = await relay(post(reportBody(), 'wrong-token'));
    assert.equal(response.status, 403);
    assert.match(await response.text(), /Tester access denied/);
    assert.equal(backlog.createCalls, 0);
  });

  test('the product id alone does not grant access', async () => {
    const { relay } = await harness();
    const response = await relay(post(reportBody(), null));
    assert.equal(response.status, 403);
  });

  test('the right token is accepted', async () => {
    const { relay, backlog } = await harness();
    const response = await relay(post(reportBody()));
    assert.equal(response.status, 201);
    assert.equal(backlog.createCalls, 1);
  });

  test('a tester token of another product cannot read a report', async () => {
    const other = await sha256Hex('other-product-token');
    const bundle: ProductBundle = {
      product_id: 'beta-tracker',
      github_repo: 'example/beta-tracker',
      github_token: GITHUB_TOKEN,
      testers: [{ name: 'beta-tester', token_sha256: other }],
    };
    const backlog = new FakeBacklog();
    const images = new FakeImageHost();
    const store = new MemoryDeliveryStore();
    const alpha: ProductBundle = {
      product_id: 'alpha-notes',
      github_repo: 'example/alpha-notes',
      github_token: GITHUB_TOKEN,
      testers: [{ name: 'zarko', token_sha256: await sha256Hex(TESTER_TOKEN) }],
    };
    const relay = createRelay({
      destinations: new MapDestinations([alpha, bundle]),
      backlog,
      store,
      imgbb: images,
      disabledImages: images,
      limiter: new MemoryRateLimiter(1000, 60),
    });

    await relay(post(reportBody()));
    const crossed = await relay(check('11111111-2222-4333-8444-555555555555', 'other-product-token'));

    assert.equal(crossed.status, 403);
    const own = await relay(check('11111111-2222-4333-8444-555555555555'));
    assert.equal(own.status, 200);
  });

  test('a delivery check without a valid token is refused', async () => {
    const { relay } = await harness();

    const withoutToken = await relay(check('99999999-0000-4000-8000-000000000000', null));
    const wrongToken = await relay(check('99999999-0000-4000-8000-000000000000', 'wrong-token'));

    assert.equal(withoutToken.status, 403);
    assert.equal(wrongToken.status, 403);
  });

  test('a report id of another product is refused', async () => {
    const other = await sha256Hex('other-product-token');
    const alpha: ProductBundle = {
      product_id: 'alpha-notes',
      github_repo: 'example/alpha-notes',
      github_token: GITHUB_TOKEN,
      testers: [{ name: 'zarko', token_sha256: await sha256Hex(TESTER_TOKEN) }],
    };
    const beta: ProductBundle = {
      product_id: 'beta-tracker',
      github_repo: 'example/beta-tracker',
      github_token: GITHUB_TOKEN,
      testers: [{ name: 'beta-tester', token_sha256: other }],
    };
    const backlog = new FakeBacklog();
    const images = new FakeImageHost();
    const relay = createRelay({
      destinations: new MapDestinations([alpha, beta]),
      backlog,
      store: new MemoryDeliveryStore(),
      imgbb: images,
      disabledImages: new DisabledImageHost(),
      limiter: new MemoryRateLimiter(1000, 60),
    });

    await relay(post(reportBody()));
    const otherProduct = reportBody();
    (otherProduct.context as Record<string, unknown>).product_id = 'beta-tracker';
    const response = await relay(post(otherProduct, 'other-product-token'));

    assert.equal(response.status, 409);
    assert.match(await response.text(), /belongs to another product/);
    assert.equal(backlog.issues.length, 1);
  });

  test('a product without a tester entry is refused at setup', async () => {
    const destinations = new MapDestinations([]);
    assert.throws(
      () =>
        destinations.add({
          product_id: 'no-testers',
          github_repo: 'example/no-testers',
          github_token: GITHUB_TOKEN,
          testers: [],
        }),
      /at least one tester/,
    );
  });
});

describe('delivery results', () => {
  test('a confirmed report is created once with its issue link', async () => {
    const { relay, backlog, store } = await harness();

    const response = await relay(post(reportBody({ screenshot_b64: 'AA==' })));
    const body = (await response.json()) as Record<string, unknown>;

    assert.equal(response.status, 201);
    assert.equal(body.ok, true);
    assert.equal(body.status, 'created');
    assert.equal(body.issue_url, backlog.issues[0].url);
    assert.deepEqual(
      store.all().map((record) => record.status),
      ['created'],
    );
    assert.equal(backlog.issues.length, 1);
    assert.equal(body.note, undefined);
  });

  test('a repeat of the same report id does not file a second issue', async () => {
    const { relay, backlog } = await harness();

    const first = await relay(post(reportBody()));
    const second = await relay(post(reportBody()));
    const firstBody = (await first.json()) as Record<string, unknown>;
    const secondBody = (await second.json()) as Record<string, unknown>;

    assert.equal(firstBody.status, 'created');
    assert.equal(secondBody.status, 'duplicate');
    assert.equal(secondBody.issue_url, firstBody.issue_url);
    assert.equal(backlog.createCalls, 1);
  });

  test('two sends of the same report at once file one issue', async () => {
    const { relay, backlog } = await harness();

    const [a, b] = await Promise.all([relay(post(reportBody())), relay(post(reportBody()))]);
    const bodies = [(await a.json()) as Record<string, unknown>, (await b.json()) as Record<string, unknown>];

    assert.equal(backlog.issues.length, 1);
    const urls = new Set(bodies.map((body) => body.issue_url ?? 'none'));
    assert.equal(urls.size, 1);
    assert.ok(bodies.some((body) => body.status === 'created'));
  });

  test('an image failure is a proven failure, so a retry is safe', async () => {
    const { relay, backlog, images, store } = await harness();
    images.mode = 'error';

    const response = await relay(post(reportBody({ screenshot_b64: 'AA==' })));
    const body = (await response.json()) as Record<string, unknown>;

    assert.equal(response.status, 502);
    assert.equal(body.delivery, 'failed');
    assert.equal(backlog.createCalls, 0);
    assert.equal(store.all()[0].status, 'failed');

    images.mode = 'ok';
    const retry = await relay(post(reportBody({ screenshot_b64: 'AA==' })));
    assert.equal(retry.status, 201);
    assert.equal(backlog.issues.length, 1);
  });

  test('a product without an image host still files the report and says so', async () => {
    const { relay, backlog } = await harness({ imageHost: false });

    const response = await relay(post(reportBody({ screenshot_b64: 'AA==' })));
    const body = (await response.json()) as Record<string, unknown>;

    assert.equal(response.status, 201);
    assert.match(String(body.note), /no image host/);
    assert.match(backlog.issues[0].body, /_No image was attached\._/);
  });

  test('an unknown issue result stays unknown and keeps the app out of a blind retry', async () => {
    const { relay, backlog, store } = await harness();
    backlog.createMode = 'error';
    backlog.searchMode = 'error';

    const response = await relay(post(reportBody()));
    const body = (await response.json()) as Record<string, unknown>;

    assert.equal(response.status, 502);
    assert.equal(body.delivery, 'unknown');
    assert.equal(store.all()[0].status, 'unknown');

    const again = await relay(post(reportBody()));
    const againBody = (await again.json()) as Record<string, unknown>;
    assert.equal(againBody.status, 'unknown');
    assert.equal(backlog.createCalls, 1);
  });

  test('a lost answer is recovered by the report marker', async () => {
    const { relay, backlog, store } = await harness();
    // The issue is filed, the answer is lost, and the search cannot help yet.
    backlog.createMode = 'create_then_error';
    backlog.searchMode = 'error';

    const response = await relay(post(reportBody()));
    const body = (await response.json()) as Record<string, unknown>;
    assert.equal(response.status, 502);
    assert.equal(body.delivery, 'unknown');
    assert.equal(backlog.issues.length, 1);

    backlog.createMode = 'ok';
    backlog.searchMode = 'ok';
    const recovered = await relay(check('11111111-2222-4333-8444-555555555555'));
    const recoveredBody = (await recovered.json()) as Record<string, unknown>;

    assert.equal(recoveredBody.status, 'created');
    assert.equal(recoveredBody.issue_url, backlog.issues[0].url);
    assert.equal(store.all()[0].status, 'created');

    const afterRecovery = await relay(post(reportBody()));
    assert.equal(((await afterRecovery.json()) as Record<string, unknown>).status, 'duplicate');
    assert.equal(backlog.issues.length, 1);
  });

  test('a late search index keeps the state unknown instead of filing twice', async () => {
    const { relay, backlog } = await harness();
    backlog.createMode = 'create_then_error';
    backlog.searchMode = 'lagging';
    const first = await relay(post(reportBody()));
    assert.equal(first.status, 502);
    assert.equal(((await first.json()) as Record<string, unknown>).delivery, 'unknown');

    backlog.createMode = 'ok';
    const checked = await relay(check('11111111-2222-4333-8444-555555555555'));
    const body = (await checked.json()) as Record<string, unknown>;

    assert.equal(body.status, 'unknown');

    const again = await relay(post(reportBody()));
    assert.equal(((await again.json()) as Record<string, unknown>).status, 'unknown');
    assert.equal(backlog.issues.length, 1);
  });

  test('a check of an unknown report id says not found, so a send is safe', async () => {
    const { relay } = await harness();
    const response = await relay(check('99999999-0000-4000-8000-000000000000'));
    assert.equal(response.status, 200);
    assert.equal(((await response.json()) as Record<string, unknown>).status, 'not_found');
  });

  test('a proven failure lets a later send create the issue', async () => {
    const { relay, backlog, images } = await harness();
    images.mode = 'error';
    await relay(post(reportBody({ screenshot_b64: 'AA==' })));

    images.mode = 'ok';
    const response = await relay(post(reportBody({ screenshot_b64: 'AA==' })));

    assert.equal(response.status, 201);
    assert.equal(backlog.issues.length, 1);
  });
});

describe('request limits and secret handling', () => {
  test('a text-only report is accepted', async () => {
    const { relay, backlog } = await harness();

    const response = await relay(post(reportBody()));

    assert.equal(response.status, 201);
    assert.match(backlog.issues[0].body, /_No image was attached\._/);
  });

  test('an oversized image is refused before any call', async () => {
    const { relay, backlog, images } = await harness();

    const response = await relay(post(reportBody({ screenshot_b64: 'A'.repeat(6 * 1024 * 1024) })));

    assert.equal(response.status, 400);
    assert.match(await response.text(), /too large/);
    assert.equal(backlog.createCalls, 0);
    assert.equal(images.uploads.length, 0);
  });

  test('a long text and a wrong schema are refused', async () => {
    const { relay } = await harness();
    assert.equal((await relay(post(reportBody({ text: 'a'.repeat(10_001) })))).status, 400);
    assert.equal((await relay(post(reportBody({ schema: 'other/2' })))).status, 400);
  });

  test('a broken image text is refused', async () => {
    const { relay } = await harness();
    assert.equal((await relay(post(reportBody({ screenshot_b64: 'not base64 !!' })))).status, 400);
  });

  test('no answer carries a server secret', async () => {
    const { relay, images } = await harness();
    const answers: string[] = [];
    answers.push(await (await relay(post(reportBody({ screenshot_b64: 'AA==' })))).text());
    answers.push(await (await relay(post(reportBody(), 'wrong-token'))).text());
    answers.push(await (await relay(post(reportBody({ github_repo: 'attacker/repo' })))).text());
    answers.push(await (await relay(check('11111111-2222-4333-8444-555555555555'))).text());
    images.mode = 'error';
    answers.push(await (await relay(post(reportBody({ screenshot_b64: 'AA==' })))).text());

    for (const answer of answers) {
      assert.ok(!answer.includes(GITHUB_TOKEN), `answer leaked the GitHub token: ${answer}`);
      assert.ok(!answer.includes(IMAGE_KEY), `answer leaked the image key: ${answer}`);
      assert.ok(!answer.includes(TESTER_TOKEN), `answer leaked the tester token: ${answer}`);
    }
  });

  test('an unknown method or path is not found', async () => {
    const { relay } = await harness();
    assert.equal((await relay(new Request('https://relay.test/reports'))).status, 404);
    assert.equal((await relay(new Request('https://relay.test/'))).status, 404);
  });

  test('a broken body is refused', async () => {
    const { relay } = await harness();
    const response = await relay(
      new Request('https://relay.test/reports', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Tester-Token': TESTER_TOKEN },
        body: '{not json',
      }),
    );
    assert.equal(response.status, 400);
  });

  test('the rate limit holds after the allowed count', async () => {
    const { relay } = await harness({ rateLimit: 2 });
    assert.equal((await relay(post(reportBody()))).status, 201);
    assert.equal((await relay(post(reportBody({ report_id: '22222222-3333-4444-8555-666666666666' })))).status, 201);
    const limited = await relay(post(reportBody({ report_id: '33333333-4444-4555-8666-777777777777' })));
    assert.equal(limited.status, 429);
  });
});

describe('issue content', () => {
  test('keeps the tester words first and the facts below', async () => {
    const { relay, backlog } = await harness();

    await relay(post(reportBody({ screenshot_b64: 'AA==' })));

    const body = backlog.issues[0].body;
    assert.match(body, /### What happened\n\nThe list is empty after a restart\./);
    assert.match(body, /### Expected\n\nThe saved items stay visible\./);
    assert.match(body, /### Steps\n\n1\. Add one item/);
    assert.match(body, /!\[screenshot\]\(https:\/\/images\.test\/1\.png\)/);
    assert.match(body, /\*\*App version\*\*: 1\.2\.4/);
    assert.match(body, /\*\*Device\*\*: Pixel 7, android Android 15 \(en_US\)/);
    assert.match(body, /avensora-report-id: /);
    assert.equal(backlog.issues[0].title, 'Feedback: The list is empty after a restart.');
  });

  test('marks an unknown fact as Unknown instead of leaving a gap', async () => {
    const { relay, backlog } = await harness();
    const body = reportBody();
    const context = body.context as Record<string, unknown>;
    context.screen = 'Unknown';
    context.source_revision = 'Unknown';

    await relay(post(body));

    assert.match(backlog.issues[0].body, /\*\*Screen\*\*: Unknown/);
    assert.match(backlog.issues[0].body, /\*\*Source revision\*\*: Unknown/);
  });

  test('a long first line is cut in the title', async () => {
    const { relay, backlog } = await harness();

    await relay(post(reportBody({ text: `${'a very long sentence '.repeat(8)}end` })));

    assert.ok(backlog.issues[0].title.length <= 80, backlog.issues[0].title);
    assert.match(backlog.issues[0].title, /^Feedback: /);
  });
});
