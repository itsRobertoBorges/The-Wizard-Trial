import SwiftUI
import WebKit

struct AnimatedGIFView: UIViewRepresentable {
    let gifName: String

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.isUserInteractionEnabled = false

        if let path = Bundle.main.path(forResource: gifName, ofType: "gif"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            let html = """
            <html><head><meta name='viewport' content='initial-scale=1, maximum-scale=1'/>
            <style>html,body{margin:0;background:transparent;height:100%}
            img{width:100%;height:100%;object-fit:cover;}</style></head>
            <body><img src='data:image/gif;base64,\(data.base64EncodedString())'></body></html>
            """
            wv.loadHTMLString(html, baseURL: nil)
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

