import UIKit

class OrderDetailViewController: UIViewController {

    private let orderId: String
    private let scrollView = UIScrollView()
    private let statusLabel = UILabel()
    private let totalLabel = UILabel()
    private let itemsLabel = UILabel()
    private let trackButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let reorderButton = UIButton(type: .system)
    private let notesField = UITextField()
    private let ratingSlider = UISlider()
    private let ratingValueLabel = UILabel()

    init(orderId: String) {
        self.orderId = orderId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Order #\(orderId)"
        setupUI()
        loadOrderDetail()

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ExampleRouter.shared.push(route: "orders.detail")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            ExampleRouter.shared.pop()
        }
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        scrollView.accessibilityIdentifier = "order_detail.scroll"
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Status
        statusLabel.font = .boldSystemFont(ofSize: 20)
        statusLabel.accessibilityIdentifier = "order_detail.status"

        // Total
        totalLabel.font = .systemFont(ofSize: 18)
        totalLabel.accessibilityIdentifier = "order_detail.total"

        // Items
        itemsLabel.numberOfLines = 0
        itemsLabel.font = .systemFont(ofSize: 14)
        itemsLabel.accessibilityIdentifier = "order_detail.items"

        // Track button
        trackButton.setTitle("Track Shipment", for: .normal)
        trackButton.backgroundColor = .systemBlue
        trackButton.setTitleColor(.white, for: .normal)
        trackButton.layer.cornerRadius = 8
        trackButton.accessibilityIdentifier = "order_detail.track"
        trackButton.addTarget(self, action: #selector(trackTapped), for: .touchUpInside)

        // Cancel button
        cancelButton.setTitle("Cancel Order", for: .normal)
        cancelButton.setTitleColor(.systemRed, for: .normal)
        cancelButton.accessibilityIdentifier = "order_detail.cancel"
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        // Reorder button
        reorderButton.setTitle("Reorder", for: .normal)
        reorderButton.backgroundColor = .systemGreen
        reorderButton.setTitleColor(.white, for: .normal)
        reorderButton.layer.cornerRadius = 8
        reorderButton.accessibilityIdentifier = "order_detail.reorder"

        // Notes
        notesField.placeholder = "Add delivery notes..."
        notesField.borderStyle = .roundedRect
        notesField.accessibilityIdentifier = "order_detail.notes"

        // Rating slider
        ratingSlider.minimumValue = 1
        ratingSlider.maximumValue = 5
        ratingSlider.value = 3
        ratingSlider.accessibilityIdentifier = "order_detail.rating_slider"
        ratingSlider.addTarget(self, action: #selector(ratingChanged), for: .valueChanged)

        ratingValueLabel.text = "Rating: 3"
        ratingValueLabel.accessibilityIdentifier = "order_detail.rating_value"

        let ratingStack = UIStackView(arrangedSubviews: [ratingSlider, ratingValueLabel])
        ratingStack.spacing = 8

        let stack = UIStackView(arrangedSubviews: [
            statusLabel, totalLabel, itemsLabel,
            notesField, ratingStack,
            trackButton, reorderButton, cancelButton
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
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
            trackButton.heightAnchor.constraint(equalToConstant: 44),
            reorderButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func loadOrderDetail() {
        ExampleNetworkClient.shared.fetchOrderDetail(id: orderId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let order):
                    self?.statusLabel.text = "Status: \(order.status)"
                    self?.totalLabel.text = "Total: $\(String(format: "%.2f", order.total))"
                    self?.itemsLabel.text = order.items.map { "\($0.name) x\($0.quantity)" }.joined(separator: "\n")
                case .failure:
                    self?.statusLabel.text = "Failed to load"
                }
            }
        }
    }

    @objc private func trackTapped() {
        let alert = UIAlertController(title: "Tracking", message: "Shipment is in transit.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func cancelTapped() {
        let alert = UIAlertController(title: "Cancel Order?", message: "This cannot be undone.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Yes, Cancel", style: .destructive) { _ in
            self.navigationController?.popViewController(animated: true)
        })
        alert.addAction(UIAlertAction(title: "Keep Order", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func ratingChanged() {
        let rounded = Int(ratingSlider.value.rounded())
        ratingValueLabel.text = "Rating: \(rounded)"
    }
}
