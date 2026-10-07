import assert from 'node:assert/strict';
import { test } from 'node:test';

import { GitHubBacklog } from '../src/backlog.ts';
import { type ProductBundle } from '../src/destinations.ts';

const bundle: ProductBundle = {
  product_id: 'ohridskiprolog2',
  github_repo: 'zarkob/ohridskiprolog2',
  github_token: 'private-test-token',
  testers: [],
};

test('GitHub report search limits the query to issues', async () => {
  let requestUrl = '';
  const backlog = new GitHubBacklog(async (input) => {
    requestUrl = String(input);
    return new Response(JSON.stringify({ items: [] }), { status: 200 });
  });

  await backlog.findByReportId(bundle, 'e411c4f1-37aa-4b96-b4bd-d19b72fa5e42');

  const query = new URL(requestUrl).searchParams.get('q');
  assert.equal(query, 'repo:zarkob/ohridskiprolog2 is:issue in:body "avensora-report-id: e411c4f1-37aa-4b96-b4bd-d19b72fa5e42"');
});
