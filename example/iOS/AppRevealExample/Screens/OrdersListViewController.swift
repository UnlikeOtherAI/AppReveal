import UIKit

class OrdersListViewController: UITableViewController {

    private var orders: [ExampleOrder] = []
    private let refresher = UIRefreshControl()
    private let searchController = UISearchController(searchResultsController: nil)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Orders"
        setupUI()
        loadOrders()

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ExampleRouter.shared.push(route: "orders.list")
    }

    private func setupUI() {
        tableView.accessibilityIdentifier = "orders.list_table"
        tableView.register(OrderCell.self, forCellReuseIdentifier: "OrderCell")

        refresher.accessibilityIdentifier = "orders.refresh"
        refresher.addTarget(self, action: #selector(refreshOrders), for: .valueChanged)
        tableView.refreshControl = refresher

        searchController.searchBar.placeholder = "Search orders..."
        searchController.searchBar.accessibilityIdentifier = "orders.search"
        navigationItem.searchController = searchController

        let filterButton = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain,
            target: self,
            action: #selector(filterTapped)
        )
        filterButton.accessibilityIdentifier = "orders.filter"
        navigationItem.rightBarButtonItem = filterButton
    }

    private func loadOrders() {
        ExampleNetworkClient.shared.fetchOrders { [weak self] result in
            DispatchQueue.main.async {
                self?.refresher.endRefreshing()
                switch result {
                case .success(let orders):
                    self?.orders = orders
                    self?.tableView.reloadData()
                case .failure:
                    break
                }
            }
        }
    }

    @objc private func refreshOrders() {
        loadOrders()
    }

    @objc private func filterTapped() {
        let alert = UIAlertController(title: "Filter", message: nil, preferredStyle: .actionSheet)
        for status in ["All", "Pending", "Shipped", "Delivered"] {
            alert.addAction(UIAlertAction(title: status, style: .default) { [weak self] _ in
                self?.applyFilter(status)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func applyFilter(_ status: String) {
        // Simulated filter
        tableView.reloadData()
    }

    // MARK: - Table view

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        orders.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "OrderCell", for: indexPath) as! OrderCell
        cell.configure(with: orders[indexPath.row], index: indexPath.row)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let order = orders[indexPath.row]
        let detail = OrderDetailViewController(orderId: order.id)
        navigationController?.pushViewController(detail, animated: true)
    }
}

// MARK: - Order Cell

class OrderCell: UITableViewCell {
    func configure(with order: ExampleOrder, index: Int) {
        accessibilityIdentifier = "orders.cell_\(index)"
        textLabel?.text = "Order #\(order.id)"
        detailTextLabel?.text = "\(order.status) - $\(String(format: "%.2f", order.total))"
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
    }

    required init?(coder: NSCoder) { fatalError() }
}
