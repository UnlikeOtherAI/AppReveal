import UIKit

#if DEBUG
import AppReveal
#endif

class ProductDetailViewController: UIViewController {

    private let product: ExampleProduct
    private let scrollView = UIScrollView()
    private let quantityStepper = UIStepper()
    private let quantityLabel = UILabel()
    private let addToCartButton = UIButton(type: .system)
    private let favoriteButton = UIButton(type: .system)

    init(product: ExampleProduct) {
        self.product = product
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = product.name
        setupUI()

        #if DEBUG
        AppReveal.registerScreen(self)
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ExampleRouter.shared.push(route: "catalog.detail")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { ExampleRouter.shared.pop() }
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        scrollView.accessibilityIdentifier = "product_detail.scroll"
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let imageView = UIImageView(image: UIImage(systemName: product.iconName))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        imageView.accessibilityIdentifier = "product_detail.image"

        let nameLabel = UILabel()
        nameLabel.text = product.name
        nameLabel.font = .boldSystemFont(ofSize: 24)
        nameLabel.accessibilityIdentifier = "product_detail.name"

        let priceLabel = UILabel()
        priceLabel.text = "$\(String(format: "%.2f", product.price))"
        priceLabel.font = .systemFont(ofSize: 20)
        priceLabel.textColor = .systemBlue
        priceLabel.accessibilityIdentifier = "product_detail.price"

        let descLabel = UILabel()
        descLabel.text = product.description
        descLabel.numberOfLines = 0
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.accessibilityIdentifier = "product_detail.description"

        // Quantity
        quantityStepper.minimumValue = 1
        quantityStepper.maximumValue = 99
        quantityStepper.value = 1
        quantityStepper.accessibilityIdentifier = "product_detail.quantity_stepper"
        quantityStepper.addTarget(self, action: #selector(stepperChanged), for: .valueChanged)

        quantityLabel.text = "Qty: 1"
        quantityLabel.accessibilityIdentifier = "product_detail.quantity_label"

        let qtyStack = UIStackView(arrangedSubviews: [quantityLabel, quantityStepper])
        qtyStack.spacing = 12

        // Add to cart
        addToCartButton.setTitle("Add to Cart", for: .normal)
        addToCartButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        addToCartButton.backgroundColor = .systemBlue
        addToCartButton.setTitleColor(.white, for: .normal)
        addToCartButton.layer.cornerRadius = 8
        addToCartButton.accessibilityIdentifier = "product_detail.add_to_cart"

        // Favorite
        favoriteButton.setImage(UIImage(systemName: "heart"), for: .normal)
        favoriteButton.setImage(UIImage(systemName: "heart.fill"), for: .selected)
        favoriteButton.accessibilityIdentifier = "product_detail.favorite"
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            imageView, nameLabel, priceLabel, descLabel,
            qtyStack, addToCartButton, favoriteButton
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 200),
            addToCartButton.heightAnchor.constraint(equalToConstant: 50),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])
    }

    @objc private func stepperChanged() {
        quantityLabel.text = "Qty: \(Int(quantityStepper.value))"
    }

    @objc private func favoriteTapped() {
        favoriteButton.isSelected.toggle()
    }
}

#if DEBUG
extension ProductDetailViewController: ScreenIdentifiable {
    var screenKey: String { "catalog.detail" }
    var screenTitle: String { product.name }
    var debugMetadata: [String: Any] { ["productId": product.id, "price": product.price] }
}
#endif
