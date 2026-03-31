import AppKit

protocol CatalogViewControllerDelegate: AnyObject {
    func catalogViewController(_ controller: CatalogViewController, didSelect product: ExampleProduct)
}

final class CatalogViewController: NSViewController {

    weak var delegate: CatalogViewControllerDelegate?

    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let collectionView: NSCollectionView

    private var products: [ExampleProduct] = []
    private var filteredProducts: [ExampleProduct] = []

    init() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 180, height: 150)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureControls()
        configureLayout()
        loadProducts()
    }

    private func configureControls() {
        searchField.placeholderString = "Search products"
        searchField.delegate = self
        searchField.setAccessibilityIdentifier("catalog.list.search")

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.register(ProductCollectionItem.self, forItemWithIdentifier: ProductCollectionItem.identifier)
        collectionView.setAccessibilityIdentifier("catalog.list.collection")

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
    }

    private func configureLayout() {
        let stack = NSStackView(views: [searchField, scrollView])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
        ])
    }

    private func loadProducts() {
        ExampleNetworkClient.shared.fetchProducts { [weak self] result in
            guard let self else { return }
            if case .success(let products) = result {
                self.products = products
                self.applyFilter()
                self.selectFirstProductIfNeeded()
            }
        }
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredProducts = products
        } else {
            filteredProducts = products.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.category.localizedCaseInsensitiveContains(query)
            }
        }
        collectionView.reloadData()
    }

    private func selectFirstProductIfNeeded() {
        guard !filteredProducts.isEmpty else { return }
        let firstPath = Set([IndexPath(item: 0, section: 0)])
        collectionView.selectItems(at: firstPath, scrollPosition: [])
        delegate?.catalogViewController(self, didSelect: filteredProducts[0])
    }
}

extension CatalogViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }
}

extension CatalogViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        filteredProducts.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ProductCollectionItem.identifier, for: indexPath)
        guard let productItem = item as? ProductCollectionItem else { return item }
        productItem.configure(with: filteredProducts[indexPath.item], index: indexPath.item)
        return productItem
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first, filteredProducts.indices.contains(indexPath.item) else { return }
        delegate?.catalogViewController(self, didSelect: filteredProducts[indexPath.item])
    }
}

private final class ProductCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ProductCollectionItem")

    private let imageViewContainer = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let categoryLabel = NSTextField(labelWithString: "")
    private let priceLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor

        imageViewContainer.imageScaling = .scaleProportionallyUpOrDown
        imageViewContainer.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        imageViewContainer.contentTintColor = .controlAccentColor

        categoryLabel.textColor = .secondaryLabelColor
        priceLabel.font = .boldSystemFont(ofSize: 14)

        let stack = NSStackView(views: [imageViewContainer, nameLabel, categoryLabel, priceLabel])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            imageViewContainer.heightAnchor.constraint(equalToConstant: 40),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func configure(with product: ExampleProduct, index: Int) {
        imageViewContainer.image = NSImage(systemSymbolName: product.iconName, accessibilityDescription: product.name)
        nameLabel.stringValue = product.name
        categoryLabel.stringValue = product.category
        priceLabel.stringValue = "$\(String(format: "%.2f", product.price))"
        view.setAccessibilityIdentifier("catalog.list.item_\(index)")
    }
}
