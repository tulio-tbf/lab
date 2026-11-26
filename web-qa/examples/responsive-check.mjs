import { artifactPath, openService, withPage } from './browser.mjs';

const sizes = [
  { width: 390, height: 844 },
  { width: 768, height: 1024 },
  { width: 1440, height: 900 },
];
const service = process.argv[2] || 'wordpress';

await withPage(async page => {
  await openService(page, service);
  for (const viewport of sizes) {
    await page.setViewportSize(viewport);
    const file = await artifactPath(`${service}-${viewport.width}x${viewport.height}.png`);
    await page.screenshot({ path: file, fullPage: true, animations: 'disabled' });
    console.log(`${viewport.width}x${viewport.height}: ${file}`);
  }
});
