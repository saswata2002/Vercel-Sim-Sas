import SwiftUI
import WebKit

/// The options sheet: everything that sits around the phone in the Mac app, as an iOS
/// bottom sheet. Opens with a double-tap anywhere (over a prototype or on the lock screen),
/// a two-finger press-and-hold, a shake, or press-and-hold on the lock screen.
struct ControlPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @State private var invalid = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                if let switcher = model.switcher {
                    iterationSection(switcher)
                }

                // MARK: prototype
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "globe").foregroundStyle(.secondary)
                        TextField("Paste a Vercel link", text: $draft)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($addressFocused)
                            .onSubmit(go)
                            .onChange(of: draft) { invalid = false }
                        Button(action: go) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(.systemBackground))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color.primary.opacity(canGo ? 1 : 0.3)))
                        }
                        .buttonStyle(PressScale())
                        .disabled(!canGo)
                        .accessibilityLabel("Open")
                    }
                    .modifier(Shake(animatableData: invalid ? 1 : 0))

                    if model.currentURL != nil {
                        Button { model.reload(); model.panelOpen = false } label: { Label("Reload", systemImage: "arrow.clockwise") }
                        Button { model.takeScreenshot() } label: { Label("Screenshot", systemImage: "camera.viewfinder") }
                        Button { model.goHome() } label: { Label("Home", systemImage: "house") }
                    }
                } header: {
                    Text("Prototype")
                } footer: {
                    if invalid { Text("That isn’t a valid link.").foregroundStyle(.red) }
                }

                if !model.recents.isEmpty {
                    Section("Recent prototypes") {
                        ForEach(model.recents, id: \.self) { url in
                            Button { model.open(url) } label: {
                                HStack {
                                    Text(String(AppModel.display(url).prefix(1)).uppercased())
                                        .font(.system(size: 13, weight: .bold))
                                        .frame(width: 28, height: 28)
                                        .background(RoundedRectangle(cornerRadius: 7).fill(Color(.tertiarySystemFill)))
                                    Text(AppModel.display(url)).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    if AppModel.sameDocument(URL(string: url), model.currentURL) {
                                        Image(systemName: "play.fill").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                        .onDelete(perform: model.removeRecents)
                    }
                }

                // MARK: display (the Mac app's options popover)
                Section {
                    Toggle("Status bar", isOn: $model.showStatusBar)
                    Toggle("Home indicator", isOn: $model.showHomeIndicator)
                    Toggle(isOn: $model.fitBase) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scale 375 designs")
                            Text("Lays the page out at 375 pt and fills wider iPhones").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Iteration pill on screen", isOn: $model.showIterationPill)
                    Toggle(isOn: $model.hapticsOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Haptics")
                            Text("Plays the prototype’s haptics on this iPhone").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Picker("Appearance", selection: $model.appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Over prototypes")
                } footer: {
                    Text("The lock screen always shows the status bar and home indicator.")
                }

                Section("This device") {
                    let d = model.device
                    LabeledContent("Model", value: d.name)
                    LabeledContent("Cutout", value: d.cutout)
                    LabeledContent("Screen", value: "\(Int(d.screen.width)) × \(Int(d.screen.height)) pt @\(Int(d.scale))x")
                    LabeledContent("Design layout", value: "\(Int(d.layout.width)) × \(Int(d.layout.height))" + (d.zoom == 1 ? " (1:1)" : String(format: " (×%.3f)", d.zoom)))
                    LabeledContent("Safe area (top / bottom)", value: "\(Int(d.layoutSafeArea.top)) / \(Int(d.layoutSafeArea.bottom))")
                }

                Section {
                    Button(role: .destructive) { model.clearWebsiteData() } label: { Label("Clear cookies & cache", systemImage: "trash") }
                } footer: {
                    Text("Double-tap the screen to open this sheet. You can also shake the iPhone, or press and hold with two fingers.")
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { model.panelOpen = false }.bold()
                }
            }
        }
        .onAppear {
            draft = model.currentURL.map { AppModel.display($0.absoluteString) } ?? ""
            if model.currentURL == nil { addressFocused = true }
        }
    }

    private var canGo: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The prototype's own picker, lifted out: numbered iterations, then reset and any
    /// other controls it carries (e.g. Spec Sheet), in the page's order.
    @ViewBuilder
    private func iterationSection(_ switcher: Switcher) -> some View {
        Section("Iteration") {
            HStack(spacing: 8) {
                ForEach(switcher.items) { item in
                    if item.index == switcher.items.first(where: { !$0.isOption })?.index {
                        Rectangle().fill(Color(.separator)).frame(width: 1, height: 26).padding(.horizontal, 2)
                    }
                    Button { model.press(item) } label: {
                        Group {
                            if item.isOption { Text(item.text).font(.system(size: 17, weight: .semibold)).monospacedDigit() }
                            else { Image(systemName: item.symbol).font(.system(size: 16, weight: .semibold)) }
                        }
                        .frame(width: 44, height: 44)
                        .foregroundStyle(item.selected ? .white : .primary)
                        .background(Circle().fill(item.selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiarySystemFill))))
                        .contentShape(Circle())
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel(item.isOption ? "Iteration \(item.text)" : item.text)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Named actions get a labelled row too, so "Spec Sheet" is findable.
            ForEach(switcher.items.filter { $0.kind == .action }) { item in
                Button { model.press(item); model.panelOpen = false } label: {
                    Label(item.text, systemImage: item.symbol)
                }
            }
        }
    }

    private func go() {
        if model.open(draft) {
            addressFocused = false
        } else {
            withAnimation(.default) { invalid = true }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

/// Horizontal shake for an invalid URL.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
