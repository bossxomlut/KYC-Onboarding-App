import { randomBytes } from 'node:crypto';
import { readFile, writeFile, access } from 'node:fs/promises';
const destination = new URL('../backend/.env', import.meta.url);
try {
  await access(destination);
  console.log('backend/.env already exists; keeping its configuration.');
} catch {
  let contents = await readFile(new URL('../backend/.env.example', import.meta.url), 'utf8');
  for (const key of ['JWT_SECRET', 'TOKEN_PEPPER', 'MEDIA_ENCRYPTION_KEY']) {
    contents = contents.replace(new RegExp(`^${key}=.*$`, 'm'), `${key}=${randomBytes(32).toString('base64')}`);
  }
  await writeFile(destination, contents, { mode: 0o600, flag: 'wx' });
  console.log('Created backend/.env with separate random secrets.');
}
