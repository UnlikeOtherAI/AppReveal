import UIKit
import SwiftUI

final class TapCalibrationViewController: UIViewController {

    private let instructionLabel = UILabel()
    private let targetView = UIView()
    private let resultLabel = UILabel()
    private let imageButtonResultLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tap Calibration"
        view.backgroundColor = .systemBackground
        setupViews()
        embedSwiftUIView()
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

        imageButtonResultLabel.text = "Image button not yet tapped"
        imageButtonResultLabel.textAlignment = .center
        imageButtonResultLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        imageButtonResultLabel.textColor = .secondaryLabel
        imageButtonResultLabel.translatesAutoresizingMaskIntoConstraints = false
        imageButtonResultLabel.accessibilityIdentifier = "calibration.image_button_result"
        view.addSubview(imageButtonResultLabel)

        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            targetView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            targetView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 40),
            targetView.widthAnchor.constraint(equalToConstant: 120),
            targetView.heightAnchor.constraint(equalToConstant: 120),

            resultLabel.topAnchor.constraint(equalTo: targetView.bottomAnchor, constant: 32),
            resultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            resultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            imageButtonResultLabel.topAnchor.constraint(equalTo: resultLabel.bottomAnchor, constant: 8),
            imageButtonResultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            imageButtonResultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func embedSwiftUIView() {
        let swiftUIVC = UIHostingController(rootView: SwiftUITapTestView(
            onTap: { [weak self] in self?.swiftUIButtonTapped() },
            onIdentifierOnlyTap: { [weak self] in self?.swiftUIIdentifierOnlyButtonTapped() },
            onImageTap: { [weak self] in self?.swiftUIImageButtonTapped() },
            onLazyGridTap: { [weak self] in self?.swiftUILazyGridButtonTapped() }
        ))
        addChild(swiftUIVC)
        swiftUIVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(swiftUIVC.view)
        swiftUIVC.didMove(toParent: self)

        NSLayoutConstraint.activate([
            swiftUIVC.view.topAnchor.constraint(equalTo: imageButtonResultLabel.bottomAnchor, constant: 16),
            swiftUIVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            swiftUIVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            swiftUIVC.view.heightAnchor.constraint(equalToConstant: 320)
        ])
    }

    @objc private func targetTapped() {
        let frame = targetView.convert(targetView.bounds, to: nil)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        resultLabel.text = "UIKit tapped! Center: (\(Int(center.x)), \(Int(center.y)))"
        resultLabel.textColor = .systemGreen
        UIView.animate(withDuration: 0.15, animations: {
            self.targetView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }, completion: { _ in
            UIView.animate(withDuration: 0.15) {
                self.targetView.transform = .identity
            }
        })
    }

    private func swiftUIButtonTapped() {
        resultLabel.text = "SwiftUI button tapped!"
        resultLabel.textColor = .systemBlue
    }

    private func swiftUIImageButtonTapped() {
        imageButtonResultLabel.text = "SwiftUI image button tapped!"
        imageButtonResultLabel.textColor = .systemOrange
    }

    private func swiftUIIdentifierOnlyButtonTapped() {
        resultLabel.text = "Identifier-only SwiftUI button tapped!"
        resultLabel.textColor = .systemPurple
    }

    private func swiftUILazyGridButtonTapped() {
        resultLabel.text = "Lazy grid SwiftUI button tapped!"
        resultLabel.textColor = .systemMint
    }
}

private struct SwiftUITapTestView: View {
    let onTap: () -> Void
    let onIdentifierOnlyTap: () -> Void
    let onImageTap: () -> Void
    let onLazyGridTap: () -> Void

    @State private var textFieldValue = ""

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(spacing: 8) {
            Text("SwiftUI Button Test")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(action: onTap) {
                    Text("Tap Me (SwiftUI)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityIdentifier("calibration.swiftui_button")
                #if DEBUG
                .appReveal("calibration.swiftui_button", label: "Tap Me (SwiftUI)")
                #endif
                Button("Identifier Only", action: onIdentifierOnlyTap)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("calibration.swiftui_identifier_only")
                // Image-only button — no label/identifier. Use .appReveal() for discovery on iOS 26+.
                Button(action: onImageTap) {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Color.orange)
                }
                #if DEBUG
                .appReveal("calibration.image_button", label: "Send")
                #endif
            }
            .padding(.horizontal, 24)

            // SwiftUI TextField for iOS 26 tap-to-focus verification.
            // tap_point on this field should bring up the keyboard (type_text should then work).
            TextField("Type here (SwiftUI)", text: $textFieldValue)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("calibration.swiftui_field")
                #if DEBUG
                .appReveal("calibration.swiftui_field", label: "Type here (SwiftUI)", type: .textField)
                #endif

            Text("Lazy Grid Button Test")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: columns, spacing: 8) {
                    lazyGridButton(action: onLazyGridTap, color: .green)
                        #if DEBUG
                        .appReveal("calibration.lazy_grid_card", activate: onLazyGridTap)
                        #endif

                    ForEach(1..<12) { index in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(index.isMultiple(of: 2) ? Color.blue.opacity(0.25) : Color.orange.opacity(0.25))
                            .frame(height: 56)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .frame(height: 96)
        }
    }

    private func lazyGridButton(action: @escaping () -> Void, color: Color) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.85))
                .frame(height: 56)
                .overlay {
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                }
        }
        .buttonStyle(.plain)
    }
}
