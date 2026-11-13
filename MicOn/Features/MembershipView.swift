import SwiftUI
import StoreKit

struct MembershipView: View {
    var rewardKind: AllowanceKind? = nil
    var exportRequired = false
    @Environment(\.locale) private var locale
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: String?
    @State private var attemptedPurchaseAction = false
    @State private var purchaseTask: Task<Void, Never>?
    @State private var rewardTask: Task<Void, Never>?
    @State private var requestedReward = false
    @State private var acknowledgedLuckyReward = false

    private var plans: [SKProduct] {
        (commerce.policy?.products ?? []).compactMap { entry in
            commerce.products.first { $0.productIdentifier == entry.id }
        }
    }
    private var selectedPlan: SKProduct? {
        plans.first(where: { $0.productIdentifier == selectedID }) ?? plans.first
    }
    private var purchasing: Bool { commerce.preparingPurchase || commerce.busy || purchaseTask != nil }
    private var interactionLocked: Bool { purchasing || commerce.loadingPlans || ads.busy || ads.isPresenting }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 12) {
                    BoothArtwork(kind: .pass, height: 136)
                        .accessibilityHidden(true)
                    LocalizedText(commerce.premium ? "More time on the floor." : "Keep the practice going.")
                        .font(.booth(.title2, display: true))
                        .foregroundStyle(MicOnStyle.paper)
                    LocalizedText("Unlimited views, downloads and media exports.")
                        .font(.booth(.subheadline)).foregroundStyle(MicOnStyle.secondary)
                }.multilineTextAlignment(.center).frame(maxWidth: .infinity)

                if exportRequired {
                    LocalizedText("Export is included with Plus.")
                        .font(.booth(.subheadline, weight: .semibold)).foregroundStyle(MicOnStyle.paper)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if commerce.premium {
                    VStack(alignment: .leading, spacing: 10) {
                        LocalizedText("Your membership is active").font(.booth(.headline))
                        if let expiration = commerce.expiration {
                            LocalizedText("Access through \(expiration.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))).")
                                .font(.booth(.subheadline)).foregroundStyle(MicOnStyle.secondary)
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(MicOnStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                } else {
                    if api.session == nil { ConnectionPanel() }
                    VStack(spacing: 12) {
                        ForEach(plans, id: \.productIdentifier) { plan in
                            planRow(plan)
                        }
                    }
                    if let error = commerce.plansError {
                        ErrorNote(message: error)
                        Button("Retry") { Task { await commerce.loadPlans() } }
                            .buttonStyle(CompactActionStyle()).disabled(interactionLocked)
                    }
                    VStack(spacing: 12) {
                        ActionButton(title: purchaseButtonTitle) { subscribe() }
                            .disabled(interactionLocked || selectedPlan == nil)
                            .accessibilityIdentifier("membership.subscribe")
                        if purchasing {
                            ProgressView().tint(MicOnStyle.accent).accessibilityHidden(true)
                        }
                    }
                }

                if attemptedPurchaseAction {
                    if let error = commerce.error { ErrorNote(message: error) }
                    if let message = commerce.message {
                        LocalizedText(message).font(.booth(.subheadline)).foregroundStyle(MicOnStyle.accent)
                    }
                }

                if !exportRequired, !commerce.premium, api.session != nil { rewardOption }

                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("Renews automatically. Cancel in your Apple account at least 24 hours before renewal.")
                        .font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            restoreLink
                            PolicyLinks(compact: true)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            restoreLink
                            PolicyLinks(compact: true)
                        }
                    }
                }

            }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 20)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SheetHeading(title: "Plus") {
                cancelRewardRequest()
                dismiss()
            }
                .disabled(purchasing || ads.isPresenting).padding(.bottom, 8)
                .miconScreenBackground()
        }
        .miconScreenBackground().foregroundStyle(.white)
        .task {
            async let rights: Void = commerce.refresh()
            await commerce.loadPlans()
            await rights
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in quota.resetIfNeeded() }
        .onDisappear {
            purchaseTask?.cancel(); purchaseTask = nil
            if !ads.isPresenting { cancelRewardRequest() }
        }
        .onChange(of: ads.completedReward) { _, completion in
            if requestedReward, completion != nil { dismiss() }
        }
        .interactiveDismissDisabled(purchasing || ads.isPresenting)
        .fullScreenCover(item: $ads.luckyReward, onDismiss: {
            if acknowledgedLuckyReward && requestedReward { dismiss() }
        }) { reward in
            LuckyRewardView(message: reward.message) {
                acknowledgedLuckyReward = true
                ads.luckyReward = nil
            }
                .presentationBackground(.clear)
        }
    }

    private var purchaseButtonTitle: String {
        if commerce.loadingProducts || commerce.loadingPlans { return "Checking with Apple…" }
        if commerce.preparingPurchase { return "Preparing your subscription…" }
        if commerce.busy { return "Confirming your purchase…" }
        return "Subscribe"
    }

    private func planRow(_ product: SKProduct) -> some View {
        let selected = selectedPlan?.productIdentifier == product.productIdentifier
        let price = commerce.price(product)
        let period = commerce.period(product, locale: locale)
        let foreground = selected ? MicOnStyle.ink : MicOnStyle.paper
        let secondary = selected ? MicOnStyle.paperSecondary : MicOnStyle.secondary
        return Button { selectedID = product.productIdentifier } label: {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) {
                    planName(product, selected: selected, foreground: foreground, secondary: secondary)
                    Spacer(minLength: 0)
                    planPrice(price, period: period, foreground: foreground, secondary: secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    planName(product, selected: selected, foreground: foreground, secondary: secondary)
                    planPrice(price, period: period, foreground: foreground, secondary: secondary)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background { BoothSurface(tone: selected ? .blush : .plum) }
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(PressStyle()).disabled(interactionLocked)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("membership.plan.\(product.productIdentifier)")
    }

    private func planName(_ product: SKProduct, selected: Bool, foreground: Color, secondary: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: product.localizedTitle).font(.booth(.headline)).foregroundStyle(foreground)
            if selected {
                LocalizedText("Selected").font(.booth(.caption)).foregroundStyle(secondary)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func planPrice(_ price: String, period: String, foreground: Color, secondary: Color) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(verbatim: price).environment(\.layoutDirection, .leftToRight)
                .font(.booth(.title2, weight: .bold)).foregroundStyle(foreground).fixedSize()
            LocalizedText("Billed every %@", period).font(.booth(.caption)).foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func subscribe() {
        guard !interactionLocked, let plan = selectedPlan else { return }
        attemptedPurchaseAction = true
        purchaseTask = Task {
            await commerce.purchase(planID: plan.productIdentifier)
            purchaseTask = nil
        }
    }

    private var rewardOption: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedText("Or, keep it free").font(.booth(.headline))
            ForEach(rewardKind.map { [$0] } ?? AllowanceKind.allCases) { kind in
                if quota.canRequestReward(for: kind, premium: commerce.premium) {
                    LocalizedText(quota.rewardSummary(for: kind)).font(.booth(.footnote)).foregroundStyle(MicOnStyle.secondary)
                    if quota.completedAds(kind) >= 3 { AllowanceResetText() }
                    ActionButton(title: kind == .watch ? "Get more views" : "Get more downloads",
                                 primary: false, busy: ads.busy || ads.isPresenting) {
                        requestedReward = true
                        rewardTask = Task { await ads.watch(commerce: commerce, quota: quota, kind: kind) }
                    }.disabled(purchasing || ads.isPreparingAppOpen || ads.busy || ads.isPresenting)
                }
            }
            if ads.busy {
                HStack(spacing: 12) {
                    ProgressView().tint(MicOnStyle.accent).accessibilityHidden(true)
                    LocalizedText("Loading ad…").font(.booth(.footnote))
                    Spacer(minLength: 12)
                    Button("Cancel") { cancelRewardRequest() }
                        .buttonStyle(CompactActionStyle())
                }
            }
            LocalizedText(quota.unlimited ? "Unlimited views today" : "\(quota.watchesLeft) views left today")
            LocalizedText(quota.downloadsUnlimited ? "Unlimited downloads today" : "\(quota.downloadsLeft) downloads left today")
            AllowanceResetText()
            LocalizedText("Ad rewards unlock when the corresponding allowance runs out.")
                .font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = ads.error { ErrorNote(message: error) }
            if let error = quota.error { ErrorNote(message: error) }
            if let message = ads.message {
                LocalizedText(message).font(.booth(.footnote)).foregroundStyle(MicOnStyle.accent)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(MicOnStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private func cancelRewardRequest() {
        rewardTask?.cancel()
        rewardTask = nil
        ads.cancelRewardLoading()
    }

    private var restoreLink: some View {
        Button {
            attemptedPurchaseAction = true
            commerce.restore()
        } label: {
            LocalizedText("Restore purchases")
                .font(.booth(.footnote, weight: .medium))
                .foregroundStyle(MicOnStyle.accent)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }.disabled(interactionLocked).buttonStyle(PressStyle())
    }

}

struct AccountView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    @State private var paywall = false
    private var unavailable: Bool {
        accountAccess.isBusy || commerce.busy || commerce.preparingPurchase || ads.busy || ads.isPresenting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let session = api.session {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            accountIdentity(session.userId.value)
                            Spacer(minLength: 16)
                            accountStatus
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            accountIdentity(session.userId.value)
                            accountStatus
                        }
                    }
                    membershipCard
                    allowance
                } else { ConnectionPanel() }
                AccountSettingsSection()
                LocalizedText("Version \(api.configuration.version)")
                    .font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 4)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
            .frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.miconScreenBackground().foregroundStyle(.white)
            .sheet(isPresented: $paywall) { MembershipView() }
    }

    private func accountIdentity(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            LocalizedText("Your practice space").font(.booth(.headline)).foregroundStyle(MicOnStyle.paper)
            LocalizedText("ID · \(id)").font(.caption.monospaced()).foregroundStyle(MicOnStyle.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountStatus: some View {
        LocalizedText(commerce.premium ? "Plus active" : "Free plan")
            .font(.booth(.caption, weight: .semibold))
            .foregroundStyle(commerce.premium ? MicOnStyle.accent : MicOnStyle.secondary)
    }

    private var membershipCard: some View {
        Button { paywall = true } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    membershipCopy
                    BoothArtwork(kind: .pass, height: 126).frame(width: 132)
                }
                VStack(alignment: .leading, spacing: 12) {
                    BoothArtwork(kind: .pass, height: 100)
                    membershipCopy
                }
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(MicOnStyle.paper, in: RoundedRectangle(cornerRadius: 24))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(PressStyle()).disabled(unavailable)
            .accessibilityIdentifier("account.membership")
    }

    private var membershipCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText(commerce.premium ? "Your all-access pass." : "Go further with Plus.")
                .font(.booth(.title3, weight: .semibold)).foregroundStyle(MicOnStyle.ink)
            LocalizedText("Unlimited views. Unlimited downloads.")
                .font(.booth(.footnote)).foregroundStyle(MicOnStyle.paperSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LocalizedText(commerce.premium ? "Manage membership" : "Explore plans")
                .font(.booth(.footnote, weight: .semibold)).foregroundStyle(MicOnStyle.ink)
                .padding(.top, 8)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private var allowance: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                LocalizedText("Today").font(.booth(.headline))
                Spacer()
                if !commerce.premium {
                    Button("Get more") { paywall = true }
                        .font(.booth(.footnote, weight: .semibold)).foregroundStyle(MicOnStyle.accent)
                        .frame(minHeight: 44).buttonStyle(PressStyle()).disabled(unavailable)
                        .accessibilityLabel("Get more daily views and downloads")
                }
            }
            HStack(alignment: .top, spacing: 20) {
                balance(value: commerce.premium || quota.unlimited ? "Unlimited" : "\(quota.watchesLeft)", label: "Views left")
                balance(value: commerce.premium || quota.downloadsUnlimited ? "Unlimited" : "\(quota.downloadsLeft)", label: "Downloads left")
            }
            if commerce.premium {
                LocalizedText("Included with your membership").font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
            } else { AllowanceResetText() }
        }
    }

    private func balance(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(value).font(value == "Unlimited" ? .headline : .title.weight(.semibold))
                .monospacedDigit().foregroundStyle(MicOnStyle.paper)
                .fixedSize(horizontal: false, vertical: true)
            LocalizedText(label).font(.booth(.footnote)).foregroundStyle(MicOnStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LuckyRewardView: View {
    let message: String
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    BoothArtwork(kind: .pass, height: 108)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                        .accessibilityHidden(true)
                    LocalizedText("A little luck, on us").font(.booth(.headline)).foregroundStyle(.white)
                    LocalizedText("No ad is available right now. \(message)")
                        .font(.booth(.subheadline)).foregroundStyle(MicOnStyle.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    ActionButton(title: "Keep exploring", action: dismiss)
                }.padding(20).frame(maxWidth: 360)
                    .background(MicOnStyle.surface, in: RoundedRectangle(cornerRadius: 28))
                    .padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(Color.black.opacity(0.68).ignoresSafeArea())
            .accessibilityAddTraits(.isModal).interactiveDismissDisabled()
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { appeared = true } }
    }
}


struct AllowanceResetText: View {
    @Environment(\.locale) private var locale
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let next = QuotaStore.nextReset(after: context.date)
            LocalizedText("Resets %@ (local time)", localTime(next))
                .font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func localTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

}
