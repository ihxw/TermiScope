## 功能

当 `web/package.json` 的 `version` 字段变更时,自动创建 Git tag,触发完整的构建和发布流程。

## 工作流程

1. **触发条件**: push到main分支且修改了`web/package.json`
2. **检查版本**: 比较当前commit和上一个commit的version字段
3. **自动构建**: 如果版本变更,直接执行完整构建流程:
   - 构建前端 (npm)
   - 构建后端 (Go)
   - 打包所有平台的二进制文件
4. **创建Release**: 创建tag并发布GitHub Release,上传构建产物

## 使用方法

1. **更新版本号**:
   ```bash
   # 修改 web/package.json 中的 version 字段
   # 例如: "version": "2.0.10"
   ```

2. **提交并推送到main分支**:
   ```bash
   git add web/package.json
   git commit -m "Bump version to 2.0.10"
   git push origin main
   ```

3. **自动完成**:
   - ✅ 自动检测版本变更
   - ✅ 自动创建tag (v2.0.10)
   - ✅ 自动触发构建流程
   - ✅ 自动创建Release并上传构建产物

## 注意事项

- 只需更新 `web/package.json` 的version字段
- 不需要手动创建tag或运行 `github-release.ps1`
- 确保每次版本号都是递增的
- Tag格式: `v{major}.{minor}.{patch}` (例如: v2.0.10)
- 构建在Windows runner上执行,产物包含所有平台的二进制文件

## 优势

- ✅ 版本号统一管理在package.json
- ✅ 自动检测重复tag
- ✅ 完整的构建和打包流程
- ✅ 自动上传所有平台的二进制文件
- ✅ 无需手动操作

## 示例

```bash
# 旧流程 (手动)
1. 修改 web/package.json version
2. 修改 github-release.ps1 中的tag
3. 运行 .\github-release.ps1
4. 等待release.yml构建

# 新流程 (自动)
1. 修改 web/package.json version
2. git commit && git push
3. 等待自动构建完成
```

## 禁用自动发布

如果需要临时禁用自动发布,可以:
- 删除或重命名 `.github/workflows/auto-release.yml`
