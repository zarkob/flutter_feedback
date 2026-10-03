/**
 * The report format that the relay accepts from a test build.
 *
 * The relay trusts only its own destination map. A report cannot name a
 * repository, a web address, or a label. Unknown fields are rejected, so a
 * changed app cannot widen the relay's reach by accident.
 */

export const REPORT_SCHEMA = 'avensora-report/1';

export const MAX_TEXT_LENGTH = 10_000;
export const MAX_OPTIONAL_TEXT_LENGTH = 4_000;
export const MAX_SCREENSHOT_BYTES = 4 * 1024 * 1024;

export const UNKNOWN_FACT = 'Unknown';

export interface ReportContext {
  product_id: string;
  product_name?: string;
  app_version: string;
  build_number: string;
  build_mode: string;
  screen: string;
  source_revision: string;
  captured_at: string;
  device: {
    model: string;
    platform: string;
    os_version: string;
    locale: string;
  };
}

export interface ReportRequest {
  schema: string;
  report_id: string;
  created_at: string;
  text: string;
  expected: string | null;
  steps: string | null;
  screenshot_b64: string | null;
  context: ReportContext;
}

/** A rejected request. The message is safe to show to a tester. */
export class ValidationError extends Error {}

const REPORT_KEYS = [
  'schema',
  'report_id',
  'created_at',
  'text',
  'expected',
  'steps',
  'screenshot_b64',
  'context',
];

const CONTEXT_KEYS = [
  'product_id',
  'product_name',
  'app_version',
  'build_number',
  'build_mode',
  'screen',
  'source_revision',
  'captured_at',
  'device',
];

const DEVICE_KEYS = ['model', 'platform', 'os_version', 'locale'];

const REPORT_ID = /^[A-Za-z0-9][A-Za-z0-9._-]{7,127}$/;
const PRODUCT_ID = /^[a-z0-9][a-z0-9._-]{0,63}$/i;

/**
 * Reads and checks one report request.
 *
 * Every check fails closed. An unknown field is a rejection, not a field that
 * the relay ignores.
 */
export function readReportRequest(value: unknown): ReportRequest {
  const body = asObject(value, 'The body must be a JSON object.');
  rejectUnknownKeys(body, REPORT_KEYS, 'report');

  const schema = requireText(body.schema, 'schema', 32);
  if (schema !== REPORT_SCHEMA) {
    throw new ValidationError(`Unsupported report schema "${schema}".`);
  }

  const reportId = requireText(body.report_id, 'report_id', 128);
  if (!REPORT_ID.test(reportId)) {
    throw new ValidationError('report_id is not a valid report id.');
  }

  const createdAt = requireText(body.created_at, 'created_at', 40);
  if (Number.isNaN(Date.parse(createdAt))) {
    throw new ValidationError('created_at is not a time.');
  }

  const text = requireText(body.text, 'text', MAX_TEXT_LENGTH);
  const expected = optionalText(body.expected, 'expected');
  const steps = optionalText(body.steps, 'steps');

  const context = asObject(body.context, 'context must be an object.');
  rejectUnknownKeys(context, CONTEXT_KEYS, 'context');
  const productId = requireText(context.product_id, 'context.product_id', 64);
  if (!PRODUCT_ID.test(productId)) {
    throw new ValidationError('context.product_id is not a valid product id.');
  }
  const device = asObject(context.device, 'context.device must be an object.');
  rejectUnknownKeys(device, DEVICE_KEYS, 'context.device');

  const screenshot = body.screenshot_b64;
  let screenshotB64: string | null = null;
  if (typeof screenshot === 'string' && screenshot.length > 0) {
    const size = estimateBase64DecodedSize(screenshot);
    if (size > MAX_SCREENSHOT_BYTES) {
      throw new ValidationError('Screenshot too large.');
    }
    if (!/^[A-Za-z0-9+/=\r\n]+$/.test(screenshot)) {
      throw new ValidationError('screenshot_b64 is not base64 text.');
    }
    screenshotB64 = screenshot;
  }

  return {
    schema,
    report_id: reportId,
    created_at: createdAt,
    text,
    expected,
    steps,
    screenshot_b64: screenshotB64,
    context: {
      product_id: productId,
      ...(typeof context.product_name === 'string' && context.product_name.length > 0
        ? { product_name: context.product_name }
        : {}),
      app_version: fact(context.app_version),
      build_number: fact(context.build_number),
      build_mode: fact(context.build_mode),
      screen: fact(context.screen),
      source_revision: fact(context.source_revision),
      captured_at: requireText(context.captured_at, 'context.captured_at', 40),
      device: {
        model: fact(device.model),
        platform: fact(device.platform),
        os_version: fact(device.os_version),
        locale: fact(device.locale),
      },
    },
  };
}

/** The decoded size of a base64 string, as an upper bound. */
export function estimateBase64DecodedSize(b64: string): number {
  const len = b64.length;
  const padding = b64.endsWith('==') ? 2 : b64.endsWith('=') ? 1 : 0;
  return Math.floor((len * 3) / 4) - padding;
}

/** Decodes base64 text into bytes. */
export function decodeBase64(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function asObject(value: unknown, message: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new ValidationError(message);
  }
  return value as Record<string, unknown>;
}

function rejectUnknownKeys(value: Record<string, unknown>, allowed: string[], where: string): void {
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) {
      throw new ValidationError(`Unknown ${where} field "${key}". The app cannot set that field.`);
    }
  }
}

function requireText(value: unknown, field: string, max: number): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new ValidationError(`${field} is missing.`);
  }
  if (value.length > max) {
    throw new ValidationError(`${field} is too long.`);
  }
  return value;
}

function optionalText(value: unknown, field: string): string | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value !== 'string') {
    throw new ValidationError(`${field} must be text or null.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }
  if (trimmed.length > MAX_OPTIONAL_TEXT_LENGTH) {
    throw new ValidationError(`${field} is too long.`);
  }
  return trimmed;
}

function fact(value: unknown): string {
  if (typeof value === 'string' && value.trim().length > 0) {
    return value.trim().slice(0, 120);
  }
  return UNKNOWN_FACT;
}
