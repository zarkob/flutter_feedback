import assert from 'node:assert/strict';
import { test } from 'node:test';

import { GitHubBacklog } from '../src/backlog.ts';
import { ImgbbImageHost } from '../src/images.ts';
import { type ProductBundle } from '../src/destinations.ts';

const bundle: ProductBundle = {
  product_id: 'ohridskiprolog2',
  github_repo: 'zarkob/ohridskiprolog2',
  github_token: 'private-test-token',
  image_api_key: 'private-image-key',
  testers: [],
};

async function withReceiverSensitiveFetch<T>(run: () => Promise<T>): Promise<T> {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = function (this: typeof globalThis, input: RequestInfo | URL): Promise<Response> {
    if (this !== globalThis) {
      throw new TypeError('Illegal invocation');
    }
    const url = String(input);
    if (url.startsWith('https://api.github.com/search/')) {
      return Promise.resolve(new Response(JSON.stringify({ items: [] }), { status: 200 }));
    }
    if (url.startsWith('https://api.imgbb.com/')) {
      return Promise.resolve(new Response(JSON.stringify({ data: { url: 'https://images.test/report.png' } }), { status: 200 }));
    }
    return Promise.resolve(new Response('unexpected URL', { status: 500 }));
  };
  try {
    return await run();
  } finally {
    globalThis.fetch = originalFetch;
  }
}

test('GitHubBacklog calls the default fetch with the global receiver', async () => {
  await withReceiverSensitiveFetch(async () => {
    const backlog = new GitHubBacklog();
    const issue = await backlog.findByReportId(bundle, '11111111-2222-4333-8444-555555555555');
    assert.equal(issue, null);
  });
});

test('ImgbbImageHost calls the default fetch with the global receiver', async () => {
  await withReceiverSensitiveFetch(async () => {
    const images = new ImgbbImageHost();
    const url = await images.upload(bundle, 'AA==');
    assert.equal(url, 'https://images.test/report.png');
  });
});
