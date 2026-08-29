# 镜像源说明

检查日期：2026-08-29（Asia/Shanghai）

本项目只使用 `conda-forge` 社区频道，不使用 `defaults`。这避免了混合频道
依赖，也绕开了 Anaconda 官方仓库的商业使用条款问题。

## 已配置镜像

| 参数 | Conda | PyPI | 本机轻量检查 |
| --- | --- | --- | --- |
| `tuna` | 清华 TUNA | 清华 TUNA | HTTP 200 / HTTP 200 |
| `bfsu` | 北京外国语大学 | 北京外国语大学 | HTTP 200 / HTTP 200 |
| `ustc` | 中国科学技术大学 | 中国科学技术大学 | HTTP 200 / HTTP 200 |
| `nju` | 南京大学 | 南京大学 | HTTP 200 / HTTP 200 |
| `official` | conda-forge | PyPI | 未纳入国内镜像检查 |

当前检查只请求响应头，不下载 Conda 环境或 Python 包。镜像可达性会随网络、
维护和同步状态变化；安装前运行：

```bash
./scripts/check-mirrors.sh
```

当日从本机测得，四组国内镜像的 Conda 与 PyPI 端点均返回 HTTP 200。清华
TUNA 可以继续使用，也是 `bootstrap.sh` 的默认值。

## 官方帮助

- [清华 TUNA：Anaconda](https://mirrors.tuna.tsinghua.edu.cn/help/anaconda/)
- [清华 TUNA：PyPI](https://mirrors.tuna.tsinghua.edu.cn/help/pypi/)
- [北京外国语大学：Anaconda](https://mirrors.bfsu.edu.cn/help/anaconda/)
- [北京外国语大学：PyPI](https://mirrors.bfsu.edu.cn/help/pypi/)
- [USTC：Anaconda](https://mirrors.ustc.edu.cn/help/anaconda.html)
- [USTC：PyPI](https://mirrors.ustc.edu.cn/help/pypi.html)
- [NJU / MirrorZ：Anaconda](https://help.mirror.nju.edu.cn/anaconda/?mirror=NJU)
- [NJU / MirrorZ：PyPI](https://help.mirror.nju.edu.cn/pypi/?mirror=NJU)

镜像配置文件保存在 `mirrors/` 中，并通过临时 `CONDARC` 传给 Conda；pip
镜像则通过本次命令的 `--index-url` 传入。两者都不会永久修改用户配置。
