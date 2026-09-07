# 在 Windows 上把 App 装进自己的 iPhone

> 一次性配置，大约 1 小时。配好之后，以后每次想要新版本，
> 在 GitHub 上点一下按钮，十几分钟后 iPhone 上的 TestFlight 就有了。
>
> **你不需要 Mac，也不需要 Xcode。** 下面每一步都能在 Windows 上完成。

---

## 为什么能这样

iOS App 必须在 macOS 上编译 —— 这一条绕不过去。
但**编译不必发生在你的电脑上**：GitHub 已经在给我们跑 macOS 机器（CI 就在上面编译）。

所以路线是：

```
你在 GitHub 点一下
   → GitHub 的 Mac 编译 + 签名 + 上传
   → Apple 处理 5–15 分钟
   → 你 iPhone 上的 TestFlight 出现新版本 → 装
```

唯一需要你自己做的，是把**签名用的证书和密钥**交给 GitHub 保管一次。
证书通常用 Mac 上的「钥匙串访问」生成，但用 OpenSSL 在 Windows 上一样能做 —— 下面就是。

---

## 你需要先有的

- [ ] **Apple 开发者账号**（Apple Developer Program，$99/年）
      上架本来就必须有，早买早用。注册后可能要等几小时到一天审核。
      https://developer.apple.com/programs/enroll/
- [ ] **一台 iPhone**，装好 App Store 里的 **TestFlight**
- [ ] **OpenSSL**（Windows）
      Git for Windows 自带：打开 **Git Bash** 就能用 `openssl`。
      验证：`openssl version`

---

## 第 1 步 · 生成证书（Windows 上做）

在 Git Bash 里，任选一个空目录：

```bash
mkdir -p ~/face3-signing && cd ~/face3-signing
```

### 1.1 生成私钥与证书请求

```bash
openssl genrsa -out private.key 2048
```

```bash
openssl req -new -key private.key -out request.certSigningRequest -subj "/emailAddress=你的邮箱/CN=face3/C=CN"
```

> `你的邮箱` 换成你的 Apple ID 邮箱。

### 1.2 到 Apple 换成证书

1. 打开 https://developer.apple.com/account/resources/certificates/list
2. 点 **+** → 选 **Apple Distribution** → Continue
3. 上传刚才的 `request.certSigningRequest` → Continue
4. **Download** 得到 `distribution.cer`，放进同一个目录

### 1.3 打包成 p12

```bash
openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
```

```bash
openssl pkcs12 -export -inkey private.key -in distribution.pem -out certificate.p12 -name "face3 distribution" -legacy
```

会让你设一个密码 —— **记下来**，等下要填进 GitHub（下面叫它 `P12_PASSWORD`）。

> `-legacy` 是必须的：新版 OpenSSL 默认用 macOS 的 `security` 命令读不了的加密方式。
> 少了它，CI 会在「导入证书」那一步失败。

---

## 第 2 步 · 注册 App 并生成描述文件

### 2.1 注册 App ID

1. https://developer.apple.com/account/resources/identifiers/list
2. **+** → App IDs → App → Continue
3. Description 填 `face3`
4. **Bundle ID 选 Explicit，填：`com.face3.app`**
   ⚠️ 必须**一模一样**，这个 ID 写在工程里
5. Capabilities 里勾上 **In-App Purchase**（订阅要用）
6. Continue → Register

### 2.2 生成描述文件

1. https://developer.apple.com/account/resources/profiles/list
2. **+** → Distribution 里选 **App Store Connect** → Continue
3. App ID 选 `com.face3.app` → Continue
4. 证书选第 1 步那张 → Continue
5. Profile Name 填 `face3 AppStore` → Generate
6. **Download** 得到 `.mobileprovision`，放进同一个目录

### 2.3 记下 Team ID

https://developer.apple.com/account 页面右上角，或 Membership 页里的 **Team ID**，
形如 `A1B2C3D4E5`。

---

## 第 3 步 · 在 App Store Connect 建 App 和 API 密钥

### 3.1 建 App

1. https://appstoreconnect.apple.com/apps → **+** → 新建 App
2. 平台 iOS，名称 `face3`，主要语言随意
3. **套装 ID 选 `com.face3.app`**
4. SKU 随便填（例如 `face3-001`），不对外显示

### 3.2 生成 API 密钥

1. https://appstoreconnect.apple.com/access/integrations/api
2. 选 **App Store Connect API** → **团队密钥** 标签 → **+**
3. 名称填 `GitHub Actions`，角色选 **App Manager**
4. 生成后：
   - 记下 **密钥 ID**（形如 `2X9R4HXF34`）
   - 记下页面上方的 **Issuer ID**（一长串 UUID）
   - **下载 `.p8` 文件 —— 只能下载一次**

---

## 第 4 步 · 把这些交给 GitHub

先把两个文件转成一行文本（Git Bash）：

```bash
base64 -w 0 certificate.p12 > cert.b64
```

```bash
base64 -w 0 *.mobileprovision > profile.b64
```

然后打开
https://github.com/fcubeve-alt/3-minite-face-ritual/settings/secrets/actions
点 **New repository secret**，逐个添加：

| Secret 名字 | 内容 |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | `cert.b64` 的全部内容 |
| `P12_PASSWORD` | 第 1.3 步设的密码 |
| `PROVISIONING_PROFILE_BASE64` | `profile.b64` 的全部内容 |
| `APPLE_TEAM_ID` | 第 2.3 步的 Team ID |
| `ASC_KEY_ID` | 第 3.2 步的密钥 ID |
| `ASC_ISSUER_ID` | 第 3.2 步的 Issuer ID |
| `ASC_PRIVATE_KEY` | `.p8` 文件的**全部内容**，含 `-----BEGIN PRIVATE KEY-----` 那两行 |

> 名字必须完全一致。GitHub 的 Secret 存进去之后看不到内容，
> 填错只能删掉重建 —— 所以粘贴时留意别少一个字符。

---

## 第 5 步 · 跑一次

1. https://github.com/fcubeve-alt/3-minite-face-ritual/actions/workflows/testflight.yml
2. 右边 **Run workflow** → 可以填一句这次改了什么 → 绿色按钮
3. 等 15–25 分钟

流水线第一步会先检查 Secret 齐不齐 —— 缺哪个会直接告诉你名字，
不用等到十几分钟后才失败。

---

## 第 6 步 · 在 iPhone 上装

1. App Store Connect → 你的 App → **TestFlight**
2. 首次会让你填**测试信息**（联系邮箱等），填完保存
3. 左边 **内部测试** → 建一个组 → 把自己加进去
4. 选刚上传的构建
5. iPhone 打开 **TestFlight** → 出现 face3 → **安装**

Apple 处理构建要 5–15 分钟，期间状态是「正在处理」，这正常。

> **内部测试不需要审核**，构建处理完就能装。
> （对外测试才需要 Apple 审一次，我们现在不需要。）

---

## 装上之后，重点看这几样

App 从没在真机上跑过，所以第一次装上主要是找问题：

- [ ] **能不能打开** —— 闪退的话把 TestFlight 里的崩溃日志发我
- [ ] **START 之后是不是直接进播放器**
- [ ] **示范视频没有时**，中间那张示意脸上有没有画出路线、起点、终点
      （20 个动作应该都能画出来，画不出来是问题）
- [ ] **点「Turn on the mirror」** 之后才弹摄像头权限，
      而不是一进播放器就弹
- [ ] **不给摄像头权限**，整套 3 分钟能不能正常做完
- [ ] **语音提示**会不会打断你正在放的音乐（应该只是压低）
- [ ] **3 分钟不碰屏幕**，会不会自动锁屏（不该锁）
- [ ] **切到后台再回来**，是不是停在暂停状态（应该是）
- [ ] **Done 页**的分钟数对不对，回首页月度汇总有没有 +1

订阅那部分要等你在 App Store Connect 里配好商品才能测 ——
没配的话 Paywall 是空的，这是预期行为，不是 bug。

---

## 出问题时

流水线失败的话，把 Actions 里那一步的报错发我。几个常见的：

| 报错里出现 | 多半是 |
| --- | --- |
| `No signing certificate` / `security: import` 失败 | p12 没加 `-legacy`，重做第 1.3 步 |
| `No profiles for 'com.face3.app'` | 描述文件的 Bundle ID 不是 `com.face3.app` |
| `Invalid Provisioning Profile` | 描述文件类型选错了，要 **App Store Connect** 不是 Ad Hoc |
| `The provided entity includes an attribute with an invalid value` | App Store Connect 里还没建这个 App（第 3.1 步） |
| `Redundant Binary Upload` | 构建号撞了 —— 流水线用的是运行编号，重新跑一次就会变 |

---

## 以后要新版本

只做第 5 步：Actions → TestFlight → Run workflow。

证书一年到期，到时候重做第 1 步并更新那两个 Secret 即可。
