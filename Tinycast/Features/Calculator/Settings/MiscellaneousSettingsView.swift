import SwiftUI

/// The catch-all pane, home to currency conversion. See docs/features/calculator.md#rates.
struct MiscellaneousSettingsView: View {
    @Environment(AppCore.self) private var core
    private var currencyRates: CurrencyRateStore { core.currencyRates }
    @State private var refreshing = false
    @State private var refreshFailed = false

    var body: some View {
        Form {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { currencyRates.isEnabled },
                        set: { currencyRates.setEnabled($0) })
                ) {
                    SettingsRowTitle(.miscellaneousCalculator, "Currency Conversion")
                    Text(conversionStatus)
                }

                if currencyRates.isEnabled {
                    LabeledContent {
                        Button("Update Now") {
                            refreshing = true
                            Task {
                                let landed = await currencyRates.refreshNow()
                                refreshFailed = !landed
                                refreshing = false
                            }
                        }
                        .disabled(refreshing)
                    } label: {
                        Text("Exchange Rates")
                        Text(ratesStatus)
                    }
                }
            } header: {
                SettingsSectionHeader(.miscellaneousCalculator)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.miscellaneous)
    }

    /// The off state still promises silence, so the subtitle keeps saying so.
    private var conversionStatus: String {
        let examples = "Convert inline — \"100 dollars to yen\", \"€20 to GBP\"."
        return currencyRates.isEnabled ? examples : "\(examples) Off — no service is contacted."
    }

    private var ratesStatus: String {
        if refreshing { return "Updating…" }
        if refreshFailed { return "Couldn't reach \(CurrencyRateStore.provider). Try again." }
        guard let fetched = currencyRates.rates?.fetchedAt else {
            return "\(CurrencyRateStore.provider) · not downloaded yet."
        }
        let stamp = fetched.formatted(date: .abbreviated, time: .shortened)
        return "\(CurrencyRateStore.provider) · updated \(stamp). Refreshes daily."
    }
}
