/**
 * The backlog adapter. GitHub Issues is the first destination.
 *
 * Every issue body carries a report marker. The marker lets the relay find a
 * report that was created while the answer was lost.
 */

import type { ProductBundle } from './destinations.ts';
import { UNKNOWN_FACT, type ReportRequest } from './report.ts';

/** A request to file one issue. */
export interface IssueRequest {
  reportId: string;
  title: string;
  body: string;
}

/** A filed issue. */
export interface IssueRef {
  url: string;
}

/** Files and finds product issues. */
export interface Backlog {
  createIssue(bundle: ProductBundle, issue: IssueRequest): Promise<IssueRef>;
  findByReportId(bundle: ProductBundle, reportId: string): Promise<IssueRef | null>;
}

/** The GitHub Issues destination. */
export class GitHubBacklog implements Backlog {
  private readonly fetchImpl: typeof fetch;

  constructor(fetchImpl: typeof fetch = fetch) {
    this.fetchImpl = fetchImpl;
  }

  async createIssue(bundle: ProductBundle, issue: IssueRequest): Promise<IssueRef> {
    const response = await this.fetchImpl(`https://api.github.com/repos/${bundle.github_repo}/issues`, {
      method: 'POST',
      headers: this.headers(bundle),
      body: JSON.stringify({
        title: issue.title,
        body: issue.body,
        labels: ['feedback', 'from-app'],
      }),
    });
    if (!response.ok) {
      throw new Error(`GitHub answered ${response.status}.`);
    }
    const data = (await response.json()) as { html_url?: string };
    if (!data.html_url) {
      throw new Error('GitHub returned no issue link.');
    }
    return { url: data.html_url };
  }

  /**
   * Finds an issue that already holds this report marker.
   *
   * The GitHub search index can lag behind a new issue. A late index keeps the
   * delivery state unknown instead of creating a second issue.
   */
  async findByReportId(bundle: ProductBundle, reportId: string): Promise<IssueRef | null> {
    const query = encodeURIComponent(`repo:${bundle.github_repo} in:body "${reportMarker(reportId)}"`);
    const response = await this.fetchImpl(`https://api.github.com/search/issues?q=${query}`, {
      headers: this.headers(bundle),
    });
    if (!response.ok) {
      throw new Error(`GitHub search answered ${response.status}.`);
    }
    const data = (await response.json()) as { items?: Array<{ html_url?: string }> };
    const item = data.items?.find((entry) => typeof entry.html_url === 'string');
    return item?.html_url ? { url: item.html_url } : null;
  }

  private headers(bundle: ProductBundle): Record<string, string> {
    return {
      Authorization: `Bearer ${bundle.github_token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Content-Type': 'application/json',
      'User-Agent': 'avensora-feedback-relay',
    };
  }
}

/** The marker line that ties one issue to one report id. */
export function reportMarker(reportId: string): string {
  return `avensora-report-id: ${reportId}`;
}

/** The issue title for one report. */
export function buildIssueTitle(report: ReportRequest): string {
  const firstLine = report.text.split('\n')[0].trim();
  const text = firstLine.length > 0 ? firstLine : report.text.trim();
  const prefix = 'Feedback: ';
  const max = 80;
  const room = max - prefix.length;
  return prefix + (text.length > room ? `${text.slice(0, room - 1)}…` : text);
}

/** The issue body for one report. It keeps the tester's own words first. */
export function buildIssueBody(report: ReportRequest, imageUrl: string | null): string {
  const lines: string[] = [];
  lines.push('### What happened', '', report.text, '');
  if (report.expected) {
    lines.push('### Expected', '', report.expected, '');
  }
  if (report.steps) {
    lines.push('### Steps', '', report.steps, '');
  }
  lines.push('### Screenshot', '');
  lines.push(imageUrl ? `![screenshot](${imageUrl})` : '_No image was attached._');
  lines.push('');
  lines.push('<details><summary>Build and device facts</summary>', '');
  lines.push(`- **Report ID**: ${report.report_id}`);
  lines.push(`- **Product**: ${report.context.product_id}`);
  lines.push(`- **App version**: ${report.context.app_version}`);
  lines.push(`- **Build number**: ${report.context.build_number}`);
  lines.push(`- **Build mode**: ${report.context.build_mode}`);
  lines.push(`- **Screen**: ${report.context.screen}`);
  lines.push(`- **Captured at**: ${report.context.captured_at}`);
  lines.push(`- **Source revision**: ${report.context.source_revision}`);
  lines.push(`- **Device**: ${report.context.device.model}, ${report.context.device.platform} ${report.context.device.os_version} (${report.context.device.locale})`);
  lines.push('', '</details>', '');
  lines.push(`<!-- ${reportMarker(report.report_id)} -->`);
  return lines.join('\n');
}

/** True when one fact is unknown, so the issue can mark it clearly. */
export function isUnknown(fact: string): boolean {
  return fact === UNKNOWN_FACT;
}
