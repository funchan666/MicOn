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
            membershipDetails
        }
        .miconScreenBackground(MicOnStyle.mediaBackground).foregroundStyle(.white)
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
        let rewardsFirst = rewardKind != nil || AllowanceKind.allCases.contains {
            quota.canRequestReward(for: $0, premium: commerce.premium)
        }
        return VStack(alignment: .leading, spacing: 24) {
            membershipIntro
            if !commerce.premium, api.session == nil { ConnectionPanel() }
            subscriptionPanel
            if rewardsFirst { availableRewards }
            membershipBenefits
            if !rewardsFirst { availableRewards }
        }.miconPage()
    }

    private var membershipIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                MediaTitle(title: "Plus", tint: MicOnStyle.accent)
                Spacer(minLength: 0)
                IconButton(symbol: .close, label: "Close") {
                    cancelRewardRequest()
                    dismiss()
                }
                .disabled(purchasing || ads.isPresenting)
                .studioGlass(in: Circle())
                .accessibilitySortPriority(1)
            }
            if !commerce.premium {
                LocalizedText(exportRequired ? "Export is included with Plus." :
                              "Export video and audio. Unlimited lesson views and downloads.")
                    .font(.booth(.subheadline))
                    .foregroundStyle(MicOnStyle.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var subscriptionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if commerce.premium {
                activeMembership
            } else {
                MediaTitle(title: "Choose a plan", textStyle: .title2)
                if !plans.isEmpty { planPicker }
                if let error = commerce.plansError {
                    VStack(alignment: .leading, spacing: 0) {
                        ErrorNote(message: error)
                        Button { Task { await commerce.loadPlans() } } label: { LocalizedText("Retry") }
                            .buttonStyle(CompactActionStyle())
                            .disabled(interactionLocked)
                    }
                }
            }
            if !commerce.premium {
                renewalDisclosure
                if commerce.plansError == nil || selectedPlan != nil { purchaseAction }
            }

            if attemptedPurchaseAction {
                if let error = commerce.error { ErrorNote(message: error) }
                if let message = commerce.message {
                    LocalizedText(message)
                        .font(.booth(.subheadline))
                        .foregroundStyle(MicOnStyle.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            restoreButton
            PolicyLinks(compact: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioGlass(in: RoundedRectangle(cornerRadius: 26))
    }

    private var activeMembership: some View {
        HStack(alignment: .top, spacing: 12) {
            Glyph(symbol: .sound, size: 20, tint: MicOnStyle.ink)
                .frame(width: 44, height: 44)
                .background(MicOnStyle.accent, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                MediaTitle(title: "Plus active", textStyle: .title2)
                if let expiration = commerce.expiration {
                    let date = expiration.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
                    LocalizedText("Access through %@.", date)
                        .font(.booth(.subheadline))
                        .foregroundStyle(MicOnStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var planPicker: some View {
        VStack(spacing: 4) {
            ForEach(plans, id: \.productIdentifier) { plan in
                planOption(plan)
            }
        }
        .padding(5)
        .background(MicOnStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func planOption(_ product: SKProduct) -> some View {
        let selected = selectedPlan?.productIdentifier == product.productIdentifier
        let price = commerce.price(product)
        let period = commerce.period(product, locale: locale)
        let title = VStack(alignment: .leading, spacing: 4) {
            Group {
                if let cycle = product.subscriptionPeriod, cycle.numberOfUnits == 1, cycle.unit == .month {
                    LocalizedText("Monthly")
                } else if let cycle = product.subscriptionPeriod, cycle.numberOfUnits == 1, cycle.unit == .year {
                    LocalizedText("Yearly")
                } else {
                    Text(verbatim: product.localizedTitle)
                }
            }.font(.booth(.subheadline, weight: .semibold))
                .foregroundStyle(MicOnStyle.paper)
            if !period.isEmpty {
                LocalizedText("Billed every %@", period)
                    .font(.booth(.footnote))
                    .foregroundStyle(MicOnStyle.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        let amount = Text(verbatim: price)
            .environment(\.layoutDirection, .leftToRight)
            .font(.booth(.title2, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(selected ? MicOnStyle.accent : MicOnStyle.paper)
            .fixedSize(horizontal: false, vertical: true)

        return Button { selectedID = product.productIdentifier } label: {
            HStack(spacing: 12) {
                TintedArtwork(name: "TabHome", tint: MicOnStyle.ink)
                    .frame(width: 16, height: 12)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 26, height: 26)
                    .background(selected ? MicOnStyle.accent : .clear, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(selected ? .clear : MicOnStyle.secondary.opacity(0.7), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .accessibilityHidden(true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        title
                        Spacer(minLength: 0)
                        amount
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        title
                        amount
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(selected ? MicOnStyle.raised : .clear, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressStyle())
        .disabled(interactionLocked)
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
            HStack(spacing: 8) {
                if purchasing || commerce.loadingProducts || commerce.loadingPlans {
                    loadingMark(width: 32, tint: MicOnStyle.ink)
                }
                LocalizedText(purchaseButtonTitle)
                    .font(.booth(.headline, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(MicOnStyle.ink)
            .background(MicOnStyle.accent, in: Capsule())
            .contentShape(.interaction, Capsule())
        }
        .buttonStyle(PressStyle())
        .disabled(interactionLocked || selectedPlan == nil)
        .accessibilityIdentifier("membership.subscribe")
    }

    private var purchaseButtonTitle: String {
        if commerce.loadingProducts || commerce.loadingPlans { return "Checking with Apple…" }
        if commerce.preparingPurchase { return "Preparing your subscription…" }
        if commerce.busy { return "Confirming your purchase…" }
        return "Subscribe"
    }

    private var membershipBenefits: some View {
        let layout: GridItem.Size = typeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 234)
        return VStack(alignment: .leading, spacing: 16) {
            MediaTitle(title: "Plus benefits", textStyle: .title2, tint: MicOnStyle.ink)
            LazyVGrid(
                columns: [GridItem(layout, spacing: 24, alignment: .topLeading)],
                alignment: .leading, spacing: 20
            ) {
                benefit(.edit, "Export edited clips",
                        "Save or share your edits as MP4 at up to 1080p.")
                benefit(.sound, "Export audio as M4A",
                        "Save the audio track separately from the video.")
                benefit(.play, "Unlimited lesson views",
                        "Watch lessons by link, code or in the lesson feed.")
                benefit(.download, "Unlimited lesson downloads",
                        "Save lessons to your library for offline practice.")
                benefit(.mute, "No launch ads",
                        "Skip the ad when you switch back to MicOn, too.")
                benefit(.feed, "Export supported lessons",
                        "Keep a video file you can open outside MicOn.")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicOnStyle.paper, in: RoundedRectangle(cornerRadius: 24))
    }

    private func benefit(_ symbol: MicOnGlyph, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(MicOnStyle.paperSecondary.opacity(0.25))
                .frame(height: 1)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 10) {
                Glyph(symbol: symbol, size: 19, tint: MicOnStyle.ink)
                    .frame(width: 23, height: 24)
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText(title)
                        .font(.booth(.subheadline, weight: .semibold))
                        .foregroundStyle(MicOnStyle.ink)
                    LocalizedText(detail)
                        .font(.booth(.footnote))
                        .foregroundStyle(MicOnStyle.paperSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func subscribe() {
        guard !interactionLocked, let plan = selectedPlan else { return }
        attemptedPurchaseAction = true
        purchaseTask = Task {
            await commerce.purchase(planID: plan.productIdentifier)
            purchaseTask = nil
        }
    }

    @ViewBuilder private var availableRewards: some View {
        if !exportRequired, !commerce.premium, api.session != nil { rewardOption }
    }

    private var rewardOption: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedText("Ad rewards").font(.booth(.headline))
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
            if quota.usage != nil {
                LocalizedText(quota.unlimited ? "Unlimited views today" : "\(quota.watchesLeft) views left today")
                LocalizedText(quota.downloadsUnlimited ? "Unlimited downloads today" : "\(quota.downloadsLeft) downloads left today")
                AllowanceResetText()
            } else if quota.error == nil {
                LocalizedText("Loading…").foregroundStyle(MicOnStyle.secondary)
            }
            LocalizedText("When you run out of views or downloads, watch an ad to get more.")
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

    private func loadingMark(width: CGFloat, tint: Color = MicOnStyle.accent) -> some View {
        Image("MicOnLoadingMark").renderingMode(.template).resizable().scaledToFit()
            .foregroundStyle(tint)
            .frame(width: width, height: 14)
            .phaseAnimator([false, true]) { content, dimmed in
                content.opacity(reduceMotion || scenePhase != .active ? 1 : (dimmed ? 0.35 : 1))
            } animation: { _ in
                reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 0.6)
            }
            .accessibilityHidden(true)
    }

    private var restoreButton: some View {
        ActionButton(title: "Restore purchases", primary: false) {
            attemptedPurchaseAction = true
            commerce.restore()
        }
        .disabled(interactionLocked)
        .accessibilityIdentifier("membership.restore")
    }
}

struct AccountView: View {
    @Environment(\.locale) private var locale
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
            VStack(alignment: .leading, spacing: 24) {
                accountHeader
                if api.session != nil {
                    membershipCard
                    allowance
                } else {
                    ConnectionPanel()
                }
                AccountSettingsSection()
                LocalizedText("Version %@", api.configuration.version)
                    .font(.booth(.caption))
                    .foregroundStyle(MicOnStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.miconPage()
        }
            .miconScreenBackground(MicOnStyle.mediaBackground).foregroundStyle(MicOnStyle.paper)
            .sheet(isPresented: $paywall) { MembershipView() }
    }

    private var accountHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            MediaTitle(title: "Account")
            if let session = api.session {
                LocalizedText(commerce.premium ? "Plus active" : "Free plan")
                    .font(.booth(.footnote, weight: .semibold))
                    .foregroundStyle(commerce.premium ? MicOnStyle.accent : MicOnStyle.mist)
                LocalizedText("ID · %@", session.userId.value)
                    .font(.booth(.footnote))
                    .monospacedDigit()
                    .foregroundStyle(MicOnStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private var membershipCard: some View {
        Button { paywall = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    MediaTitle(title: "Plus", textStyle: .title2, tint: MicOnStyle.ink)
                    Spacer(minLength: 0)
                    TintedArtwork(name: "TabHome", tint: MicOnStyle.ink)
                        .frame(width: 27, height: 20)
                        .frame(width: 48, height: 48)
                        .background(MicOnStyle.mist, in: Circle())
                        .accessibilityHidden(true)
                }
                if commerce.premium, let expiration = commerce.expiration {
                    let date = expiration.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
                    LocalizedText("Access through %@.", date)
                        .font(.booth(.footnote))
                        .foregroundStyle(MicOnStyle.ink)
                } else {
                    LocalizedText("Export video and audio. Unlimited lesson views and downloads.")
                        .font(.booth(.footnote))
                        .foregroundStyle(MicOnStyle.ink)
                }
                HStack(spacing: 8) {
                    LocalizedText(commerce.premium ? "View membership" : "See plans")
                        .font(.booth(.subheadline, weight: .semibold))
                    Glyph(symbol: .back, size: 13, tint: MicOnStyle.ink)
                        .rotationEffect(.degrees(180))
                }
                .foregroundStyle(MicOnStyle.ink)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(MicOnStyle.accent, in: RoundedRectangle(cornerRadius: 24))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(PressStyle())
        .disabled(unavailable)
        .accessibilityIdentifier("account.membership")
    }

    private var allowance: some View {
        let title = MediaTitle(title: "Today’s online allowance", textStyle: .title2)
        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    title
                    Spacer(minLength: 0)
                    if !commerce.premium { allowanceAction }
                }
                VStack(alignment: .leading, spacing: 0) {
                    title
                    if !commerce.premium { allowanceAction }
                }
            }

            if commerce.premium || quota.usage != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { allowanceBalances }
                    VStack(alignment: .leading, spacing: 14) { allowanceBalances }
                }
            } else if quota.error == nil {
                LocalizedText("Loading…")
                    .font(.booth(.subheadline))
                    .foregroundStyle(MicOnStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !commerce.premium, let error = quota.error {
                ErrorNote(message: error)
            } else if !commerce.premium, quota.usage != nil {
                AllowanceResetText()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioGlass(in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder private var allowanceBalances: some View {
        balance(.watch, symbol: .play, label: "Views left")
        balance(.download, symbol: .download, label: "Downloads left")
    }

    private var allowanceAction: some View {
        Button { paywall = true } label: {
            HStack(spacing: 8) {
                LocalizedText("Get more")
                    .font(.booth(.footnote, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Glyph(symbol: .back, size: 11, tint: MicOnStyle.accent)
                    .rotationEffect(.degrees(180))
            }
            .foregroundStyle(MicOnStyle.accent)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(unavailable)
        .accessibilityLabel(Text(verbatim: L10n.text(
            "Get more daily views and downloads", language: AppLanguage.from(locale)
        )))
    }

    private func balance(_ kind: AllowanceKind, symbol: MicOnGlyph, label: String) -> some View {
        let unlimited = commerce.premium || quota.isUnlimited(kind)
        return VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(MicOnStyle.line)
                .frame(height: 1)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 6) {
                Glyph(symbol: symbol, size: 14, tint: MicOnStyle.accent)
                    .frame(width: 18, height: 20)
                LocalizedText(label)
                    .font(.booth(.footnote, weight: .medium))
                    .foregroundStyle(MicOnStyle.secondary)
            }
            Group {
                if unlimited {
                    LocalizedText("Unlimited").font(.booth(.headline))
                } else {
                    Text(verbatim: quota.remaining(kind).formatted(.number.grouping(.never).locale(locale)))
                        .font(.booth(.largeTitle, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(MicOnStyle.paper)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
                    LocalizedText("Bonus added").font(.booth(.headline)).foregroundStyle(.white)
                    LocalizedText("No ad is available right now. \(message)")
                        .font(.booth(.subheadline)).foregroundStyle(MicOnStyle.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    ActionButton(title: "Done", action: dismiss)
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
