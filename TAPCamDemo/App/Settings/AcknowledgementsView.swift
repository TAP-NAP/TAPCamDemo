import SwiftUI

struct AcknowledgementsView: View {
    private static let names = [
        "0xhhh",
        "Alex",
        "Amos",
        "Bangbang",
        "Cat",
        "Chen",
        "Clover",
        "Constantin",
        "Eggy",
        "Even",
        "Fay",
        "Francy",
        "FuYongjun",
        "GuoYu",
        "Jade",
        "Jerry",
        "Jesse",
        "Jetson",
        "Jiang",
        "JiaoYao",
        "JiaXue",
        "Kaka",
        "Lucian",
        "Luminous",
        "Pollux",
        "Qiao",
        "Ray",
        "Ren",
        "Riely",
        "Roger",
        "Sensen",
        "Titian",
        "Togo",
        "Vee",
        "WYZ",
        "Xiaochuan",
        "Xiaoyu",
        "Yifan",
        "Yingfei",
        "Yiwen",
        "YouYang",
        "YuanBo",
        "Yuemin",
        "Zhang",
        "阿菜",
        "阿喜",
        "安非他命",
        "陈浩",
        "电脑",
        "番茄",
        "飞离赛特",
        "红橙",
        "鸡丁",
        "昆妮",
        "刘磊",
        "麦咪",
        "噗噗",
        "尾麦",
        "未完成",
        "五一",
        "小布",
        "小熊",
        "鱼翅",
        "走弋",
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Text(verbatim: "感谢你们提供的支持、建议、帮助和反馈。")

                ForEach(Self.names, id: \.self) { name in
                    Text(verbatim: name)
                }

                Text(verbatim: "以及感谢我的父母和姥姥。")
                Text(verbatim: "And You 🩵")
                Text(verbatim: "希望我们在未来遥远的某一天，依旧能看到漂流来的真实的回忆。")
            }
            .font(.footnote)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
