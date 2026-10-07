import assert from 'node:assert/strict';
import { test } from 'node:test';

import { ImgbbImageHost } from '../src/images.ts';
import { type ProductBundle } from '../src/destinations.ts';

const bundle: ProductBundle = {
  product_id: 'ohridskiprolog2',
  github_repo: 'zarkob/ohridskiprolog2',
  github_token: 'private-test-token',
  image_api_key: 'private-image-key',
  testers: [],
};

test('ImgBB uses the full image when a small preview is also present', async () => {
  const fetchImpl = (async () => new Response(JSON.stringify({ data: {
    url: 'https://images.test/full.png',
    display_url: 'https://images.test/small.png',
  } }), { status: 200 })) as typeof fetch;
  const host = new ImgbbImageHost(fetchImpl);
  assert.equal(await host.upload(bundle, 'AA=='), 'https://images.test/full.png');
});

test('ImgBB can use the display image when the full image link is absent', async () => {
  const fetchImpl = (async () => new Response(JSON.stringify({ data: {
    display_url: 'https://images.test/display.png',
  } }), { status: 200 })) as typeof fetch;
  const host = new ImgbbImageHost(fetchImpl);
  assert.equal(await host.upload(bundle, 'AA=='), 'https://images.test/display.png');
});
