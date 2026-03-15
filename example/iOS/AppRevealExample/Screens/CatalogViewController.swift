import UIKit

#if DEBUG
import AppReveal
#endif

class CatalogViewController: UICollectionViewController {

    private var products: [ExampleProduct] = []
    private let searchController = UISearchController(searchResultsController: nil)

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 170, height: 220)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        super.init(collectionViewLayout: layout)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Catalog"
        setupUI()
        loadProducts()

        #if DEBUG
        AppReveal.registerScreen(self)
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ExampleRouter.shared.push(route: "catalog.list")
    }

    private func setupUI() {
        collectionView.backgroundColor = .systemBackground
        collectionView.accessibilityIdentifier = "catalog.grid"
        collectionView.register(ProductCell.self, forCellWithReuseIdentifier: "ProductCell")

        searchController.searchBar.placeholder = "Search products..."
        searchController.searchBar.accessibilityIdentifier = "catalog.search"
        navigationItem.searchController = searchController

        let cartButton = UIBarButtonItem(
            image: UIImage(systemName: "cart"),
            style: .plain,
            target: self,
            action: #selector(cartTapped)
        )
        cartButton.accessibilityIdentifier = "catalog.cart"
        navigationItem.rightBarButtonItem = cartButton
    }

    private func loadProducts() {
        ExampleNetworkClient.shared.fetchProducts { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let products) = result {
                    self?.products = products
                    self?.collectionView.reloadData()
                }
            }
        }
    }

    @objc private func cartTapped() {
        let cartVC = CartViewController()
        cartVC.modalPresentationStyle = .pageSheet
        present(cartVC, animated: true)
        ExampleRouter.shared.presentModal(route: "cart.main")
    }

    // MARK: - Collection view

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        products.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ProductCell", for: indexPath) as! ProductCell
        cell.configure(with: products[indexPath.item], index: indexPath.item)
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let product = products[indexPath.item]
        let detail = ProductDetailViewController(product: product)
        navigationController?.pushViewController(detail, animated: true)
    }
}

// MARK: - Product Cell

class ProductCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let nameLabel = UILabel()
    private let priceLabel = UILabel()
    private let addButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCell()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupCell() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8

        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemGray

        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nameLabel.numberOfLines = 2

        priceLabel.font = .boldSystemFont(ofSize: 16)
        priceLabel.textColor = .systemBlue

        addButton.setTitle("Add to Cart", for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)

        let stack = UIStackView(arrangedSubviews: [imageView, nameLabel, priceLabel, addButton])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 100),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    func configure(with product: ExampleProduct, index: Int) {
        accessibilityIdentifier = "catalog.product_\(index)"
        imageView.image = UIImage(systemName: product.iconName)
        nameLabel.text = product.name
        priceLabel.text = "$\(String(format: "%.2f", product.price))"
        addButton.accessibilityIdentifier = "catalog.add_to_cart_\(index)"
    }
}

#if DEBUG
extension CatalogViewController: ScreenIdentifiable {
    var screenKey: String { "catalog.list" }
    var screenTitle: String { "Catalog" }
    var debugMetadata: [String: Any] { ["productCount": products.count] }
}
#endif
