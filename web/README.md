# moonform browser demo

moonform + tiye/react 的登录表单浏览器演示：required/email/min-length 实时校验、
blur 触发、错误呈现、提交生命周期（校验拦截 → 成功欢迎语）。

## 运行

```bash
# 1. 构建 wasm-js 产物（生成 _build/js/release/build/web-demo/web-demo.js）
moon build src/web-demo --target js --release

# 2. 拷贝产物到 web/（重命名为 main.js）
Copy-Item _build\js\release\build\web-demo\web-demo.js web\main.js   # Windows
cp _build/js/release/build/web-demo/web-demo.js web/main.js          # *nix

# 3. 静态服务 web/ 目录（React 从 unpkg CDN 加载）
npx serve web
# 或 python -m http.server -d web
```

打开 http://localhost:3000 ：

1. 输入非法 email（如 `ab`）→ 失焦后显示 "Invalid email address" 等错误
2. 修正为合法 email + ≥8 位密码 → 错误清除
3. 提交 → "Welcome, you@example.com!"

## 实现说明

- 表单状态/校验全部在 moonform（core + rules），React 侧仅经
  `FieldBridge`（`use_sync_external_store` 契约）消费快照
- 宿主页提供 `globalThis.React / ReactDOM`（tiye/react 契约）
- 组件源码：`src/web-demo/main.mbt`
