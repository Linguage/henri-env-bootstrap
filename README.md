# henri-env-bootstrap

从本机 `henri_env` 审计结果生成的可复现安装仓库。它会在 macOS 或 Linux 上：

1. 自动发现 Conda；若没有，则安装 Miniforge。
2. 创建一个干净的 `henri_env`。
3. 安装原环境中的数据分析、Jupyter、地理计算、PDF/Office、AI SDK、Manim
   与开发工具。
4. 克隆并以 editable 方式安装 `MiaoYan-Notes` 和 `zotero-workbench`。
5. 注册 Jupyter kernel，并检查导入、重复元数据、pip 依赖及 `ffmpeg`。

默认使用清华 TUNA 的 Conda 与 PyPI 镜像，但配置仅对此次安装命令生效，
不会覆盖目标设备现有的全局 `~/.condarc` 或 pip 配置。

## 一键安装

```bash
git clone <此仓库地址>
cd henri-env-bootstrap
./bootstrap.sh
```

仓库当前只在本地初始化，还没有远程地址；推送后，把上面的占位地址替换成
真实 Git URL。

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

如果目标设备已经存在同名环境，安装器会停止以保护它。显式替换：

```bash
./bootstrap.sh --recreate
```

也可以先安装为另一个名称做验收：

```bash
./bootstrap.sh --name henri_env_test --skip-projects --no-kernel
```

只检查现有环境：

```bash
./bootstrap.sh --verify-only
```

更多参数见 `./bootstrap.sh --help`。也可以用 `HENRI_MIRROR` 设置镜像。
editable 项目默认放在
`~/henri-projects`，可用 `--projects-dir` 或 `HENRI_PROJECTS_DIR` 修改。

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
