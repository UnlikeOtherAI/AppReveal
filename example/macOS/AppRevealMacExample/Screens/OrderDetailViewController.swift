import AppKit

final class OrderDetailViewController: NSViewController {

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let headerLabel = NSTextField(labelWithString: "Select an order")
    private let totalLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let addressLabel = NSTextField(labelWithString: "")
    private let itemsLabel = NSTextField(wrappingLabelWithString: "")

    private var order: ExampleOrder?

    convenience init(order: ExampleOrder) {
        self.init()
        self.order = order
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        render()
    }

    private func configureUI() {
        stackView.orientation = .vertical
        stackView.spacing = 12
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        headerLabel.font = .boldSystemFont(ofSize: 24)
        totalLabel.font = .systemFont(ofSize: 15, weight: .medium)
        dateLabel.textColor = .secondaryLabelColor
        addressLabel.lineBreakMode = .byWordWrapping
        itemsLabel.maximumNumberOfLines = 0

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        [headerLabel, totalLabel, dateLabel, addressLabel, itemsLabel].forEach(stackView.addArrangedSubview)
    }

    private func render() {
        guard let order else {
            headerLabel.stringValue = "Select an order"
            totalLabel.stringValue = "Choose an order from the list to inspect line items and delivery details."
            dateLabel.stringValue = ""
            addressLabel.stringValue = ""
            itemsLabel.stringValue = ""
            return
        }

        headerLabel.stringValue = order.id
        totalLabel.stringValue = "Total: $\(String(format: "%.2f", order.total))  •  \(order.status)"
        dateLabel.stringValue = "Placed on \(DateFormatter.orderDetail.string(from: order.createdAt))"
        addressLabel.stringValue = "Ship to: \(order.shippingAddress)"
        itemsLabel.stringValue = order.items
            .map { "\($0.quantity)x \($0.name)  •  $\(String(format: "%.2f", $0.price))" }
            .joined(separator: "\n")
    }
}

private extension DateFormatter {
    static let orderDetail: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}
