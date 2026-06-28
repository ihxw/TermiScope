import assert from 'node:assert';
import { spawn, exec } from 'node:child_process';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const execPromise = promisify(exec);
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const BASE_URL = 'http://localhost:3000';
let adminToken = '';
let userToken = '';
let serverProcess = null;

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

async function apiCall(endpoint, method = 'GET', body = null, token = '') {
  const headers = {};
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }
  if (body) {
    headers['Content-Type'] = 'application/json';
  }

  const options = {
    method,
    headers,
  };

  if (body) {
    options.body = JSON.stringify(body);
  }

  const res = await fetch(`${BASE_URL}${endpoint}`, options);
  return res;
}

// Start TermiScope server
async function startServer() {
  const rootDir = path.resolve(__dirname, '..');
  console.log('==> Killing existing TermiScope servers...');
  try {
    await execPromise('pkill -f "/root/code/gitea/TermiScope/server" || true');
    await execPromise('pkill -f "go run cmd/server/main.go" || true');
    await sleep(2000);
  } catch (err) {
    console.log(`==> Warning when killing server: ${err.message}`);
  }

  console.log('==> Building TermiScope server...');
  await execPromise('go build -o server cmd/server/main.go', { cwd: rootDir });

  console.log('==> Starting TermiScope server on port 3000...');
  const binaryPath = path.join(rootDir, 'server');
  serverProcess = spawn(binaryPath, [], {
    cwd: rootDir,
    env: { ...process.env, PORT: '3000' }
  });

  serverProcess.stdout.on('data', (data) => {
    // console.log(`[Server] ${data}`);
  });
  serverProcess.stderr.on('data', (data) => {
    // console.error(`[Server Error] ${data}`);
  });

  for (let i = 0; i < 20; i++) {
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
  throw new Error('Failed to start server');
}

function stopServer() {
  if (serverProcess) {
    console.log('==> Stopping TermiScope server...');
    serverProcess.kill();
  }
}

async function runTests() {
  await startServer();

  try {
    // 1. Initial login / setup
    const checkRes = await apiCall('/api/auth/check-init');
    const checkData = await checkRes.json();
    if (!checkData.data.initialized) {
      await apiCall('/api/auth/initialize', 'POST', {
        username: 'admin',
        email: 'admin@example.com',
        password: 'AdminPassword123!'
      });
    }

    const loginRes = await apiCall('/api/auth/login', 'POST', {
      username: 'admin',
      password: 'AdminPassword123!'
    });
    const loginData = await loginRes.json();
    adminToken = loginData.data.token;
    console.log('==> Logged in as admin.');

    // Delete existing adversarial hosts
    const listRes = await apiCall('/api/ssh-hosts', 'GET', null, adminToken);
    const listData = await listRes.json();
    for (const h of listData.data || []) {
      if (h.name.startsWith('ADV_')) {
        await apiCall(`/api/ssh-hosts/${h.id}/permanent`, 'DELETE', null, adminToken);
      }
    }

    // Create a secondary user for cross-user tests
    const userCreateRes = await apiCall('/api/users', 'POST', {
      username: 'advuser',
      email: 'advuser@example.com',
      password: 'AdvUserPassword123!',
      display_name: 'Adversarial User',
      role: 'user'
    }, adminToken);
    
    if (userCreateRes.status === 409) {
      console.log('==> Secondary user already exists.');
    } else {
      assert.strictEqual(userCreateRes.status, 201);
      console.log('==> Created secondary user.');
    }

    // Login as secondary user
    const userLoginRes = await apiCall('/api/auth/login', 'POST', {
      username: 'advuser',
      password: 'AdvUserPassword123!'
    });
    assert.strictEqual(userLoginRes.status, 200);
    const userLoginData = await userLoginRes.json();
    userToken = userLoginData.data.token;
    console.log('==> Logged in as secondary user.');

    // Delete existing adversarial hosts for secondary user
    const userListRes = await apiCall('/api/ssh-hosts', 'GET', null, userToken);
    const userListData = await userListRes.json();
    for (const h of userListData.data || []) {
      if (h.name.startsWith('ADV_')) {
        await apiCall(`/api/ssh-hosts/${h.id}/permanent`, 'DELETE', null, userToken);
      }
    }

    // Create 3 hosts for Admin
    const adminHosts = [];
    for (let i = 1; i <= 3; i++) {
      const res = await apiCall('/api/ssh-hosts', 'POST', {
        name: `ADV_Admin_Host${i}`,
        host: '127.0.0.1',
        port: 2200 + i,
        username: 'root',
        auth_type: 'password',
        password: 'testpassword',
        host_type: 'control_monitor'
      }, adminToken);
      assert.strictEqual(res.status, 200);
      const data = await res.json();
      adminHosts.push(data.data);
    }
    const adminHostIds = adminHosts.map(h => h.id);
    console.log('==> Created admin test hosts:', adminHostIds);

    // Create 2 hosts for Secondary User
    const userHosts = [];
    for (let i = 1; i <= 2; i++) {
      const res = await apiCall('/api/ssh-hosts', 'POST', {
        name: `ADV_User_Host${i}`,
        host: '127.0.0.1',
        port: 2300 + i,
        username: 'root',
        auth_type: 'password',
        password: 'testpassword',
        host_type: 'control_monitor'
      }, userToken);
      assert.strictEqual(res.status, 200);
      const data = await res.json();
      userHosts.push(data.data);
    }
    const userHostIds = userHosts.map(h => h.id);
    console.log('==> Created user test hosts:', userHostIds);

    // ============================================
    // TEST 1: Normal Reorder (PascalCase DeviceIds)
    // ============================================
    console.log('\n[Test 1] Testing normal reorder with PascalCase DeviceIds...');
    const reorder1 = [adminHostIds[1], adminHostIds[0], adminHostIds[2]];
    const res1 = await apiCall('/api/ssh-hosts/reorder', 'PUT', { DeviceIds: reorder1 }, adminToken);
    assert.strictEqual(res1.status, 200);
    const getRes1 = await apiCall('/api/ssh-hosts', 'GET', null, adminToken);
    const getData1 = await getRes1.json();
    const sortedIds1 = getData1.data.filter(h => h.name.startsWith('ADV_')).map(h => h.id);
    assert.deepStrictEqual(sortedIds1, reorder1);
    console.log('  PASS: Reordered successfully using DeviceIds.');

    // ============================================
    // TEST 2: Normal Reorder (snake_case device_ids)
    // ============================================
    console.log('\n[Test 2] Testing normal reorder with snake_case device_ids...');
    const reorder2 = [adminHostIds[2], adminHostIds[1], adminHostIds[0]];
    const res2 = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: reorder2 }, adminToken);
    assert.strictEqual(res2.status, 200);
    const getRes2 = await apiCall('/api/ssh-hosts', 'GET', null, adminToken);
    const getData2 = await getRes2.json();
    const sortedIds2 = getData2.data.filter(h => h.name.startsWith('ADV_')).map(h => h.id);
    assert.deepStrictEqual(sortedIds2, reorder2);
    console.log('  PASS: Reordered successfully using device_ids.');

    // ============================================
    // TEST 3: Empty Array
    // ============================================
    console.log('\n[Test 3] Testing empty device_ids array...');
    const res3 = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [] }, adminToken);
    assert.strictEqual(res3.status, 400);
    const err3 = await res3.json();
    assert.ok(err3.message.includes('cannot be empty'));
    console.log('  PASS: Rejected empty array with 400 Bad Request.');

    // ============================================
    // TEST 4: Negative Host IDs
    // ============================================
    console.log('\n[Test 4] Testing negative host IDs...');
    const res4 = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [-1, adminHostIds[0]] }, adminToken);
    assert.strictEqual(res4.status, 400);
    console.log('  PASS: Rejected negative ID with 400 Bad Request.');

    // ============================================
    // TEST 5: Large non-existent ID (within uint scope)
    // ============================================
    console.log('\n[Test 5] Testing non-existent large ID...');
    const res5 = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [9999999, adminHostIds[0]] }, adminToken);
    assert.strictEqual(res5.status, 403);
    const err5 = await res5.json();
    assert.ok(err5.message.includes('invalid or unauthorized host ID'));
    console.log('  PASS: Rejected non-existent ID with 403 Forbidden.');

    // ============================================
    // TEST 6: Extremely large ID overflowing uint64
    // ============================================
    console.log('\n[Test 6] Testing overflowing large ID...');
    const res6 = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [99999999999999999999999999999999n] }, adminToken);
    assert.strictEqual(res6.status, 400);
    console.log('  PASS: Rejected overflowing ID with 400 Bad Request.');

    // ============================================
    // TEST 7: Floating-point ID
    // ============================================
    console.log('\n[Test 7] Testing floating-point ID...');
    const res7 = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [adminHostIds[0], 2.5] }, adminToken);
    assert.strictEqual(res7.status, 400);
    console.log('  PASS: Rejected floating-point ID with 400 Bad Request.');

    // ============================================
    // TEST 8: Unauthorized host ID (Cross-User Access)
    // ============================================
    console.log('\n[Test 8] Testing unauthorized host ID (cross-user access)...');
    // Admin trying to order including User's Host
    const res8a = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [adminHostIds[0], userHostIds[0]] }, adminToken);
    assert.strictEqual(res8a.status, 403);
    
    // User trying to order including Admin's Host
    const res8b = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [userHostIds[0], adminHostIds[0]] }, userToken);
    assert.strictEqual(res8b.status, 403);
    console.log('  PASS: Rejected unauthorized host ID with 403 Forbidden.');

    // ============================================
    // TEST 9: Duplicate host IDs in request
    // ============================================
    console.log('\n[Test 9] Testing duplicate host IDs in request...');
    const res9 = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [adminHostIds[0], adminHostIds[0], adminHostIds[1]] }, adminToken);
    assert.strictEqual(res9.status, 200);
    const getRes9 = await apiCall('/api/ssh-hosts', 'GET', null, adminToken);
    const getData9 = await getRes9.json();
    const advHosts9 = getData9.data.filter(h => h.name.startsWith('ADV_'));
    console.log('  Updated sort_orders in DB:');
    advHosts9.forEach(h => console.log(`    Host ID ${h.id}: sort_order = ${h.sort_order}`));
    console.log('  PASS: Handled duplicates successfully.');

    // ============================================
    // TEST 10: Null inside array
    // ============================================
    console.log('\n[Test 10] Testing null value inside array...');
    const res10 = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [adminHostIds[0], null, adminHostIds[1]] }, adminToken);
    assert.strictEqual(res10.status, 400);
    console.log('  PASS: Rejected null value in array with 400 Bad Request.');

    // ============================================
    // TEST 11: Concurrent Updates / Race Conditions
    // ============================================
    console.log('\n[Test 11] Testing concurrent updates/race conditions...');
    const concurrentRequests = [];
    const count = 50;
    for (let i = 0; i < count; i++) {
      const order = i % 2 === 0 
        ? [adminHostIds[0], adminHostIds[1], adminHostIds[2]]
        : [adminHostIds[2], adminHostIds[1], adminHostIds[0]];
      concurrentRequests.push(apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: order }, adminToken));
    }
    const results = await Promise.all(concurrentRequests);
    const successes = results.filter(r => r.status === 200).length;
    console.log(`  Sent ${count} concurrent requests. Successes: ${successes}/${count}`);
    assert.strictEqual(successes, count);
    
    // Verify database remains consistent
    const getRes11 = await apiCall('/api/ssh-hosts', 'GET', null, adminToken);
    const getData11 = await getRes11.json();
    const advHosts11 = getData11.data.filter(h => h.name.startsWith('ADV_'));
    console.log('  Final consistent DB sort orders:');
    advHosts11.forEach(h => console.log(`    Host ID ${h.id}: sort_order = ${h.sort_order}`));
    console.log('  PASS: No database locks or crashes under concurrent updates.');

    // ============================================
    // TEST 12: Partial list of host IDs
    // ============================================
    console.log('\n[Test 12] Testing partial list of host IDs...');
    const res12 = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [adminHostIds[0], adminHostIds[2]] }, adminToken);
    assert.strictEqual(res12.status, 200);
    const getRes12 = await apiCall('/api/ssh-hosts', 'GET', null, adminToken);
    const getData12 = await getRes12.json();
    const advHosts12 = getData12.data.filter(h => h.name.startsWith('ADV_'));
    console.log('  DB sort orders after partial reorder:');
    advHosts12.forEach(h => console.log(`    Host ID ${h.id}: sort_order = ${h.sort_order}`));
    // Host1 and Host3 updated to 0 and 1, Host2 retains its previous order
    console.log('  PASS: Partial reordering succeeded.');

    // Clean up created hosts
    console.log('\n==> Cleaning up test hosts...');
    for (const id of adminHostIds) {
      await apiCall(`/api/ssh-hosts/${id}/permanent`, 'DELETE', null, adminToken);
    }
    for (const id of userHostIds) {
      await apiCall(`/api/ssh-hosts/${id}/permanent`, 'DELETE', null, userToken);
    }
    console.log('==> Cleanup complete.');

  } catch (err) {
    console.error('Test run failed with error:', err);
    process.exit(1);
  } finally {
    stopServer();
  }
}

runTests();
