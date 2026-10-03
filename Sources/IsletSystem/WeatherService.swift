import CoreLocation
import Foundation
import IsletCore

/// Fetches forecasts and finds places on Open-Meteo, over an ephemeral session that refuses
/// redirects, so a typed place or a rounded position can't be carried to another host. Used only
/// while the user has the weather turned on.
public final class WeatherService {
    private let session: URLSession

    /// `protocolClasses` lets tests answer requests without a network.
    public init(version: String, protocolClasses: [AnyClass] = []) {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.httpAdditionalHeaders = ["User-Agent": "Islet \(version) (https://github.com/aviralgarg05/islet)"]
        if !protocolClasses.isEmpty { c.protocolClasses = protocolClasses + (c.protocolClasses ?? []) }
        session = URLSession(configuration: c, delegate: NoRedirects(), delegateQueue: nil)
    }

    /// The forecast for a position (rounded before it is sent). Completes on the main thread.
    public func forecast(latitude: Double, longitude: Double, completion: @escaping (Result<WeatherReport, Error>) -> Void) {
        load(OpenMeteo.forecastURL(latitude: latitude, longitude: longitude), completion: completion) { data in
            try OpenMeteo.decodeForecast(data, fetchedAt: Date())
        }
    }

    /// Places matching a name the user typed. Completes on the main thread.
    public func places(named name: String, completion: @escaping (Result<[WeatherPlace], Error>) -> Void) {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        guard let url = OpenMeteo.geocodingURL(name, language: language) else {
            completion(.success([]))
            return
        }
        load(url, completion: completion, decode: OpenMeteo.decodePlaces)
    }

    private func load<T>(_ url: URL, completion: @escaping (Result<T, Error>) -> Void, decode: @escaping (Data) throws -> T) {
        session.dataTask(with: url) { data, response, error in
            let result: Result<T, Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(URLError(.badServerResponse))
            } else {
                result = Result { try decode(data ?? Data()) }
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

/// Where the Mac is, for the weather, asked for once each time the forecast is due. macOS asks
/// the user the first time; nothing is requested unless "Where I am" is chosen in Settings.
public final class LocationProvider: NSObject, CLLocationManagerDelegate {
    public enum Access: Equatable { case notDetermined, granted, denied }

    public enum Failure: Error, Equatable {
        case denied
        case unavailable
    }

    private var manager: CLLocationManager?
    private var waiting: [(Result<CLLocationCoordinate2D, Failure>) -> Void] = []

    public override init() {}

    public static var access: Access {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Asks macOS for permission if it hasn't been asked yet, then for one position.
    public func requestLocation(completion: @escaping (Result<CLLocationCoordinate2D, Failure>) -> Void) {
        waiting.append(completion)
        let m = manager ?? CLLocationManager()
        manager = m
        m.delegate = self
        // Kilometre accuracy is all a forecast needs, and the quickest to get.
        m.desiredAccuracy = kCLLocationAccuracyKilometer
        switch m.authorizationStatus {
        case .notDetermined: m.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: m.requestLocation()
        default: finish(.failure(.denied))
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !waiting.isEmpty else { return }
        switch manager.authorizationStatus {
        case .notDetermined: break
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: finish(.failure(.denied))
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        finish(.success(last.coordinate))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure((error as? CLError)?.code == .denied ? .denied : .unavailable))
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Failure>) {
        let callbacks = waiting
        waiting = []
        DispatchQueue.main.async { callbacks.forEach { $0(result) } }
    }
}
