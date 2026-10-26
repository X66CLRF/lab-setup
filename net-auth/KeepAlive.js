/**
 * KeepAlive.js - NSRU FortiGate captive-portal keepalive (Node.js engine).
 * Windows Schannel (PowerShell .NET / curl.exe) gets "connection closed unexpectedly" from the
 * portal's TLS; Node's OpenSSL does not. KeepAlive.ps1 uses this when node.exe is installed.
 * Credentials arrive via NSRU_USER / NSRU_PASS env vars (set by KeepAlive.ps1), never argv.
 */
const fs = require('fs');
const https = require('https');
const http = require('http');

let portal = 'https://login.nsru.ac.th:1000';
let intervalSec = 90;
let stopHour = -1;
let once = false;
let logPath = null;

const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--portal' && args[i + 1]) portal = args[++i];
  else if (args[i] === '--interval' && args[i + 1]) intervalSec = parseInt(args[++i], 10);
  else if (args[i] === '--stop-hour' && args[i + 1]) stopHour = parseInt(args[++i], 10);
  else if (args[i] === '--log' && args[i + 1]) logPath = args[++i];
  else if (args[i] === '--once') once = true;
}

function writeLog(msg) {
  const line = `${new Date().toLocaleString('sv-SE')}  ${msg}`;
  if (logPath) { try { fs.appendFileSync(logPath, line + '\n', 'utf8'); } catch (e) {} }
  if (process.stdout.isTTY) console.log(line);
}

const username = process.env.NSRU_USER;
const password = process.env.NSRU_PASS;
if (!username || !password) {
  writeLog('FAIL: No credentials passed (NSRU_USER / NSRU_PASS missing).');
  process.exit(1);
}

// like curl -k: the portal certificate is not trusted by the lab PCs
function request(url, options = {}) {
  return new Promise((resolve, reject) => {
    try {
      const u = new URL(url);
      const isHttps = u.protocol === 'https:';
      const req = (isHttps ? https : http).request({
        hostname: u.hostname,
        port: u.port || (isHttps ? 443 : 80),
        path: u.pathname + u.search,
        rejectUnauthorized: false,
        headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36', ...options.headers },
        method: options.method || 'GET',
        timeout: 10000
      }, (res) => {
        let data = '';
        res.on('data', (c) => data += c);
        res.on('end', () => resolve({ statusCode: res.statusCode, headers: res.headers, body: data }));
      });
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('Request timeout')); });
      if (options.body) req.write(options.body);
      req.end();
    } catch (err) { reject(err); }
  });
}

async function checkInternet() {
  try {
    const res = await request('http://clients3.google.com/generate_204');
    if (res.statusCode === 204) return { isOnline: true };
    let redirectUrl = '';
    if (res.headers.location) redirectUrl = res.headers.location;
    else {
      const m = res.body && res.body.match(/window\.location\s*=\s*"([^"]+)"/);
      if (m) redirectUrl = m[1];
    }
    return { isOnline: false, redirectUrl };
  } catch (err) {
    return { isOnline: false };
  }
}

async function login(redirectUrl) {
  try {
    let targetPortal = portal;
    let magicToken = '';
    let loginPage = `${portal}/`;
    if (redirectUrl) {
      try {
        loginPage = redirectUrl;
        const u = new URL(redirectUrl);
        targetPortal = `${u.protocol}//${u.host}`;
        if (u.searchParams.has('magic')) magicToken = u.searchParams.get('magic');
        else if (u.search) magicToken = u.search.substring(1);
      } catch (e) {}
    }
    const page = (await request(loginPage)).body;
    const mm = page.match(/name="?magic"?\s+value="([^"]+)"/);
    const magic = mm ? mm[1] : magicToken;
    const rm = page.match(/name="?4Tredir"?\s+value="([^"]+)"/);
    const redir = rm ? rm[1] : `${targetPortal}/`;

    const postData = new URLSearchParams({ '4Tredir': redir, magic, username, password }).toString();
    const resp = (await request(`${targetPortal}/`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(postData) },
      body: postData
    })).body;

    const tm = resp.match(/keepalive\?([0-9a-fA-F]+)/) || resp.match(/logout\?([0-9a-fA-F]+)/);
    const token = tm ? tm[1] : null;
    writeLog(`Login detail: redirect=${redirectUrl ? targetPortal : 'none'} magic=${magic ? 'found' : 'MISSING'} token=${token ? 'found' : (/type="password"/.test(resp) ? 'none (login page again: wrong user/password?)' : 'none')}`);
    return token;
  } catch (err) {
    writeLog(`Login request failed: ${err.message}`);
    return null;
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  writeLog(`KeepAlive (node ${process.version}) started (Target: ${portal}, Interval: ${intervalSec}s)`);
  let token = null;

  let st = await checkInternet();
  if (st.isOnline) {
    writeLog('Internet is online.');
  } else {
    writeLog(`Internet is offline or captive portal detected. Attempting login for '${username}'...`);
    token = await login(st.redirectUrl);
    await sleep(2000);
    st = await checkInternet();
    writeLog(st.isOnline ? 'Login SUCCESS' : 'Login attempted, internet still offline.');
  }
  if (once) process.exit(st.isOnline ? 0 : 1);

  while (true) {
    if (stopHour >= 0 && new Date().getHours() === stopHour) {
      writeLog(`Stop hour reached (${stopHour}:00). Exiting daemon.`);
      if (token) { try { await request(`${portal}/logout?${token}`); } catch (e) {} }
      process.exit(0);
    }
    st = await checkInternet();
    if (st.isOnline) {
      if (token) {
        try {
          const res = await request(`${portal}/keepalive?${token}`);
          if (res.body.includes('name="magic"') && res.body.includes('type="password"')) {
            writeLog('Session expired. Re-authenticating...');
            token = await login();
            writeLog(`Re-login result: ${token ? 'OK' : 'FAILED'}`);
          }
        } catch (err) {
          writeLog(`keepalive call failed (${err.message}), internet is OK`);
        }
      }
      await sleep(intervalSec * 1000);
    } else {
      writeLog('Connection dropped. Re-authenticating...');
      token = await login(st.redirectUrl);
      st = await checkInternet();
      if (st.isOnline) {
        writeLog('Re-connected successfully.');
        await sleep(intervalSec * 1000);
      } else {
        writeLog('Re-connection attempt failed. Retrying in 10s...');
        await sleep(10000);
      }
    }
  }
}

main().catch((err) => { writeLog(`Fatal: ${err.message}`); process.exit(2); });
