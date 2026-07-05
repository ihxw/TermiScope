# E2E Test Infra: TermiScope

## Test Philosophy
- Opaque-box, requirement-driven. No dependency on implementation design.
- Methodology: Category-Partition + BVA + Pairwise + Workload Testing.

## Feature Inventory
| # | Feature | Source (requirement) | Tier 1 | Tier 2 | Tier 3 |
|---|---------|---------------------|:------:|:------:|:------:|
| 1 | 主机卡片拖拽排序及持久化 | F1 | 5 | 5 | ✓ |
| 2 | SFTP 流式直传上传 | F2 | 5 | 5 | ✓ |
| 3 | SFTP 传输的非阻塞 UI 以及实时进度显示 | F3 | 5 | 5 | ✓ |
| 4 | SFTP 传输任务按目标主机分组及状态显示 | F4 | 5 | 5 | ✓ |

## Test Architecture
- Test runner: Node.js (v24.16.0) script using native Fetch and FormData APIs. Located at `e2e-tests/runner.js`.
- Test case format: Programmatic JavaScript assertions using Node's native `assert` module.
- Directory layout:
  - `e2e-tests/package.json` — Test suite metadata & script entry.
  - `e2e-tests/runner.js` — All 49 E2E test cases implementation & runner code.

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | 日常多主机运维环境下的主机管理与多通道文件上传 | F1, F2, F3, F4 | High |
| 2 | 恶劣网络环境下的超大文件直传与任务阻断恢复 | F2, F3 | High |
| 3 | 双面板跨网络隔离主机的跨主机直传负载 | F1, F4 | High |
| 4 | 生产发布场景下的多主机同步直传极限并发 | F2, F3, F4 | High |
| 5 | 终端混合操作：多文件传输、主机重排与会话断开 | F1, F2, F3, F4 | High |

## Coverage Thresholds
- Tier 1: ≥5 per feature (Total: 20)
- Tier 2: ≥5 per feature (Total: 20)
- Tier 3: ≥4 cross-feature combinations
- Tier 4: ≥5 realistic application scenarios
- Total Target: 49 cases
