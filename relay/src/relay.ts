/**
 * The relay request handler.
 *
 * The handler owns three honest answers: the destination confirmed a report,
 * the destination rejected it, or the relay cannot prove what happened. The
 * last case never counts as a send.
 */

import { buildIssueBody, buildIssueTitle, GitHubApiError, type Backlog, type IssueRef } from './backlog.ts';
import { hasTesterAccess, sha256Hex, type DestinationMap, type ProductBundle } from './destinations.ts';
import { imageHostFor, type ImageHost } from './images.ts';
import { readReportRequest, ValidationError, type ReportRequest } from './report.ts';
import type { DeliveryRecord, DeliveryStore, RateLimiter } from './store.ts';

const IMAGE_NOT_STORED_NOTE = 'The image was not stored, because this product has no image host yet.';

/** Everything the relay needs. Tests supply fakes. */
export interface RelayDeps {
  destinations: DestinationMap;
  backlog: Backlog;
  imgbb: ImageHost;
  disabledImages: ImageHost;
  store: DeliveryStore;
  limiter: RateLimiter;
  now?: () => Date;
  log?: (event: string, fields: Record<string, string>) => void;
}

/** The request handler of the relay. */
export type RelayHandler = (request: Request) => Promise<Response>;

/** Builds the relay handler from its parts. */
export function createRelay(deps: RelayDeps): RelayHandler {
  const now = deps.now ?? (() => new Date());
  const log = deps.log ?? (() => {});
  const stamp = () => now().toISOString();

  async function handleReport(request: Request, token: string | null): Promise<Response> {
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return json({ ok: false, error: 'Invalid JSON body.' }, 400);
    }

    let report: ReportRequest;
    try {
      report = readReportRequest(body);
    } catch (error) {
      const message = error instanceof ValidationError ? error.message : 'The report was rejected.';
      return json({ ok: false, error: message }, 400);
    }

    const bundle = deps.destinations.resolve(report.context.product_id);
    if (!bundle) {
      log('unknown_product', { product: report.context.product_id });
      return json({ ok: false, error: 'Unknown product.' }, 404);
    }
    if (!(await hasTesterAccess(bundle, token))) {
      log('access_denied', { product: bundle.product_id });
      return json({ ok: false, error: 'Tester access denied.' }, 403);
    }
    if (!(await deps.limiter.allow(`${bundle.product_id}:${await sha256Hex(token ?? '')}`))) {
      return json({ ok: false, error: 'Rate limit exceeded. Try again later.' }, 429);
    }

    const existing = await deps.store.get(report.report_id);
    if (existing && existing.product_id !== bundle.product_id) {
      // One report id belongs to one product. A colliding id is refused.
      log('product_conflict', { product: bundle.product_id, report: report.report_id });
      return json({ ok: false, error: 'This report id belongs to another product.' }, 409);
    }
    if (existing && existing.status === 'created' && existing.issue_url) {
      log('duplicate', { product: bundle.product_id, report: report.report_id });
      return json({ ok: true, status: 'duplicate', issue_url: existing.issue_url, ...(existing.note ? { note: existing.note } : {}) }, 200);
    }
    let note: string | undefined = (existing?.status === 'preflight_unknown' ? existing.note : undefined) ?? (report.screenshot_b64 && !bundle.image_api_key
      ? IMAGE_NOT_STORED_NOTE
      : undefined);
    let preflightSearchDone = false;
    if (existing?.status === 'preflight_unknown') {
      const preflight = await safeFind(deps.backlog, bundle, report.report_id, log);
      if (preflight.failed) {
        log('issue_search_unknown', { product: bundle.product_id, report: report.report_id });
        return json({ ok: false, error: 'Issue search did not answer. The report may exist.', delivery: 'unknown', ...(note ? { note } : {}) }, 502);
      }
      if (preflight.issue) {
        const record: DeliveryRecord = { ...existing, status: 'created', issue_url: preflight.issue.url, updated_at: stamp() };
        if (!(await saveDeliveryRecord(record, 'after_preflight_search'))) {
          return json({ ok: false, error: 'Check delivery before retrying.', delivery: 'unknown', ...(note ? { note } : {}) }, 502);
        }
        return json({ ok: true, status: 'duplicate', issue_url: preflight.issue.url, ...(note ? { note } : {}) }, 200);
      }
      preflightSearchDone = true;
    }
    if (existing && (existing.status === 'pending' || existing.status === 'unknown')) {
      // A claim exists but delivery is not proven. Look before any new issue.
      const resolved = await resolveDelivery(bundle, report.report_id, existing);
      if (resolved.status === 'created' && resolved.issue_url) {
        await deps.store.put(resolved);
        return json({ ok: true, status: 'duplicate', issue_url: resolved.issue_url, ...(resolved.note ? { note: resolved.note } : {}) }, 200);
      }
      await deps.store.put(resolved);
      return json({ ok: true, status: 'unknown', error: 'The relay cannot prove what happened to this report yet.', ...(resolved.note ? { note: resolved.note } : {}) }, 200);
    }

    const claim: DeliveryRecord = {
      report_id: report.report_id,
      product_id: bundle.product_id,
      status: 'pending',
      ...(note ? { note } : {}),
      updated_at: stamp(),
    };
    const firstSearch = preflightSearchDone
      ? { issue: null, failed: false }
      : await safeFind(deps.backlog, bundle, report.report_id, log);
    if (firstSearch.failed) {
      const preflightRecord: DeliveryRecord = { ...claim, status: 'preflight_unknown' };
      if (existing) {
        if (!(await saveDeliveryRecord(preflightRecord, 'before_create_search'))) {
          return json({ ok: false, error: 'Issue search did not answer. Check delivery before retrying.', delivery: 'unknown', ...(note ? { note } : {}) }, 502);
        }
      } else if (!(await deps.store.claim(preflightRecord))) {
        const taken = await deps.store.get(report.report_id);
        if (taken?.issue_url) {
          return json({ ok: true, status: 'duplicate', issue_url: taken.issue_url, ...(taken.note ? { note: taken.note } : {}) }, 200);
        }
      }
      log('issue_search_unknown', { product: bundle.product_id, report: report.report_id });
      return json({ ok: false, error: 'Issue search did not answer. The report may exist.', delivery: 'unknown', ...(note ? { note } : {}) }, 502);
    }
    const alreadyFiled = firstSearch.issue;
    if (alreadyFiled) {
      const record: DeliveryRecord = { ...claim, status: 'created', issue_url: alreadyFiled.url, updated_at: stamp() };
      if (existing) {
        if (!(await saveDeliveryRecord(record, 'after_preflight_search'))) {
          return json({ ok: false, error: 'Check delivery before retrying.', delivery: 'unknown', ...(note ? { note } : {}) }, 502);
        }
      } else if (!(await deps.store.claim(record))) {
        const taken = await deps.store.get(report.report_id);
        if (taken?.issue_url) {
          return json({ ok: true, status: 'duplicate', issue_url: taken.issue_url, ...(taken.note ? { note: taken.note } : {}) }, 200);
        }
        return json({ ok: true, status: 'unknown', error: 'Another send of this report is running.', ...(note ? { note } : {}) }, 200);
      }
      log('duplicate_after_search', { product: bundle.product_id, report: report.report_id });
      return json({ ok: true, status: 'duplicate', issue_url: alreadyFiled.url, ...(note ? { note } : {}) }, 200);
    }

    if (existing) {
      if (!(await saveDeliveryRecord(claim, 'before_create'))) {
        return json({ ok: false, error: 'Check delivery before retrying.', delivery: 'unknown', ...(note ? { note } : {}) }, 502);
      }
    } else if (!(await deps.store.claim(claim))) {
      const taken = await deps.store.get(report.report_id);
      if (taken?.issue_url) {
        return json({ ok: true, status: 'duplicate', issue_url: taken.issue_url, ...(taken.note ? { note: taken.note } : {}) }, 200);
      }
      return json({ ok: true, status: 'unknown', error: 'Another send of this report is running.', ...(note ? { note } : {}) }, 200);
    }

    let imageUrl: string | null = null;
    if (report.screenshot_b64) {
      const host = imageHostFor(bundle, deps.imgbb, deps.disabledImages);
      try {
        imageUrl = await host.upload(bundle, report.screenshot_b64);
      } catch {
        if (bundle.image_api_key) {
          const failed: DeliveryRecord = { ...claim, status: 'failed', note: 'Screenshot upload failed.', updated_at: stamp() };
          await deps.store.put(failed);
          log('image_failed', { product: bundle.product_id, report: report.report_id });
          return json({ ok: false, error: 'Screenshot upload failed.', delivery: 'failed' }, 502);
        }
        note = IMAGE_NOT_STORED_NOTE;
      }
    }

    let issue: IssueRef;
    try {
      issue = await deps.backlog.createIssue(bundle, {
        reportId: report.report_id,
        title: buildIssueTitle(report),
        body: buildIssueBody(report, imageUrl),
      });
    } catch (error) {
      logGitHubFailure(log, 'create', error, bundle.product_id, report.report_id);
      // The issue may exist even when the answer was lost. Look again.
      const recoverySearch = await safeFind(deps.backlog, bundle, report.report_id, log);
      const recovered = recoverySearch.issue;
      if (recovered) {
        const record: DeliveryRecord = { ...claim, status: 'created', issue_url: recovered.url, note, updated_at: stamp() };
        if (!(await saveDeliveryRecord(record, 'after_create_recovery'))) {
          return json({ ok: false, error: 'The issue may exist. Check delivery before retrying.', delivery: 'unknown', ...(note ? { note } : {}) }, 502);
        }
        log('created_after_error', { product: bundle.product_id, report: report.report_id });
        return json({ ok: true, status: 'created', issue_url: recovered.url, ...(note ? { note } : {}) }, 201);
      }
      const unknown: DeliveryRecord = { ...claim, status: 'unknown', note, updated_at: stamp() };
      if (!(await saveDeliveryRecord(unknown, 'after_create_unknown'))) {
        return json({ ok: false, error: 'Issue creation did not answer. Check delivery before retrying.', delivery: 'unknown', ...(note ? { note } : {}) }, 502);
      }
      log('issue_unknown', { product: bundle.product_id, report: report.report_id });
      return json({ ok: false, error: 'Issue creation did not answer. The report may exist.', delivery: 'unknown' }, 502);
    }

    const record: DeliveryRecord = { ...claim, status: 'created', issue_url: issue.url, note, updated_at: stamp() };
    if (!(await saveDeliveryRecord(record, 'after_create'))) {
      return json({ ok: false, error: 'The issue may exist. Check delivery before retrying.', delivery: 'unknown', ...(note ? { note } : {}) }, 502);
    }
    log('created', { product: bundle.product_id, report: report.report_id });
    return json({ ok: true, status: 'created', issue_url: issue.url, ...(note ? { note } : {}) }, 201);
  }

  async function saveDeliveryRecord(record: DeliveryRecord, stage: string): Promise<boolean> {
    try {
      await deps.store.put(record);
      return true;
    } catch {
      log('delivery_store_failed', { product: record.product_id, report: record.report_id, stage });
      return false;
    }
  }

  async function handleCheck(reportId: string, token: string | null): Promise<Response> {
    const record = await deps.store.get(reportId);
    if (!record) {
      // A missing record must not become a way to probe report ids.
      if (!(await hasAnyAccess(deps.destinations, token))) {
        return json({ ok: false, error: 'Tester access denied.' }, 403);
      }
      return json({ ok: true, status: 'not_found' }, 200);
    }
    const bundle = deps.destinations.resolve(record.product_id);
    if (!bundle) {
      return json({ ok: false, error: 'Unknown product.' }, 404);
    }
    if (!(await hasTesterAccess(bundle, token))) {
      return json({ ok: false, error: 'Tester access denied.' }, 403);
    }
    if (record.status === 'preflight_unknown') {
      const search = await safeFind(deps.backlog, bundle, reportId, log);
      if (search.failed) {
        return json({ ok: true, status: 'unknown', error: 'The relay cannot prove what happened to this report yet.', ...(record.note ? { note: record.note } : {}) }, 200);
      }
      if (!search.issue) {
        return json({ ok: true, status: 'not_found', ...(record.note ? { note: record.note } : {}) }, 200);
      }
      const confirmed: DeliveryRecord = { ...record, status: 'created', issue_url: search.issue.url, updated_at: stamp() };
      if (!(await saveDeliveryRecord(confirmed, 'after_preflight_check'))) {
        return json({ ok: true, status: 'unknown', error: 'The relay could not save the delivery result. Check again before retrying.', ...(record.note ? { note: record.note } : {}) }, 200);
      }
      return json({ ok: true, status: 'created', issue_url: search.issue.url, ...(record.note ? { note: record.note } : {}) }, 200);
    }
    if (record.status === 'created' && record.issue_url) {
      return json({ ok: true, status: 'created', issue_url: record.issue_url, ...(record.note ? { note: record.note } : {}) }, 200);
    }
    if (record.status === 'failed') {
      return json({ ok: true, status: 'not_found', note: 'The last attempt failed before the destination accepted it.' }, 200);
    }
    const resolved = await resolveDelivery(bundle, reportId, record);
    await deps.store.put(resolved);
    if (resolved.status === 'created' && resolved.issue_url) {
      return json({ ok: true, status: 'created', issue_url: resolved.issue_url, ...(resolved.note ? { note: resolved.note } : {}) }, 200);
    }
    return json({ ok: true, status: 'unknown', error: 'The relay cannot prove what happened to this report yet.', ...(resolved.note ? { note: resolved.note } : {}) }, 200);
  }

  async function resolveDelivery(bundle: ProductBundle, reportId: string, record: DeliveryRecord): Promise<DeliveryRecord> {
    const search = await safeFind(deps.backlog, bundle, reportId, log);
    const found = search.issue;
    const note = record.note === IMAGE_NOT_STORED_NOTE ? record.note : undefined;
    if (found) {
      return { ...record, status: 'created', issue_url: found.url, note, updated_at: stamp() };
    }
    return { ...record, status: 'unknown', note, updated_at: stamp() };
  }

  return async function relay(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const token = request.headers.get('X-Tester-Token');
    try {
      if (request.method === 'POST' && url.pathname === '/reports') {
        return await handleReport(request, token);
      }
      const match = /^\/reports\/([A-Za-z0-9][A-Za-z0-9._-]{7,127})$/.exec(url.pathname);
      if (request.method === 'GET' && match) {
        return await handleCheck(match[1], token);
      }
      return json({ ok: false, error: 'Not found.' }, 404);
    } catch {
      // Never leak internals, settings, or secret material to a client.
      return json({ ok: false, error: 'Internal error.' }, 500);
    }
  };
}

async function hasAnyAccess(destinations: DestinationMap, token: string | null): Promise<boolean> {
  if (!token) {
    return false;
  }
  for (const bundle of destinations.all()) {
    if (await hasTesterAccess(bundle, token)) {
      return true;
    }
  }
  return false;
}

interface SearchResult {
  issue: IssueRef | null;
  failed: boolean;
}

async function safeFind(backlog: Backlog, bundle: ProductBundle, reportId: string, log: RelayDeps['log']): Promise<SearchResult> {
  try {
    return { issue: await backlog.findByReportId(bundle, reportId), failed: false };
  } catch (error) {
    logGitHubFailure(log ?? (() => {}), 'search', error, bundle.product_id, reportId);
    return { issue: null, failed: true };
  }
}

function logGitHubFailure(
  log: NonNullable<RelayDeps['log']>,
  operation: 'create' | 'search',
  error: unknown,
  product: string,
  report: string,
): void {
  if (error instanceof GitHubApiError && error.operation === operation) {
    log(`github_${operation}_failed`, {
      product,
      report,
      http_status: error.httpStatus === null ? 'unknown' : String(error.httpStatus),
    });
  }
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
