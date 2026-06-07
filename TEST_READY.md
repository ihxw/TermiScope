# E2E Test Suite Ready

## Test Runner
- Command: `cd e2e-tests && npm test`
- Expected: all tests pass with exit code 0

## Coverage Summary
| Tier | Count | Description |
|------|------:|-------------|
| 1. Feature Coverage | 20 | 5 cases per feature (F1-F4) |
| 2. Boundary & Corner | 20 | 5 cases per feature (F1-F4) |
| 3. Cross-Feature | 4 | Combinations of drag-sorting and SFTP |
| 4. Real-World Application | 5 | Complex real-world workload scenarios |
| **Total** | **49** | |

## Feature Checklist
| Feature | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|---------|:------:|:------:|:------:|:------:|
| 特征 1：主机卡片拖拽排序及持久化 | 5 | 5 | ✓ | ✓ |
| 特征 2：SFTP 流式直传上传 | 5 | 5 | ✓ | ✓ |
| 特征 3：SFTP 传输的非阻塞 UI 以及实时进度显示 | 5 | 5 | ✓ | ✓ |
| 特征 4：SFTP 传输任务按目标主机分组及状态显示 | 5 | 5 | ✓ | ✓ |
