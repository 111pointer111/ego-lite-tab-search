# 组件参考

界面结构移植自 beUI Command Palette，保留搜索输入、紧凑结果列表、选中行、键盘导航和圆角面板的组织方式。原始 Web 组件的最大宽度、16px 面板圆角、12px 图标间隔和 8px 列表内边距作为原生界面参考。为标题、网址及空间信息增加了双行布局。

- [beUI Command Palette](https://beui.dev/components/blocks/command-palette)
- [上游组件源码](https://github.com/starc007/ui-components/blob/main/components/motion/command-palette.tsx)
- [MIT 授权全文](licenses/beui-MIT.txt)

毛玻璃材质参考 ExpoKit Glass Search Bar 和 Glass Sheet。ExpoKit 文档采用原生玻璃或系统模糊材质适配不同平台。本工具使用 macOS NSVisualEffectView 的系统材质，遵循系统明暗模式与辅助功能设置。ExpoKit Pro 仅用于公开视觉与交互参考。

- [ExpoKit Glass 公开说明](https://expokit.in/docs/glass)

应用图标由 OpenAI 图像生成工具生成。原始提示词见 `Assets/icon-prompt.txt`。
