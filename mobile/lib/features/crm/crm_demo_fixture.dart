// Synthetic data from the approved HTML prototype. Never used in live mode.
const crmDemoFixture = r'''
{
  "customers": [
    {
      "id": "lin",
      "name": "林小满",
      "type": "个人",
      "initial": "林",
      "subtitle": "商城会员 · 演出年卡",
      "owner": "陈晨",
      "since": "2025.06.18",
      "pending": 2,
      "contact": "138 **** 0268",
      "note": "偏好周末场次；服务安排以本人确认结果为准。",
      "members": [
        "club",
        "annual"
      ]
    },
    {
      "id": "heyu",
      "name": "禾屿设计工作室",
      "type": "企业",
      "initial": "禾",
      "subtitle": "企业参访 · 主题沙龙",
      "owner": "许禾",
      "since": "2025.09.12",
      "pending": 1,
      "contact": "021 **** 0620",
      "note": "企业联系人分工不同，活动通知由项目联系人统一接收。",
      "members": []
    },
    {
      "id": "zhou",
      "name": "周知夏",
      "type": "个人",
      "initial": "周",
      "subtitle": "演出年卡 · 私宴服务",
      "owner": "陈晨",
      "since": "2025.03.10",
      "pending": 0,
      "contact": "139 **** 0526",
      "note": "年卡已到期，历史使用记录继续保留。",
      "members": [
        "expired"
      ]
    },
    {
      "id": "qingshan",
      "name": "青山文化",
      "type": "企业",
      "initial": "青",
      "subtitle": "沙龙 · 企业合作",
      "owner": "许禾",
      "since": "2026.02.16",
      "pending": 0,
      "contact": "020 **** 0719",
      "note": "合作资料由公司业务负责人维护。",
      "members": []
    },
    {
      "id": "shen",
      "name": "沈予安",
      "type": "个人",
      "initial": "沈",
      "subtitle": "商城会员",
      "owner": "陈晨",
      "since": "2026.07.02",
      "pending": 0,
      "contact": "136 **** 0319",
      "note": "暂无补充说明。",
      "members": [
        "club"
      ]
    },
    {
      "id": "yun",
      "name": "云间科技有限公司",
      "type": "企业",
      "initial": "云",
      "subtitle": "企业参访",
      "owner": "许禾",
      "since": "2026.10.20",
      "pending": 0,
      "contact": "010 **** 0921",
      "note": "企业参访资料已归档。",
      "members": []
    }
  ],
  "qualifications": {
    "club": {
      "name": "拾光商城会员",
      "source": "商城会员体系",
      "status": "有效",
      "from": "2026.06.18",
      "until": "2027.06.17",
      "benefits": [
        [
          "会员专属选品",
          "有效期内可享",
          "不限次"
        ],
        [
          "专属咨询服务",
          "按约定预约",
          "不限次"
        ]
      ],
      "history": [
        [
          "2026.11.18",
          "已享用会员专属选品"
        ],
        [
          "2026.10.08",
          "专属咨询服务已完成"
        ]
      ]
    },
    "annual": {
      "name": "星光演出年卡",
      "source": "线下演出 · 计次资格",
      "status": "有效",
      "from": "2026.01.01",
      "until": "2026.12.31",
      "benefits": [
        [
          "演出入场权益",
          "已用 4 次 / 共 6 次",
          "余 2 次"
        ],
        [
          "演出预约咨询",
          "有效期内可享",
          "不限次"
        ]
      ],
      "history": [
        [
          "2026.10.18",
          "秋日音乐现场 · 入场核销 1 次"
        ],
        [
          "2026.08.09",
          "夏夜音乐会 · 入场核销 1 次"
        ],
        [
          "2026.05.16",
          "城市之声 · 入场核销 1 次"
        ],
        [
          "2026.03.21",
          "春日音乐会 · 入场核销 1 次"
        ]
      ]
    },
    "expired": {
      "name": "星光演出年卡",
      "source": "线下演出 · 历史资格",
      "status": "已到期",
      "from": "2025.11.01",
      "until": "2026.10.31",
      "benefits": [
        [
          "演出入场权益",
          "历史已用 5 次 / 共 6 次",
          "已失效"
        ]
      ],
      "history": [
        [
          "2026.09.20",
          "周末音乐现场 · 入场核销 1 次"
        ]
      ]
    }
  },
  "records": [
    {
      "id": "s1",
      "customer": "lin",
      "kind": "services",
      "type": "会员服务",
      "name": "冬日演出预约协助",
      "status": "待完成",
      "date": "2026.12.05",
      "owner": "陈晨",
      "staff": "陈晨、许禾",
      "source": "星光演出年卡",
      "description": "确认客户意向场次及到场时间，预约结果需由客户确认。",
      "events": [
        [
          "11.25 15:30",
          "已确认意向场次"
        ],
        [
          "11.24 10:00",
          "已登记服务需求"
        ]
      ]
    },
    {
      "id": "s2",
      "customer": "lin",
      "kind": "services",
      "type": "私宴服务",
      "name": "生日私宴菜单确认",
      "status": "待完成",
      "date": "2026.12.12",
      "owner": "许禾",
      "staff": "许禾、陈晨",
      "source": "高端私宴",
      "description": "确认人数、菜品及饮食偏好，保留最终确认记录。",
      "events": [
        [
          "11.25 11:20",
          "已发送首版菜单"
        ],
        [
          "11.23 14:00",
          "已登记需求"
        ]
      ]
    },
    {
      "id": "s3",
      "customer": "lin",
      "kind": "services",
      "type": "会员服务",
      "name": "秋季会员礼遇咨询",
      "status": "已完成",
      "date": "2026.10.08",
      "owner": "陈晨",
      "staff": "陈晨",
      "source": "拾光商城会员",
      "description": "已完成会员礼遇说明，客户确认收到服务信息。",
      "events": [
        [
          "10.08 16:00",
          "服务完成 · 陈晨确认"
        ]
      ]
    },
    {
      "id": "s4",
      "customer": "heyu",
      "kind": "services",
      "type": "活动交付",
      "name": "沙龙会后资料交付",
      "status": "待完成",
      "date": "2026.11.28",
      "owner": "许禾",
      "staff": "许禾、陈晨",
      "source": "设计与生活主题沙龙",
      "description": "整理经授权的分享资料，发送给企业项目联系人。",
      "events": [
        [
          "11.25 17:00",
          "资料整理中"
        ],
        [
          "11.22 18:00",
          "活动已结束，资料尚未交付"
        ]
      ]
    },
    {
      "id": "s5",
      "customer": "lin",
      "kind": "services",
      "type": "预约服务",
      "name": "夏夜场次预约",
      "status": "已取消",
      "date": "2026.07.12",
      "owner": "陈晨",
      "staff": "陈晨",
      "source": "星光演出年卡",
      "description": "客户行程调整后取消预约；本次没有核销权益。",
      "events": [
        [
          "07.12 09:00",
          "客户取消 · 陈晨记录"
        ]
      ]
    },
    {
      "id": "a1",
      "customer": "lin",
      "kind": "activities",
      "type": "赛演",
      "name": "秋日音乐现场",
      "status": "已结束",
      "date": "2026.10.18",
      "owner": "陈晨",
      "staff": "陈晨、许禾",
      "source": "线下演出",
      "description": "已到场参加。入场权益另有核销记录，活动状态不代替权益流水。",
      "events": [
        [
          "10.18 21:30",
          "活动结束"
        ],
        [
          "10.18 18:30",
          "到场记录已登记"
        ]
      ]
    },
    {
      "id": "a2",
      "customer": "lin",
      "kind": "activities",
      "type": "私宴",
      "name": "冬日生日私宴",
      "status": "筹备中",
      "date": "2026.12.12",
      "owner": "许禾",
      "staff": "许禾、陈晨",
      "source": "高端私宴交付",
      "description": "菜单和人数待确认。具体待办见该客户的服务记录。",
      "events": [
        [
          "11.23 14:00",
          "已确认初步安排"
        ]
      ]
    },
    {
      "id": "a3",
      "customer": "heyu",
      "kind": "activities",
      "type": "沙龙",
      "name": "设计与生活主题沙龙",
      "status": "已结束",
      "date": "2026.11.22",
      "owner": "许禾",
      "staff": "许禾、陈晨、周舟",
      "source": "线下沙龙",
      "description": "主题交流已完成，会后资料交付仍在进行。",
      "events": [
        [
          "11.22 18:00",
          "沙龙结束"
        ],
        [
          "11.22 14:00",
          "企业代表签到"
        ]
      ]
    },
    {
      "id": "a4",
      "customer": "heyu",
      "kind": "activities",
      "type": "企业参访",
      "name": "城市创新空间参访",
      "status": "已结束",
      "date": "2026.09.16",
      "owner": "陈晨",
      "staff": "陈晨、许禾",
      "source": "B 端商业参访",
      "description": "参访与交流结束，参访资料已归档。",
      "events": [
        [
          "09.16 17:00",
          "参访完成"
        ]
      ]
    },
    {
      "id": "a5",
      "customer": "heyu",
      "kind": "activities",
      "type": "沙龙",
      "name": "品牌交流沙龙",
      "status": "筹备中",
      "date": "2026.12.08",
      "owner": "许禾",
      "staff": "许禾、周舟",
      "source": "线下沙龙",
      "description": "正在确认嘉宾名单及活动议程。",
      "events": [
        [
          "11.25 09:00",
          "已登记业务"
        ]
      ]
    },
    {
      "id": "a6",
      "customer": "heyu",
      "kind": "activities",
      "type": "企业参访",
      "name": "秋季工坊参访",
      "status": "已结束",
      "date": "2026.08.12",
      "owner": "陈晨",
      "staff": "陈晨",
      "source": "B 端商业参访",
      "description": "交流记录已归档。",
      "events": [
        [
          "08.12 16:00",
          "参访完成"
        ]
      ]
    },
    {
      "id": "o1",
      "customer": "lin",
      "kind": "orders",
      "type": "商城订单",
      "name": "秋日会员精选礼盒",
      "status": "已完成",
      "date": "2026.11.18",
      "owner": "陈晨",
      "source": "拾光商城",
      "number": "DEMO-20261118-001",
      "amount": "¥ 268.00",
      "refund": "¥ 0.00",
      "description": "订单状态及金额以商城返回记录为准。金额仅用于本单核对。",
      "events": [
        [
          "11.21 15:00",
          "订单完成"
        ],
        [
          "11.18 10:20",
          "下单并支付"
        ]
      ]
    },
    {
      "id": "o2",
      "customer": "lin",
      "kind": "orders",
      "type": "商城订单",
      "name": "周末茶点组合",
      "status": "配送中",
      "date": "2026.11.24",
      "owner": "陈晨",
      "source": "拾光商城",
      "number": "DEMO-20261124-002",
      "amount": "¥ 128.00",
      "refund": "¥ 0.00",
      "description": "本次订单由商城提供配送状态。",
      "events": [
        [
          "11.25 09:20",
          "已发货"
        ],
        [
          "11.24 13:40",
          "已支付"
        ]
      ]
    },
    {
      "id": "o3",
      "customer": "lin",
      "kind": "orders",
      "type": "商城订单",
      "name": "会员季节精选",
      "status": "已退款",
      "date": "2026.10.02",
      "owner": "陈晨",
      "source": "拾光商城",
      "number": "DEMO-20261002-003",
      "amount": "¥ 198.00",
      "refund": "¥ 198.00",
      "description": "本单已全额退款。订单原实付与退款分别展示，不作营收汇总。",
      "events": [
        [
          "10.04 12:00",
          "全额退款完成"
        ]
      ]
    },
    {
      "id": "o4",
      "customer": "lin",
      "kind": "orders",
      "type": "商城订单",
      "name": "夏日会员礼包",
      "status": "已完成",
      "date": "2026.08.16",
      "owner": "陈晨",
      "source": "拾光商城",
      "number": "DEMO-20260816-004",
      "amount": "¥ 168.00",
      "refund": "¥ 0.00",
      "description": "历史订单记录。",
      "events": [
        [
          "08.20 12:00",
          "订单完成"
        ]
      ]
    }
  ]
}
''';
