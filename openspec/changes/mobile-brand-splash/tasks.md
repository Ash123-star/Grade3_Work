## 1. Planning
- [x] 1.1 明确布局、动画、状态保留和异常范围，通过实施前strict：33 passed / 0 failed，退出码0。

## 2. Implementation and acceptance
- [ ] 2.1 接入CustomPainter三色角色与名称、入场及交叉淡化；实际冷启动和大小屏视觉验收尚未执行。
- [ ] 2.2 维持底层挂载与原登录流程，减少动画及输入/焦点保护；运行态状态与异常验收尚未执行。
- [ ] 2.3 统一原生启动背景和矢量角色；Android不同版本冷启动验收尚未执行。
- [x] 2.4 完成定向Dart分析、XML资源检查和diff检查：No issues found，7个XML解析及资源引用检查通过，命令退出码均0，详见verification.md。

用户此前只允许定向静态检查，本批不执行测试、构建、模拟器或设备。未取得运行证据的事项不勾选。
