/**
 * A local relay for checks. It runs the real handler with fake destinations.
 *
 * The fake backlog and image host stay in memory. No real service is called,
 * so a local check never files an issue and never uploads a tester image.
 *
 * Use it from a test or from a local contract check:
 *
 * ```bash
 * node src/local_server.ts --port 8791
 * ```
 */

import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';

import type { Backlog, IssueRef, IssueRequest } from './backlog.ts';
import { MapDestinations, sha256Hex, type ProductBundle } from './destinations.ts';
import { DisabledImageHost, type ImageHost } from './images.ts';
import { createRelay } from './relay.ts';
import { MemoryDeliveryStore, MemoryRateLimiter } from './store.ts';

/** One filed fake issue. */
export interface FakeIssue {
  url: string;
  title: string;
  body: string;
}

/** How the fake backlog answers. */
export type CreateMode = 'ok' | 'error' | 'create_then_error';
export type SearchMode = 'ok' | 'error' | 'lagging';

/** A fake backlog that records the issues it would file. */
export class FakeBacklog implements Backlog {
  readonly issues: FakeIssue[] = [];
  createMode: CreateMode = 'ok';
  searchMode: SearchMode = 'ok';
  createCalls = 0;

  async createIssue(bundle: ProductBundle, issue: IssueRequest): Promise<IssueRef> {
    this.createCalls += 1;
    if (this.createMode === 'error') {
      throw new Error('The fake backlog is down.');
    }
    const url = `https://github.com/${bundle.github_repo}/issues/${this.issues.length + 101}`;
    this.issues.push({ url, title: issue.title, body: issue.body });
    if (this.createMode === 'create_then_error') {
      // The issue exists, but the answer was lost on the way back.
      throw new Error('The answer was lost.');
    }
    return { url };
  }

  async findByReportId(_bundle: ProductBundle, reportId: string): Promise<IssueRef | null> {
    if (this.searchMode === 'error') {
      throw new Error('The fake search is down.');
    }
    if (this.searchMode === 'lagging') {
      return null;
    }
    const found = this.issues.find((issue) => issue.body.includes(`avensora-report-id: ${reportId}`));
    return found ? { url: found.url } : null;
  }
}

/** A fake image host that records the images it would store. */
export class FakeImageHost implements ImageHost {
  readonly uploads: string[] = [];
  mode: 'ok' | 'error' = 'ok';

  async upload(_bundle: ProductBundle, imageBase64: string): Promise<string> {
    if (this.mode === 'error') {
      throw new Error('The fake image host is down.');
    }
    this.uploads.push(imageBase64);
    return `https://images.test/${this.uploads.length}.png`;
  }
}

/** A started local relay. */
export interface LocalRelay {
  url: string;
  port: number;
  testerToken: string;
  productId: string;
  backlog: FakeBacklog;
  images: FakeImageHost;
  store: MemoryDeliveryStore;
  close: () => Promise<void>;
}

const LOCAL_TESTER_TOKEN = 'local-tester-token';
const LOCAL_PRODUCT_ID = 'local-product';

/** Starts the local relay on a free or given port. */
export async function startLocalRelay(options: { port?: number; imageHost?: boolean } = {}): Promise<LocalRelay> {
  const testerHash = await sha256Hex(LOCAL_TESTER_TOKEN);
  const bundle: ProductBundle = {
    product_id: LOCAL_PRODUCT_ID,
    github_repo: 'example/test-product',
    github_token: 'fake-github-token',
    testers: [{ name: 'local-tester', token_sha256: testerHash }],
  };
  if (options.imageHost !== false) {
    bundle.image_api_key = 'fake-image-key';
  }

  const backlog = new FakeBacklog();
  const images = new FakeImageHost();
  const store = new MemoryDeliveryStore();
  const relay = createRelay({
    destinations: new MapDestinations([bundle]),
    backlog,
    imgbb: images,
    disabledImages: new DisabledImageHost(),
    store,
    limiter: new MemoryRateLimiter(1000, 60),
  });

  const server: Server = createServer((request, response) => {
    void handle(relay, request, response);
  });
  await new Promise<void>((resolve) => server.listen(options.port ?? 0, '127.0.0.1', resolve));
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 0;

  return {
    url: `http://127.0.0.1:${port}`,
    port,
    testerToken: LOCAL_TESTER_TOKEN,
    productId: LOCAL_PRODUCT_ID,
    backlog,
    images,
    store,
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}

async function handle(relay: (request: Request) => Promise<Response>, request: IncomingMessage, response: ServerResponse): Promise<void> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(chunk as Buffer);
  }
  const body = chunks.length > 0 ? Buffer.concat(chunks) : undefined;
  const headers = new Headers();
  for (const [key, value] of Object.entries(request.headers)) {
    if (typeof value === 'string') {
      headers.set(key, value);
    }
  }
  const url = `http://127.0.0.1:${(request.socket.localPort ?? 0).toString()}${request.url ?? '/'}`;
  const webRequest = new Request(url, { method: request.method ?? 'GET', headers, body });
  const webResponse = await relay(webRequest);
  response.statusCode = webResponse.status;
  webResponse.headers.forEach((value, key) => response.setHeader(key, value));
  const buffer = Buffer.from(await webResponse.arrayBuffer());
  response.end(buffer);
}

if (process.argv[1] && process.argv[1].endsWith('local_server.ts')) {
  const portArg = process.argv.indexOf('--port');
  const port = portArg >= 0 ? Number.parseInt(process.argv[portArg + 1] ?? '0', 10) : 0;
  const local = await startLocalRelay({ port });
  console.log(`Local feedback relay listening on ${local.url}`);
  console.log(`Product id: ${local.productId}`);
  console.log(`Tester token: ${local.testerToken}`);
  console.log('The backlog and the image host are in memory. No real service is called.');
}
