import { openService, withPage } from './browser.mjs';

await withPage(async page => {
  const response = await openService(page, 'n8n');
  console.log(`n8n disponível (HTTP ${response.status()})`);
});
