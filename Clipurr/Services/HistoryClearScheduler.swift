import Foundation

@MainActor
final class HistoryClearScheduler {
    private let historyStore: HistoryStore
    private let onCleared: () -> Void
    private var timer: Timer?

    init(historyStore: HistoryStore, onCleared: @escaping () -> Void = {}) {
        self.historyStore = historyStore
        self.onCleared = onCleared
    }

    func start() {
        stop()
        performScheduledClear(isLaunch: true)

        let timer = Timer(timeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performScheduledClear(isLaunch: false)
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func performScheduledClear(isLaunch: Bool) {
        switch AppSettings.historyClearInterval {
        case .never:
            return
        case .onRestart:
            guard isLaunch else { return }
            clearHistory()
        case .hourly, .daily, .weekly, .monthly:
            guard let component = AppSettings.historyClearInterval.calendarComponent else { return }
            // Nil lastClear means the window was never started — begin counting now
            // instead of treating it as distantPast (which would wipe history immediately).
            guard let lastClear = AppSettings.lastAutomaticHistoryClear else {
                AppSettings.lastAutomaticHistoryClear = .now
                return
            }
            guard let nextClear = Calendar.current.date(byAdding: component, value: 1, to: lastClear),
                  Date.now >= nextClear else {
                return
            }
            clearHistory()
        }
    }

    private func clearHistory() {
        historyStore.clear()
        AppSettings.lastAutomaticHistoryClear = .now
        onCleared()
    }
}
