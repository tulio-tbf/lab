import { artifactPath, openService, withPage } from './browser.mjs';

await withPage(async page => {
  const response = await openService(page, 'wordpress');
  const file = await artifactPath('wordpress-home.png');
  await page.screenshot({ path: file, fullPage: true, animations: 'disabled' });
  console.log(`WordPress HTTP ${response.status()}; screenshot: ${file}`);
});
