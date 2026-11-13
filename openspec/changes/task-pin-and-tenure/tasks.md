## 1. Planning
- [x] 1.1 用户确认本设计；核对迁移编号与租户外键
## 2. Task pin
- [x] 2.1 迁移 task_pins
- [x] 2.2 置顶/取消接口（权限、上限、幂等、JavaDoc、OpenApi）
- [x] 2.3 列表返回 pinned/pinnedAt 并置顶优先排序
- [x] 2.4 移动端 Repository/Mock 与任务管理表、详情置顶开关
## 3. Tenure
- [x] 3.1 tenureLabel 工具函数
- [x] 3.2 我的页与个人资料页展示，Mock 补字段
## 4. Docs & Verification
- [x] 4.1 backend-interface.md、openapi.json、database-schema.md
- [x] 4.2 后端相关测试通过；`scripts/test-backend.ps1` 全量仍有与基线一致的既有失败
- [x] 4.3 Flutter analyze 与相关测试通过；全量仍有与基线一致的既有失败

备注（2026-11-01）：迁移编号确定为 V29；4.2/4.3 中全量套件既有失败与基线一致，相关测试全部通过，见 docs/zhw-week7-validation.md。

## 5. Tenure day precision
- [x] 5.1 Issue #84：统一显示年月天，验证同日、月末、闰日、空值、未来和无效日期；证据见 docs/backend-validation.md 的个人资料与首页修正段落。
