## 1. Planning

- [x] 1.1 Compare local storage routes and define encrypted Drift/session boundaries.
- [x] 1.2 Create proposal, design, spec and acceptance matrix; planning strict validation15 passed exit0; compatible dependency resolution exit0 (SDK/file_picker constraints recorded).

## 2. Encrypted drafts

- [x] 2.1 Add Drift schema1, opaque HMAC lookup and AES-GCM envelope with secure key provider; real SQLite file reopen/random nonce/swapped ciphertext/missing key tests passed exit0.
- [x] 2.2 Replace form save/restore/clear and dashboard indicator; exact migration/readback/cleanup and UI failure/input recovery passed; no new plaintext preference writes.
- [x] 2.3 Add account/date/server/revision/corruption tests; extended HTTP diary test disposes/reopens editor and retains server version9 then submit10; verification documented in mobile/docs/secure-local-state-verification.md.

## 3. Secure session recovery

- [x] 3.1 Add minimal secure credential store and main startup auth/me gate; pending recovery allows onlyauth/me/public departments, no business reads; platform secure storage injected in tests, device evidence remains4.3.
- [x] 3.2 Connect logout/expiry/password/rejected recovery clearing and conditional token isolation; network failure preserves explicit retry and drafts; old-token cleanup/new-account recovery tests passed exit0.
- [x] 3.3 Add15 local-state tests including actual SQL persistence, malformed/expired/rejected credentials, pending/password, held/late recovery and UI failure; both Mock/formal runs passed exit0.

## 4. Unified acceptance

- [x] 4.1 Final analyzer exit0, full Mock124/formal96 tests exit0, strict15 passed exit0, diffcheck exit0; new360dp/font1.5 recovery render inspected and original editor compared. NoAPK.
- [x] 4.2 Update report, audit, API contract, README, local Issue and originalstage3 task3.6 reference; distinguish payload encryption/SQL and injected platform tests from device proof.
- [ ] 4.3 Verify native AndroidKeystore/SQLite hooks, restart/lockscreen/backup exclusions and TalkBack on an available device without an APK build in this environment; current Windows Flutter tests do not prove native plugin deployment.
- [x] 4.4 User explicitly authorized all current changes on HCJ; associate Issue #7, push ba7369a and create draft PR #9 via official GitHub API. Delivery: mobile/docs/hcj-delivery.md. Native device4.3 remains unverified.

## 5. 认证记录与启动复核（2026-10-29）

- [ ] 5.1 安全写入回读确认、默认记住登录说明和 Android 网络权限
- [ ] 5.2 验证登录后重建应用状态免输密码、写入失败、失效及隔离，记录明确退出码
- [ ] 5.3 统一分析和 APK 编译，更新文档并说明设备和有效期边界

- [ ] 5.4 默认会话168小时，同步部署配置并验证签发到期时间、撤销和过期拒绝
