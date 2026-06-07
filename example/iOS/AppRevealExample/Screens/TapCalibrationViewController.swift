import UIKit

final class TapCalibrationViewController: UIViewController {

    private let instructionLabel = UILabel()
    private let targetView = UIView()
    private let resultLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tap Calibration"
        view.backgroundColor = .systemBackground
        setupViews()
    }

    private func setupViews() {
        instructionLabel.text = "Tap the red target to verify\nMCP tap_point accuracy"
        instructionLabel.numberOfLines = 0
        instructionLabel.textAlignment = .center
        instructionLabel.font = .preferredFont(forTextStyle: .body)
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)

        targetView.backgroundColor = .systemRed
        targetView.layer.cornerRadius = 8
        targetView.translatesAutoresizingMaskIntoConstraints = false
        targetView.accessibilityIdentifier = "calibration.target"
        targetView.isUserInteractionEnabled = true
        targetView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(targetTapped)))
        view.addSubview(targetView)

        resultLabel.text = "Target not yet tapped"
        resultLabel.textAlignment = .center
        resultLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        resultLabel.textColor = .secondaryLabel
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.accessibilityIdentifier = "calibration.result"
        view.addSubview(resultLabel)

        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            targetView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            targetView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            targetView.widthAnchor.constraint(equalToConstant: 120),
            targetView.heightAnchor.constraint(equalToConstant: 120),

            resultLabel.topAnchor.constraint(equalTo: targetView.bottomAnchor, constant: 32),
            resultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            resultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    @objc private func targetTapped() {
        let frame = targetView.convert(targetView.bounds, to: nil)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        resultLabel.text = "Tapped! Center: (\(Int(center.x)), \(Int(center.y)))"
        resultLabel.textColor = .systemGreen
        UIView.animate(withDuration: 0.15, animations: {
            self.targetView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }, completion: { _ in
            UIView.animate(withDuration: 0.15) {
                self.targetView.transform = .identity
            }
        })
    }
}
