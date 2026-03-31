import AppKit

protocol OrdersListViewControllerDelegate: AnyObject {
    func ordersListViewController(_ controller: OrdersListViewController, didSelect order: ExampleOrder)
}

final class OrdersListViewController: NSViewController {

    weak var delegate: OrdersListViewControllerDelegate?

    private let searchField = NSSearchField()
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    private var orders: [ExampleOrder] = []
    private var filteredOrders: [ExampleOrder] = []

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureControls()
        configureLayout()
        loadOrders()
    }

    private func configureControls() {
        searchField.placeholderString = "Search orders"
        searchField.delegate = self
        searchField.setAccessibilityIdentifier("orders.list.search")

        refreshButton.target = self
        refreshButton.action = #selector(refreshOrders)
        refreshButton.bezelStyle = .rounded
        refreshButton.setAccessibilityIdentifier("orders.list.refresh")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("orders"))
        column.title = "Orders"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 60
        tableView.delegate = self
        tableView.dataSource = self
        tableView.setAccessibilityIdentifier("orders.list.table")

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
    }

    private func configureLayout() {
        let header = NSStackView(views: [searchField, refreshButton])
        header.orientation = .horizontal
        header.spacing = 8
        header.alignment = .centerY

        let stack = NSStackView(views: [header, scrollView])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        searchField.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

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

    @objc private func refreshOrders() {
        loadOrders()
    }

    private func loadOrders() {
        ExampleNetworkClient.shared.fetchOrders { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let orders):
                self.orders = orders
                self.applyFilter()
                self.selectFirstOrderIfNeeded()
            case .failure:
                break
            }
        }
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredOrders = orders
        } else {
            filteredOrders = orders.filter {
                $0.id.localizedCaseInsensitiveContains(query) ||
                $0.status.localizedCaseInsensitiveContains(query)
            }
        }
        tableView.reloadData()
    }

    private func selectFirstOrderIfNeeded() {
        guard !filteredOrders.isEmpty else { return }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        delegate?.ordersListViewController(self, didSelect: filteredOrders[0])
    }
}

extension OrdersListViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }
}

extension OrdersListViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredOrders.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.setAccessibilityIdentifier("orders.list.row_\(row)")
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("OrderCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? OrderCellView ?? OrderCellView()
        cell.identifier = identifier
        cell.configure(with: filteredOrders[row])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard filteredOrders.indices.contains(row) else { return }
        delegate?.ordersListViewController(self, didSelect: filteredOrders[row])
    }
}

private final class OrderCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with order: ExampleOrder) {
        titleLabel.stringValue = "\(order.id)  •  \(order.status)"
        subtitleLabel.stringValue = "$\(String(format: "%.2f", order.total))  •  \(DateFormatter.orderDate.string(from: order.createdAt))"
    }

    private func configure() {
        subtitleLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

private extension DateFormatter {
    static let orderDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
