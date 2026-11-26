import { mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { chromium } from 'playwright';

export function serviceUrl(service) {
  const domain = process.env.QA_DOMAIN || 'lab.test';
  const port = process.env.QA_TRAEFIK_PORT || '80';
  const url = new URL(`http://${service}.${domain}/`);
  if (port !== '80') url.port = port;
  return url.href;
}

export async function artifactPath(filename) {
  const directory = resolve(
    process.env.QA_OUTPUT_DIR || process.env.QA_ARTIFACTS || 'web-qa-artifacts',
  );
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const path = resolve(directory, filename);
  if (!path.startsWith(`${directory}/`)) throw new Error('Nome de artefato inválido');
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  return path;
}

export async function withPage(action, { recordVideo = false, viewport } = {}) {
  const endpoint = process.env.PLAYWRIGHT_WS_ENDPOINT || 'ws://127.0.0.1:3000/';
  const browser = await chromium.connect(endpoint, { timeout: 10000 });
  let context;
  try {
    const options = { viewport: viewport || { width: 1440, height: 900 } };
    if (recordVideo) options.recordVideo = { dir: process.env.QA_ARTIFACTS || '/artifacts' };
    context = await browser.newContext(options);
    const page = await context.newPage();
    return await action(page, context);
  } finally {
    try {
      await context?.close();
    } finally {
      await browser.close();
    }
  }
}

export async function openService(page, service) {
  const url = serviceUrl(service);
  const response = await page.goto(url, { waitUntil: 'domcontentloaded' });
  if (!response?.ok()) {
    throw new Error(`${url} retornou HTTP ${response?.status() ?? 'desconhecido'}`);
  }
  await page.locator('body').waitFor({ state: 'visible' });
  return response;
}
