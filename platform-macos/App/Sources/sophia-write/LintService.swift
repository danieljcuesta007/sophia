// LintService — drives the Rust core off the main thread (blueprint §17.2):
// lint on a worker queue with a hard budget, results marshalled back to main.
// Stale results are dropped via a generation counter so a fast typist never
// sees underlines for text that no longer exists.

import CSophiaFFI
import Foundation

final class LintService {
    private let queue = DispatchQueue(label: "sophia.lint", qos: .userInitiated)
    private var generation = 0
    private let dictionary: DictionaryStore

    init(dictionary: DictionaryStore) {
        self.dictionary = dictionary
        queue.async { sophia_warmup() }  // ~300 ms once; never in the ambient loop
    }

    /// Lint `text`; `completion` fires on main only if no newer request was made.
    func lint(_ text: String, completion: @escaping ([Issue]) -> Void) {
        generation += 1
        let gen = generation
        let opts = optionsJSON()
        queue.async { [weak self] in
            let issues = Self.lintNow(text, optsJSON: opts)
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                completion(issues)
            }
        }
    }

    func cancelPending() {
        generation += 1
    }

    private func optionsJSON() -> String {
        let obj = ["dictionary": dictionary.terms]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    static func lintNow(_ text: String, optsJSON: String) -> [Issue] {
        guard let raw = sophia_lint(text, optsJSON) else { return [] }
        defer { sophia_free(raw) }
        return IssueDecoder.decode(Data(bytes: raw, count: strlen(raw)))
    }
}
