//: View your reddit comment history by phases of subreddit activity
  
import UIKit
import PlaygroundSupport

let username = "YOUR_REDDIT_USERNAME"
let period: Period /* .day, .week, .month */ = .week
let maxComments /* min: 1, max: 1000 */ = 200

// filters
let minCommentThreshold = 1
let minActiveDays = 1

// TODO:
// < > to go through subs
// < > to expand/limit history

class MyViewController: UIViewController {
    
    var comments = [Comment]()
    var plots = [Plot]()

    // view containers
    var header: HeaderView!
    var loadingView: LoadingView!

    // fetching
    var remainingComments = 0
    let apiLimit = 100
    var after: String?
    
    // graphing
    var chart: Chart!
    var legend: Legend!
    var cycleTimer: Timer!
    var maxDaysAgo = 0
    
    override func loadView() {
        let view = UIView()
        
        // create header (title, subtitle, cycle button, icon)
        header = HeaderView(frame: CGRect(x: 0, y: 0, width: 750, height: 90))
        header.cycleButton.addTarget(self, action: #selector(cycleColors), for: .touchUpInside)
        view.addSubview(header)
        
        // add line chart for analysis
        chart = Chart(frame: CGRect(x: 30, y: 90, width: 720, height: 360))
        chart.minX = 0
        chart.minY = 0
        chart.hideHighlightLineOnTouchEnd = true
        view.addSubview(chart)
        
        // add labels for each axis
        let axisLabels = [AxisLabel(.x, period), AxisLabel(.y)]
        axisLabels.forEach { view.addSubview($0) }
        
        // add legend for associated subreddits
        legend = Legend(frame: CGRect(x: 0, y: 465, width: 750, height: 285), padding: 10)
        legend.dataSource = self
        legend.delegate = self
        view.addSubview(legend)
        
        // create loading view for fetching, parsing, graphing
        loadingView = LoadingView(frame: CGRect(x: 300, y: 200, width: 150, height: 100))
        view.addSubview(loadingView)
        
        self.view = view
        
        fetchCommentsForUser(username, limit: maxComments) { comments in
            let groupedDataPoints = self.createGroupedDataPoints(for: comments, period)
            self.graphDataPoints(groupedDataPoints, self.chart)
        }
    }
    
    func getCommentsUrl(username: String, limit: Int, after: String?) -> URL {
        var urlString = "https://www.reddit.com/user/\(username)/comments/.json?limit=\(limit)"
        if let after = after {  // subsequent calls
            urlString += "&after=\(after)"
        }
        return URL(string: urlString)!
    }
    
    // MARK: - STEP 1
    /// Fetch user comments from the reddit api, recursively called until complete
    func fetchCommentsForUser(_ username: String, limit: Int, completion: @escaping ([Comment]) -> ()) {
        let limit = limit.clamped(1, 1000)
        self.remainingComments = limit
        let fetchLimit = limit > apiLimit ? apiLimit : limit
        
        DispatchQueue.main.async {
            // update loading indicator (first 40%)
            if !self.loadingView.indicator.isAnimating {
                self.loadingView.indicator.startAnimating()
            }
            let percentage = Double(fetchLimit) / Double(limit)
            self.loadingView.label.text = "Fetching: \(Int((percentage * 100) / 2.5))%"
        }
        
        let url = getCommentsUrl(username: username, limit: fetchLimit, after: self.after)
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                return
            }
            if let data = data {
                if let parent = try? JSONDecoder().decode(JSONParent.self, from: data) {
                    let comments = parent.data.children.map { $0.data }
                    
                    self.comments.append(contentsOf: comments)
                    self.remainingComments -= fetchLimit
                    self.after = parent.data.after
                    
                    // only finish when all comments are fetched
                    if self.remainingComments == 0 || self.after == nil {
                        completion(self.comments)
                    } else {
                        self.fetchCommentsForUser(username, limit: self.remainingComments, completion: completion)
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - STEP 2
    /// Creates data points grouped by given period (day, week, month) for each subreddit
    func createGroupedDataPoints(for comments: [Comment], _ period: Period) -> [String : [DataPoint]] {
        var dataPoints = [DataPoint]()
        
        let now = Int(Date().timeIntervalSince1970)
        var daysAgo = 0
        var offset = period.rawValue

        for (index, comment) in comments.enumerated() {
            let date = comment.createdUTC
            
            // increase offset until date falls within given period
            while date < now - offset {
                daysAgo += 1
                offset = period.rawValue + (daysAgo * period.rawValue)
            }
            
            let subreddit = comment.subreddit
            let newDataPoint = DataPoint(daysAgo: daysAgo, subreddit: subreddit, count: 1)
            let dataPoint = dataPoints.filter { $0 == newDataPoint }.first
            
            // modify existing DataPoint if available
            if let dataPoint = dataPoint {
                dataPoint.count += 1
            } else {
                dataPoints.append(newDataPoint)
            }
            
            // kept track of so all series match in length
            if daysAgo > maxDaysAgo {
                maxDaysAgo = daysAgo
            }
            
            DispatchQueue.main.async {
                // update loading indicator
                let percentage = Double(index) / Double(comments.count)
                self.loadingView.label.text = "Parsing: \(40 + Int((percentage * 100) / 2.5))%"
            }
        }
        
        let groupedDataPoints = Dictionary(grouping: dataPoints, by: { $0.subreddit })
        return groupedDataPoints
    }
    
    // MARK: - STEP 3
    /// Take a dictionary of graph points and plot each series on the chart
    func graphDataPoints(_ groupedDataPoints: [String : [DataPoint]], _ chart: Chart) {
        for (index, key) in groupedDataPoints.keys.enumerated() {
            let dataPoints = groupedDataPoints[key] ?? []
            var daysAgo = 0
            var points = [Double]()
            
            /* begin filters */
            let exceedsCommentThreshold = dataPoints
                .filter { $0.count >= minCommentThreshold }
                .count > 0
            if !exceedsCommentThreshold {
                continue
            }
            
            let exceedsActiveDaysThreshold = dataPoints.count >= minActiveDays
            if !exceedsActiveDaysThreshold {
                continue
            }
            /* end filters */
            
            // helper for cleaner code
            func addPoint(point: Double) {
                points.append(point)
                daysAgo += 1
            }
            
            for dataPoint in dataPoints {
                // fill in points up to first data point
                while daysAgo < dataPoint.daysAgo {
                    addPoint(point: 0)
                }
                // add point (x: period ago, y: number of comments in sub)
                addPoint(point: Double(dataPoint.count))
            }
            // fill in points after last data point
            while daysAgo <= self.maxDaysAgo {
                addPoint(point: 0)
            }
            
            // add subreddit line to chart
            let series = ChartSeries(points)
            series.color = self.generateRandomColor()
            series.area = true
            chart.add(series)
            
            DispatchQueue.main.async {
                // update loading indicator
                let percentage = Double(index) / Double(groupedDataPoints.count)
                self.loadingView.label.text = "Graphing: \(80 + Int((percentage * 100) / 6.66666666666))%"
            }
            
            // pair subreddit with series for legend
            plots.append(Plot(subreddit: key, series: series))
        }
        
        // sort subreddits to be in alphabetical order
        plots.sort(by: { $0.subreddit.lowercased() < $1.subreddit.lowercased() })
        
        // helpful for debugging
        plots.forEach { print("\($0.subreddit): \(groupedDataPoints[$0.subreddit]!)") }
        
        // enable cycle colors button, generate legend
        DispatchQueue.main.async {
            self.loadingView.label.text = "Finished: 100%"
            self.loadingView.indicator.stopAnimating()
            self.header.cycleButton.isEnabled = true
            self.legend.reloadData()
        }
        // show legend scroll indicators
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.legend.flashScrollIndicators()
        }
        // remove loading view
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.loadingView.removeFromSuperview()
        }
    }
    
    // UIButton action to cycle colors
    // run after delay for UI responsiveness
    @objc func cycleColors() {
        for plot in plots {
            plot.series.color = generateRandomColor()
            plot.series.areaAlphaComponent = 0.1
        }
        redrawChart()
        
        cycleTimer?.invalidate()
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false, block: { _ in
            self.legend.reloadData()
        })
    }
    
    func redrawChart() {
        chart.removeAllSeries()
        let series = plots.map { $0.series }
        chart.add(series)
    }
    
    func generateRandomColor() -> UIColor {
        return UIColor(red: CGFloat(drand48()), green: CGFloat(drand48()), blue: CGFloat(drand48()), alpha: 1)
    }
}

// MARK: - Chart Legend
extension MyViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return plots.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath)
        cell.backgroundColor = UIColor(white: 0.9, alpha: 1)
        cell.selectedBackgroundView = UIView(frame: cell.bounds)
        cell.selectedBackgroundView?.backgroundColor = UIColor(white: 0.7, alpha: 1)
        
        let icon = UIImageView(frame: CGRect(x: 5, y: 5, width: 10, height: 10))
        let fullAlphaColor = plots[indexPath.row].series.color.withAlphaComponent(1)
        icon.image = UIImage.circle(diameter: 10, color: fullAlphaColor)
        cell.contentView.addSubview(icon)
        
        let label = UILabel()
        label.text = plots[indexPath.row].subreddit
        let size = label.intrinsicContentSize
        label.frame = CGRect(x: 20, y: 0, width: size.width, height: size.height)
        cell.contentView.addSubview(label)
        
        return cell
    }
  
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let label = UILabel()
        label.text = plots[indexPath.row].subreddit
        let size = label.intrinsicContentSize
        return CGSize(width: size.width + 25, height: size.height)
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        if let selectedIndexPath = collectionView.indexPathsForSelectedItems?.first, selectedIndexPath == indexPath {
            collectionView.deselectItem(at: indexPath, animated: true)
            
            for plot in plots {
                let color = plot.series.color
                plot.series.color = color.withAlphaComponent(1)
                plot.series.areaAlphaComponent = 0.1
            }
            redrawChart()
            
            return false
        }
        // animate selection
        collectionView.selectItem(at: indexPath, animated: true, scrollPosition: .left)
        return true
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let selectedPlot = plots[indexPath.row]
        for plot in plots {
            let color = plot.series.color
            if plot == selectedPlot {
                plot.series.color = color.withAlphaComponent(1)
                plot.series.areaAlphaComponent = 0.3
            } else {
                plot.series.color = color.withAlphaComponent(0.05)
                plot.series.areaAlphaComponent = 0.05
            }
        }
        redrawChart()
    }
}

extension UICollectionViewCell {
    // reset cell before reuse (after scroll)
    open override func prepareForReuse() {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        isSelected = false
    }
}

// Present the view controller in the Live View window
let vc = MyViewController()
vc.preferredContentSize = CGSize(width: 750, height: 750)
PlaygroundPage.current.liveView = vc
