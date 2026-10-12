# 富文本回复

支持 **粗体**、*斜体*、~~删除线~~、`行内代码` 和 https://example.com。

> 引用可以包含 **强调**。

> [!TIP]
> 内容随生成逐步出现，代码和表格可以横向滚动。

1. 有序列表
   - 嵌套项目
2. 第二项

- [x] 已完成
- [ ] 待完成

| 能力 | iPhone | iPad | Mac |
| :--- | :---: | :---: | ---: |
| Markdown | ✓ | ✓ | ✓ |
| Mermaid | ✓ | ✓ | ✓ |

```swift
let message = "你好🙂"
print(message)
```

```mermaid
flowchart LR
    A[接收文本] --> B[Markdown]
    B --> C[逐步显示]
```

公式 $E = mc^2$ 与脚注[^1]。

$$
\frac{a}{b} + \sqrt{x}
$$

<details><summary>更多说明</summary>可以展开阅读。</details>

[^1]: 脚注支持返回正文。
