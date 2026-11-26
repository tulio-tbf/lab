import { artifactPath, openService, withPage } from './browser.mjs';

const service = process.argv[2] || 'wordpress';

await withPage(async page => {
  await openService(page, service);
  const title = await page.title();
  const content = (await page.locator('body').innerText()).slice(0, 4000);
  const screenshot = await artifactPath(`${service}-inspection.png`);
  await page.screenshot({ path: screenshot, fullPage: true, animations: 'disabled' });
  console.log(JSON.stringify({ service, title, content, screenshot }, null, 2));
});
