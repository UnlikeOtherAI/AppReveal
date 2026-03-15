import UIKit
import WebKit

class WebViewDemoViewController: UIViewController {

    private let webView = WKWebView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Web View"
        setupUI()
        loadLocalHTML()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        webView.accessibilityIdentifier = "webdemo.webview"
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func loadLocalHTML() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                * { box-sizing: border-box; margin: 0; padding: 0; }
                body { font-family: -apple-system, sans-serif; padding: 20px; background: #f5f5f7; color: #1d1d1f; }
                h1 { font-size: 22px; margin-bottom: 16px; }
                h2 { font-size: 17px; margin: 20px 0 10px; color: #6e6e73; }
                .card { background: white; border-radius: 12px; padding: 16px; margin-bottom: 16px; }
                label { display: block; font-size: 13px; color: #6e6e73; margin-bottom: 4px; }
                input[type="text"], input[type="email"], input[type="password"], textarea, select {
                    width: 100%; padding: 10px; border: 1px solid #d2d2d7; border-radius: 8px;
                    font-size: 16px; margin-bottom: 12px; -webkit-appearance: none;
                }
                textarea { height: 80px; resize: none; }
                button {
                    width: 100%; padding: 12px; border: none; border-radius: 8px;
                    font-size: 16px; font-weight: 600; cursor: pointer; margin-bottom: 8px;
                }
                .btn-primary { background: #007aff; color: white; }
                .btn-secondary { background: #e5e5ea; color: #1d1d1f; }
                .btn-danger { background: #ff3b30; color: white; }
                .checkbox-row { display: flex; align-items: center; gap: 8px; margin-bottom: 12px; }
                .checkbox-row input { width: auto; margin: 0; }
                .checkbox-row label { margin: 0; font-size: 15px; color: #1d1d1f; }
                .result { padding: 10px; background: #e8f5e9; border-radius: 8px; margin-top: 12px; display: none; }
                .link-list a { display: block; padding: 8px 0; color: #007aff; text-decoration: none; border-bottom: 1px solid #e5e5ea; }
                .counter { display: flex; align-items: center; gap: 12px; margin-bottom: 12px; }
                .counter button { width: 40px; padding: 8px; margin: 0; }
                .counter span { font-size: 20px; font-weight: 600; min-width: 30px; text-align: center; }
                #scroll-section { margin-top: 40px; }
                .scroll-item { padding: 12px; background: white; border-radius: 8px; margin-bottom: 8px; }
            </style>
        </head>
        <body>
            <h1>Web View Demo</h1>

            <div class="card">
                <h2>Contact Form</h2>
                <label for="name-input">Full Name</label>
                <input type="text" id="name-input" name="name" placeholder="John Doe" data-testid="form-name">

                <label for="email-input">Email</label>
                <input type="email" id="email-input" name="email" placeholder="john@example.com" data-testid="form-email">

                <label for="message-input">Message</label>
                <textarea id="message-input" name="message" placeholder="Your message..." data-testid="form-message"></textarea>

                <label for="category-select">Category</label>
                <select id="category-select" name="category" data-testid="form-category">
                    <option value="">Select...</option>
                    <option value="support">Support</option>
                    <option value="sales">Sales</option>
                    <option value="feedback">Feedback</option>
                </select>

                <div class="checkbox-row">
                    <input type="checkbox" id="terms-check" name="terms" data-testid="form-terms">
                    <label for="terms-check">I agree to the terms and conditions</label>
                </div>

                <div class="checkbox-row">
                    <input type="checkbox" id="newsletter-check" name="newsletter" data-testid="form-newsletter">
                    <label for="newsletter-check">Subscribe to newsletter</label>
                </div>

                <button class="btn-primary" id="submit-btn" data-testid="form-submit" onclick="submitForm()">Submit</button>
                <button class="btn-secondary" id="reset-btn" data-testid="form-reset" onclick="resetForm()">Reset</button>

                <div class="result" id="form-result" data-testid="form-result"></div>
            </div>

            <div class="card">
                <h2>Counter</h2>
                <div class="counter">
                    <button class="btn-secondary" id="decrement-btn" data-testid="counter-decrement" onclick="changeCounter(-1)">-</button>
                    <span id="counter-value" data-testid="counter-value">0</span>
                    <button class="btn-secondary" id="increment-btn" data-testid="counter-increment" onclick="changeCounter(1)">+</button>
                </div>
                <button class="btn-danger" data-testid="counter-reset" onclick="resetCounter()">Reset Counter</button>
            </div>

            <div class="card">
                <h2>Links</h2>
                <div class="link-list">
                    <a href="#home" data-testid="link-home">Home</a>
                    <a href="#about" data-testid="link-about">About Us</a>
                    <a href="#products" data-testid="link-products">Products</a>
                    <a href="#contact" data-testid="link-contact">Contact</a>
                </div>
            </div>

            <div class="card" id="scroll-section">
                <h2>Scrollable Content</h2>
                <div class="scroll-item" data-testid="item-1">Item 1 - First scrollable item</div>
                <div class="scroll-item" data-testid="item-2">Item 2 - Second scrollable item</div>
                <div class="scroll-item" data-testid="item-3">Item 3 - Third scrollable item</div>
                <div class="scroll-item" data-testid="item-4">Item 4 - Fourth scrollable item</div>
                <div class="scroll-item" data-testid="item-5">Item 5 - Fifth scrollable item</div>
                <div class="scroll-item" data-testid="item-6">Item 6 - Sixth scrollable item</div>
                <div class="scroll-item" data-testid="item-7">Item 7 - Seventh scrollable item</div>
                <div class="scroll-item" data-testid="item-8">Item 8 - Eighth scrollable item</div>
                <div class="scroll-item" data-testid="item-9">Item 9 - Ninth scrollable item</div>
                <div class="scroll-item" data-testid="item-10">Item 10 - Tenth scrollable item</div>
            </div>

            <div id="bottom-anchor" data-testid="bottom-anchor" style="padding: 20px; text-align: center; color: #6e6e73;">
                End of page
            </div>

            <script>
                var counterVal = 0;

                function submitForm() {
                    var name = document.getElementById('name-input').value;
                    var email = document.getElementById('email-input').value;
                    var message = document.getElementById('message-input').value;
                    var category = document.getElementById('category-select').value;
                    var terms = document.getElementById('terms-check').checked;

                    if (!name || !email) {
                        showResult('Please fill in name and email.', '#ffebee');
                        return;
                    }
                    if (!terms) {
                        showResult('Please agree to the terms.', '#ffebee');
                        return;
                    }

                    showResult('Form submitted! Name: ' + name + ', Email: ' + email + ', Category: ' + category, '#e8f5e9');
                }

                function resetForm() {
                    document.getElementById('name-input').value = '';
                    document.getElementById('email-input').value = '';
                    document.getElementById('message-input').value = '';
                    document.getElementById('category-select').value = '';
                    document.getElementById('terms-check').checked = false;
                    document.getElementById('newsletter-check').checked = false;
                    document.getElementById('form-result').style.display = 'none';
                }

                function showResult(msg, bg) {
                    var el = document.getElementById('form-result');
                    el.textContent = msg;
                    el.style.background = bg;
                    el.style.display = 'block';
                }

                function changeCounter(delta) {
                    counterVal += delta;
                    document.getElementById('counter-value').textContent = counterVal;
                }

                function resetCounter() {
                    counterVal = 0;
                    document.getElementById('counter-value').textContent = '0';
                }
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
