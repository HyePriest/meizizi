# 原始素材

- `launcher-icons/`：七天图标加工使用的规范输入，`tool/prepare-launcher-icons.ps1` 读取这里。
- `source-emoji/`：原根目录“表情”文件夹，保留用户提供的原图。
- 其他现有设计材料保留在此。

应用实际加载的是 `assets/` 和 Android 的 `res/`。这里的原图不加入 Flutter assets 清单。
