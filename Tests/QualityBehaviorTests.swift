import Foundation

enum QualityTestFailure: Error { case assertion(String) }
@main struct QualityBehaviorTests {
    static func main() async throws {
        var passed: [String] = []
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw QualityTestFailure.assertion(name) }; passed.append(name)
        }
        for (name,text) in [
            ("blank"," \t\r\n\n"), ("paragraphs","  Hello world.\r\n\r\nNext line.\n"),
            ("CJK",String(repeating:"明日の会議は午前九時です。",count:1000)),
            ("emoji",String(repeating:"👨‍👩‍👧‍👦 café e\u{301} ",count:1000)),
            ("long word",String(repeating:"a",count:20_000)),
            ("20k source",String(repeating:"The backup must not be deleted. ",count:625))
        ] {
            let pieces = TranslationChunker.pieces(text)
            try check(pieces.map(\.original).joined() == text,name + " lossless segmentation")
            try check(pieces.allSatisfy { if case .text(let value) = $0 { return value.utf8.count <= 1700 && !value.isEmpty && !value.contains(where: \.isNewline) }; return true },name + " bounded single-line chunks")
        }
        let pathological = "a" + String(repeating:"\u{301}",count:2000)
        try check(TranslationChunker.pieces(pathological).map(\.original).joined() == pathological,"oversized grapheme preserved for explicit refusal")
        try check(TranslationChunker.preservesProtectedFragments(source:"Hello {user_name} https://example.com %1$@",output:"Привет {user_name} https://example.com %1$@"),"protected placeholders preserved")
        try check(!TranslationChunker.preservesProtectedFragments(source:"Hello {user_name}",output:"Привет {имя}"),"translated placeholder rejected")
        try check(!TranslationChunker.preservesProtectedFragments(source:"{id} {id}",output:"{id}"),"missing duplicate placeholder rejected")
        let valid = LocalInsightDocument(meaning:"Кот спит на стуле.",observations:[.init(quote:"is sleeping",explanation:"Действие происходит сейчас.")],alternatives:[])
        try valid.validate(source:"The cat is sleeping on the chair.",alternatives:false)
        try check(true,"insights quote original")
        let invalid = LocalInsightDocument(meaning:"Кот спит",observations:[.init(quote:"на стуле",explanation:"родительный падеж")],alternatives:[])
        do { try invalid.validate(source:"The cat is sleeping on the chair.",alternatives:false); throw QualityTestFailure.assertion("invented quote accepted") }
        catch is TranslationFailure { try check(true,"analysis of translated text rejected") }
        let duplicate = LocalInsightDocument(meaning:"Смысл",observations:[],alternatives:["Кот спит","Кот спит","Кот спит"])
        do { try duplicate.validate(source:"The cat sleeps.",alternatives:true); throw QualityTestFailure.assertion("duplicate alternatives accepted") }
        catch is TranslationFailure { try check(true,"duplicate alternatives rejected") }
        let payload = LocalGenerationService.payload(instruction:"fixture",input:"quoted source",schema:["type":"object","required":["translation"]],maximumTokens:100)
        let format = payload["response_format"] as? [String:Any]
        let wrapper = format?["json_schema"] as? [String:Any]
        let schema = wrapper?["schema"] as? [String:Any]
        try check(format?["type"] as? String == "json_schema" && schema?["required"] as? [String] == ["translation"],"runtime reads nested strict JSON schema")
        let unavailable = LocalRuntimeSupervisor(resourceRoot:URL(fileURLWithPath:"/nonexistent-koto-test-resources"))
        let engine = LocalTranslationEngine(runtime:unavailable)
        let unsupported = try TranslationRequest(text:"Hello",source:TranslationLanguage(id:"en"),target:TranslationLanguage(id:"xx"))
        do { _ = try await engine.readiness(for:unsupported); throw QualityTestFailure.assertion("unsupported target accepted") }
        catch TranslationFailure.unsupportedPair { try check(!unavailable.isRunning,"unsupported pair rejected before model loading") }
        let ambiguous = try TranslationRequest(text:"12345",source:nil,target:TranslationLanguage(id:"ru"))
        do { _ = try await engine.readiness(for:ambiguous); throw QualityTestFailure.assertion("ambiguous language accepted") }
        catch TranslationFailure.unableToIdentify { try check(!unavailable.isRunning,"ambiguous auto language rejected before model loading") }
        let report: [String:Any] = ["status":"passed","count":passed.count,"tests":passed]
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
