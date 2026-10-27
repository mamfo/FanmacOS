import Foundation

final class PublicIPService {
    private(set) var ip: String?
    private var lastAttempt = Date.distantPast
    private var isFetching = false

    var onChange: (() -> Void)?

    func refreshIfNeeded(force: Bool = false) {
        guard !isFetching else { return }
        if !force, Date().timeIntervalSince(lastAttempt) < 900 {
            return
        }

        isFetching = true
        lastAttempt = Date()
        fetch(from: "https://api.ipify.org?format=json") { [weak self] result in
            guard let self else { return }
            if let result {
                self.finish(result)
            } else {
                self.fetch(from: "https://icanhazip.com") { [weak self] fallback in
                    guard let self else { return }
                    self.finish(fallback)
                }
            }
        }
    }

    private func finish(_ value: String?) {
        isFetching = false
        guard let value, !value.isEmpty else { return }
        ip = value
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }

    private func fetch(from urlString: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("FanmacOS/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let data,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                completion(nil)
                return
            }

            if text.hasPrefix("{") {
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ip = object["ip"] as? String {
                    completion(ip)
                } else {
                    completion(nil)
                }
            } else {
                completion(text.components(separatedBy: .newlines).first)
            }
        }.resume()
    }
}
