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
    @Environment(\.dynamicTypeSize) private var typeSize
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
            VStack(spacing: 0) {
                membershipIntro
                membershipDetails
            }
        }
        .scrollClipDisabled()
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

    private var membershipDetails: some View {
        VStack(alignment: .leading, spacing: 20) {
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
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(MicOnStyle.raised, in: RoundedRectangle(cornerRadius: 16))
                    renewalDisclosure
                } else {
                    if api.session == nil { ConnectionPanel(showsArtwork: false) }
                    if !plans.isEmpty { planPicker }
                    if let error = commerce.plansError {
                        ErrorNote(message: error)
                        Button("Retry") { Task { await commerce.loadPlans() } }
                            .buttonStyle(CompactActionStyle()).disabled(interactionLocked)
                    }
                    renewalDisclosure
                    VStack(spacing: 12) {
                        purchaseAction
                        if purchasing {
                            loadingMark(width: 42)
                        }
                    }
                }

                restoreLink

                if attemptedPurchaseAction {
                    if let error = commerce.error { ErrorNote(message: error) }
                    if let message = commerce.message {
                        LocalizedText(message).font(.booth(.subheadline)).foregroundStyle(MicOnStyle.accent)
                    }
                }

                PolicyLinks(compact: true)

                if !exportRequired, !commerce.premium, api.session != nil { rewardOption }
        }.miconPage()
    }

    private var purchaseButtonTitle: String {
        if commerce.loadingProducts || commerce.loadingPlans { return "Checking with Apple…" }
        if commerce.preparingPurchase { return "Preparing your subscription…" }
        if commerce.busy { return "Confirming your purchase…" }
        return "Subscribe"
    }

    private var membershipIntro: some View {
        StudioCover(artwork: "PlusArtwork", height: 218...366, ratio: 1.19) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    LocalizedText("Plus").font(.booth(.subheadline, weight: .bold))
                        .foregroundStyle(MicOnStyle.paper)
                    Spacer(minLength: 8)
                    IconButton(symbol: .close, label: "Close") {
                        cancelRewardRequest()
                        dismiss()
                    }
                    .studioGlass(in: Circle())
                    .disabled(purchasing || ads.isPresenting)
                }
                Spacer(minLength: 50)
                CoverTitle(title: "Booth pass", size: 64)
                LocalizedText("Unlimited views, downloads and media exports.")
                    .font(.booth(.subheadline)).foregroundStyle(MicOnStyle.paper)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var planPicker: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 275 : 142), spacing: 10, alignment: .top)],
            alignment: .leading, spacing: 10
        ) {
            ForEach(plans, id: \.productIdentifier) { plan in
                planOption(plan)
            }
        }
    }

    private func planOption(_ product: SKProduct) -> some View {
        let selected = selectedPlan?.productIdentifier == product.productIdentifier
        let price = commerce.price(product)
        let period = commerce.period(product, locale: locale)
        return Button { selectedID = product.productIdentifier } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    TintedArtwork(name: "TabHome", tint: selected ? MicOnStyle.ink : MicOnStyle.accent)
                        .frame(width: 23, height: 18)
                        .frame(width: 37, height: 29)
                        .background(selected ? MicOnStyle.accent : MicOnStyle.surface, in: Capsule())
                    Spacer(minLength: 0)
                }
                Text(verbatim: product.localizedTitle).font(.booth(.subheadline, weight: .semibold))
                Text(verbatim: price).environment(\.layoutDirection, .leftToRight)
                    .font(.booth(.title2, weight: .semibold)).monospacedDigit().foregroundStyle(MicOnStyle.accent)
                LocalizedText("Billed every %@", period).font(.booth(.footnote)).foregroundStyle(MicOnStyle.secondary)
            }.fixedSize(horizontal: false, vertical: true)
                .padding(13).frame(maxWidth: .infinity, minHeight: 135, alignment: .topLeading)
                .foregroundStyle(MicOnStyle.paper)
                .studioGlass(in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17).strokeBorder(selected ? MicOnStyle.accent : .clear)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).disabled(interactionLocked)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("membership.plan.\(product.productIdentifier)")
    }

    private var renewalDisclosure: some View {
        LocalizedText("Renews automatically. Cancel in your Apple account at least 24 hours before renewal.")
            .font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var purchaseAction: some View {
        Button(action: subscribe) {
            HStack(spacing: 10) {
                Glyph(symbol: .sound, size: 18, tint: MicOnStyle.accent)
                    .frame(width: 36, height: 36)
                    .background(MicOnStyle.ink, in: Capsule()).accessibilityHidden(true)
                LocalizedText(purchaseButtonTitle).font(.booth(.headline, display: true))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(MicOnStyle.ink)
                .background(MicOnStyle.accent, in: RoundedRectangle(cornerRadius: 18))
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .disabled(interactionLocked || selectedPlan == nil)
            .accessibilityIdentifier("membership.subscribe")
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
                    loadingMark(width: 28)
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

    private func loadingMark(width: CGFloat) -> some View {
        Image("MicOnLoadingMark").renderingMode(.template).resizable().scaledToFit()
            .foregroundStyle(MicOnStyle.accent)
            .frame(width: width, height: 14)
            .phaseAnimator([false, true]) { content, dimmed in
                content.opacity(reduceMotion || scenePhase != .active ? 1 : (dimmed ? 0.35 : 1))
            } animation: { _ in
                reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 0.6)
            }
            .accessibilityHidden(true)
    }

    private var restoreLink: some View {
        Button {
            attemptedPurchaseAction = true
            commerce.restore()
        } label: {
            LocalizedText("Restore purchases")
                .font(.booth(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(minHeight: 44)
                .foregroundStyle(MicOnStyle.accent)
                .background(MicOnStyle.raised, in: Capsule())
                .contentShape(Rectangle())
        }.disabled(interactionLocked).buttonStyle(PressStyle())
            .accessibilityIdentifier("membership.restore")
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
            VStack(spacing: 0) {
                accountCover
                VStack(alignment: .leading, spacing: 24) {
                    if api.session != nil {
                        membershipCard
                        allowance
                        Divider().overlay(MicOnStyle.line)
                    } else { ConnectionPanel(showsArtwork: false) }
                    AccountSettingsSection()
                    LocalizedText("Version \(api.configuration.version)")
                        .font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                        .padding(.top, 4)
                }.miconPage()
            }
        }.scrollClipDisabled()
            .miconScreenBackground().foregroundStyle(.white)
            .sheet(isPresented: $paywall) { MembershipView() }
    }

    private var accountCover: some View {
        StudioCover(artwork: "AccountCover", height: 178...322, ratio: 1.26) {
            VStack(alignment: .leading, spacing: 8) {
                CoverTitle(title: "Your practice space", size: 55)
                if let session = api.session {
                    LocalizedText("ID · \(session.userId.value)").font(.booth(.footnote)).monospacedDigit()
                        .foregroundStyle(MicOnStyle.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    accountStatus
                }
            }
        }
    }

    private var accountStatus: some View {
        LocalizedText(commerce.premium ? "Plus active" : "Free plan")
            .font(.booth(.caption, weight: .semibold))
            .foregroundStyle(commerce.premium ? MicOnStyle.accent : MicOnStyle.secondary)
    }

    private var membershipCard: some View {
        Button { paywall = true } label: {
            HStack(alignment: .center, spacing: 16) {
                membershipCopy.frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .back, size: 16, tint: MicOnStyle.ink)
                    .rotationEffect(.degrees(180))
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(MicOnStyle.paper, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(PressStyle()).disabled(unavailable)
            .accessibilityIdentifier("account.membership")
    }

    private var membershipCopy: some View {
        VStack(alignment: .leading, spacing: 7) {
            LocalizedText(commerce.premium ? "Your all-access pass." : "Go further with Plus.")
                .font(.booth(.title3, weight: .semibold)).foregroundStyle(MicOnStyle.ink)
            LocalizedText("Unlimited views. Unlimited downloads.")
                .font(.booth(.footnote)).foregroundStyle(MicOnStyle.paperSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LocalizedText(commerce.premium ? "Manage membership" : "Explore plans")
                .font(.booth(.footnote, weight: .semibold)).foregroundStyle(MicOnStyle.ink)
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
