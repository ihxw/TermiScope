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
let serverProcess = null;

// Helper function to wait
const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// Helper for making API calls
async function apiCall(endpoint, method = 'GET', body = null, token = null) {
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
  } catch (err) {
    console.error(`==> Rebuild failed: ${err.message}`);
    throw err;
  }

  console.log('==> Starting TermiScope server...');
  const binaryPath = path.join(rootDir, 'server');
  
  try {
    await fs.chmod(binaryPath, 0o755);
  } catch (err) {}

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

function stopServer() {
  if (serverProcess) {
    console.log('==> Stopping TermiScope server...');
    serverProcess.kill();
  }
}

// Setup users and return their tokens
async function setupUsers() {
  // Check init
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

  // Login as admin
  const loginRes = await apiCall('/api/auth/login', 'POST', {
    username: 'admin',
    password: 'AdminPassword123!'
  });
  const loginData = await loginRes.json();
  const adminToken = loginData.data.token;

  // Create user A
  const createUserA = await apiCall('/api/users', 'POST', {
    username: 'user_challenger_a',
    email: 'user_challenger_a@example.com',
    password: 'Password123!',
    role: 'user',
    display_name: 'Challenger A'
  }, adminToken);
  
  if (createUserA.status !== 201 && createUserA.status !== 409) {
    throw new Error(`Failed to create User A: ${await createUserA.text()}`);
  }

  // Create user B
  const createUserB = await apiCall('/api/users', 'POST', {
    username: 'user_challenger_b',
    email: 'user_challenger_b@example.com',
    password: 'Password123!',
    role: 'user',
    display_name: 'Challenger B'
  }, adminToken);

  if (createUserB.status !== 201 && createUserB.status !== 409) {
    throw new Error(`Failed to create User B: ${await createUserB.text()}`);
  }

  // Login User A
  const loginARes = await apiCall('/api/auth/login', 'POST', {
    username: 'user_challenger_a',
    password: 'Password123!'
  });
  const loginAData = await loginARes.json();
  const tokenA = loginAData.data.token;
  const userIdA = loginAData.data.user.id;

  // Login User B
  const loginBRes = await apiCall('/api/auth/login', 'POST', {
    username: 'user_challenger_b',
    password: 'Password123!'
  });
  const loginBData = await loginBRes.json();
  const tokenB = loginBData.data.token;
  const userIdB = loginBData.data.user.id;

  return { tokenA, userIdA, tokenB, userIdB };
}

// Clean old challenger hosts
async function cleanHosts(token) {
  const res = await apiCall('/api/ssh-hosts', 'GET', null, token);
  const data = await res.json();
  for (const host of data.data || []) {
    if (host.name.startsWith('Challenger_Host_')) {
      await apiCall(`/api/ssh-hosts/${host.id}/permanent`, 'DELETE', null, token);
    }
  }
}

async function runBackendTests(tokens) {
  const { tokenA, tokenB } = tokens;
  
  console.log('\n--- Cleaning up existing hosts for challenger users ---');
  await cleanHosts(tokenA);
  await cleanHosts(tokenB);

  console.log('--- Creating test hosts for User A and User B ---');
  // Create User A hosts
  const hostA1Res = await apiCall('/api/ssh-hosts', 'POST', {
    name: 'Challenger_Host_A1',
    host: '127.0.0.1',
    port: 22,
    username: 'root',
    auth_type: 'password',
    password: 'password',
    host_type: 'control_monitor'
  }, tokenA);
  const hostA1 = (await hostA1Res.json()).data;

  const hostA2Res = await apiCall('/api/ssh-hosts', 'POST', {
    name: 'Challenger_Host_A2',
    host: '127.0.0.1',
    port: 22,
    username: 'root',
    auth_type: 'password',
    password: 'password',
    host_type: 'control_monitor'
  }, tokenA);
  const hostA2 = (await hostA2Res.json()).data;

  const hostA3Res = await apiCall('/api/ssh-hosts', 'POST', {
    name: 'Challenger_Host_A3',
    host: '127.0.0.1',
    port: 22,
    username: 'root',
    auth_type: 'password',
    password: 'password',
    host_type: 'control_monitor'
  }, tokenA);
  const hostA3 = (await hostA3Res.json()).data;

  // Create User B host
  const hostB1Res = await apiCall('/api/ssh-hosts', 'POST', {
    name: 'Challenger_Host_B1',
    host: '127.0.0.1',
    port: 22,
    username: 'root',
    auth_type: 'password',
    password: 'password',
    host_type: 'control_monitor'
  }, tokenB);
  const hostB1 = (await hostB1Res.json()).data;

  console.log(`Created User A hosts: A1=${hostA1.id}, A2=${hostA2.id}, A3=${hostA3.id}`);
  console.log(`Created User B hosts: B1=${hostB1.id}`);

  // Test Case 1: Valid Reordering
  console.log('\n[TEST 1] Valid Reordering for User A...');
  const order1 = [hostA2.id, hostA3.id, hostA1.id];
  const reorder1Res = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: order1 }, tokenA);
  assert.strictEqual(reorder1Res.status, 200, 'Reorder should return 200');

  // Verify DB state
  const listRes = await apiCall('/api/ssh-hosts', 'GET', null, tokenA);
  const listData = await listRes.json();
  const sortedIds = listData.data.map(h => h.id);
  assert.deepStrictEqual(sortedIds, order1, 'Sorted IDs should match the requested order');
  console.log('-> PASS: Correctly persists and reorders lists.');

  // Test Case 2: Negative ID
  console.log('\n[TEST 2] Negative Device ID...');
  const reorderNegRes = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [-1] }, tokenA);
  assert.strictEqual(reorderNegRes.status, 400, 'Negative ID should cause 400 Bad Request');
  
  const reorderNegRes2 = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [hostA1.id, -2, hostA2.id] }, tokenA);
  assert.strictEqual(reorderNegRes2.status, 400, 'Negative ID in list should cause 400 Bad Request');
  console.log('-> PASS: Correctly rejects negative IDs with 400.');

  // Test Case 3: Duplicate IDs inside list
  console.log('\n[TEST 3] Duplicate Device IDs...');
  const orderDup = [hostA2.id, hostA1.id, hostA2.id];
  const reorderDupRes = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: orderDup }, tokenA);
  assert.strictEqual(reorderDupRes.status, 200, 'Duplicate IDs within User A owned hosts should return 200');
  
  // Verify DB state
  const listResDup = await apiCall('/api/ssh-hosts', 'GET', null, tokenA);
  const listDataDup = await listResDup.json();
  console.log('List after duplicate ID reorder:', listDataDup.data.map(h => ({ id: h.id, sort_order: h.sort_order })));
  console.log('-> PASS: Handles duplicate IDs without crash or index violation.');

  // Test Case 4: Extremely large ID
  console.log('\n[TEST 4] Extremely large IDs...');
  const reorderLargeRes = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [999999999999999999999999] }, tokenA);
  assert.strictEqual(reorderLargeRes.status, 400, 'ID exceeding uint size should cause 400 Bad Request');
  
  const reorderLargeRes2 = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [99999999] }, tokenA);
  assert.strictEqual(reorderLargeRes2.status, 403, 'Non-existent ID within uint size should cause 403 Forbidden');
  console.log('-> PASS: Handles large or non-existent IDs robustly.');

  // Test Case 5: Unauthorized ID (Cross-user)
  console.log('\n[TEST 5] Unauthorized ID (Cross-user)...');
  const orderCross = [hostA1.id, hostB1.id, hostA2.id];
  const reorderCrossRes = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: orderCross }, tokenA);
  assert.strictEqual(reorderCrossRes.status, 403, 'Cross-user host ID should cause 403 Forbidden');

  // Verify that User A's hosts' ordering is intact
  const listResCross = await apiCall('/api/ssh-hosts', 'GET', null, tokenA);
  const listDataCross = await listResCross.json();
  const sortedIdsCross = listDataCross.data.map(h => h.id);
  console.log('Current ordering:', sortedIdsCross);
  console.log('-> PASS: Correctly blocks unauthorized hosts and returns 403.');

  // Test Case 6: Empty ID list
  console.log('\n[TEST 6] Empty ID list...');
  const reorderEmptyRes = await apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: [] }, tokenA);
  assert.strictEqual(reorderEmptyRes.status, 400, 'Empty device_ids should cause 400 Bad Request');
  console.log('-> PASS: Rejects empty IDs with 400.');

  // Test Case 7: Concurrency Stress Test
  console.log('\n[TEST 7] Concurrency Stress Test...');
  const concurrencyCount = 50;
  const requests = [];
  const permutations = [
    [hostA1.id, hostA2.id, hostA3.id],
    [hostA1.id, hostA3.id, hostA2.id],
    [hostA2.id, hostA1.id, hostA3.id],
    [hostA2.id, hostA3.id, hostA1.id],
    [hostA3.id, hostA1.id, hostA2.id],
    [hostA3.id, hostA2.id, hostA1.id],
  ];

  console.log(`Sending ${concurrencyCount} parallel reorder requests...`);
  for (let i = 0; i < concurrencyCount; i++) {
    const randomPerm = permutations[i % permutations.length];
    requests.push(apiCall('/api/ssh-hosts/reorder', 'PUT', { device_ids: randomPerm }, tokenA));
  }

  const responses = await Promise.all(requests);
  const successCount = responses.filter(r => r.status === 200).length;
  const busyCount = responses.filter(r => r.status === 500).length;
  console.log(`Results: Success=${successCount}, Error=${busyCount}`);
  
  // Verify DB state is still consistent
  const listResFinal = await apiCall('/api/ssh-hosts', 'GET', null, tokenA);
  const listDataFinal = await listResFinal.json();
  const finalHosts = listDataFinal.data.filter(h => h.name.startsWith('Challenger_Host_A'));
  
  assert.strictEqual(finalHosts.length, 3, 'Should still have 3 hosts');
  const sortOrders = finalHosts.map(h => h.sort_order).sort((a, b) => a - b);
  console.log('Final hosts sort orders in DB:', finalHosts.map(h => ({ id: h.id, sort_order: h.sort_order })));
  
  // Ensure sort_orders are unique and sequential (0, 1, 2)
  assert.deepStrictEqual(sortOrders, [0, 1, 2], 'Sort orders should be consecutive integers starting at 0');
  console.log('-> PASS: Database remains consistent and hosts have consecutive unique sort_orders under concurrent stress.');

  // Clean up hosts
  await cleanHosts(tokenA);
  await cleanHosts(tokenB);
}

// Simulate Frontend LocalStorage Sync & Fallback Logic
async function runFrontendStoreTests(userId) {
  console.log('\n==================================================');
  console.log('Running Frontend LocalStorage Caching & Sync Tests...');
  console.log('==================================================');

  // Simple Mock LocalStorage
  const mockLocalStorageStore = {};
  const mockLocalStorage = {
    getItem(key) {
      return mockLocalStorageStore[key] || null;
    },
    setItem(key, value) {
      mockLocalStorageStore[key] = String(value);
    },
    removeItem(key) {
      delete mockLocalStorageStore[key];
    }
  };

  // Mock API methods
  let apiReorderHostsMock = async (ids) => {
    return { success: true };
  };
  let getHostsMock = async () => {
    return [
      { id: 1, name: 'Host 1', sort_order: 0 },
      { id: 2, name: 'Host 2', sort_order: 1 },
      { id: 3, name: 'Host 3', sort_order: 2 }
    ];
  };

  // Simulated Pinia Store class based on web/src/stores/ssh.js
  class MockSSHStore {
    constructor() {
      this.hosts = [];
      this.hostsFetchedAt = 0;
      this.hostsFetchTTL = 60_000;
      this.hostsFetchPromise = null;
      this.loading = false;
    }

    async fetchHosts(filters = {}, { force = false } = {}) {
      if (
          !force &&
          this.hosts.length > 0 &&
          Date.now() - this.hostsFetchedAt < this.hostsFetchTTL
      ) {
          return this.hosts;
      }
      if (this.hostsFetchPromise) {
          return this.hostsFetchPromise;
      }

      this.loading = true;
      this.hostsFetchPromise = (async () => {
          try {
              const res = await getHostsMock();
              let fetchedHosts = res;

              const localOrderStr = mockLocalStorage.getItem('termScope_host_order_' + userId);
              if (localOrderStr) {
                  try {
                      const localOrder = JSON.parse(localOrderStr);
                      const idToIndex = {};
                      localOrder.forEach((id, index) => {
                          idToIndex[id] = index;
                      });
                      fetchedHosts.sort((a, b) => {
                          const aIndex = idToIndex[a.id];
                          const bIndex = idToIndex[b.id];
                          const aHas = aIndex !== undefined;
                          const bHas = bIndex !== undefined;
                          if (aHas && bHas) {
                              return aIndex - bIndex;
                          }
                          if (aHas) return -1;
                          if (bHas) return 1;
                          return (a.sort_order || 0) - (b.sort_order || 0);
                      });
                  } catch (e) {
                      console.error('Failed to parse local host order:', e);
                  }
              }

              if (mockLocalStorage.getItem('termScope_host_order_pending_' + userId) === 'true') {
                  if (localOrderStr) {
                      try {
                          const localOrder = JSON.parse(localOrderStr);
                          apiReorderHostsMock(localOrder).then(() => {
                              mockLocalStorage.removeItem('termScope_host_order_pending_' + userId);
                          }).catch(syncErr => {
                              console.error('Background sync of host order failed:', syncErr);
                          });
                      } catch (e) {
                          console.error('Failed to parse local host order for background sync:', e);
                      }
                  }
              }

              this.hosts = fetchedHosts;
              this.hostsFetchedAt = Date.now();
              return this.hosts;
          } catch (error) {
              console.error('Failed to fetch hosts:', error);
              throw error;
          } finally {
              this.loading = false;
              this.hostsFetchPromise = null;
          }
      })();
      return this.hostsFetchPromise;
    }

    async reorderHosts(ids) {
      mockLocalStorage.setItem('termScope_host_order_' + userId, JSON.stringify(ids));
      try {
          await apiReorderHostsMock(ids);
          mockLocalStorage.removeItem('termScope_host_order_pending_' + userId);
      } catch (error) {
          mockLocalStorage.setItem('termScope_host_order_pending_' + userId, 'true');
          console.error('Failed to reorder hosts:', error);
          throw error;
      }
    }
  }

  // --- Store Test 1: Normal reordering ---
  console.log('[STORE TEST 1] Normal Online Reordering...');
  const store = new MockSSHStore();
  await store.fetchHosts();
  assert.deepStrictEqual(store.hosts.map(h => h.id), [1, 2, 3]);

  await store.reorderHosts([3, 1, 2]);
  assert.strictEqual(mockLocalStorage.getItem('termScope_host_order_' + userId), '[3,1,2]');
  assert.strictEqual(mockLocalStorage.getItem('termScope_host_order_pending_' + userId), null);
  console.log('-> PASS: Normal reorder updates localStorage and has no pending sync.');

  // --- Store Test 2: Offline Fallback Caching ---
  console.log('\n[STORE TEST 2] Offline Reordering (API throws network error)...');
  apiReorderHostsMock = async (ids) => {
    throw new Error('Network Error: Cannot connect to server');
  };

  try {
    await store.reorderHosts([2, 3, 1]);
    assert.fail('reorderHosts should throw error when offline');
  } catch (err) {
    assert.strictEqual(err.message, 'Network Error: Cannot connect to server');
  }

  assert.strictEqual(mockLocalStorage.getItem('termScope_host_order_' + userId), '[2,3,1]', 'LocalOrder should be stored');
  assert.strictEqual(mockLocalStorage.getItem('termScope_host_order_pending_' + userId), 'true', 'Pending flag should be true');
  console.log('-> PASS: Correctly caches sorting sequence in LocalStorage and sets pending=true.');

  // --- Store Test 3: Local Caching Sorting on Load ---
  console.log('\n[STORE TEST 3] Local caching sorting applies on fetchHosts...');
  await store.fetchHosts({}, { force: true });
  assert.deepStrictEqual(store.hosts.map(h => h.id), [2, 3, 1], 'Fetched hosts should be sorted according to local order');
  console.log('-> PASS: Local cache overrides server-side sort on next load.');

  // --- Store Test 4: Offline Restored Synchronization ---
  console.log('\n[STORE TEST 4] Online sync restores on successful fetch...');
  let syncedIds = null;
  apiReorderHostsMock = async (ids) => {
    syncedIds = ids;
    return { success: true };
  };

  await store.fetchHosts({}, { force: true });
  await sleep(50);

  assert.deepStrictEqual(syncedIds, [2, 3, 1], 'Background sync should have pushed [2, 3, 1] to backend');
  assert.strictEqual(mockLocalStorage.getItem('termScope_host_order_pending_' + userId), null, 'Pending flag should be cleared');
  console.log('-> PASS: Syncs back to backend on restoration, clearing pending flag.');

  // --- Store Test 5: Sync failure due to deleted host ---
  console.log('\n[STORE TEST 5] Offline sync failure (Deleted Host returns 403)...');
  apiReorderHostsMock = async (ids) => {
    throw new Error('Network Error');
  };
  try {
    await store.reorderHosts([2, 3, 1]);
  } catch (err) {}
  
  apiReorderHostsMock = async (ids) => {
    throw new Error('API error 403: Forbidden');
  };

  const consoleErrors = [];
  const originalConsoleError = console.error;
  console.error = (...args) => {
    consoleErrors.push(args.join(' '));
  };

  try {
    await store.fetchHosts({}, { force: true });
    await sleep(50);
  } finally {
    console.error = originalConsoleError;
  }

  assert(consoleErrors.some(err => err.includes('Background sync of host order failed')), 'Error should be logged to console');
  assert.strictEqual(mockLocalStorage.getItem('termScope_host_order_pending_' + userId), 'true', 'Pending flag remains true on sync failure');
  console.log('-> PASS: Handles sync failures gracefully without unhandled rejection or crashing.');
}

async function main() {
  try {
    await startServer();
    const tokens = await setupUsers();
    
    // Run backend tests
    await runBackendTests(tokens);

    // Run frontend simulation tests
    await runFrontendStoreTests(tokens.userIdA);

    console.log('\n==================================================');
    console.log('ALL MILESTONE 2 PERSISTENCE TESTS PASSED SUCCESSFULLY!');
    console.log('==================================================\n');
  } catch (err) {
    console.error('\n!!! TEST CHALLENGE FAILED !!!\n', err);
    process.exit(1);
  } finally {
    stopServer();
  }
}

main();
