import Foundation

// Host-side corpus runner. Compiles the real production sources and the real
// corpus, so a family question costs seconds instead of a simulator run.
//
// Deliberately does NOT use String(format:) with `(s as NSString).utf8String`,
// which is how `SemanticCorpusTests.testCorpusSummaryReport` formats its table:
// that hands printf a pointer into a temporary NSString and segfaults under
// -O on the host. Padding is done in Swift instead.

struct FamilyResult {
    let family: String
    let cases: Int
    let failingUtterances: Int
    let critical: Int
    let behavioral: Int
    let metadata: Int
    let cosmetic: Int
}

let args = CommandLine.arguments.dropFirst()
var familyFilter: String? = nil
var renderingName = "identity"
var verbose = false
var listCases = false
var preservation = false
var it = args.makeIterator()
while let a = it.next() {
    switch a {
    case "--family": familyFilter = it.next()
    case "--rendering": renderingName = it.next() ?? "identity"
    case "--verbose": verbose = true
    case "--list": listCases = true
    case "--preservation": preservation = true
    default: break
    }
}

func unpunctuated(_ text: String) -> String {
    text.replacingOccurrences(of: #"[,;:.!?]"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
}
func commaFree(_ text: String) -> String {
    text.replacingOccurrences(of: #"\s*,\s*"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
}
let rendering: (String) -> String
switch renderingName {
case "unpunctuated": rendering = unpunctuated
case "comma-free": rendering = commaFree
case "lowercased": rendering = { $0.lowercased() }
default: rendering = { $0 }
}

let evaluator = CorpusEvaluator(rendering: rendering)
var results: [FamilyResult] = []
var totalCases = 0, totalFailing = 0
var sev: [Int: Int] = [:]

for (family, cases) in CorpusEvaluator.allFamilies {
    if let f = familyFilter, !family.rawValue.lowercased().contains(f.lowercased()) { continue }
    var ds: [CorpusDisagreement] = []
    for c in cases { ds.append(contentsOf: evaluator.evaluate(c)) }
    var local: [Int: Int] = [:]
    for d in ds { local[d.severity.rawValue, default: 0] += 1; sev[d.severity.rawValue, default: 0] += 1 }
    let failing = Set(ds.map(\.utterance)).count
    totalCases += cases.count; totalFailing += failing
    results.append(FamilyResult(family: family.rawValue, cases: cases.count,
                                failingUtterances: failing,
                                critical: local[3] ?? 0, behavioral: local[2] ?? 0,
                                metadata: local[1] ?? 0, cosmetic: local[0] ?? 0))
    if verbose && !ds.isEmpty {
        print(CorpusEvaluator.report(title: family.rawValue, cases: cases, disagreements: ds))
    }
    if listCases {
        for c in cases { print("\(family.rawValue)\t\(c.utterance)") }
    }
}

if listCases { exit(0) }

// --preservation: does every content word the person said survive into some
// item's quote, and does any item carry a word they never said?
if preservation {
    let stop: Set<String> = [
        "a","an","the","to","of","for","at","on","in","and","or","is","are","was","were",
        "be","been","i","me","my","we","us","our","you","your","it","its","that","this",
        "these","those","please","just","um","uh","er","ah","like","so","okay","ok","well",
        "actually","really","kind","sort","mean","know","right","then","also","plus",
    ]
    func words(_ value: String) -> [String] {
        value.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}'’\s]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
    }
    /// A word counts as surviving if some kept word shares a stem with it, so
    /// ordinary morphology and declared repairs are not reported as loss.
    func related(_ word: String, _ pool: Set<String>) -> Bool {
        if pool.contains(word) { return true }
        // A split clock — "830" surfacing as "8:30" — is not a fabricated 30.
        if word.allSatisfy(\.isNumber) {
            return pool.contains { $0.allSatisfy(\.isNumber) && ($0.contains(word) || word.contains($0)) }
        }
        let head = String(word.prefix(max(3, word.count - 2)))
        return pool.contains { $0.hasPrefix(head) || word.hasPrefix(String($0.prefix(max(3, $0.count - 2)))) }
    }

    var checked = 0, lost = 0, invented = 0
    for (_, cases) in CorpusEvaluator.allFamilies {
        for testCase in cases {
            let utterance = rendering(testCase.utterance)
            let result = ThoughtExtractionEngine.extractWithRules(
                utterance,
                referenceDate: CorpusEvaluator.referenceDate,
                calendar: CorpusEvaluator.calendar
            )
            // An operation legitimately creates nothing, so it has no quote to
            // carry the words; those are reported separately by the corpus.
            guard result.operations.isEmpty, !result.items.isEmpty else { continue }
            checked += 1
            let kept = Set(result.items.flatMap { words($0.sourceQuote) })
            // Raw words plus whatever the repair layer resolved them to.
            let said = Set(words(utterance)).union(kept)
            let titled = Set(result.items.flatMap { words(CorpusEvaluator.displayTitle(for: $0)) })

            let missing = Set(words(utterance)).subtracting(stop).filter { !related($0, kept) }
            if !missing.isEmpty {
                lost += 1
                print("LOST     \"\(utterance)\"\n         dropped: \(missing.sorted().joined(separator: ", "))")
            }
            let extra = titled.subtracting(stop).subtracting(said).filter { !related($0, said) }
            if !extra.isEmpty {
                invented += 1
                print("INVENTED \"\(utterance)\"\n         added: \(extra.sorted().joined(separator: ", "))")
            }
        }
    }
    print("")
    print("preservation over \(checked) item-producing captures:")
    print("  captures losing a content word from every quote: \(lost)")
    print("  captures whose title adds an unsaid word:        \(invented)")
    exit(0)
}

print("")
func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
func rpad(_ s: String, _ n: Int) -> String { s.count >= n ? s : String(repeating: " ", count: n - s.count) + s }
print(pad("FAMILY",34) + rpad("CASES",6) + rpad("FAILING",9) + rpad("CRIT",6) + rpad("BEH",6) + rpad("META",6) + rpad("COSM",6))
print(String(repeating: "-", count: 78))
for r in results.sorted(by: { ($0.critical + $0.behavioral, $0.failingUtterances) > ($1.critical + $1.behavioral, $1.failingUtterances) }) {
    print(pad(r.family,34) + rpad("\(r.cases)",6) + rpad("\(r.failingUtterances)",9) + rpad("\(r.critical)",6) + rpad("\(r.behavioral)",6) + rpad("\(r.metadata)",6) + rpad("\(r.cosmetic)",6))
}
print(String(repeating: "-", count: 78))
print("rendering=\(renderingName)  TOTAL \(totalCases) cases, \(totalFailing) failing, \(totalCases - totalFailing) clean")
print("CRITICAL \(sev[3] ?? 0)  BEHAVIORAL \(sev[2] ?? 0)  METADATA \(sev[1] ?? 0)  COSMETIC \(sev[0] ?? 0)")
let blocking = (sev[3] ?? 0) + (sev[2] ?? 0)
print("BLOCKING(crit+beh) = \(blocking)")
