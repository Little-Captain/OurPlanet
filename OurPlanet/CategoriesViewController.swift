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

import UIKit
import RxSwift
import RxCocoa

class CategoriesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    @IBOutlet var tableView: UITableView!
    var activityIndicator: UIActivityIndicatorView!
    let download = DownloadView()
    
    let categories = Variable<[EOCategory]>([])
    let bag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        activityIndicator = UIActivityIndicatorView()
        activityIndicator.color = .black
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: activityIndicator)
        activityIndicator.startAnimating()
        
        view.addSubview(download)
        view.layoutIfNeeded()
        
        tableView.tableFooterView = UIView()
        
        categories
            .asObservable()
            .subscribe(onNext: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.tableView?.reloadData()
                }
            })
            .disposed(by: bag)
        
        startDownload()
    }
    
    func startDownload() {
        download.progress.progress = 0
        download.label.text = "Download: 0%"
        
        let eoCategories = EONET.categories
        let downloadedEvents = eoCategories
            .flatMap { Observable.from($0.map { EONET.events(category: $0) }) }
            .merge(maxConcurrent: 2)
        
        // Challenge 2: 方法 1
        let updatedCategories = eoCategories
            .flatMap {
                downloadedEvents.scan((0, $0)) { tuple, events in
                    (tuple.0 + 1, tuple.1.map {
                        let eventsForCategory = EONET.filteredEvents(events: events, forCategory: $0)
                        if !eventsForCategory.isEmpty {
                            var c = $0
                            c.events += eventsForCategory
                            return c
                        }
                        return $0
                    })
                }
            }
            .do(onNext: { [weak self] tuple in
                DispatchQueue.main.async {
                    let progress = Float(tuple.0) / Float(tuple.1.count)
                    self?.download.progress.progress = progress
                    let percent = Int(progress * 100.0)
                    self?.download.label.text = "Download: \(percent)%"
                }
            })
            .do(onCompleted: { [weak self] in
                DispatchQueue.main.async {
                    self?.activityIndicator?.stopAnimating()
                    self?.download.isHidden = true
                }
            })

        eoCategories
            .concat(updatedCategories.map { $0.1 })
            .bind(to: categories)
            .disposed(by: bag)
        
        // Challenge 2: 方法 2
//        let updatedCategories = eoCategories
//            .flatMap {
//                downloadedEvents.scan($0) { updated, events in
//                    updated.map {
//                        let eventsForCategory = EONET.filteredEvents(events: events, forCategory: $0)
//                        if !eventsForCategory.isEmpty {
//                            var c = $0
//                            c.events += eventsForCategory
//                            return c
//                        }
//                        return $0
//                    }
//                }
//            }
//            // 这里必须使用 share() 共享订阅. share() 会共享已经创建的订阅给所有订阅者
//            // 不然会因为重复订阅而产生重复的网络请求(所有的分类事件都请求两次)
//            // 为什么这里能使用 share() 解决这个 bug
//            // 1. 所有针对 updatedCategories 的订阅都是同时进行的
//            // 2. updatedCategories 完成后, 没有新的订阅
//            .share()
//            .do(onCompleted: { [weak self] in
//                DispatchQueue.main.async {
//                    self?.activityIndicator?.stopAnimating()
//                    self?.download.isHidden = true
//                }
//            })
//
//        eoCategories
//            .flatMap { categories in
//                updatedCategories
//                    .scan(0) { count, _ in count + 1 }
//                    .startWith(0)
//                    .map { ($0, categories.count) }
//            }
//            .subscribe(onNext: { [weak self] tuple in
//                DispatchQueue.main.async {
//                    let progress = Float(tuple.0) / Float(tuple.1)
//                    self?.download.progress.progress = progress
//                    let percent = Int(progress * 100.0)
//                    self?.download.label.text = "Download: \(percent)%"
//                }
//            })
//            .disposed(by: bag)
//
//        eoCategories
//            .concat(updatedCategories)
//            .bind(to: categories)
//            .disposed(by: bag)
        
        // 方法 1 和 方法 2 比较
        // 方法 2 的进度更新在列表刷新之前
        // 方法 2 所有的事件请求都发送了两次请求(重复发送请求), 使用 share() 解决这个 bug
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let category = categories.value[indexPath.row]
        if !category.events.isEmpty {
            let eventsController = storyboard!.instantiateViewController(withIdentifier: "events") as! EventsViewController
            eventsController.title = category.name
            eventsController.events.value = category.events
            navigationController!.pushViewController(eventsController, animated: true)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return categories.value.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "categoryCell")!
        let category = categories.value[indexPath.row]
        cell.textLabel?.text = "\(category.name) (\(category.events.count))"
        cell.accessoryType = (category.events.count > 0) ? .disclosureIndicator : .none
        cell.detailTextLabel?.text = category.description
        return cell
    }
    
}

