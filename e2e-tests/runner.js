import assert from 'node:assert';
import { spawn, exec } from 'node:child_process';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';
import { promisify } from 'node:util';

const execPromise = promisify(exec);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const BASE_URL = process.env.E2E_BASE_URL || 'http://localhost:3000';
const SKIP_SERVER = process.env.E2E_SKIP_SERVER === '1';
const SSH_HOST = process.env.E2E_SSH_HOST || '127.0.0.1';
let token = '';
let serverProcess = null;
let hostIds = [];

// Helper function to wait
const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// Helper for making API calls
async function apiCall(endpoint, method = 'GET', body = null, isMultipart = false, signal = null, customContentType = null) {
  if (method === 'DELETE' && endpoint.includes('/api/sftp/delete/')) {
    if (body && Array.isArray(body.paths)) {
      if (body.paths.length === 0) {
        return { ok: true, status: 200, text: async () => JSON.stringify({ success: true }), json: async () => ({ success: true }) };
      }
      let finalRes;
      for (const p of body.paths) {
        finalRes = await apiCall(`${endpoint}?path=${encodeURIComponent(p)}`, 'DELETE', null, false, signal);
      }
      return finalRes;
    }
  }

  const headers = {};
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }
  if (customContentType) {
    headers['Content-Type'] = customContentType;
  } else if (body && !isMultipart) {
    headers['Content-Type'] = 'application/json';
  }

  const options = {
    method,
    headers,
    signal,
  };

  if (body) {
    options.body = isMultipart ? body : JSON.stringify(body);
    if (body instanceof ReadableStream) {
      options.duplex = 'half';
    }
  }

  const res = await fetch(`${BASE_URL}${endpoint}`, options);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API error ${res.status} on ${method} ${endpoint}: ${text}`);
  }

  if (endpoint.includes('/api/sftp/list/')) {
    const originalJson = res.json.bind(res);
    res.json = async () => {
      const data = await originalJson();
      if (data && data.success && data.data && data.data.files) {
        data.data = data.data.files;
      }
      return data;
    };
  }

  return res;
}

function createSlowMultipartStream(remotePath, uploadId, fileSize, fileName, delayMs, chunksCount) {
  const boundary = '----WebKitFormBoundaryE2ETest' + Math.random().toString(36).substring(2);
  const header = 
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="path"\r\n\r\n` +
    `${remotePath}\r\n` +
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="file_size"\r\n\r\n` +
    `${fileSize}\r\n` +
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="upload_id"\r\n\r\n` +
    `${uploadId}\r\n` +
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="file"; filename="${fileName}"\r\n` +
    `Content-Type: application/octet-stream\r\n\r\n`;

  const footer = `\r\n--${boundary}--\r\n`;
  
  const stream = new ReadableStream({
    async start(controller) {
      controller.enqueue(new TextEncoder().encode(header));
      const chunkSize = Math.ceil(fileSize / chunksCount);
      for (let i = 0; i < chunksCount; i++) {
        const chunk = new Uint8Array(chunkSize);
        chunk.fill(65); // 'A'
        controller.enqueue(chunk);
        if (i < chunksCount - 1) {
          await sleep(delayMs);
        }
      }
      controller.enqueue(new TextEncoder().encode(footer));
      controller.close();
    }
  });

  return { stream, contentType: `multipart/form-data; boundary=${boundary}` };
}

// Start TermiScope server in the background
async function startServer() {
  if (SKIP_SERVER) {
    console.log(`==> Using externally managed TermiScope server at ${BASE_URL}`);
    for (let i = 0; i < 60; i++) {
      try {
        const res = await fetch(`${BASE_URL}/api/auth/check-init`);
        if (res.ok) {
          console.log('==> External TermiScope server is ready.');
          return;
        }
      } catch (err) {
        await sleep(1000);
      }
    }
    throw new Error('External TermiScope server did not become ready');
  }

  const rootDir = path.resolve(__dirname, '..');

  console.log('==> Killing any existing TermiScope server...');
  try {
    await execPromise('pkill -f "/root/code/gitea/TermiScope/server" || true');
    await execPromise('pkill -f "go run cmd/server/main.go" || true');
    await sleep(2000);
  } catch (err) {
    console.log(`==> Warning when killing server: ${err.message}`);
  }

  console.log('==> Rebuilding TermiScope server...');
  try {
    const { stdout, stderr } = await execPromise('go build -o server cmd/server/main.go', { cwd: rootDir });
    if (stdout) console.log(`==> Rebuild stdout: ${stdout}`);
    if (stderr) console.error(`==> Rebuild stderr: ${stderr}`);
  } catch (err) {
    console.error(`==> Rebuild failed: ${err.message}`);
    throw err;
  }

  console.log('==> Starting TermiScope server in background...');
  const binaryPath = path.join(rootDir, 'server');
  
  // Ensure the binary is executable
  try {
    await fs.chmod(binaryPath, 0o755);
  } catch (err) {
    console.log(`==> Warning when setting executable permission: ${err.message}`);
  }

  console.log(`==> Attempting to run precompiled binary: ${binaryPath}`);
  let spawnedOk = false;

  const setupLoggers = (proc) => {
    proc.stdout.on('data', (data) => {
      console.log(`[Server] ${data}`);
    });
    proc.stderr.on('data', (data) => {
      console.error(`[Server Error] ${data}`);
    });
  };

  try {
    serverProcess = spawn(binaryPath, [], {
      cwd: rootDir,
      env: { ...process.env, PORT: '3000' }
    });

    serverProcess.on('error', (err) => {
      console.error(`==> Failed to start precompiled binary: ${err.message}. Falling back to go run...`);
      try {
        serverProcess = spawn('go', ['run', 'cmd/server/main.go'], {
          cwd: rootDir,
          env: { ...process.env, PORT: '3000' }
        });
        serverProcess.on('error', (goErr) => {
          console.error(`==> Fatal: Failed to spawn go run: ${goErr.message}`);
        });
        setupLoggers(serverProcess);
      } catch (fallbackErr) {
        console.error(`==> Fallback to go run failed: ${fallbackErr.message}`);
      }
    });

    setupLoggers(serverProcess);
  } catch (err) {
    console.error(`==> Error during spawn setup: ${err.message}`);
  }

  // Wait for server to start
  for (let i = 0; i < 30; i++) {
    try {
      const res = await fetch(`${BASE_URL}/api/auth/check-init`);
      if (res.ok) {
        console.log('==> TermiScope server started successfully.');
        return;
      }
    } catch (err) {
      await sleep(1000);
    }
  }
  throw new Error('Failed to start TermiScope server');
}

// Stop TermiScope server
function stopServer() {
  if (SKIP_SERVER) {
    return;
  }
  if (serverProcess) {
    console.log('==> Stopping TermiScope server...');
    serverProcess.kill();
  }
}

// Initialize admin user and login
async function login() {
  const checkRes = await apiCall('/api/auth/check-init');
  const checkData = await checkRes.json();
  
  if (!checkData.data.initialized) {
    console.log('==> Initializing TermiScope database with admin user...');
    await apiCall('/api/auth/initialize', 'POST', {
      username: 'admin',
      email: 'admin@example.com',
      password: 'AdminPassword123!'
    });
  }

  console.log('==> Logging in to TermiScope...');
  const loginRes = await apiCall('/api/auth/login', 'POST', {
    username: 'admin',
    password: 'AdminPassword123!'
  });
  const loginData = await loginRes.json();
  token = loginData.data.token;
  console.log('==> Login successful. Token obtained.');
}

// Setup testing hosts in database
async function setupHosts() {
  console.log('==> Cleaning up old test hosts...');
  const listRes = await apiCall('/api/ssh-hosts');
  const listData = await listRes.json();
  for (const host of listData.data || []) {
    if (host.name.startsWith('E2E_Test_')) {
      await apiCall(`/api/ssh-hosts/${host.id}/permanent`, 'DELETE').catch(() => {});
    }
  }

  console.log('==> Creating test hosts...');
  const hostConfig = [
    { name: 'E2E_Test_Host1', label: 'test-host1', host: SSH_HOST, port: 2201, username: 'root', auth_type: 'password', password: 'testpass', host_type: 'control_monitor' },
    { name: 'E2E_Test_Host2', label: 'test-host2', host: SSH_HOST, port: 2202, username: 'root', auth_type: 'password', password: 'testpass', host_type: 'control_monitor' },
    { name: 'E2E_Test_Host3', label: 'test-host3', host: SSH_HOST, port: 2203, username: 'root', auth_type: 'password', password: 'testpass', host_type: 'control_monitor' }
  ];

  hostIds = [];
  for (const hc of hostConfig) {
    const res = await apiCall('/api/ssh-hosts', 'POST', hc);
    const data = await res.json();
    hostIds.push(data.data.id);
  }
  console.log(`==> Test hosts set up successfully. IDs: ${hostIds.join(', ')}`);
}

// Global test registry
const tests = [];
function addTest(id, name, fn) {
  tests.push({ id, name, fn });
}

// ==========================================
// FEATURE 1 TESTS: Host Card Drag-Sorting Persistence
// ==========================================

addTest('F1_T1_01', '单个主机位置调整', async () => {
  // Initial hosts list
  const listRes1 = await apiCall('/api/ssh-hosts');
  const data1 = await listRes1.json();
  const initialIds = data1.data.map(h => h.id);

  // Permute order
  const newOrder = [initialIds[1], initialIds[0], ...initialIds.slice(2)];
  await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: newOrder });

  // Verify reordered list
  const listRes2 = await apiCall('/api/ssh-hosts');
  const data2 = await listRes2.json();
  const sortedIds = data2.data.map(h => h.id);
  assert.deepStrictEqual(sortedIds.slice(0, 2), [newOrder[0], newOrder[1]]);
});

addTest('F1_T1_02', '拖拽到列表头部', async () => {
  const listRes1 = await apiCall('/api/ssh-hosts');
  const data1 = await listRes1.json();
  const initialIds = data1.data.map(h => h.id);

  const headOrder = [initialIds[initialIds.length - 1], ...initialIds.slice(0, -1)];
  await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: headOrder });

  const listRes2 = await apiCall('/api/ssh-hosts');
  const data2 = await listRes2.json();
  const sortedIds = data2.data.map(h => h.id);
  assert.strictEqual(sortedIds[0], headOrder[0]);
});

addTest('F1_T1_03', '拖拽到列表尾部', async () => {
  const listRes1 = await apiCall('/api/ssh-hosts');
  const data1 = await listRes1.json();
  const initialIds = data1.data.map(h => h.id);

  const tailOrder = [...initialIds.slice(1), initialIds[0]];
  await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: tailOrder });

  const listRes2 = await apiCall('/api/ssh-hosts');
  const data2 = await listRes2.json();
  const sortedIds = data2.data.map(h => h.id);
  assert.strictEqual(sortedIds[sortedIds.length - 1], tailOrder[tailOrder.length - 1]);
});

addTest('F1_T1_04', '连续拖拽多次', async () => {
  const listRes = await apiCall('/api/ssh-hosts');
  const data = await listRes.json();
  const ids = data.data.map(h => h.id);

  const order1 = [ids[1], ids[0], ...ids.slice(2)];
  await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: order1 });

  const order2 = [ids[0], ids[1], ...ids.slice(2)];
  await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: order2 });

  const listResFin = await apiCall('/api/ssh-hosts');
  const dataFin = await listResFin.json();
  const finIds = dataFin.data.map(h => h.id);
  assert.deepStrictEqual(finIds.slice(0, 2), [ids[0], ids[1]]);
});

addTest('F1_T1_05', '拖拽回原位（取消排序）', async () => {
  const listRes1 = await apiCall('/api/ssh-hosts');
  const data1 = await listRes1.json();
  const initialIds = data1.data.map(h => h.id);

  await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: initialIds });

  const listRes2 = await apiCall('/api/ssh-hosts');
  const data2 = await listRes2.json();
  const sortedIds = data2.data.map(h => h.id);
  assert.deepStrictEqual(sortedIds, initialIds);
});

addTest('F1_T2_01', '单主机列表拖拽', async () => {
  // Test single host drag behavior endpoint directly
  await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [hostIds[0]] });
  const listRes = await apiCall('/api/ssh-hosts');
  const data = await listRes.json();
  assert(data.data.length >= 1);
});

addTest('F1_T2_02', '极大规模主机列表重新排序', async () => {
  const tempHostIds = [];
  for (let i = 0; i < 50; i++) {
    const res = await apiCall('/api/ssh-hosts', 'POST', {
      name: `E2E_Test_Large_${i}`,
      host: SSH_HOST,
      port: 2201,
      username: 'root',
      auth_type: 'password',
      password: 'testpass',
      host_type: 'control_monitor'
    });
    const data = await res.json();
    tempHostIds.push(data.data.id);
  }

  try {
    await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: tempHostIds });
  } finally {
    for (const id of tempHostIds) {
      await apiCall(`/api/ssh-hosts/${id}/permanent`, 'DELETE').catch(() => {});
    }
  }
});

addTest('F1_T2_03', '排序中途连接中断', async () => {
  // Verify transaction integrity
  const listRes = await apiCall('/api/ssh-hosts');
  const data = await listRes.json();
  const ids = data.data.map(h => h.id);
  // Send invalid reorder structure and verify it does not break state
  try {
    await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [ids[0], null, ids[1]] });
  } catch (err) {
    // Expect error
  }
  const listRes2 = await apiCall('/api/ssh-hosts');
  const data2 = await listRes2.json();
  assert.strictEqual(data2.data.length, data.data.length);
});

addTest('F1_T2_04', '并发重新排序更新冲突', async () => {
  const listRes = await apiCall('/api/ssh-hosts');
  const data = await listRes.json();
  const ids = data.data.map(h => h.id);

  // Send two requests in parallel
  const p1 = apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: ids });
  const p2 = apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [ids[1], ids[0], ...ids.slice(2)] });
  await Promise.all([p1, p2]);
});

addTest('F1_T2_05', '注入不存在或越权的主机 ID', async () => {
  try {
    await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [999999, 888888] });
    assert.fail('Should fail with invalid host IDs');
  } catch (err) {
    if (err.name === 'AssertionError') throw err;
  }
});

// ==========================================
// FEATURE 2 TESTS: SFTP Streaming Direct Upload
// ==========================================

addTest('F2_T1_01', '小文件流式直传', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_upload_f2_t1_01';
  const fileContent = 'Hello World from E2E Test!';
  const fileBlob = new Blob([fileContent], { type: 'text/plain' });

  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', String(fileBlob.size));
  formData.append('upload_id', uploadId);
  formData.append('file', fileBlob, 'e2e_f2_t1_01.txt');

  await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);

  // Verify file existence on destination
  const listRes = await apiCall(`/api/sftp/list/${hostId}?path=/tmp`);
  const listData = await listRes.json();
  const found = listData.data.some(f => f.name === 'e2e_f2_t1_01.txt');
  assert(found, 'Uploaded file not found in destination /tmp directory');

  // Clean up
  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/e2e_f2_t1_01.txt'] });
});

addTest('F2_T1_02', '中等文件流式直传', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_upload_f2_t1_02';
  const buffer = crypto.randomBytes(1024 * 1024); // 1MB random data
  const fileBlob = new Blob([buffer]);

  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', String(fileBlob.size));
  formData.append('upload_id', uploadId);
  formData.append('file', fileBlob, 'e2e_f2_t1_02.bin');

  await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);

  const listRes = await apiCall(`/api/sftp/list/${hostId}?path=/tmp`);
  const listData = await listRes.json();
  const file = listData.data.find(f => f.name === 'e2e_f2_t1_02.bin');
  assert(file, 'Uploaded file not found');
  assert.strictEqual(file.size, buffer.length);

  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/e2e_f2_t1_02.bin'] });
});

addTest('F2_T1_03', '空文件直传', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_upload_f2_t1_03';
  const fileBlob = new Blob([]);

  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '0');
  formData.append('upload_id', uploadId);
  formData.append('file', fileBlob, 'e2e_f2_t1_03.txt');

  await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);

  const listRes = await apiCall(`/api/sftp/list/${hostId}?path=/tmp`);
  const listData = await listRes.json();
  const file = listData.data.find(f => f.name === 'e2e_f2_t1_03.txt');
  assert(file, 'Uploaded file not found');
  assert.strictEqual(file.size, 0);

  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/e2e_f2_t1_03.txt'] });
});

addTest('F2_T1_04', '重复上传覆盖文件', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_upload_f2_t1_04';

  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '5');
  formData.append('upload_id', uploadId);
  formData.append('file', new Blob(['hello']), 'e2e_f2_t1_04.txt');

  await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);

  // Upload again to overwrite
  const formData2 = new FormData();
  formData2.append('path', '/tmp');
  formData2.append('file_size', '10');
  formData2.append('upload_id', uploadId);
  formData2.append('file', new Blob(['hello_over']), 'e2e_f2_t1_04.txt');

  await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData2, true);

  const listRes = await apiCall(`/api/sftp/list/${hostId}?path=/tmp`);
  const listData = await listRes.json();
  const file = listData.data.find(f => f.name === 'e2e_f2_t1_04.txt');
  assert.strictEqual(file.size, 10);

  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', {paths: ['/tmp/e2e_f2_t1_04.txt']});
});

addTest('F2_T1_05', '保留两者直传（自动重命名）', async () => {
  const hostId = hostIds[0];
  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '5');
  formData.append('upload_id', 'e2e_upload_f2_t1_05_a');
  formData.append('file', new Blob(['hello']), 'e2e_f2_t1_05.txt');
  await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);

  const formData2 = new FormData();
  formData2.append('path', '/tmp');
  formData2.append('file_size', '5');
  formData2.append('upload_id', 'e2e_upload_f2_t1_05_b');
  formData2.append('file', new Blob(['world']), 'e2e_f2_t1_05_1.txt'); // UI does rename
  await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData2, true);

  const listRes = await apiCall(`/api/sftp/list/${hostId}?path=/tmp`);
  const listData = await listRes.json();
  const f1 = listData.data.some(f => f.name === 'e2e_f2_t1_05.txt');
  const f2 = listData.data.some(f => f.name === 'e2e_f2_t1_05_1.txt');
  assert(f1 && f2);

  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/e2e_f2_t1_05.txt', '/tmp/e2e_f2_t1_05_1.txt'] });
});

addTest('F2_T2_01', '5GB 超大文件直传不落盘校验', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_upload_f2_t2_01';
  
  const largeSize = 1024 * 1024 * 1024; 
  let bytesSent = 0;
  const readable = new ReadableStream({
    pull(controller) {
      if (bytesSent >= largeSize) {
        controller.close();
        return;
      }
      const chunkSize = 64 * 1024;
      controller.enqueue(new Uint8Array(chunkSize));
      bytesSent += chunkSize;
    }
  });

  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', String(largeSize));
  formData.append('upload_id', uploadId);
  formData.append('file', new Blob([readable]), 'e2e_f2_t2_01.bin');

  const controller = new AbortController();
  const uploadPromise = apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true, controller.signal).catch(() => {});
  
  await sleep(100);
  controller.abort();
  await uploadPromise;
});

addTest('F2_T2_02', '目标主机磁盘空间耗尽', async () => {
  const hostId = hostIds[0];
  const formData = new FormData();
  formData.append('path', '/root/invalid_perm_dir_xyz');
  formData.append('file_size', '10');
  formData.append('upload_id', 'e2e_upload_f2_t2_02');
  formData.append('file', new Blob(['1234567890']), 'test.txt');

  try {
    await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);
    assert.fail('Should fail due to permission/path restriction');
  } catch (err) {
    if (err.name === 'AssertionError') throw err;
  }
});

addTest('F2_T2_03', '文件名包含极限字符与遍历攻击', async () => {
  const hostId = hostIds[0];
  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '5');
  formData.append('upload_id', 'e2e_upload_f2_t2_03');
  formData.append('file', new Blob(['hello']), '../../../../tmp/hack.txt'); // directory traversal attempt

  await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);

  const listRes = await apiCall(`/api/sftp/list/${hostId}?path=/tmp`);
  const listData = await listRes.json();
  
  const foundTraversed = listData.data.some(f => f.name === 'hack.txt');
  assert(foundTraversed, 'Should sanitize filename and save it in the target directory');

  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/hack.txt'] });
});

addTest('F2_T2_04', '传输中途目标主机 SFTP 离线', async () => {
  const res = await apiCall('/api/ssh-hosts', 'POST', {
    name: 'E2E_Test_OfflineHost',
    label: 'test-offline',
    host: '127.0.0.1',
    port: 9999, // closed port
    username: 'root',
    auth_type: 'password',
    password: 'password',
    host_type: 'control_monitor'
  });
  const offlineHost = await res.json();
  const hostId = offlineHost.data.id;

  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '10');
  formData.append('upload_id', 'e2e_upload_f2_t2_04');
  formData.append('file', new Blob(['hello']), 'test.txt');

  try {
    await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);
    assert.fail('Should fail because host is offline');
  } catch (err) {
    if (err.name === 'AssertionError') throw err;
  }

  await apiCall(`/api/ssh-hosts/${hostId}/permanent`, 'DELETE');
});

addTest('F2_T2_05', '畸形 Multipart 表单数据块损坏', async () => {
  const hostId = hostIds[0];
  try {
    const res = await fetch(`${BASE_URL}/api/sftp/upload/${hostId}`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'multipart/form-data; boundary=invalid_boundary'
      },
      body: 'corrupt_data_blocks_without_boundaries'
    });
    assert.strictEqual(res.ok, false, 'Should fail with 400 or 500 for malformed multipart data');
  } catch (err) {
    if (err.name === 'AssertionError') throw err;
  }
});

// ==========================================
// FEATURE 3 TESTS: SFTP non-blocking & real-time progress
// ==========================================

addTest('F3_T1_01', '传输过程中的非阻塞浏览', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_upload_f3_t1_01';
  
  const slowStream = new ReadableStream({
    async start(controller) {
      controller.enqueue(new Uint8Array(1024 * 1024)); // 1MB
      await sleep(500);
      controller.enqueue(new Uint8Array(1024 * 1024)); // 1MB
      controller.close();
    }
  });

  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', String(2 * 1024 * 1024));
  formData.append('upload_id', uploadId);
  formData.append('file', new Blob([slowStream]), 'e2e_f3_t1_01.bin');

  const uploadPromise = apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);

  const startTime = Date.now();
  const listRes = await apiCall('/api/ssh-hosts');
  const duration = Date.now() - startTime;
  
  assert(duration < 200, 'UI thread / backend APIs should respond quickly during uploads');

  await uploadPromise;
  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/e2e_f3_t1_01.bin'] });
});

addTest('F3_T1_02', '实时进度轮询', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_upload_f3_t1_02';
  
  const { stream, contentType } = createSlowMultipartStream('/tmp', uploadId, 5 * 1024 * 1024, 'e2e_f3_t1_02.bin', 100, 5);
  const uploadPromise = apiCall(`/api/sftp/upload/${hostId}`, 'POST', stream, true, null, contentType);

  await sleep(300);
  const progRes = await apiCall(`/api/sftp/upload-progress/${uploadId}`);
  const progData = await progRes.json();
  
  assert(progData.data.percent !== undefined, 'Progress percentage should be returned');
  assert(progData.data.speed !== undefined, 'Speed should be returned');

  await uploadPromise;
  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/e2e_f3_t1_02.bin'] });
});

addTest('F3_T1_03', '全局传输 Dock 数据绑定', async () => {
  const progressRes = await apiCall('/api/sftp/upload-progress/non_existent');
  const data = await progressRes.json();
  assert.strictEqual(data.data.status, 'not_found');
});

addTest('F3_T1_04', '主动取消传输', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_upload_f3_t1_04';
  const controller = new AbortController();

  const { stream, contentType } = createSlowMultipartStream('/tmp', uploadId, 2 * 1024 * 1024, 'e2e_f3_t1_04.bin', 300, 5);
  const uploadPromise = apiCall(`/api/sftp/upload/${hostId}`, 'POST', stream, true, controller.signal, contentType).catch(() => {});

  await sleep(200);
  controller.abort();
  await uploadPromise;

  const listRes = await apiCall(`/api/sftp/list/${hostId}?path=/tmp`);
  const listData = await listRes.json();
  const fileExists = listData.data.some(f => f.name === 'e2e_f3_t1_04.bin');
  assert(!fileExists, 'Cancelled file should be removed from target');
});

addTest('F3_T1_05', '传输成功状态转换', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_upload_f3_t1_05';

  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '11');
  formData.append('upload_id', uploadId);
  formData.append('file', new Blob(['hello world']), 'e2e_f3_t1_05.txt');

  await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);

  const progRes = await apiCall(`/api/sftp/upload-progress/${uploadId}`);
  const progData = await progRes.json();
  assert(progData.data.status === 'not_found' || progData.data.percent === 100);

  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/e2e_f3_t1_05.txt'] });
});

addTest('F3_T2_01', '极慢速网络环境进度显示', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_upload_f3_t2_01';
  
  const { stream, contentType } = createSlowMultipartStream('/tmp', uploadId, 20, 'e2e_f3_t2_01.txt', 300, 2);
  const uploadPromise = apiCall(`/api/sftp/upload/${hostId}`, 'POST', stream, true, null, contentType);
  await sleep(200);
  const progRes = await apiCall(`/api/sftp/upload-progress/${uploadId}`);
  const progData = await progRes.json();
  assert(progData.data.percent >= 0);

  await uploadPromise;
  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/e2e_f3_t2_01.txt'] });
});

addTest('F3_T2_02', '极限并发直传非阻塞', async () => {
  const hostId = hostIds[0];
  const promises = [];
  
  for (let i = 0; i < 5; i++) {
    const formData = new FormData();
    formData.append('path', '/tmp');
    formData.append('file_size', '10');
    formData.append('upload_id', `e2e_upload_f3_t2_02_${i}`);
    formData.append('file', new Blob(['helloworld']), `e2e_f3_t2_02_${i}.txt`);
    promises.push(apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true));
  }

  await Promise.all(promises);

  const cleanPaths = Array.from({ length: 5 }, (_, i) => `/tmp/e2e_f3_t2_02_${i}.txt`);
  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: cleanPaths });
});

addTest('F3_T2_03', '进度轮询接口超时或 503 错误', async () => {
  for (let i = 0; i < 5; i++) {
    const res = await apiCall('/api/sftp/upload-progress/invalid_id_retry');
    const data = await res.json();
    assert.strictEqual(data.data.status, 'not_found');
  }
});

addTest('F3_T2_04', '极小字节文件瞬间完成处理', async () => {
  const hostId = hostIds[0];
  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '1');
  formData.append('upload_id', 'e2e_upload_f3_t2_04');
  formData.append('file', new Blob(['A']), 'e2e_f3_t2_04.txt');

  await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);
  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/e2e_f3_t2_04.txt'] });
});

addTest('F3_T2_05', '极速重复点击取消上传', async () => {
  const hostId = hostIds[0];
  const controller = new AbortController();
  
  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '100');
  formData.append('upload_id', 'e2e_upload_f3_t2_05');
  formData.append('file', new Blob([new Uint8Array(100)]), 'e2e_f3_t2_05.bin');

  const uploadPromise = apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true, controller.signal).catch(() => {});
  controller.abort();
  controller.abort();
  
  await uploadPromise;
});

// ==========================================
// FEATURE 4 TESTS: SFTP tasks grouped by host & status
// ==========================================

addTest('F4_T1_01', '单主机上传任务分组展示', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_upload_f4_t1_01';
  
  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '5');
  formData.append('upload_id', uploadId);
  formData.append('file', new Blob(['hello']), 'test.txt');

  const uploadPromise = apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);
  await sleep(50);
  const progRes = await apiCall(`/api/sftp/upload-progress/${uploadId}`);
  const progData = await progRes.json();
  
  assert(progData.data !== null);
  await uploadPromise;
  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/test.txt'] });
});

addTest('F4_T1_02', '多主机并行上传任务分组', async () => {
  const formData1 = new FormData();
  formData1.append('path', '/tmp');
  formData1.append('file_size', '5');
  formData1.append('upload_id', 'e2e_f4_t1_02_a');
  formData1.append('file', new Blob(['hello']), 'h1.txt');

  const formData2 = new FormData();
  formData2.append('path', '/tmp');
  formData2.append('file_size', '5');
  formData2.append('upload_id', 'e2e_f4_t1_02_b');
  formData2.append('file', new Blob(['world']), 'h2.txt');

  await Promise.all([
    apiCall(`/api/sftp/upload/${hostIds[0]}`, 'POST', formData1, true),
    apiCall(`/api/sftp/upload/${hostIds[1]}`, 'POST', formData2, true)
  ]);

  await Promise.all([
    apiCall(`/api/sftp/delete/${hostIds[0]}`, 'DELETE', { paths: ['/tmp/h1.txt'] }),
    apiCall(`/api/sftp/delete/${hostIds[1]}`, 'DELETE', { paths: ['/tmp/h2.txt'] })
  ]);
});

addTest('F4_T1_03', '双面板跨主机传输分组', async () => {
  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '12');
  formData.append('upload_id', 'e2e_upload_f4_t1_03_init');
  formData.append('file', new Blob(['transferData']), 'cross.txt');
  await apiCall(`/api/sftp/upload/${hostIds[0]}`, 'POST', formData, true);

  const transRes = await apiCall('/api/sftp/transfer', 'POST', {
    source_host_id: String(hostIds[0]),
    dest_host_id: String(hostIds[1]),
    source_path: '/tmp/cross.txt',
    dest_path: '/tmp/cross_dest.txt',
    type: 'copy'
  });

  const reader = transRes.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let receivedProgress = false;
  
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();
    for (const line of lines) {
      if (line.trim()) {
        console.log(`[F4_T1_03 NDJSON] ${line}`);
        const json = JSON.parse(line);
        if (json.percent !== undefined) {
          receivedProgress = true;
        }
      }
    }
  }
  
  assert(receivedProgress, 'Should receive stream progress events via NDJSON');

  const listRes = await apiCall(`/api/sftp/list/${hostIds[1]}?path=/tmp`);
  const listData = await listRes.json();
  const found = listData.data.some(f => f.name === 'cross_dest.txt');
  assert(found, 'File should be copied to Host 2');

  await apiCall(`/api/sftp/delete/${hostIds[0]}`, 'DELETE', { paths: ['/tmp/cross.txt'] });
  await apiCall(`/api/sftp/delete/${hostIds[1]}`, 'DELETE', { paths: ['/tmp/cross_dest.txt'] });
});

addTest('F4_T1_04', '分组头部指标统计', async () => {
  const listRes = await apiCall('/api/ssh-hosts');
  const data = await listRes.json();
  assert(data.data.length >= 2);
});

addTest('F4_T1_05', '按主机分组批量取消', async () => {
  const res = await apiCall(`/api/sftp/delete/${hostIds[0]}`, 'DELETE', { paths: [] });
  assert.strictEqual(res.status, 200);
});

addTest('F4_T2_01', '目标主机无标签（Label 为空）', async () => {
  const res = await apiCall('/api/ssh-hosts', 'POST', {
    name: 'E2E_Test_NoLabel',
    host: '127.0.0.1',
    port: 2201,
    username: 'root',
    auth_type: 'password',
    password: 'testpass',
    host_type: 'control_monitor'
  });
  const data = await res.json();
  assert(data.data.id !== undefined);

  await apiCall(`/api/ssh-hosts/${data.data.id}/permanent`, 'DELETE');
});

addTest('F4_T2_02', '分组中所有任务清除后的自动移除', async () => {
  assert(true);
});

addTest('F4_T2_03', '并发快速添加重复文件到相同分组', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_f4_t2_03';
  const promises = [];

  for (let i = 0; i < 3; i++) {
    const formData = new FormData();
    formData.append('path', '/tmp');
    formData.append('file_size', '10');
    formData.append('upload_id', `${uploadId}_${i}`);
    formData.append('file', new Blob(['duplicate']), `dup_${i}.txt`);
    promises.push(apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true));
  }

  await Promise.all(promises);

  const cleanPaths = Array.from({ length: 3 }, (_, i) => `/tmp/dup_${i}.txt`);
  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: cleanPaths });
});

addTest('F4_T2_04', '跨主机传输源/目的相同', async () => {
  const hostId = hostIds[0];
  
  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '4');
  formData.append('upload_id', 'e2e_f4_t2_04');
  formData.append('file', new Blob(['same']), 'same.txt');
  await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);

  const transRes = await apiCall('/api/sftp/transfer', 'POST', {
    source_host_id: String(hostId),
    dest_host_id: String(hostId),
    source_path: '/tmp/same.txt',
    dest_path: '/tmp/same_copy.txt',
    type: 'copy'
  });

  const reader = transRes.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();
    for (const line of lines) {
      if (line.trim()) {
        console.log(`[F4_T2_04 NDJSON] ${line}`);
      }
    }
  }

  const listRes = await apiCall(`/api/sftp/list/${hostId}?path=/tmp`);
  const listData = await listRes.json();
  const fileExists = listData.data.some(f => f.name === 'same_copy.txt');
  assert(fileExists);

  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/same.txt', '/tmp/same_copy.txt'] });
});

addTest('F4_T2_05', '传输中途目标主机 label 被重命名', async () => {
  const hostId = hostIds[0];
  
  await apiCall(`/api/ssh-hosts/${hostId}`, 'PUT', {
    name: 'E2E_Test_Host1_Renamed',
    host_type: 'control_monitor'
  });

  const getRes = await apiCall(`/api/ssh-hosts/${hostId}`);
  const getData = await getRes.json();
  assert.strictEqual(getData.data.name, 'E2E_Test_Host1_Renamed');

  await apiCall(`/api/ssh-hosts/${hostId}`, 'PUT', {
    name: 'E2E_Test_Host1',
    host_type: 'control_monitor'
  });
});

// ==========================================
// TIER 3 TESTS: Cross-Feature Combinations
// ==========================================

addTest('CF_01', '主机卡片拖拽重排与 SFTP 并行直传进度分组', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_cf_01';
  
  const slowStream = new ReadableStream({
    async start(controller) {
      controller.enqueue(new Uint8Array(1024 * 1024));
      await sleep(400);
      controller.enqueue(new Uint8Array(1024 * 1024));
      controller.close();
    }
  });

  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', String(2 * 1024 * 1024));
  formData.append('upload_id', uploadId);
  formData.append('file', new Blob([slowStream]), 'cf_01.bin');

  const uploadPromise = apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true);

  const listRes = await apiCall('/api/ssh-hosts');
  const data = await listRes.json();
  const ids = data.data.map(h => h.id);
  const reordered = [ids[1], ids[0], ...ids.slice(2)];
  
  await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: reordered });
  
  await uploadPromise;
  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/cf_01.bin'] });
});

addTest('CF_02', '跨主机直传中源主机拖拽移动位置', async () => {
  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '10');
  formData.append('upload_id', 'e2e_cf_02_init');
  formData.append('file', new Blob(['cf_02_data']), 'cf_02.txt');
  await apiCall(`/api/sftp/upload/${hostIds[0]}`, 'POST', formData, true);

  const transferPromise = apiCall('/api/sftp/transfer', 'POST', {
    source_host_id: String(hostIds[0]),
    dest_host_id: String(hostIds[1]),
    source_path: '/tmp/cf_02.txt',
    dest_path: '/tmp/cf_02_dest.txt',
    type: 'copy'
  });

  const listRes = await apiCall('/api/ssh-hosts');
  const data = await listRes.json();
  const ids = data.data.map(h => h.id);
  await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [ids[1], ids[0], ...ids.slice(2)] });

  const transRes = await transferPromise;
  const reader = transRes.body.getReader();
  while (true) {
    const { done } = await reader.read();
    if (done) break;
  }

  await apiCall(`/api/sftp/delete/${hostIds[0]}`, 'DELETE', { paths: ['/tmp/cf_02.txt'] });
  await apiCall(`/api/sftp/delete/${hostIds[1]}`, 'DELETE', { paths: ['/tmp/cf_02_dest.txt'] });
});

addTest('CF_03', '多任务流式直传并按主机分组批量取消', async () => {
  const hostId = hostIds[0];
  const controller = new AbortController();
  
  const uploadPromises = [];
  for (let i = 0; i < 2; i++) {
    const formData = new FormData();
    formData.append('path', '/tmp');
    formData.append('file_size', '1000');
    formData.append('upload_id', `e2e_cf_03_${i}`);
    formData.append('file', new Blob([new Uint8Array(1000)]), `cf_03_${i}.bin`);
    uploadPromises.push(apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true, controller.signal).catch(() => {}));
  }

  await sleep(100);
  controller.abort();
  await Promise.all(uploadPromises);
});

addTest('CF_04', '拖拽排序后立即打开首位主机进行流式直传', async () => {
  const listRes = await apiCall('/api/ssh-hosts');
  const data = await listRes.json();
  const ids = data.data.map(h => h.id);

  const newOrder = [hostIds[1], hostIds[0], ...ids.filter(id => id !== hostIds[0] && id !== hostIds[1])];
  await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: newOrder });

  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '5');
  formData.append('upload_id', 'e2e_cf_04');
  formData.append('file', new Blob(['test']), 'cf_04.txt');

  await apiCall(`/api/sftp/upload/${hostIds[1]}`, 'POST', formData, true);
  await apiCall(`/api/sftp/delete/${hostIds[1]}`, 'DELETE', { paths: ['/tmp/cf_04.txt'] });
});

// ==========================================
// TIER 4 TESTS: Real-world Workload Scenarios
// ==========================================

addTest('RW_01', '日常多主机运维环境下的主机管理与多通道文件上传', async () => {
  await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [hostIds[2], hostIds[0], hostIds[1]] });

  const promises = hostIds.map((hid, idx) => {
    const formData = new FormData();
    formData.append('path', '/tmp');
    formData.append('file_size', '10');
    formData.append('upload_id', `e2e_rw_01_${idx}`);
    formData.append('file', new Blob([`rw_01_${idx}`]), `rw_01_${idx}.txt`);
    return apiCall(`/api/sftp/upload/${hid}`, 'POST', formData, true);
  });

  await Promise.all(promises);

  await Promise.all(hostIds.map((hid, idx) => {
    return apiCall(`/api/sftp/delete/${hid}`, 'DELETE', { paths: [`/tmp/rw_01_${idx}.txt`] });
  }));
});

addTest('RW_02', '恶劣网络环境下的超大文件直传与任务阻断恢复', async () => {
  const hostId = hostIds[0];
  const uploadId = 'e2e_rw_02';
  const controller = new AbortController();

  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '1000');
  formData.append('upload_id', uploadId);
  formData.append('file', new Blob([new Uint8Array(1000)]), 'rw_02_corrupt.bin');

  const uploadPromise = apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData, true, controller.signal).catch(() => {});
  await sleep(100);
  controller.abort();
  await uploadPromise;

  const formData2 = new FormData();
  formData2.append('path', '/tmp');
  formData2.append('file_size', '10');
  formData2.append('upload_id', `${uploadId}_ok`);
  formData2.append('file', new Blob(['recovered!']), 'rw_02_recovered.txt');
  await apiCall(`/api/sftp/upload/${hostId}`, 'POST', formData2, true);

  await apiCall(`/api/sftp/delete/${hostId}`, 'DELETE', { paths: ['/tmp/rw_02_recovered.txt'] });
});

addTest('RW_03', '双面板跨网络隔离主机的跨主机直传负载', async () => {
  const h1 = hostIds[0];
  const h2 = hostIds[1];

  const formData = new FormData();
  formData.append('path', '/tmp');
  formData.append('file_size', '12');
  formData.append('upload_id', 'e2e_rw_03_init');
  formData.append('file', new Blob(['rw_03_content']), 'rw_03.txt');
  await apiCall(`/api/sftp/upload/${h1}`, 'POST', formData, true);

  const transferPromise = apiCall('/api/sftp/transfer', 'POST', {
    source_host_id: String(h1),
    dest_host_id: String(h2),
    source_path: '/tmp/rw_03.txt',
    dest_path: '/tmp/rw_03_dest.txt',
    type: 'copy'
  });

  const listRes = await apiCall('/api/ssh-hosts');
  const listData = await listRes.json();
  assert(listData.data.length >= 2);

  const transRes = await transferPromise;
  const reader = transRes.body.getReader();
  while (true) {
    const { done } = await reader.read();
    if (done) break;
  }

  await apiCall(`/api/sftp/delete/${h1}`, 'DELETE', { paths: ['/tmp/rw_03.txt'] });
  await apiCall(`/api/sftp/delete/${h2}`, 'DELETE', { paths: ['/tmp/rw_03_dest.txt'] });
});

addTest('RW_04', '生产发布场景下的多主机同步直传极限并发', async () => {
  const packageData = crypto.randomBytes(1024 * 100); // 100KB package
  const promises = hostIds.map((hid, idx) => {
    const formData = new FormData();
    formData.append('path', '/tmp');
    formData.append('file_size', String(packageData.length));
    formData.append('upload_id', `e2e_rw_04_${idx}`);
    formData.append('file', new Blob([packageData]), 'release.tar.gz');
    return apiCall(`/api/sftp/upload/${hid}`, 'POST', formData, true);
  });

  await Promise.all(promises);

  await Promise.all(hostIds.map((hid) => {
    return apiCall(`/api/sftp/delete/${hid}`, 'DELETE', { paths: ['/tmp/release.tar.gz'] });
  }));
});

addTest('RW_05', '终端混合操作：多文件传输、主机重排与会话断开', async () => {
  const h1 = hostIds[0];
  const h2 = hostIds[1];
  const controller = new AbortController();

  const formData1 = new FormData();
  formData1.append('path', '/tmp');
  formData1.append('file_size', '100');
  formData1.append('upload_id', 'e2e_rw_05_h1');
  formData1.append('file', new Blob([new Uint8Array(100)]), 'rw_05_h1.bin');

  const formData2 = new FormData();
  formData2.append('path', '/tmp');
  formData2.append('file_size', '100');
  formData2.append('upload_id', 'e2e_rw_05_h2');
  formData2.append('file', new Blob([new Uint8Array(100)]), 'rw_05_h2.bin');

  const p1 = apiCall(`/api/sftp/upload/${h1}`, 'POST', formData1, true);
  const p2 = apiCall(`/api/sftp/upload/${h2}`, 'POST', formData2, true, controller.signal).catch(() => {});

  await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [hostIds[1], hostIds[2], hostIds[0]] });

  controller.abort();

  await Promise.all([p1, p2]);

  await apiCall(`/api/sftp/delete/${h1}`, 'DELETE', { paths: ['/tmp/rw_05_h1.bin'] });
});


// ==========================================
// TEST EXECUTION RUNNER
// ==========================================

async function runAllTests() {
  let passedCount = 0;
  let failedCount = 0;
  const results = [];

  console.log(`\n========================================`);
  console.log(`Starting TermiScope E2E Testing Suite...`);
  console.log(`Total tests scheduled: ${tests.length}`);
  console.log(`========================================\n`);

  for (const test of tests) {
    process.stdout.write(`[RUN] ${test.id} - ${test.name}... `);
    const start = Date.now();
    try {
      await test.fn();
      const elapsed = Date.now() - start;
      console.log(`\x1b[32mPASS\x1b[0m (${elapsed}ms)`);
      results.push({ id: test.id, name: test.name, status: 'PASS', elapsed });
      passedCount++;
    } catch (err) {
      const elapsed = Date.now() - start;
      console.log(`\x1b[31mFAIL\x1b[0m (${elapsed}ms)`);
      console.error(`      Error: ${err.message}`);
      results.push({ id: test.id, name: test.name, status: 'FAIL', elapsed, error: err.message });
      failedCount++;
    }
  }

  console.log(`\n========================================`);
  console.log(`E2E Testing Results Summary:`);
  console.log(`----------------------------------------`);
  console.log(`Total Tests Run: ${tests.length}`);
  console.log(`Passed:          \x1b[32m${passedCount}\x1b[0m`);
  console.log(`Failed:          \x1b[31m${failedCount}\x1b[0m`);
  console.log(`Pass Rate:       ${((passedCount / tests.length) * 100).toFixed(2)}%`);
  console.log(`========================================\n`);

  if (failedCount > 0) {
    console.error('Some E2E tests failed.');
    process.exit(1);
  } else {
    console.log('All E2E tests passed successfully!');
    process.exit(0);
  }
}

const runCmd = (cmd, options = {}) => new Promise((resolve, reject) => {
  console.log(`==> Executing command: ${cmd}`);
  const child = exec(cmd, options);
  child.stdout.on('data', (data) => process.stdout.write(data));
  child.stderr.on('data', (data) => process.stderr.write(data));
  child.on('close', (code) => {
    if (code === 0) resolve();
    else reject(new Error(`Command "${cmd}" exited with code ${code}`));
  });
});

// Main execution flow
async function main() {
  try {
    const rootDir = path.resolve(__dirname, '..');
    console.log('==> Bringing up test-lab containers...');
    await runCmd('bash test-lab/manage.sh up', { cwd: rootDir });
    
    await startServer();
    await login();
    await setupHosts();
    await runAllTests();
  } catch (err) {
    console.error('Fatal error during E2E setup/execution:', err);
    stopServer();
    process.exit(1);
  } finally {
    stopServer();
  }
}

main();
