# 签名配置说明

当前 `.sign/sign-config.json5` 使用 DevEco 自动生成的调试签名材料（华为开发者账号自动签名）。
证书持有者、账号与 Profile 信息不写入仓库，也不进日志。

应用代码、`AppScope`、`build-profile.json5` 不能直接改变证书持有者身份。要更换签名账号，必须在 DevEco 中重新生成签名配置：

1. 打开 DevEco Studio → **File → Project Structure → Signing Configs**；
2. 退出当前华为开发者账号，登录目标账号；
3. 选择 `default` 配置，勾选 **Automatically generate signature**；
4. 确认 Bundle name 为 `com.gduthelper.app`，选择调试证书和设备；
5. 点击 **Apply/OK**，DevEco 会生成新的 `.cer`、`.p12`、`.p7b` 并更新 `.sign/sign-config.json5`；
6. 执行 **Build → Clean Project** 后重新构建。

注意：

- 仅修改 `keyAlias`、文件名或 `vendor` 不会改变证书身份；
- 不要手工替换 `.p7b`，它与证书和华为开发者账号绑定；
- 当前自动签名 Profile 未开通“代理提醒”权益，真机 ReminderAgent 返回 `1700002`，系统日历提醒与即时本地通知仍可用；
- 签名材料不要提交到仓库；
- 本项目 1.1.0 的侧载分发以 GitHub Actions 构建的 unsigned HAP 为主，不依赖 CI 签名。unsigned 构建会移除 `signingConfig`，产物为 `entry-default-unsigned.hap`；
- 本地 release 构建仍使用 DevEco 自动签名配置，仅用于模拟器/真机调试。
