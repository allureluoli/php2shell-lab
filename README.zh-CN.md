# php2shell-lab（中文说明）

对 PHP **php2shell** 修复（CVE-2026-109618 / CVE-2026-109619）的**差分复现**：
同一套两请求触发序列，分别打 **PHP 8.4.26（漏洞版）** 和 **PHP 8.4.27（修复版）**，
两版都用 AddressSanitizer 从源码编译，脚本自动给出"漏洞版崩、修复版不崩"的判定。

**[English → README.md](README.md)**

```
$ lab/run-ab.sh
── php-8.4.26-vuln run 1/3 ──
   R1 arm  : HTTP/1.1 200 OK   (Fatal error: Allowed memory size ... in Unknown on line 0)
   R2 probe: <无响应 / 进程 abort>
   -> SUMMARY: AddressSanitizer: SEGV ext/standard/var_unserializer.c:168 in tmp_var
[php-8.4.26-vuln] ASAN hits: 3/3
── php-8.4.27-fixed run 1/3 ──
   R1 arm  : HTTP/1.1 200 OK   (同样的 OOM 致命错误)
   R2 probe: HTTP/1.1 200 OK
   -> ASAN: none
[php-8.4.27-fixed] ASAN hits: 0/3

RESULT: reproduced (vulnerable crashes, fixed does not)
```

## 它到底证明了什么（先读这段）

PHP 在 **RINIT 之前**就处理 `multipart/form-data`
（`php_request_startup() → php_hash_environment()`）。在
`session.upload_progress.enabled=1`（默认值）下，这条路径会进入 session 处理器并
解码/编码会话数据。若中途发生 OOM，8.4.26 会 bailout，把序列化上下文留在
"已分配但指向已释放内存"的状态；**同一进程的下一个请求**在 RINIT 之前复用它 ——
整个过程与应用代码无关。8.4.27（`506e87fa` "Avoid state corruption via bailout"）
把解析期分配改成可失败、延迟 OOM 处理、并在 RINIT 前重置相关全局，因此上下文不再存活。

所以本仓库复现的是**状态损坏 / 内存安全型**问题（崩溃：SEGV / heap-use-after-free）
以及"修复它"这件事本身。

它**不是** RCE，也不是单包利用：

- **arming 请求需要一个"存了大值"的会话**，大到能在 pre-RINIT 解码/编码时撑爆
  `memory_limit`。本仓库用 `tools/seed_session.py` 直接写会话文件，因为那是
  **lab 侧前置条件**。真实攻击者能否把大值写进自己的会话，完全取决于目标应用。
- 需要"启动失败后进程仍存活"的 SAPI（prefork `mod_php`，或本仓库用的 CLI 内置服务器）。
  php-fpm / CGI 会在该失败后结束 worker，链条在第一步就断了。
- 载荷是"一个长度"，不是命令：没有 shell，没有代码执行。

如果你在找"一个请求打过去就 RCE"，那个说法不成立；
流传 PoC 的实际行为见 [docs/02-poc-review.md](docs/02-poc-review.md)（构建本仓库时逐个跑过）。

## 快速开始（WSL2 / Linux）

```bash
# 依赖（Debian/Kali）
sudo apt install build-essential autoconf bison pkg-config libxml2-dev curl python3

# 编译 8.4.26 + 8.4.27（带 ASAN，约 10 分钟，-j$(nproc)）
lab/bootstrap.sh

# 跑 A/B（各 3 次，只绑 127.0.0.1）
lab/run-ab.sh

# 可调参数
RUNS=5 MEMLIMIT=8M SESSBYTES=6000000 lab/run-ab.sh
PHP8426=/path/bin/php PHP8427=/path/bin/php lab/run-ab.sh
```

证据落在 `evidence/`（`php-8.4.26-vuln-run*.log`、`php-8.4.27-fixed-run*.log`）。
只有当"漏洞版崩、修复版不崩"时退出码才是 `0`。

## 目录

```
lab/bootstrap.sh        按 sha256 下载源码 + ASAN 编译两版
lab/run-ab.sh           A/B 主程序：seed → arm → probe → 判定
lab/www/index.php       中性靶页（漏洞在它运行之前就触发）
tools/seed_session.py   生成大会话文件（lab 前置条件）
tools/trigger.py        R1（arming，OOM）+ R2（probe，复用悬垂状态）
docs/01-root-cause.md   源码级分析 + 修复内容
docs/02-poc-review.md   流传 php2shell PoC 的逐个实测与定性
docs/03-validation.md   已记录的 A/B 结果、环境、边界
```

## 说明

- PHP 版本在 `lab/bootstrap.sh` 里用 SHA-256 固定。
- 必须带 `--enable-debug`：它让会话序列化上下文的布局可预测，ASAN 报告也更好读。
- 只绑 `127.0.0.1`，只用本地 socket。
- 在 WSL2（Debian/Kali、gcc 12/14、20 vCPU）上测试通过，不需要 Docker。

## 使用范围

这是一个防守向研究环境：给需要**亲眼看到** 8.4.27 补丁差异的人，以及需要评估
"泄露 PoC 到底能不能用"的人。只在你自己的机器上跑，不要拿这套触发去打第三方系统。

## 许可

MIT，见 [LICENSE](LICENSE)。
