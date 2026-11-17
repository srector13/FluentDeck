import CoreLocation
import Observation
import SwiftUI

/// The weather where you are, from Open-Meteo (free, no account). The place is one you search for,
/// or the iPad's location. Runs on the iPad, so it works without the PC.
struct WeatherPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "weather",
        title: "Weather",
        summary: "Current conditions, today's high and low, and the days ahead, for a place you choose or where the iPad is. Forecasts from Open-Meteo.",
        symbol: "cloud.sun",
        sizes: [.small, .medium, .large, .wide],
        defaultSize: .medium,
        menu: { ctx in
            [.action("Choose Location…", symbol: "magnifyingglass") { WeatherPanel.chooseLocation(ctx) },
             .action("Use Current Location", symbol: "location") { WeatherPanel.useCurrentLocation(ctx) }]
        },
        view: { AnyView(WeatherPanel(ctx: $0)) })

    @Environment(\.theme) private var theme
    @State private var store = WeatherStore.shared

    private var place: WeatherPlace? {
        if let lat = ctx.config["lat"].flatMap(Double.init), let lon = ctx.config["lon"].flatMap(Double.init) {
            return WeatherPlace(name: ctx.config["place"] ?? "", latitude: lat, longitude: lon)
        }
        return LaunchOptions.demoPlanner ? WeatherDemo.place : nil
    }

    var body: some View {
        if let place {
            Group {
                if let f = store.forecasts[place.key] {
                    switch ctx.size {
                    case .small: small(f, place)
                    case .large, .tall, .huge: large(f, place)
                    case .wide, .banner: wide(f, place)
                    default: medium(f, place)
                    }
                } else if let error = store.errors[place.key] {
                    PanelEmptyState(symbol: "exclamationmark.icloud", text: error)
                } else {
                    Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task(id: place.key) {
                while !Task.isCancelled {
                    await store.load(place)
                    try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
                }
            }
        } else {
            VStack(spacing: 10) {
                PanelEmptyState(symbol: "cloud.sun", text: "Where should the weather be for?").frame(maxHeight: 70)
                HStack(spacing: 8) {
                    Button("Search…") { Self.chooseLocation(ctx) }.buttonStyle(PillButtonStyle(compact: true))
                    Button { Self.useCurrentLocation(ctx) } label: { Label("Here", systemImage: "location.fill") }
                        .buttonStyle(PillButtonStyle(kind: .accent, compact: true))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: layouts

    private func header(_ place: WeatherPlace) -> some View {
        HStack(spacing: 4) {
            if ctx.config["auto"] == "1" { Image(systemName: "location.fill").font(.system(size: 10)) }
            Text(place.name.isEmpty ? "Weather" : place.name).lineLimit(1)
        }
        .font(AppFont.caption.weight(.semibold))
        .foregroundStyle(theme.textSecondary)
    }

    private func small(_ f: Forecast, _ place: WeatherPlace) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(place)
            Spacer(minLength: 0)
            WeatherIcon(code: f.current.code, isDay: f.current.isDay, size: 28)
            Text(f.temp(f.current.temperature)).font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ f: Forecast, _ place: WeatherPlace) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                header(place)
                Text(f.temp(f.current.temperature))
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                WeatherIcon(code: f.current.code, isDay: f.current.isDay, size: 34)
                Text(WeatherCode.describe(f.current.code)).font(AppFont.caption.weight(.semibold)).foregroundStyle(theme.textPrimary)
                if let today = f.days.first {
                    Text("H:\(f.temp(today.high))  L:\(f.temp(today.low))").font(AppFont.caption).foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    private func wide(_ f: Forecast, _ place: WeatherPlace) -> some View {
        HStack(spacing: 22) {
            medium(f, place).frame(maxWidth: 320)
            Rectangle().fill(theme.divider).frame(width: 1).padding(.vertical, 6)
            HStack(spacing: 0) {
                ForEach(f.days.dropFirst().prefix(5)) { day in
                    VStack(spacing: 8) {
                        Text(day.weekday).font(AppFont.caption.weight(.semibold)).foregroundStyle(theme.textSecondary)
                        WeatherIcon(code: day.code, isDay: true, size: 22)
                        Text(f.temp(day.high)).font(AppFont.bodyStrong).foregroundStyle(theme.textPrimary)
                        Text(f.temp(day.low)).font(AppFont.caption).foregroundStyle(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func large(_ f: Forecast, _ place: WeatherPlace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            medium(f, place)
            Rectangle().fill(theme.divider).frame(height: 1)
            let range = f.weekRange
            VStack(spacing: 0) {
                ForEach(f.days.prefix(5)) { day in
                    HStack(spacing: 12) {
                        Text(day.isToday ? "Today" : day.weekday).font(AppFont.body.weight(.medium)).frame(width: 64, alignment: .leading)
                            .foregroundStyle(theme.textPrimary)
                        WeatherIcon(code: day.code, isDay: true, size: 20).frame(width: 30)
                        Text(f.temp(day.low)).font(AppFont.body).foregroundStyle(theme.textSecondary).frame(width: 42, alignment: .trailing)
                        TempBar(low: day.low, high: day.high, range: range)
                        Text(f.temp(day.high)).font(AppFont.body).foregroundStyle(theme.textPrimary).frame(width: 42, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: choosing a place

    static func chooseLocation(_ ctx: PanelContext) {
        ctx.overlays.present { WeatherSearchDialog(ctx: ctx) }
    }

    static func useCurrentLocation(_ ctx: PanelContext) {
        Task { @MainActor in
            do {
                let place = try await LocationOnce.current()
                ctx.updateConfig("lat", String(place.latitude))
                ctx.updateConfig("lon", String(place.longitude))
                ctx.updateConfig("place", place.name)
                ctx.updateConfig("auto", "1")
            } catch {
                ctx.connection.report(HostError.action((error as? LocalizedError)?.errorDescription ?? "Couldn't find where the iPad is."))
            }
        }
    }
}

/// A day's low-to-high span against the whole week's, as in the Weather app.
private struct TempBar: View {
    let low: Double
    let high: Double
    let range: ClosedRange<Double>
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { g in
            let span = max(1, range.upperBound - range.lowerBound)
            let x0 = (low - range.lowerBound) / span * g.size.width
            let x1 = (high - range.lowerBound) / span * g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(theme.trackFill)
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: "#64D2FF"), Color(hex: "#FFD60A"), Color(hex: "#FF9F0A")], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, x1 - x0))
                    .offset(x: x0)
            }
        }
        .frame(height: 5)
    }
}

struct WeatherIcon: View {
    let code: Int
    let isDay: Bool
    var size: CGFloat

    var body: some View {
        Image(systemName: WeatherCode.symbol(code, isDay: isDay))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
            .accessibilityLabel(WeatherCode.describe(code))
    }
}

// MARK: - Data

struct WeatherPlace: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    var key: String { String(format: "%.3f,%.3f", latitude, longitude) }
}

struct Forecast: Equatable {
    struct Now: Equatable { var temperature: Double; var code: Int; var isDay: Bool }
    struct Day: Equatable, Identifiable {
        var date: Date
        var code: Int
        var high: Double
        var low: Double
        var id: Date { date }
        var weekday: String { date.formatted(.dateTime.weekday(.abbreviated)) }
        var isToday: Bool { Calendar.current.isDateInToday(date) }
    }
    var current: Now
    var days: [Day]
    var fahrenheit: Bool

    func temp(_ value: Double) -> String { "\(Int(value.rounded()))°" }

    var weekRange: ClosedRange<Double> {
        let lows = days.prefix(5).map(\.low), highs = days.prefix(5).map(\.high)
        let lo = lows.min() ?? 0, hi = highs.max() ?? 1
        return lo...max(hi, lo + 1)
    }
}

/// Fetches and caches forecasts, refreshed at most every 15 minutes per place.
@MainActor
@Observable
final class WeatherStore {
    static let shared = WeatherStore()

    private(set) var forecasts: [String: Forecast] = [:]
    private(set) var errors: [String: String] = [:]
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]

    static var fahrenheit: Bool { Locale.current.measurementSystem == .us }

    func load(_ place: WeatherPlace) async {
        if let at = fetchedAt[place.key], Date.now.timeIntervalSince(at) < 14 * 60, forecasts[place.key] != nil { return }
        if LaunchOptions.demoPlanner {
            forecasts[place.key] = WeatherDemo.forecast(fahrenheit: Self.fahrenheit)
            return
        }
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "6"),
            .init(name: "temperature_unit", value: Self.fahrenheit ? "fahrenheit" : "celsius"),
        ]
        do {
            let (data, response) = try await URLSession.shared.data(from: parts.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            forecasts[place.key] = try Self.decode(data, fahrenheit: Self.fahrenheit)
            errors[place.key] = nil
            fetchedAt[place.key] = .now
        } catch {
            if forecasts[place.key] == nil { errors[place.key] = "Couldn't get the weather. Check the iPad's internet connection." }
        }
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double
            var weather_code: Int
            var is_day: Int
        }
        struct Daily: Decodable {
            var time: [String]
            var weather_code: [Int]
            var temperature_2m_max: [Double]
            var temperature_2m_min: [Double]
        }
        var current: Current
        var daily: Daily
    }

    static func decode(_ data: Data, fahrenheit: Bool) throws -> Forecast {
        let r = try JSONDecoder().decode(Response.self, from: data)
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd"
        parse.locale = Locale(identifier: "en_US_POSIX")
        let days = r.daily.time.indices.compactMap { i -> Forecast.Day? in
            guard let date = parse.date(from: r.daily.time[i]),
                  r.daily.weather_code.indices.contains(i), r.daily.temperature_2m_max.indices.contains(i),
                  r.daily.temperature_2m_min.indices.contains(i) else { return nil }
            return Forecast.Day(date: date, code: r.daily.weather_code[i], high: r.daily.temperature_2m_max[i], low: r.daily.temperature_2m_min[i])
        }
        return Forecast(current: .init(temperature: r.current.temperature_2m, code: r.current.weather_code, isDay: r.current.is_day == 1),
                        days: days, fahrenheit: fahrenheit)
    }
}

/// WMO weather codes, as Open-Meteo reports them.
enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63: return "cloud.rain.fill"
        case 65: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 82: return "cloud.heavyrain.fill"
        case 95: return "cloud.bolt.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorms"
        case 96, 99: return "Hail"
        default: return "—"
        }
    }
}

/// Stand-in weather for screenshots and tests: nothing is fetched and no location is asked for.
enum WeatherDemo {
    static let place = WeatherPlace(name: "Seattle", latitude: 47.606, longitude: -122.332)

    static func forecast(fahrenheit: Bool) -> Forecast {
        func t(_ f: Double) -> Double { fahrenheit ? f : (f - 32) * 5 / 9 }
        let today = Calendar.current.startOfDay(for: .now)
        let days: [(Int, Double, Double)] = [(2, 54, 43), (61, 51, 44), (3, 49, 41), (80, 52, 42), (1, 56, 40), (0, 58, 41)]
        return Forecast(
            current: .init(temperature: t(51), code: 2, isDay: true),
            days: days.enumerated().map { i, d in
                Forecast.Day(date: Calendar.current.date(byAdding: .day, value: i, to: today)!, code: d.0, high: t(d.1), low: t(d.2))
            },
            fahrenheit: fahrenheit)
    }
}

// MARK: - Choosing a place

/// Searches Open-Meteo's place names.
private struct WeatherSearchDialog: View {
    let ctx: PanelContext
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var results: [Result] = []
    @State private var searching = false

    struct Result: Decodable, Identifiable {
        var name: String
        var latitude: Double
        var longitude: Double
        var country: String?
        var admin1: String?
        var id: String { "\(latitude),\(longitude)" }
        var detail: String { [admin1, country].compactMap { $0 }.joined(separator: ", ") }
    }

    var body: some View {
        DialogSheet(title: "Weather Location",
                    cancel: DialogAction("Cancel") { ctx.overlays.dismissDialog() },
                    confirm: DialogAction("Use Current Location") {
                        ctx.overlays.dismissDialog()
                        WeatherPanel.useCurrentLocation(ctx)
                    }) {
            TextBox(placeholder: "City or town", text: $query)
            if searching {
                Spinner(size: 18).frame(maxWidth: .infinity, minHeight: 44)
            }
            VStack(spacing: 2) {
                ForEach(results.prefix(6)) { r in
                    Button { choose(r) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name).font(AppFont.body).foregroundStyle(theme.textPrimary)
                            if !r.detail.isEmpty { Text(r.detail).font(AppFont.caption).foregroundStyle(theme.textSecondary) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DimOnPress())
                }
            }
            Text("Forecasts come from Open-Meteo. The place you pick is sent to it to look up the weather.")
                .font(AppFont.caption).foregroundStyle(theme.textSecondary)
        }
        .task(id: query) {
            let term = query.trimmingCharacters(in: .whitespaces)
            guard term.count >= 2 else { results = []; return }
            try? await Task.sleep(nanoseconds: 350_000_000) // wait for typing to pause
            guard !Task.isCancelled else { return }
            await search(term)
        }
    }

    private struct Response: Decodable { var results: [Result]? }

    private func search(_ term: String) async {
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        parts.queryItems = [.init(name: "name", value: term), .init(name: "count", value: "6"),
                            .init(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en")]
        searching = true
        defer { searching = false }
        guard let (data, _) = try? await URLSession.shared.data(from: parts.url!),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return }
        results = decoded.results ?? []
    }

    private func choose(_ r: Result) {
        ctx.updateConfig("lat", String(r.latitude))
        ctx.updateConfig("lon", String(r.longitude))
        ctx.updateConfig("place", r.name)
        ctx.updateConfig("auto", nil)
        ctx.overlays.dismissDialog()
    }
}

/// One fix of the iPad's location, and the town it's in.
@MainActor
final class LocationOnce: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private static var active: LocationOnce?

    struct Denied: LocalizedError {
        var errorDescription: String? { "FluentDeck can't use the iPad's location. Allow it in Settings › FluentDeck › Location, or search for a place instead." }
    }

    static func current() async throws -> WeatherPlace {
        let finder = LocationOnce()
        active = finder
        defer { active = nil }
        let location = try await finder.locate()
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        return WeatherPlace(name: placemark?.locality ?? placemark?.name ?? "Current Location",
                            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private func locate() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: finish(.failure(Denied()))
            default: manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .denied, .restricted: self.finish(.failure(Denied()))
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in if let l = locations.last { self.finish(.success(l)) } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }
}
