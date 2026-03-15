import UIKit

#if DEBUG
import AppReveal
#endif

class CartViewController: UIViewController {

    private let tableView = UITableView()
    private let checkoutButton = UIButton(type: .system)
    private let emptyLabel = UILabel()
    private let totalLabel = UILabel()

    private var cartItems: [(product: ExampleProduct, quantity: Int)] = [
        (ExampleProduct.samples[0], 2),
        (ExampleProduct.samples[1], 1),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        #if DEBUG
        AppReveal.registerScreen(self)
        #endif
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Shopping Cart"
        titleLabel.font = .boldSystemFont(ofSize: 24)
        titleLabel.accessibilityIdentifier = "cart.title"

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
        closeButton.accessibilityIdentifier = "cart.close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, closeButton])
        header.distribution = .equalSpacing

        tableView.accessibilityIdentifier = "cart.items_table"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CartItem")
        tableView.dataSource = self
        tableView.delegate = self

        let total = cartItems.reduce(0.0) { $0 + $1.product.price * Double($1.quantity) }
        totalLabel.text = "Total: $\(String(format: "%.2f", total))"
        totalLabel.font = .boldSystemFont(ofSize: 20)
        totalLabel.accessibilityIdentifier = "cart.total"

        checkoutButton.setTitle("Checkout", for: .normal)
        checkoutButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        checkoutButton.backgroundColor = .systemGreen
        checkoutButton.setTitleColor(.white, for: .normal)
        checkoutButton.layer.cornerRadius = 8
        checkoutButton.accessibilityIdentifier = "cart.checkout"

        emptyLabel.text = "Your cart is empty"
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.isHidden = !cartItems.isEmpty
        emptyLabel.accessibilityIdentifier = "cart.empty_message"

        let stack = UIStackView(arrangedSubviews: [header, tableView, emptyLabel, totalLabel, checkoutButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            tableView.heightAnchor.constraint(equalToConstant: 300),
            checkoutButton.heightAnchor.constraint(equalToConstant: 50),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
        ExampleRouter.shared.dismissModal()
    }
}

extension CartViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { cartItems.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CartItem", for: indexPath)
        let item = cartItems[indexPath.row]
        cell.textLabel?.text = "\(item.product.name) x\(item.quantity)"
        cell.accessibilityIdentifier = "cart.item_\(indexPath.row)"
        return cell
    }
}

#if DEBUG
extension CartViewController: ScreenIdentifiable {
    var screenKey: String { "cart.main" }
    var screenTitle: String { "Cart" }
    var debugMetadata: [String: Any] { ["itemCount": cartItems.count] }
}
#endif
