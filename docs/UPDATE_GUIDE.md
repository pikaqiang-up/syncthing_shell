# Syncthing 升级指南（面向 AI / 自动化执行）

> 场景：syncthing 发布了新版本，需要把壳里内嵌的二进制与 API 适配升级。
> 一条命令完成大部分工作：`scripts/update_syncthing.sh v<新版本号>`。
> 本文档描述该脚本做了什么、之后需要检查什么。

## 自动部分（脚本完成）

1. **下载** 官方 `syncthing-source-<ver>.tar.gz` + sha256 校验
   （直连 GitHub 失败自动走 gh-proxy.com，再失败用 `tools/parallel_dl.py` 分段续传）。
2. **构建** 纯静态二进制：
   `GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -mod=vendor -trimpath -tags noupgrade`
   （sqlite 为纯 Go 的 modernc 后端；不要用官方预编译 linux 包 —— 它是 cgo+静态glibc，
   在 Android 上 `runtime/cgo: pthread_create failed` 崩溃）。
   同步构建 linux/amd64 用于本地 API 探测。
3. **校验** `file` 为 statically linked、arm64 ELF `p_align=0x10000`（16KB 页兼容）。
4. **安装** 到 `android/app/src/main/jniLibs/arm64-v8a/libsyncthing.so`，
   更新 `third_party/syncthing/BINARY.txt` 溯源记录。
5. **快照** 运行 `tools/probe_api.sh`，把新版本所有 REST 端点的真实响应
   保存到 `docs/api-snapshot/<新版本>/`。
6. **diff** 与旧版本快照逐端点对比，输出 `[CHANGED]` 列表。

## 人工/AI 检查部分（脚本之后）

按 `[CHANGED]` 列表逐项核对：

### A. config 结构变化（config.json / defaults-folder.json / defaults-device.json）

- `lib/syncthing/models.dart` 的配置类是 **raw 事实源**设计：新增字段自动保留，
  无需改代码；只有当 UI 需要暴露新字段时才加 getter/setter。
- 字段改名/删除（罕见，syncthing 遵循兼容性承诺）才需要改模型与相关页面。

### B. 端点行为变化

- 核对 `lib/syncthing/controller.dart` 中用到的端点：
  - `/rest/system/{status,connections,version,log,error,discovery,restart,shutdown}`
  - `/rest/config` 及 `/rest/config/{folders,devices,options,gui,defaults/*}` CRUD
  - `/rest/db/{status,completion,scan,override,revert,browse,ignores}`
  - `/rest/folder/{errors,versions}`、`/rest/cluster/pending/*`
  - `/rest/events` 长轮询（since/timeout/limit 参数）
  - `/rest/stats/device`、`/rest/svc/deviceid`、`/rest/svc/report`
- 官方文档副本在 `docs/api-docs/`（rst 格式），也可从
  syncthing/docs 仓库刷新。

### C. CLI 参数变化

- `SyncthingConfig.kt` 用到：`generate --home <dir> --no-port-probing`
- `SyncthingService.kt` 用到：`serve --home <dir> --log-file <path>`
- v1→v2 时的历史教训：`--skip-port-probing` 改名 `--no-port-probing`；
  `--logfile` 改名 `--log-file`。检查 `<binary> generate --help` 与 `serve --help`。

### D. 事件类型变化

- `controller.dart` 的 `_handleEvent` 处理：
  ItemFinished / LocalChangeDetected / RemoteChangeDetected / ConfigSaved /
  FolderSummary / StateChanged / FolderCompletion / FolderErrors /
  DeviceConnected / DeviceDisconnected / DeviceRejected / ClusterConfigReceived /
  FolderRejected。新增事件类型默认忽略（安全），类型改名需同步。

### E. 收尾验证

```bash
dart analyze lib && flutter test     # 代码健康
flutter build apk --release          # 构建
adb install -r build/app/outputs/flutter-apk/app-release.apk
# 真机冒烟：启动→设备ID二维码→加一个文件夹→确认扫描完成→（如有）对端同步
```

## 快速参考：本壳与 syncthing 的全部耦合点

| 耦合点 | 文件 |
|---|---|
| CLI 启动参数 | `android/.../SyncthingConfig.kt`、`SyncthingService.kt` |
| config.xml 解析（apikey/address 正则） | `android/.../SyncthingConfig.kt` |
| REST 端点与查询参数 | `lib/syncthing/controller.dart` |
| JSON 字段解析 | `lib/syncthing/models.dart` |
| 事件类型 switch | `lib/syncthing/controller.dart` `_handleEvent` |
| API 行为语义（状态字符串 idle/syncing/…） | `lib/ui/widgets/common.dart` `FolderStateView` |

其余全部（页面、导航、主题）与 syncthing 版本无关。
