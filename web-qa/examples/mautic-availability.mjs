import { openService, withPage } from './browser.mjs';

await withPage(async page => {
  const response = await openService(page, 'mautic');
  console.log(`Mautic disponível (HTTP ${response.status()})`);
});
