import Testing

@testable import DanmakuCore

struct CombinerTests {
    func d(_ text: String, _ ms: Int, mode: DanmakuMode = .roll, id: UInt64 = 0, size: Int = 25) -> Danmaku {
        Danmaku(id: id, text: text, timeMs: ms, mode: mode, fontSize: size)
    }

    var settings: MergeSettings {
        var s = MergeSettings()
        s.enlarge = false
        return s
    }

    @Test func normalizer() {
        let n = TextNormalizer()
        #expect(n.normalize("  哈哈哈！！！ ") == "哈哈哈")
        #expect(n.normalize("ｈｅｌｌｏ　ｗｏｒｌｄ") == "hello world")
        #expect(n.normalize("前方 高能") == "前方高能")
        #expect(n.normalize("a   b") == "a b")
        #expect(n.normalize("???") == "???")
    }

    @Test func mergesIdenticalAndMarksCount() throws {
        let items = (0..<6).map { d("awsl", $0 * 1000, id: UInt64($0)) }
        let out = try Combiner(settings: settings).combine(items)
        #expect(out.count == 1)
        #expect(out[0].text == "awsl₍₆₎")
        #expect(out[0].mergeCount == 6)
        #expect(out[0].timeMs == 0)
    }

    @Test func mergesWidthAndPunctuationVariants() throws {
        let items = [d("前方高能", 0), d("前方高能！！", 500), d("前方　高能。", 900)]
        let out = try Combiner(settings: settings).combine(items)
        #expect(out.count == 1)
        #expect(out[0].mergeCount == 3)
    }

    @Test func mergesHomophonesViaPinyin() throws {
        // 是 / 事 share pinyin "shi".
        var s = settings
        s.maxEditDistance = 0
        s.maxCosineDistance = 11
        let items = [d("这是真的", 0), d("这事真的", 1000)]
        #expect(try Combiner(settings: s).combine(items).count == 1)
        s.usePinyin = false
        #expect(try Combiner(settings: s).combine(items).count == 2)
    }

    @Test func respectsTimeWindow() throws {
        var s = settings
        s.timeWindow = 5
        let items = [d("好耶", 0), d("好耶", 4000), d("好耶", 6000)]
        let out = try Combiner(settings: s).combine(items)
        #expect(out.map(\.mergeCount) == [2, 1])
    }

    @Test func differentModesStayApartUnlessCrossMode() throws {
        let items = [d("泪目", 0, mode: .roll), d("泪目", 100, mode: .top)]
        #expect(try Combiner(settings: settings).combine(items).count == 2)
        var s = settings
        s.crossMode = true
        s.modeElevation = true
        let out = try Combiner(settings: s).combine(items)
        #expect(out.count == 1)
        #expect(out[0].kind == .top)
    }

    @Test func joinsTheClusterItMatched() throws {
        // "AAAA" opens cluster 1, "zzzzzz" opens cluster 2; a later "AAAA" must join cluster 1, not the newest.
        let items = [d("AAAA", 0), d("zzzzzz", 100), d("AAAA", 200)]
        let out = try Combiner(settings: settings).combine(items)
        #expect(out.first { $0.text.hasPrefix("AAAA") }?.mergeCount == 2)
        #expect(out.first { $0.text.hasPrefix("zzzzzz") }?.mergeCount == 1)
    }

    @Test func excludedDanmakuPassThrough() throws {
        var s = settings
        s.processBottom = false
        var adv = d(#"[0,0,"1-1",1,"x",0,0,0,0,0,0,0,"",0]"#, 0, mode: .advanced)
        adv.parseAdvancedIfNeeded()
        let items = [d("同", 0, mode: .bottom), d("同", 10, mode: .bottom), adv]
        let out = try Combiner(settings: s).combine(items)
        #expect(out.count == 3)
    }

    @Test func markStylesAndEnlarge() throws {
        var s = MergeSettings()
        s.markStyle = .prefix
        s.markUsesSubscript = false
        let items = (0..<25).map { d("草", $0 * 10) }
        let out = try Combiner(settings: s).combine(items)
        #expect(out[0].text == "[x25]草")
        #expect(out[0].fontSize == 50)  // 25 · log 25 / log 5 = 50
        s.markStyle = .off
        #expect(try Combiner(settings: s).combine(items)[0].text == "草")
    }

    @Test func scrollConversionOfLongStaticDanmaku() throws {
        var s = settings
        s.scrollThreshold = 100
        let out = try Combiner(settings: s).combine([d("这是一条很长很长的顶部弹幕", 0, mode: .top)])
        #expect(out[0].kind == .roll)
        #expect(out[0].text.hasPrefix("↑"))
    }

    @Test func densityDropIsDeterministic() throws {
        var s = settings
        s.dropThreshold = 5
        let items = syntheticDanmaku(count: 3000, spanMs: 30_000)
        let a = try Combiner(settings: s).combine(items)
        let b = try Combiner(settings: s).combine(items)
        #expect(a == b)
        #expect(a.count < (try Combiner(settings: settings).combine(items)).count)
    }

    @Test func filterChain() async throws {
        var f = FilterSettings()
        f.keywords = ["屏蔽"]
        f.regexes = ["^\\d+$", "("]
        f.userHashes = ["bad"]
        f.showTop = false
        var m = MergeSettings()
        m.enabled = false
        let items = [
            d("正常", 0), d("要屏蔽的", 1), d("23333", 2), d("顶部", 3, mode: .top),
            Danmaku(text: "某人", timeMs: 4, userHash: "bad"),
        ]
        let out = try await FilterChain(filter: f, merge: m).run(items)
        #expect(out.map(\.text) == ["正常"])
        #expect(BlocklistFilter(settings: f).invalidPatterns == ["("])
    }
}
