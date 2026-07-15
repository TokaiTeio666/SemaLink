# HarmonyOS Stage 模型

Stage 模型以 AbilityStage、UIAbility 和 ExtensionAbility 组织应用组件。UIAbility 管理一个界面能力实例的生命周期，WindowStage 承载页面窗口，应用上下文提供资源、数据库和其他系统能力的访问入口。

Stage 模型强调模块化与统一生命周期。页面加载通常在 UIAbility 的 onWindowStageCreate 中完成，前后台切换由 onForeground 和 onBackground 通知。业务对象不应依赖页面生命周期细节，适合通过 composition root 在明确位置创建并注入应用服务。
