# moonform browser demo

两个浏览器演示（tiye/react + moonform core/react/schema）：

1. **login**（`index.html`）：单表单登录——required/email/min-length 实时校验、
   blur 触发、错误呈现、提交生命周期（校验拦截 → 成功欢迎语）
2. **wizard**（`wizard.html`）：多步分组表单——step 1 用 moonschema schema 作组校验器
   （错误经 JSON-Pointer 路径分发到子字段），step 2 用手工双通道校验器
   （组级错误 + 字段错误）；组提交把关每一步，最终整表提交

## 运行

```bash
# 1. 构建 js 产物（各自生成到 _build/js/release/build/ 下）
moon build src/web-demo --target js --release
moon build src/web-demo-wizard --target js --release

# 2. 拷贝产物到 web/（重命名）
Copy-Item _build\js\release\build\web-demo\web-demo.js web\main.js         # Windows
Copy-Item _build\js\release\build\web-demo-wizard\web-demo-wizard.js web\wizard.js
cp _build/js/release/build/web-demo/web-demo.js web/main.js                # *nix
cp _build/js/release/build/web-demo-wizard/web-demo-wizard.js web/wizard.js

# 3. 静态服务 web/ 目录（React 从本地 vendor 加载）
npx serve web
# 或 python -m http.server -d web
```

打开 http://localhost:3000/index.html （登录表单）或
http://localhost:3000/wizard.html （分步表单）。

login 的操作路径：

1. 输入非法 email（如 `ab`）→ 失焦后显示 "Invalid email address" 等错误
2. 修正为合法 email + ≥8 位密码 → 错误清除
3. 提交 → "Welcome, you@example.com!"

wizard 的操作路径：

1. step 1 输入过短用户名 / 非法 email → schema 错误按字段呈现；"Next" 被组校验拦截
2. 修正 → 错误清除 → "Next" 进入 step 2
3. 空 nickname 点 "Finish" → 组级错误 "Nickname is required"；过短 → 字段错误
4. 填 "moon" → "Finish" → **异步整表提交**（真实时钟宿主适配器）：按钮进入
   "Submitting..." 禁用态（FormBridge 快照驱动）→ 600ms 后完成 → "Done, moon!"

## 无头验证

```bash
node tools/headless-verify.cjs
# → ALL <N> BROWSER CHECKS PASSED（login + wizard，N 由注册的检查项动态推导）
```

## 实现说明

- 表单状态/校验全部在 moonform（core + rules + schema），React 侧仅经
  `FieldBridge` / `GroupBridge` / `FormBridge`（`use_sync_external_store` 契约）消费快照
- wizard 的 step 1 组校验器来自 `@formSchema.schema_group_validator`
  （moonschema 编译的 schema → 组值校验 → 错误按组内相对路径分发给子字段）
- wizard 的最终提交是**异步**的：`@formreact.real_clock()` 宿主时钟（真实定时器）
  驱动 `is_submitting` 生命周期——与测试中的 VirtualClock 同一协议
- 宿主页提供 `globalThis.React / ReactDOM`（tiye/react 契约）
- 组件源码：`src/web-demo/main.mbt`、`src/web-demo-wizard/main.mbt`
