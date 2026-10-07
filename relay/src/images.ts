/**
 * The image host adapter.
 *
 * The image service key stays on the relay. A report image is optional. When a
 * product has no image host, the relay files the report without an image
 * instead of failing the whole report.
 */

import type { ProductBundle } from './destinations.ts';

/** Uploads one report image and returns a public link. */
export interface ImageHost {
  upload(bundle: ProductBundle, imageBase64: string): Promise<string>;
}

/** The imgbb image host. It accepts base64 image text directly. */
export class ImgbbImageHost implements ImageHost {
  private readonly fetchImpl: typeof fetch;

  constructor(fetchImpl: typeof fetch = fetch) {
    this.fetchImpl = fetchImpl.bind(globalThis);
  }

  async upload(bundle: ProductBundle, imageBase64: string): Promise<string> {
    const key = bundle.image_api_key;
    if (!key) {
      throw new Error('No image host key is set for this product.');
    }
    const params = new URLSearchParams();
    params.set('key', key);
    params.set('image', imageBase64);
    const response = await this.fetchImpl('https://api.imgbb.com/1/upload', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    });
    if (!response.ok) {
      throw new Error(`The image host answered ${response.status}.`);
    }
    const data = (await response.json()) as { data?: { display_url?: string; url?: string } };
    // The display link can point to a small image. Keep the full screenshot.
    const url = data.data?.url ?? data.data?.display_url;
    if (!url) {
      throw new Error('The image host returned no link.');
    }
    return url;
  }
}

/** The image path stays out when a product has no image host. */
export class DisabledImageHost implements ImageHost {
  async upload(): Promise<string> {
    throw new Error('No image host is configured for this product.');
  }
}

/** Picks the image host for one product. */
export function imageHostFor(bundle: ProductBundle, imgbb: ImageHost, disabled: ImageHost): ImageHost {
  return bundle.image_api_key ? imgbb : disabled;
}
