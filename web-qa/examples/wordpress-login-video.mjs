import { artifactPath, openService, serviceUrl, withPage } from './browser.mjs';

const username = process.env.WP_USERNAME;
const password = process.env.WP_PASSWORD;
if (!username || !password) {
  throw new Error('Defina WP_USERNAME e WP_PASSWORD com credenciais de teste do WordPress.');
}

await withPage(async page => {
  const loginUrl = new URL('wp-login.php', serviceUrl('wordpress'));
  const response = await page.goto(loginUrl, { waitUntil: 'domcontentloaded' });
  if (!response?.ok()) {
    throw new Error(`${loginUrl} retornou HTTP ${response?.status() ?? 'desconhecido'}`);
  }
  await page.getByLabel('Username or Email Address').fill(username);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: /log in/i }).click();
  await page.getByRole('heading', { name: 'Dashboard' }).waitFor({ state: 'visible' });
  const screenshot = await artifactPath('wordpress-dashboard.png');
  await page.screenshot({ path: screenshot, fullPage: true, animations: 'disabled' });
  console.log(`Login concluído; screenshot: ${screenshot}`);
  console.log(`Vídeo gravado no volume do Lab: ${process.env.QA_ARTIFACTS || '/artifacts'}`);
}, { recordVideo: true });
