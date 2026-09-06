# site/ —— 官网（落地页 + 上架必需的两个法律页）

三个自包含单文件 HTML，没有构建步骤、没有依赖、没有外部资源。放哪都能用。

| 文件 | 用途 | App Store |
| --- | --- | --- |
| `index.html` | 落地页 / 营销主页 | 选填，但审核员会点 |
| `privacy.html` | 隐私政策 | **必填，缺了不能提交** |
| `support.html` | 支持页 | **必填，缺了不能提交** |

用户协议（EULA）**不用自己写**，直接用苹果标准版：
`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`
代码里已经指向它（`LegalLinks.termsOfUse`）。

> 域名怎么选、要不要在这个站上写文章引流 —— 见 [`../docs/DOMAIN_AND_GROWTH.md`](../docs/DOMAIN_AND_GROWTH.md)。
> 简短版：建议买 `faceritual.app`（已查，可注册），但**先别急着写 SEO 文章**。

---

## 一、先填占位符

所有待填位置都用 `[[ ]]` 标了。全文搜 `[[` 找全，或者：

```bash
grep -o '\[\[[^]]*\]\]' site/*.html | sort -u
```

| 占位符 | 填什么 |
| --- | --- |
| `[[APP NAME]]` | 最终产品名（规格 §19 待你确定） |
| `[[COMPANY OR INDIVIDUAL NAME]]` | 发布者名义：公司或个人 |
| `[[SUPPORT EMAIL]]` | 客服邮箱。有域名后可以用 `support@你的域名` |
| `[[DATE]]` | 隐私政策生效日期 |
| `[[YEAR]]` | 版权年份 |

---

## 二、发布（GitHub Pages，免费）

⚠️ **主仓库是私有的，免费账号不能从私有仓库发 Pages。**
所以要单独建一个**公开**仓库放这三页。法律页面本来就是给所有人看的，公开没有问题。

1. GitHub 新建仓库，名字如 `face-ritual-site`，选 **Public**
2. 把 `site/` 里的三个 `.html` 传进去（放仓库根目录）
3. 仓库 Settings → Pages → Source 选 `main` 分支 / `/ (root)`
4. 几分钟后就能访问：
   - `https://<用户名>.github.io/face-ritual-site/`
   - `https://<用户名>.github.io/face-ritual-site/privacy.html`
   - `https://<用户名>.github.io/face-ritual-site/support.html`

这一步**不需要域名**，现在就能做完，上架的两个必填网址立刻有了。

---

## 三、接自己的域名（买了之后）

在上面那个公开仓库里加一个名为 `CNAME` 的文件（没有扩展名），内容就一行：

```
faceritual.app
```

然后在域名注册商那边加 DNS 记录：

| 类型 | 名称 | 值 |
| --- | --- | --- |
| A | `@` | `185.199.108.153` |
| A | `@` | `185.199.109.153` |
| A | `@` | `185.199.110.153` |
| A | `@` | `185.199.111.153` |
| CNAME | `www` | `<用户名>.github.io` |

回到 Settings → Pages，勾上 **Enforce HTTPS**（证书自动签，等几分钟）。

之后网址变成：
- `https://faceritual.app/`
- `https://faceritual.app/privacy.html`
- `https://faceritual.app/support.html`

> `.app` 域名整个 TLD 强制 HTTPS，所以证书签好之前浏览器会打不开 —— 这是正常的，等就行。

---

## 四、发布之后回填代码

把隐私政策网址填进 `App/FaceRitual/Features/Settings/SafetyView.swift`：

```swift
enum LegalLinks {
    static let termsOfUse: URL? = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    static let privacyPolicy: URL? = URL(string: "https://faceritual.app/privacy.html")
}
```

填之前，Debug 诊断页会显示「缺失（上架会被拒）」，Paywall 在 DEBUG 构建下也会红字提醒。

App Store Connect 后台还要填一遍：Privacy Policy URL、Support URL，
Marketing URL 填落地页。

---

## 五、文案上的硬约束

**这三页不得出现任何医学 / 美容 / 护理功效表述**（规格 §20、Sprint 3 §1）。

这条是自动检查的：

```bash
python tools/check_architecture.py     # 规则：网站文案无功效表述
```

它会扫 `site/*.html`，命中 `tighten`、`de-puff`、`anti-aging`、`visible results`
这类词就报 error。确实需要写「我们**不**声称 X」时，把那段包进：

```html
<div data-claims-disclaimer> ... </div>
```

以后往这个站上加任何页面或文章，这道闸门都会拦一遍。营销文案天然往承诺上滑，
靠自觉是拦不住的。

---

## 六、隐私政策为什么能这么写

不是套模板，是**照代码实际行为写的**：

- 全工程没有任何联网 API（唯一出网 import 是 StoreKit，只走苹果支付通道）
- 摄像头帧只在内存里过一遍就丢，不落盘、不上传
- 练习记录与设置只存在设备本地
- 没有账号、没有第三方 SDK、没有广告标识符

`tools/check_architecture.py` 有一条规则锁住「无联网」这个前提 ——
谁哪天加了网络请求，检查会失败并指回这些文案。

**这也意味着**：如果以后接入第三方 analytics（规格 §19 的待决项），
这份隐私政策、App 内的摄像头说明、以及 App Store 的隐私标签**必须一起改**。

> 我不是律师。这是一份**事实准确**的草稿 ——
> 律师审一份事实已经写对的稿子，比从零开始便宜得多。
