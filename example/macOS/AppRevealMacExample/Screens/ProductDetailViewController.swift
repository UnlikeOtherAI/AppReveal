import AppKit

final class ProductDetailViewController: NSViewController {

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let imageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "Select a product")
    private let priceLabel = NSTextField(labelWithString: "")
    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let quantityLabel = NSTextField(labelWithString: "Quantity: 1")
    private let quantityStepper = NSStepper()
    private let addButton = NSButton(title: "Add to Cart", target: nil, action: nil)

    private var product: ExampleProduct?

    convenience init(product: ExampleProduct) {
        self.init()
        self.product = product
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
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = .controlAccentColor

        nameLabel.font = .boldSystemFont(ofSize: 24)
        nameLabel.setAccessibilityIdentifier("catalog.detail.name")

        priceLabel.font = .systemFont(ofSize: 18, weight: .medium)
        priceLabel.textColor = .controlAccentColor
        priceLabel.setAccessibilityIdentifier("catalog.detail.price")

        descriptionLabel.maximumNumberOfLines = 0

        quantityStepper.minValue = 1
        quantityStepper.maxValue = 99
        quantityStepper.integerValue = 1
        quantityStepper.target = self
        quantityStepper.action = #selector(quantityChanged)
        quantityStepper.setAccessibilityIdentifier("catalog.detail.quantity")

        addButton.target = self
        addButton.action = #selector(addToCart)
        addButton.bezelStyle = .rounded
        addButton.setAccessibilityIdentifier("catalog.detail.add_button")

        let quantityStack = NSStackView(views: [quantityLabel, quantityStepper])
        quantityStack.orientation = .horizontal
        quantityStack.spacing = 10

        stackView.orientation = .vertical
        stackView.spacing = 14
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        [imageView, nameLabel, priceLabel, descriptionLabel, quantityStack, addButton].forEach(stackView.addArrangedSubview)

        let documentView = NSView()
        documentView.addSubview(stackView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 120),
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
    }

    private func render() {
        guard let product else {
            priceLabel.stringValue = "Choose a product to inspect pricing and quantity controls."
            descriptionLabel.stringValue = ""
            quantityLabel.stringValue = "Quantity: 1"
            addButton.isEnabled = false
            return
        }

        imageView.image = NSImage(systemSymbolName: product.iconName, accessibilityDescription: product.name)
        nameLabel.stringValue = product.name
        priceLabel.stringValue = "$\(String(format: "%.2f", product.price))"
        descriptionLabel.stringValue = product.description
        quantityLabel.stringValue = "Quantity: \(quantityStepper.integerValue)"
        addButton.isEnabled = true
    }

    @objc private func quantityChanged() {
        quantityLabel.stringValue = "Quantity: \(quantityStepper.integerValue)"
    }

    @objc private func addToCart() {
        ExampleStateContainer.shared.cartItemCount += quantityStepper.integerValue
    }
}
