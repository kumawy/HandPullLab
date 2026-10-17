import SwiftUI

struct CatalogView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var controller: HandPullController
    @State private var frames: HandFrameStore
    @State private var position = ScrollPosition(y: 0)
    @State private var category: FoodCategory = .all
    @State private var favorites: Set<String> = []
    @State private var favoritesOnly = false
    @State private var selectedItem: FoodItem?
    @State private var showSearch = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    init() {
        let store = HandFrameStore()
        var configuration = HandPullConfiguration()
        configuration.use(store.descriptor)
        _frames = State(initialValue: store)
        _controller = State(initialValue: HandPullController(configuration: configuration))
    }

    private var visibleItems: [FoodItem] {
        FoodItem.samples.filter {
            (category == .all || $0.category == category) &&
            (!favoritesOnly || favorites.contains($0.id)) &&
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                CatalogStyle.background.ignoresSafeArea()
                catalog
            }
            .overlayPreferenceValue(ClothHeaderPreference.self) { anchors in
                GeometryReader { overlayGeometry in
                    HandOverlayView(controller: controller, frames: frames,
                                    size: geometry.size, safeAreaTop: geometry.safeAreaInsets.top,
                                    protectedAreas: anchors.controls.map { overlayGeometry[$0] },
                                    headerBottom: anchors.bounds.map { overlayGeometry[$0].maxY })
                }
                .allowsHitTesting(false)
            }
            .onChange(of: geometry.size) { _, _ in controller.cancel() }
        }
        .tint(.primary)
        .onChange(of: selectedItem) { _, item in if item != nil { controller.cancel() } }
        .onChange(of: showSearch) { _, shown in if shown { controller.cancel() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { controller.cancel() } }
        .onChange(of: reduceMotion, initial: true) { _, value in
            controller.setPreferences(enabled: controller.enabled, reduceMotion: value)
        }
        .onDisappear { controller.cancel() }
        .onChange(of: frames.isReady) { _, ready in if !ready { controller.cancel() } }
    }

    private var catalog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if showSearch { inlineSearch }
                catalogHeading
                Button("Replay effect", systemImage: "hand.draw", action: replay)
                    .font(.subheadline)
                    .accessibilityLabel("Replay effect. Повторить эффект")
                    .accessibilityIdentifier("effect.replay")
                    .disabled(!frames.isReady || !controller.enabled || controller.reduceMotion || controller.isPlaying || controller.isPulling)
                Text(controller.refreshStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("refresh.status")
                    .accessibilityValue(controller.accessibilityStatus)
                categories
                promotion
                if !query.isEmpty {
                    HStack {
                        Text("Поиск: \(query)").font(.subheadline)
                        Spacer()
                        Button("Сбросить") { resetCatalog { query = "" } }
                    }
                }
                if visibleItems.isEmpty {
                    ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass",
                                           description: Text("Выберите другую категорию или измените поиск."))
                        .accessibilityIdentifier("catalog.empty")
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                             count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach(visibleItems) { item in
                            FoodCardView(item: item, isExpanded: selectedItem?.id == item.id, isFavorite: favorites.contains(item.id)) {
                                if !favorites.insert(item.id).inserted { favorites.remove(item.id) }
                            } open: {
                                controller.cancel()
                                selectedItem = selectedItem?.id == item.id ? nil : item
                            }
                        }
                    }
                }
                effectActions
                AnimationDebugView(controller: controller, frames: frames, replay: replay)
                Text("HandPullLab · Demo menu").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12 + controller.surfaceHeight)
            .padding(.bottom, 24)
            .background {
                ScrollPullLimiter(maximumDistance: controller.configuration.refreshThreshold,
                                  enabled: controller.enabled && frames.isReady && !reduceMotion)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollPosition($position)
        .accessibilityIdentifier("catalog.scroll")
        .onScrollGeometryChange(for: Double.self) {
            Double($0.contentOffset.y + $0.contentInsets.top)
        } action: { _, offset in
            controller.geometryChanged(offset: offset)
        }
        .onScrollPhaseChange { oldPhase, phase, context in
            let offset = Double(context.geometry.contentOffset.y + context.geometry.contentInsets.top)
            if phase == .tracking || phase == .interacting {
                if !controller.isUserInteracting {
                    controller.userGestureBegan(at: offset, framesReady: frames.isReady)
                }
            } else if oldPhase == .tracking || oldPhase == .interacting {
                controller.userScrollEnded(at: offset, framesReady: frames.isReady, move: moveScroll)
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
            // Простое касание не всегда меняет scrollPhase (например, на кнопке).
            // Оно всё равно должно сразу прервать программное воспроизведение.
            if controller.isPlaying { controller.cancel() }
        })
    }

    private var catalogHeading: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            Text("Popular Food")
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
            Button {
                resetCatalog { category = .all; favoritesOnly = false; query = "" }
            } label: {
                Text("View all").font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityLabel("Показать все блюда")
        }
    }

    private var header: some View {
        HStack {
            Button { controller.cancel(); showSearch.toggle(); searchFocused = showSearch } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 24)).frame(width: 44, height: 44)
            }.accessibilityLabel("Поиск блюд").accessibilityIdentifier("search.open")
                .anchorPreference(key: ClothHeaderPreference.self, value: .bounds) {
                    ClothHeaderAnchors(controls: [$0])
                }
            Spacer()
            VStack(spacing: 3) {
                Text("location:").font(.caption).foregroundStyle(.secondary)
                Text("New York").font(.headline)
            }.accessibilityElement(children: .combine)
                .anchorPreference(key: ClothHeaderPreference.self, value: .bounds) {
                    ClothHeaderAnchors(controls: [$0])
                }
            Spacer()
            Button {
                resetCatalog { favoritesOnly.toggle() }
            } label: {
                Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                    .font(.system(size: 24)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(favoritesOnly ? "Показать всё меню" : "Показать избранное")
            .accessibilityValue(favoritesOnly ? "Только избранное" : "Всё меню")
            .accessibilityIdentifier("favorites.filter")
            .anchorPreference(key: ClothHeaderPreference.self, value: .bounds) {
                ClothHeaderAnchors(controls: [$0])
            }
        }.buttonStyle(.plain)
            .transformAnchorPreference(key: ClothHeaderPreference.self, value: .bounds) { value, anchor in
                value.bounds = anchor
            }
    }

    private var categories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FoodCategory.allCases) { item in
                    Button { resetCatalog { category = item } } label: {
                        HStack(spacing: 6) {
                            Text(item.emoji).accessibilityHidden(true)
                            Text(item.rawValue).font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .foregroundStyle(category == item ? .white : .black)
                        .background(category == item ? Color.black : .white, in: Capsule())
                    }
                    .accessibilityLabel("Категория \(item.rawValue)")
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                    .accessibilityIdentifier("category.\(item.rawValue)")
                }
            }
        }
    }

    private var promotion: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 18))
        return layout {
                Text("🍢").font(.system(size: 56)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("A little taste of Japan").font(.headline)
                    Text("Discover your next favorite").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white).padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black, in: RoundedRectangle(cornerRadius: 24))
    }

    private var effectActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("Вернуться к началу", systemImage: "arrow.up.to.line", action: returnToTop)
                .accessibilityIdentifier("catalog.top")
            Text(controller.refreshStatus)
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("effect.status")
                .accessibilityValue(controller.isPlaying ? "playing" : "idle")
            if let diagnostic = frames.diagnostic {
                Text(diagnostic).font(.footnote).foregroundStyle(.red)
            }
            if controller.reduceMotion {
                Button("Обновить меню") { controller.refreshWithoutMotion() }
                    .accessibilityIdentifier("refresh.accessible")
                Text("Уменьшение движения включено: декоративная рука отключена.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.font(.subheadline).padding(.vertical, 6)
    }

    private var inlineSearch: some View {
        HStack {
            TextField("Название блюда", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("search.field")
            Button("Готово") { searchFocused = false; showSearch = false }
                .accessibilityIdentifier("search.done")
        }
        .onChange(of: query) { _, _ in controller.cancel(); moveScroll(0) }
    }

    private func moveScroll(_ y: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { position.scrollTo(y: y) }
    }

    private func replay() { controller.replay(framesReady: frames.isReady, move: moveScroll) }
    private func returnToTop() { controller.cancel(); moveScroll(0) }
    private func resetCatalog(_ change: () -> Void) { controller.cancel(); change(); moveScroll(0) }
}

/// Якоря следуют за настоящими элементами ScrollView, включая Dynamic Type.
private struct ClothHeaderAnchors {
    var controls: [Anchor<CGRect>] = []
    var bounds: Anchor<CGRect>?
}

private enum ClothHeaderPreference: PreferenceKey {
    static var defaultValue: ClothHeaderAnchors { .init() }

    static func reduce(value: inout ClothHeaderAnchors, nextValue: () -> ClothHeaderAnchors) {
        let next = nextValue()
        value.controls.append(contentsOf: next.controls)
        if let bounds = next.bounds { value.bounds = bounds }
    }
}
