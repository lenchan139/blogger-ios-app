import SwiftUI

/// Displays pageview statistics for a blog.
struct StatsView: View {
    let blog: Blog
    @EnvironmentObject private var appState: AppState

    @State private var pageViews: PageViews?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading stats…")
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn't load stats", systemImage: "chart.bar")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if let counts = pageViews?.counts, !counts.isEmpty {
                List {
                    ForEach(counts, id: \.timeRangeString) { count in
                        HStack {
                            Text(label(for: count.timeRange))
                            Spacer()
                            Text("\(count.views ?? 0)")
                                .font(.headline.monospacedDigit())
                        }
                    }
                }
            } else {
                ContentUnavailableView("No stats available", systemImage: "chart.bar")
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            pageViews = try await appState.api.getPageViews(blogId: blog.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func label(for range: String?) -> String {
        switch range {
        case "TOTAL": return "Total"
        case "1Y": return "Last 12 months"
        case "30DAYS": return "Last 30 days"
        case "7DAYS": return "Last 7 days"
        case "ALL_TIME": return "All time"
        default: return range ?? "Views"
        }
    }
}
