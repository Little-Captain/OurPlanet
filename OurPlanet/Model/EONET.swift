/*
 * Copyright (c) 2016 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */


import Foundation
import RxSwift
import RxCocoa

class EONET {
    
    static let API = "https://eonet.sci.gsfc.nasa.gov/api/v2.1"
    static let categoriesEndpoint = "/categories"
    static let eventsEndpoint = "/events"
    
    static var ISODateReader: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZ"
        return formatter
    }()
    
    static func filteredEvents(events: [EOEvent], forCategory category: EOCategory) -> [EOEvent] {
        return events.filter { event in
            return event.categories.contains(category.id) &&
                !category.events.contains {
                    $0.id == event.id
            }
            }
            .sorted(by: EOEvent.compareDates)
    }
    
    static func request(endpoint: String, query: [String: Any] = [:]) -> Observable<[String: Any]> {
        do {
            guard let url = URL(string: API)?.appendingPathComponent(endpoint),
                var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                    throw EOError.invalidURL(endpoint)
            }
            
            components.queryItems = try query.compactMap {
                guard let v = $1 as? CustomStringConvertible else {
                    throw EOError.invalidParameter($0, $1)
                }
                return URLQueryItem(name: $0, value: v.description)
            }
            
            guard let finalURL = components.url else {
                throw EOError.invalidURL(endpoint)
            }
            
            return URLSession.shared.rx.response(request: URLRequest(url: finalURL))
                .map { _, d -> [String: Any] in
                    guard let json = try? JSONSerialization.jsonObject(with: d, options: []),
                        let r = json as? [String: Any] else {
                            throw EOError.invalidJSON(finalURL.absoluteString)
                    }
                    return r
            }
        } catch {
            return Observable.empty()
        }
    }
    
    static let categories: Observable<[EOCategory]> = {
        return EONET.request(endpoint: categoriesEndpoint)
            .map {
                guard let raw = $0["categories"] as? [[String: Any]] else {
                    throw EOError.invalidJSON(categoriesEndpoint)
                }
                return raw
                    .compactMap(EOCategory.init)
                    .sorted { $0.name < $1.name }
            }
            .catchErrorJustReturn([])
            .share(replay: 1, scope: .forever)
    }()
    
    static func events(forLast days: Int = 360) -> Observable<[EOEvent]> {
        let openEvents = events(forLast: days, closed: false)
        let closedEvents = events(forLast: days, closed: true)
        return openEvents.concat(closedEvents)
    }
    
    fileprivate static func events(forLast days: Int, closed: Bool) -> Observable<[EOEvent]> {
        return request(endpoint: eventsEndpoint,
                       query: ["days": NSNumber(value: days), "status": (closed ? "closed" : "open")])
            .map {
                guard let raw = $0["events"] as? [[String: Any]] else {
                    throw EOError.invalidJSON(eventsEndpoint)
                }
                return raw.compactMap(EOEvent.init)
            }
            .catchErrorJustReturn([])
    }
    
}
