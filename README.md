# henri-env-bootstrap

从本机 `henri_env` 审计结果生成的可复现环境协调仓库。它会在 macOS 或 Linux 上：

1. 自动发现 Conda；若没有，则安装 Miniforge。
2. 若环境不存在则创建；若已经存在则先核查当前状态。
3. 只安装或调整与 `environment.yml`、`requirements-pip.txt` 不一致的直接包，
   不主动查询或升级到清单之外的“最新版本”。
4. 只在 checkout、editable 安装或 Jupyter kernel 缺失、漂移时处理对应部分。
5. 最后检查导入、重复元数据、pip 依赖及 `ffmpeg`；无法安全增量修复时明确建议重建。

默认使用清华 TUNA 的 Conda 与 PyPI 镜像，但配置仅对此次安装命令生效，
不会覆盖目标设备现有的全局 `~/.condarc` 或 pip 配置。

## 一键协调

```bash
git clone https://github.com/Linguage/henri-env-bootstrap.git
cd henri-env-bootstrap
./bootstrap.sh
```

已有 `henri_env` 时，这条命令不会直接重建环境。它先比较当前安装与仓库清单，
Conda 和 pip 分别只接收缺失或版本漂移的直接包。无变化的部分会明确显示为
`already match` 并跳过。

只核查，不做任何修改：

```bash
./bootstrap.sh --check
```

`--check` 同时检查清单一致性和运行健康；发现漂移或健康问题时退出码为 4。
只预览将执行的协调计划、但不把漂移作为命令失败：

```bash
./bootstrap.sh --dry-run
```

切换镜像：

```bash
./bootstrap.sh --mirror tuna      # 默认，清华 TUNA
./bootstrap.sh --mirror bfsu      # 北京外国语大学
./bootstrap.sh --mirror ustc      # 中国科学技术大学
./bootstrap.sh --mirror nju       # 南京大学
./bootstrap.sh --mirror official  # conda-forge / PyPI 官方源
```

安装前可用轻量 HEAD 请求检查当前网络下的可达性，不会下载环境包：

```bash
./scripts/check-mirrors.sh
```

当前镜像状态、端点和各站官方帮助链接见 `docs/mirrors.md`。

只有确认不需要保留旧环境时，才直接删除并重建：

```bash
./bootstrap.sh --recreate
```

`--recreate` 会先删除目标环境，安装失败时没有可直接切回的旧副本。对于当前这类
重复 `.dist-info` 污染，推荐先在旁路环境中完整创建和验收，不要手工逐个删除元数据：

```bash
./bootstrap.sh --name henri_env_candidate --skip-projects --no-kernel
./bootstrap.sh --name henri_env_candidate --check --skip-projects --no-kernel
```

确认候选环境通过核查后，在没有激活 `henri_env` 的终端中保留旧环境为备份，再切换名称：

```bash
conda rename -n henri_env henri_env_backup_before_rebuild
conda rename -n henri_env_candidate henri_env
./bootstrap.sh
```

最后一条命令会补齐 editable 项目和 Jupyter kernel，并重新验证。确认新环境稳定后，
再自行删除备份。以上创建候选环境的步骤会下载依赖；仓库自身的轻量测试不会。

也可以先协调到另一个名称做验收：

```bash
./bootstrap.sh --name henri_env_test --skip-projects --no-kernel
```

只运行导入、重复元数据、`pip check` 与 `ffmpeg` 健康检查，不比较清单：

```bash
./bootstrap.sh --verify-only
```

更多参数见 `./bootstrap.sh --help`。也可以用 `HENRI_MIRROR` 设置镜像。
editable 项目默认放在
`~/henri-projects`，可用 `--projects-dir` 或 `HENRI_PROJECTS_DIR` 修改。

## 核查与更新边界

- `scripts/audit_environment.py` 核查 Conda/pip 直接依赖、重复 Python 元数据和
  Jupyter kernel；editable checkout 与安装位置由 `bootstrap.sh` 核查。
- 核查过程不访问包索引，也不提出清单之外的版本升级。
- Conda 只在对应直接包缺失或版本不符合 `environment.yml` 时调用 `conda install`。
- pip 只把缺失或版本不符合 `requirements-pip.txt` 的条目交给安装器；已匹配条目跳过。
- editable 项目只有在 checkout 缺失、锁定提交漂移或安装位置错误时处理。若 checkout
  有未提交修改且提交漂移，协调会停止并保留现场。
- Jupyter kernel 已经指向目标环境 Python 时不会重复注册。
- 增量协调不会擅自删除额外包或残留元数据。开始修改前会检查重复 distribution
  metadata；发现此类污染时直接停止，确保不会留下“部分更新但仍不健康”的环境。
  审查报告后，再决定是否显式使用 `--recreate`。

这里所说的“不健康”不是环境目录损坏，而是解析器看到互相矛盾的包状态。例如同一包
同时存在多个 `.dist-info` 版本，或 `pip check` 发现已安装版本不满足依赖约束。这类环境
可能暂时仍能导入模块，但结果依赖元数据扫描顺序，不宜视为可复现状态。

## 为什么不是直接复制 `conda env export`

源环境存在 PyJWT 版本冲突、22 组重复包元数据，以及两个已经失效的本机
editable 路径。直接导出会把污染状态和绝对路径一起带到新设备。

本仓库采用两层记录：

- `environment.yml` 与 `requirements-pip.txt` 是干净、可移植的安装输入；
- `locks/` 保存源环境的 Conda 精确包 URL 和实际观察到的 PyPI 版本，供审计
  与对比，不直接用于安装。

具体发现和兼容性修正见 `audit/source-environment.md`。

## 更新快照

当本机 `henri_env` 有计划地升级后，可刷新原始证据：

```bash
./scripts/refresh-snapshot.sh henri_env
```

刷新后应先审查差异，再人工更新干净安装输入；不要把新的冲突直接复制进去。

## 轻量测试

以下命令只运行 Shell/Python 语法检查、单元测试和帮助命令，不创建或下载 Conda 环境：

```bash
./scripts/smoke-test.sh
```
