# Better Fan 交互方案

离线可用的单文件 HTML 原型，打开 `index.html` 即可使用。不需要安装依赖或构建。

如需通过本地服务器预览，在仓库目录运行：

```sh
python3 -m http.server 5178 --bind 127.0.0.1 --directory ui-demo
```

浏览器打开 `http://127.0.0.1:5178/`。

## 设计重点

- 总览先显示控制权、当前转速、运行范围和关键温度；原始传感器名称移到可搜索的完整列表中。
- 系统自动、随温度调节、固定转速、全速散热分别解释使用方式及结果。
- 可调节单只或两只风扇。编辑、预览、应用和已应用状态分开，支持还原编辑、撤销和恢复系统自动。
- 温度跟随设置可预览曲线；输入越界或温度顺序无效时给出具体错误，并禁用应用。
- 原型顶部可切换日常、高负载、未授权、无风扇和传感器不可用五种场景。
- 支持传感器搜索、分类、最多三个关注项、摄氏／华氏、深浅色、菜单栏预览、键盘操作和减少动画偏好。
- 桌面采用固定窗口框架及内部滚动；窄屏重新排列内容。

## 原型范围

所有设备信息、传感器名称、读数、转速范围和控制结果都是演示数据；未连接 SMC 或真实硬件。“模拟授权”不会安装辅助工具或索取密码。温度曲线参数用于展示编辑方式，不能作为真实机型的调速建议。

外观、温度单位及关注列表保存在当前浏览器的 `localStorage` 中。调速设置及模拟授权只保留在当前页面内。

新增提案包括温度趋势、友好传感器名称、关注列表、调节预览和完整引导。传感器失联后回退系统自动是本方案展示的目标行为，尚未在真实控制服务中实现。

此页面独立于本机硬件。仓库中的 macOS 应用在构建时复用界面结构，并通过 Swift 模块读取和控制设备。

## 依据

- [仓库说明](https://github.com/Changan-Su/better-macs-fan-control/blob/master/README.md)
- [现有中文界面文案](https://github.com/Changan-Su/better-macs-fan-control/blob/master/languages/Chinese_Simplified.xml)
- [官方功能与界面](https://crystalidea.com/macs-fan-control)
- [原应用预设模式](https://crystalidea.com/macs-fan-control/fan-presets)

查看时的仓库提交：`542f1a366b7086b35d8c5c7fac7dd203bf9ba09a`。

## 验证

在仓库根目录执行 `npm ci`、`npx playwright install chromium webkit` 和 `npm test`。检查涵盖参数校验、应用和撤销、单风扇作用范围、草稿保留、单位与外观切换、异常场景及 320–1440px 布局。
