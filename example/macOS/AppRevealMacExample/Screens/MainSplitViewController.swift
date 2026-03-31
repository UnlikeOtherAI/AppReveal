import AppKit

final class MainSplitViewController: NSSplitViewController {

    private let sidebarViewController = SidebarViewController()
    private let detailContainer = ContainerViewController()

    private lazy var ordersController = OrdersSectionSplitViewController()
    private lazy var catalogController = CatalogSectionSplitViewController()
    private lazy var profileController = ProfileViewController()
    private lazy var settingsController = SettingsViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        sidebarViewController.delegate = self

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 240

        let detailItem = NSSplitViewItem(viewController: detailContainer)

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)

        display(section: .orders)
        sidebarViewController.select(.orders)
    }

    private func display(section: ExampleSection) {
        ExampleRouter.shared.switchSection(section)

        switch section {
        case .orders:
            detailContainer.display(ordersController)
        case .catalog:
            detailContainer.display(catalogController)
        case .profile:
            detailContainer.display(profileController)
        case .settings:
            detailContainer.display(settingsController)
        }
    }
}

extension MainSplitViewController: SidebarViewControllerDelegate {
    func sidebarViewController(_ controller: SidebarViewController, didSelect section: ExampleSection) {
        display(section: section)
    }
}

private final class ContainerViewController: NSViewController {
    private var currentViewController: NSViewController?

    override func loadView() {
        view = NSView()
    }

    func display(_ viewController: NSViewController) {
        if currentViewController === viewController { return }

        currentViewController?.view.removeFromSuperview()
        currentViewController?.removeFromParent()

        addChild(viewController)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(viewController.view)

        NSLayoutConstraint.activate([
            viewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        currentViewController = viewController
    }
}

private final class OrdersSectionSplitViewController: NSSplitViewController {
    private let listController = OrdersListViewController()
    private let detailContainer = ContainerViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        listController.delegate = self

        let listItem = NSSplitViewItem(viewController: listController)
        listItem.minimumThickness = 320
        listItem.maximumThickness = 420

        let detailItem = NSSplitViewItem(viewController: detailContainer)

        addSplitViewItem(listItem)
        addSplitViewItem(detailItem)
        detailContainer.display(PlaceholderViewController(title: "Orders", message: "Select an order to inspect its details."))
    }
}

extension OrdersSectionSplitViewController: OrdersListViewControllerDelegate {
    func ordersListViewController(_ controller: OrdersListViewController, didSelect order: ExampleOrder) {
        ExampleNetworkClient.shared.fetchOrderDetail(id: order.id) { [weak self] result in
            guard let self else { return }
            guard case .success(let detailOrder) = result else { return }
            self.detailContainer.display(OrderDetailViewController(order: detailOrder))
            ExampleRouter.shared.showOrderDetail(detailOrder)
        }
    }
}

private final class CatalogSectionSplitViewController: NSSplitViewController {
    private let listController = CatalogViewController()
    private let detailContainer = ContainerViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        listController.delegate = self

        let listItem = NSSplitViewItem(viewController: listController)
        listItem.minimumThickness = 360
        listItem.maximumThickness = 520

        let detailItem = NSSplitViewItem(viewController: detailContainer)

        addSplitViewItem(listItem)
        addSplitViewItem(detailItem)
        detailContainer.display(PlaceholderViewController(title: "Catalog", message: "Select a product to inspect pricing and cart controls."))
    }
}

extension CatalogSectionSplitViewController: CatalogViewControllerDelegate {
    func catalogViewController(_ controller: CatalogViewController, didSelect product: ExampleProduct) {
        detailContainer.display(ProductDetailViewController(product: product))
        ExampleRouter.shared.showProductDetail(product)
    }
}

private final class PlaceholderViewController: NSViewController {
    private let titleText: String
    private let messageText: String

    init(title: String, message: String) {
        self.titleText = title
        self.messageText = message
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

        let titleLabel = NSTextField(labelWithString: titleText)
        titleLabel.font = .boldSystemFont(ofSize: 24)

        let messageLabel = NSTextField(wrappingLabelWithString: messageText)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 0

        let stack = NSStackView(views: [titleLabel, messageLabel])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])
    }
}
