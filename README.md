# Better Fan

Better Fan 是 macOS 风扇与温度监测工具。总览显示真实转速、关键温度和当前控制权。启用后台服务后，可为单只或全部风扇设置固定转速、温度曲线或全速散热，也可以恢复系统自动。

![Better Fan 界面原型](ui-demo/shots/overview-desktop.png)

从 [GitHub Releases](https://github.com/Changan-Su/better-macs-fan-control/releases) 下载与你的 Mac 匹配的 DMG（Apple 芯片 `arm64` 或 Intel `x86_64`）。将应用拖入“应用程序”文件夹。需要 macOS 13 或更新版本。[安装说明](packaging/INSTALL.zh-CN.md)

版本仍处于 alpha。带 `unsigned-monitor` 后缀的安装包使用临时签名，提供真实监测。调速需要 Developer ID 签名、后台服务授权以及机型支持。无风扇和读数不可用是两种不同状态。无法获得的读数不会用模拟数据填补。

## 本地开发

需要 Xcode 和 Node.js 22 或更新版本。

```sh
npm ci
npx playwright install chromium webkit
npm test
swift test
npm run build:mac
npm run package:mac
```

双击 `ui-demo/index.html` 可离线查看交互原型。原型独立运行，所有读数和控制结果均为模拟。App 与原型共用界面结构，构建时加入本机读数和控制适配器。[界面设计说明](ui-demo/README.md)

`swift run BetterFanProbe` 可在当前 Mac 上运行只读 SMC 探针。`--smoke-test` 可传给打包应用的 `Contents/MacOS/BetterFan` 可执行文件，验证 WebKit 界面从本机读取数据。Swift 测试使用模拟驱动验证调速、参数校验和自动恢复逻辑。

## GitHub 自动打包与发布

PR 和对 `master` 的推送会执行浏览器检查、Swift 测试，以及两种架构的 DMG 和 ZIP 构建。推送与 `package.json` 版本一致的 `v` 标签后，Actions 会在同一提交上重新验证、构建并发布 DMG、ZIP 和 SHA-256 校验文件。标签必须指向已经合入 `master` 的提交。

开发者可在仓库 Settings → Secrets and variables → Actions 配置以下五个 Secrets，启用签名和公证：

| Secret | 内容 |
| --- | --- |
| `APPLE_CERTIFICATE_P12` | Developer ID Application 证书和私钥的 `.p12`，Base64 编码 |
| `APPLE_CERTIFICATE_PASSWORD` | `.p12` 导出密码 |
| `APPLE_NOTARY_KEY` | App Store Connect 团队 API 密钥 `.p8`，Base64 编码 |
| `APPLE_NOTARY_KEY_ID` | 公证 API Key ID |
| `APPLE_NOTARY_ISSUER` | 公证 API Issuer ID |

五项均未配置时，标签发布监测预览。仅配置部分凭据会让发布失败，便于发现配置问题。签名版本发布前仍需要在真实设备上验收辅助服务授权、调速和恢复系统自动。已发布版本保留原有构建，签名后请递增版本并推送新标签。

## 上游项目

[CrystalIDEA Macs Fan Control](https://crystalidea.com/macs-fan-control) 的界面翻译保留在 [`languages/`](languages/) 中。原版的 [问题追踪](https://github.com/crystalidea/macs-fan-control/issues) 和 [发布归档](https://github.com/crystalidea/macs-fan-control/releases) 仍由上游维护。修改翻译时请保留 `%1`、`%s` 等占位符。

Better Fan 的 SMC 访问代码基于 [Stats](https://github.com/exelban/stats/tree/7de898dda04945031073b22f061f5e926d96a358/SMC)，其 [MIT 许可](third-party/Stats-LICENSE.txt) 随应用分发。
