# site/ —— 上架必需的两个网页

苹果提交 App 时有两个网址是**必填**的，缺了不能提交：

| 网址 | 用途 | 文件 |
| --- | --- | --- |
| Privacy Policy URL | 所有 App 强制 | `privacy.html` |
| Support URL | 所有 App 强制 | `support.html` |

第三个 —— 用户协议（EULA）—— **不用自己写**，直接用苹果的标准版即可：
`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`
代码里已经指向它（`LegalLinks.termsOfUse`）。

---

## 怎么发布（三选一）

这两个文件是**自包含的单文件 HTML**，没有构建步骤、没有依赖，放哪都能用。

### 方案 A：GitHub Pages（免费，推荐先用这个）

⚠️ **注意**：主仓库是私有的，而免费账号**不能**从私有仓库发布 Pages。
所以要单独建一个**公开**仓库专门放这两页：

1. GitHub 新建仓库，名字如 `face-ritual-site`，选 **Public**
2. 把 `site/` 里的 `privacy.html` 和 `support.html` 传进去
3. 仓库 Settings → Pages → Source 选 `main` 分支根目录
4. 几分钟后拿到网址：
   - `https://<用户名>.github.io/face-ritual-site/privacy.html`
   - `https://<用户名>.github.io/face-ritual-site/support.html`

法律页面本来就是要给所有人看的，放公开仓库没有任何问题。

### 方案 B：自己的域名（定了产品名之后）

买域名（约 60–100 元/年），把这两个文件上传，得到
`https://你的域名/privacy` 这样的地址。看起来更正规，还能配 `support@你的域名` 邮箱。

**别在定产品名之前买** —— 先买域名再想名字是倒过来的。

### 方案 C：Notion / Carrd / Google Sites

把正文贴进去发布成公开页面也行。苹果只要求网址能打开。

---

## 发布之后

把两个网址填进 `App/FaceRitual/Features/Settings/SafetyView.swift` 的 `LegalLinks`：

```swift
enum LegalLinks {
    static let termsOfUse: URL? = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    static let privacyPolicy: URL? = URL(string: "https://你的地址/privacy.html")
}
```

填之前，Debug 诊断页会显示「缺失（上架会被拒）」，Paywall 在 DEBUG 构建下也会红字提醒。

---

## 待填的占位符

两个文件里所有待填位置都用 `[[ ]]` 标了，全文搜索 `[[` 即可找全：

| 占位符 | 填什么 |
| --- | --- |
| `[[APP NAME]]` | 最终产品名（规格 §19 Owner 待定） |
| `[[COMPANY OR INDIVIDUAL NAME]]` | 发布者名义：公司或个人 |
| `[[SUPPORT EMAIL]]` | 客服邮箱 |
| `[[DATE]]` | 隐私政策生效日期 |

---

## 内容为什么是这样写的

隐私政策**不是套模板，是照代码实际行为写的**：

- 全工程没有任何联网 API（唯一出网 import 是 StoreKit，只走苹果支付通道）
- 摄像头帧只在内存里过一遍就丢，不落盘、不上传
- 练习记录与设置只存在设备本地
- 没有账号、没有第三方 SDK、没有广告标识符

`tools/check_architecture.py` 有一条规则锁住「无联网」这个前提 ——
谁哪天加了网络请求，检查会直接失败并指回这些文案。

**这也意味着**：如果以后接入第三方 analytics（规格 §19 的待决项），
这份隐私政策、App 内的摄像头说明、以及 App Store 的隐私标签**必须一起改**。

> 我不是律师。这是一份**事实准确**的草稿 ——
> 律师审一份事实已经写对的稿子，比从零开始便宜得多。
