export type BenchmarkCategory = 'direct' | 'paraphrase' | 'noisy' | 'multiConcept' |
  'longDocument' | 'singleKeyword' | 'noAnswer';
export type BenchmarkDifficulty = 'easy' | 'medium' | 'hard';
export type BenchmarkSplit = 'development' | 'holdout';

export interface AnswerableBenchmarkQuery {
  queryId: string;
  queryText: string;
  expectedDocumentIds: string[];
  optionalExpectedTerms: string[];
  category: BenchmarkCategory;
  difficulty: BenchmarkDifficulty;
  split: BenchmarkSplit;
}

export interface NoAnswerBenchmarkQuery {
  queryId: string;
  queryText: string;
  expectedDocumentIds: string[];
  optionalExpectedTerms: string[];
  category: 'noAnswer';
  difficulty: BenchmarkDifficulty;
  split: BenchmarkSplit;
}

function answered(queryId: string, queryText: string, documentId: string, expectedTerms: string[],
  category: BenchmarkCategory, difficulty: BenchmarkDifficulty, split: BenchmarkSplit): AnswerableBenchmarkQuery {
  return {
    queryId: queryId, queryText: queryText, expectedDocumentIds: [documentId],
    optionalExpectedTerms: expectedTerms, category: category, difficulty: difficulty, split: split
  };
}

function unanswered(queryId: string, queryText: string, difficulty: BenchmarkDifficulty,
  split: BenchmarkSplit): NoAnswerBenchmarkQuery {
  return {
    queryId: queryId, queryText: queryText, expectedDocumentIds: [], optionalExpectedTerms: [],
    category: 'noAnswer', difficulty: difficulty, split: split
  };
}

export const ANSWERABLE_BENCHMARK_QUERIES: AnswerableBenchmarkQuery[] = [
  answered('os-process-01', '进程和线程分别拥有哪些资源？', 'doc-4964aabe', ['地址空间', '栈'], 'direct', 'easy', 'development'),
  answered('os-process-02', '为什么说任务隔离通常由进程承担，而执行调度落在线程上？', 'doc-4964aabe', ['资源分配', '调度'], 'paraphrase', 'medium', 'development'),
  answered('os-process-03', '部署开销先不谈，同一个程序里的执行单元怎样共享堆和文件？', 'doc-4964aabe', ['线程', '共享'], 'noisy', 'hard', 'development'),
  answered('os-process-04', '比较进程的保护边界与线程切换开销', 'doc-4964aabe', ['隔离', '切换'], 'multiConcept', 'medium', 'development'),
  answered('os-process-05', '虚拟地址空间', 'doc-4964aabe', ['进程'], 'singleKeyword', 'hard', 'holdout'),

  answered('os-schedule-01', '时间片轮转适合什么类型的系统？', 'doc-6ba3ae2e', ['交互系统'], 'direct', 'easy', 'development'),
  answered('os-schedule-02', '怎样避免低优先级任务一直没有机会运行？', 'doc-6ba3ae2e', ['老化'], 'paraphrase', 'medium', 'development'),
  answered('os-schedule-03', '忽略界面刷新，长作业挡住短作业属于哪种调度缺点？', 'doc-6ba3ae2e', ['先来先服务'], 'noisy', 'hard', 'development'),
  answered('os-schedule-04', '多级反馈队列如何兼顾响应速度和持续计算任务？', 'doc-6ba3ae2e', ['队列', '时间片'], 'multiConcept', 'medium', 'development'),
  answered('os-schedule-05', '饥饿', 'doc-6ba3ae2e', ['短作业优先'], 'singleKeyword', 'hard', 'holdout'),

  answered('testing-01', '单元测试与集成测试验证的范围有什么差异？', 'doc-61ebd356', ['单元测试', '集成测试'], 'direct', 'easy', 'development'),
  answered('testing-02', '业务方最终判断产品能否交付属于哪个测试阶段？', 'doc-61ebd356', ['验收测试'], 'paraphrase', 'medium', 'development'),
  answered('testing-03', '暂时不看网络性能，模块接口和错误传播应该由什么测试覆盖？', 'doc-61ebd356', ['集成测试'], 'noisy', 'hard', 'development'),
  answered('testing-04', '为什么测试活动可以在编码完成之前开始，并且仍需自动化回归？', 'doc-61ebd356', ['需求评审', '回归测试'], 'multiConcept', 'medium', 'development'),
  answered('testing-05', '兼容性测试', 'doc-61ebd356', ['测试'], 'singleKeyword', 'hard', 'holdout'),

  answered('requirements-01', '需求分析需要识别哪些输入输出和异常路径？', 'doc-c229326c', ['输入输出', '异常路径'], 'direct', 'easy', 'development'),
  answered('requirements-02', '怎样把模糊的用户愿望转成可以验收和追踪的描述？', 'doc-c229326c', ['可验证', '可追踪'], 'paraphrase', 'medium', 'development'),
  answered('requirements-03', '先排除实现细节，参与者、业务规则和外部限制在哪个阶段澄清？', 'doc-c229326c', ['需求分析'], 'noisy', 'hard', 'development'),
  answered('requirements-04', '需求追踪如何帮助判断变更影响并减少遗漏？', 'doc-c229326c', ['设计', '测试'], 'multiConcept', 'medium', 'development'),
  answered('requirements-05', '验收标准', 'doc-c229326c', ['需求'], 'singleKeyword', 'hard', 'holdout'),

  answered('arkts-01', 'ArkTS 和 ArkUI 各自负责什么？', 'doc-fe5a9f0c', ['语言', '界面框架'], 'direct', 'easy', 'development'),
  answered('arkts-02', 'HarmonyOS 用哪种强类型语言编写业务逻辑和异步调用？', 'doc-fe5a9f0c', ['ArkTS'], 'paraphrase', 'easy', 'development'),
  answered('arkts-03', '不讨论数据库，声明式组件树怎样随状态变化更新界面？', 'doc-fe5a9f0c', ['ArkUI', '状态'], 'noisy', 'hard', 'development'),
  answered('arkts-04', '静态类型检查与页面业务边界为什么都重要？', 'doc-fe5a9f0c', ['编译阶段', '边界'], 'multiConcept', 'medium', 'development'),
  answered('arkts-05', '声明式 UI', 'doc-fe5a9f0c', ['ArkUI'], 'singleKeyword', 'hard', 'holdout'),

  answered('stage-01', 'Stage 模型中 UIAbility 的作用是什么？', 'doc-26f55d0f', ['生命周期', '界面能力'], 'direct', 'easy', 'development'),
  answered('stage-02', '页面窗口由哪个对象承载，通常又在哪里加载页面？', 'doc-26f55d0f', ['WindowStage', 'onWindowStageCreate'], 'paraphrase', 'medium', 'development'),
  answered('stage-03', '先忽略网络会话，应用前后台切换会收到哪些生命周期通知？', 'doc-26f55d0f', ['onForeground', 'onBackground'], 'noisy', 'hard', 'development'),
  answered('stage-04', '为什么 composition root 适合创建业务对象并注入应用服务？', 'doc-26f55d0f', ['生命周期', '注入'], 'multiConcept', 'medium', 'development'),
  answered('stage-05', 'AbilityStage 与 ExtensionAbility 如何共同组织应用组件？', 'doc-26f55d0f', ['Stage', '组件'], 'multiConcept', 'hard', 'holdout'),

  answered('tcp-stream-01', 'TCP 没有消息边界意味着什么？', 'doc-2988ddc9', ['字节流', '消息边界'], 'direct', 'easy', 'development'),
  answered('tcp-stream-02', '如何解决一次读取只有半条消息的问题？', 'doc-2988ddc9', ['长度字段', '部分帧'], 'paraphrase', 'medium', 'development'),
  answered('tcp-stream-03', '不考虑重传机制，为什么连续 write 可能被一次 read 合并？', 'doc-2988ddc9', ['粘包', '字节流'], 'noisy', 'hard', 'development'),
  answered('tcp-stream-04', '长度前缀协议要同时防范哪些非法长度与多帧情况？', 'doc-2988ddc9', ['过大长度', '多帧'], 'multiConcept', 'medium', 'holdout'),
  answered('tcp-stream-05', '拆包', 'doc-2988ddc9', ['TCP'], 'singleKeyword', 'hard', 'holdout'),

  answered('tcp-reliable-01', 'TCP 如何通过确认和重传保证可靠交付？', 'doc-cc3d9775', ['确认号', '重传'], 'direct', 'easy', 'development'),
  answered('tcp-reliable-02', '接收窗口为什么能阻止发送端压垮接收端？', 'doc-cc3d9775', ['流量控制'], 'paraphrase', 'medium', 'development'),
  answered('tcp-reliable-03', '先排除应用消息边界，重复确认出现时怎样更早处理丢包？', 'doc-cc3d9775', ['快速重传'], 'noisy', 'hard', 'development'),
  answered('tcp-reliable-04', '慢启动、拥塞避免和接收窗口分别解决什么约束？', 'doc-cc3d9775', ['拥塞控制', '流量控制'], 'multiConcept', 'medium', 'holdout'),
  answered('tcp-reliable-05', '序列号', 'doc-cc3d9775', ['TCP'], 'singleKeyword', 'hard', 'holdout'),

  answered('db-tx-01', '数据库事务的 ACID 分别表示什么？', 'doc-cb49d01e', ['原子性', '持久性'], 'direct', 'easy', 'development'),
  answered('db-tx-02', '事务失败后为什么必须回滚并关闭资源？', 'doc-cb49d01e', ['回滚', '资源'], 'paraphrase', 'medium', 'development'),
  answered('db-tx-03', '暂不讨论索引，如何按脏读、不可重复读和幻读风险选择隔离强度？', 'doc-cb49d01e', ['隔离级别'], 'noisy', 'hard', 'development'),
  answered('db-tx-04', '为什么事务边界既要覆盖共同成功的写操作又要保持短小？', 'doc-cb49d01e', ['事务边界', '并发'], 'multiConcept', 'medium', 'holdout'),
  answered('db-tx-05', '一致性和持久性在故障前后分别保证什么？', 'doc-cb49d01e', ['一致性', '持久性'], 'multiConcept', 'hard', 'holdout'),

  answered('db-index-01', 'B+树为什么适合范围查询和排序访问？', 'doc-ef069176', ['范围', '排序'], 'direct', 'easy', 'development'),
  answered('db-index-02', '复合索引的列顺序为什么影响查询能否利用索引？', 'doc-ef069176', ['复合索引', '列顺序'], 'paraphrase', 'medium', 'development'),
  answered('db-index-03', '忽略事务隔离，优化器如何根据统计信息选择全表扫描或索引？', 'doc-ef069176', ['查询优化器', '统计信息'], 'noisy', 'hard', 'development'),
  answered('db-index-04', '索引加速读取的同时会带来哪些存储和写入成本？', 'doc-ef069176', ['存储空间', '维护'], 'multiConcept', 'medium', 'holdout'),
  answered('db-index-05', '唯一索引如何同时支持访问和业务唯一性？', 'doc-ef069176', ['唯一索引'], 'multiConcept', 'hard', 'holdout'),

  answered('concurrency-01', '并发访问共享状态时为什么需要互斥临界区？', 'doc-2b24d582', ['数据竞争', '锁'], 'direct', 'easy', 'development'),
  answered('concurrency-02', '条件变量被唤醒后为何还必须循环检查谓词？', 'doc-2b24d582', ['虚假唤醒'], 'paraphrase', 'medium', 'development'),
  answered('concurrency-03', '先不看吞吐图，信号量许可在异常路径泄漏会造成什么后果？', 'doc-2b24d582', ['信号量', '停滞'], 'noisy', 'hard', 'development'),
  answered('concurrency-04', '死锁预防、取消传播和有界队列如何共同提升并发模块稳健性？', 'doc-2b24d582', ['死锁', '取消', '队列'], 'longDocument', 'hard', 'holdout'),
  answered('concurrency-05', '读写锁、无锁算法和消息传递应如何按真实负载取舍？', 'doc-2b24d582', ['读写锁', '消息'], 'longDocument', 'hard', 'holdout'),

  answered('tcp-long-01', '长度前缀解码器怎样处理半包和一次读取多个帧？', 'doc-c78adc90', ['长度前缀', '多个帧'], 'direct', 'easy', 'development'),
  answered('tcp-long-02', '多字节 UTF-8 字符跨两次网络读取时应该何时解码？', 'doc-c78adc90', ['完整帧', '无效编码'], 'paraphrase', 'medium', 'development'),
  answered('tcp-long-03', '先忽略 UI，重连后为什么不能盲目重发最后一条业务请求？', 'doc-c78adc90', ['幂等', '重复写入'], 'noisy', 'hard', 'development'),
  answered('tcp-long-04', 'HELLO 版本协商、心跳和优雅关闭分别属于会话的哪些环节？', 'doc-c78adc90', ['HELLO', '心跳', '关闭'], 'longDocument', 'hard', 'holdout'),
  answered('tcp-long-05', 'TLS、分层超时和资源上限如何影响协议工程？', 'doc-c78adc90', ['TLS', '超时', '最大帧长'], 'longDocument', 'hard', 'holdout')
];

export const NO_ANSWER_BENCHMARK_QUERIES: NoAnswerBenchmarkQuery[] = [
  unanswered('none-01', '量子引力黑洞蒸发实验数据有哪些结论？', 'hard', 'development'),
  unanswered('none-02', '银河系暗物质晕的最新观测质量是多少？', 'hard', 'development'),
  unanswered('none-03', '如何诊断急性心肌梗死并选择药物剂量？', 'hard', 'development'),
  unanswered('none-04', 'CRISPR 基因编辑的脱靶率如何计算？', 'hard', 'development'),
  unanswered('none-05', '宋代青瓷窑口的考古分期依据是什么？', 'medium', 'development'),
  unanswered('none-06', '火星土壤样本的高氯酸盐浓度是多少？', 'hard', 'development'),
  unanswered('none-07', '如何证明黎曼猜想？', 'hard', 'development'),
  unanswered('none-08', '量子纠缠隐形传态实验需要哪些光学器件？', 'hard', 'development'),
  unanswered('none-09', '儿童疫苗接种后发热应怎样用药？', 'hard', 'development'),
  unanswered('none-10', '古典吉他的西班牙轮指怎样练习？', 'medium', 'development'),
  unanswered('none-11', '热带气旋眼墙置换过程如何预测？', 'hard', 'development'),
  unanswered('none-12', '蛋白质折叠中的分子伴侣有哪些家族？', 'hard', 'development'),
  unanswered('none-13', '油画颜料的罩染媒介怎样配比？', 'medium', 'development'),
  unanswered('none-14', '系外行星凌日光变曲线如何反演半径？', 'hard', 'development'),
  unanswered('none-15', '锂硫电池穿梭效应的电化学机理是什么？', 'hard', 'holdout'),
  unanswered('none-16', '甲骨文中祭祀卜辞有哪些语法特征？', 'hard', 'holdout'),
  unanswered('none-17', '深海热液喷口的化能合成生态如何形成？', 'hard', 'holdout'),
  unanswered('none-18', '小麦锈病抗性基因如何定位？', 'hard', 'holdout'),
  unanswered('none-19', '引力波双中子星并合如何约束状态方程？', 'hard', 'holdout'),
  unanswered('none-20', '巴洛克复调音乐的赋格主题怎样发展？', 'medium', 'holdout')
];
