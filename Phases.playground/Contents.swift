//: View your reddit comment history by phases of subreddit activity

import UIKit
import PlaygroundSupport

let username = "YOUR_REDDIT_USERNAME"
let period: Period /* .hour, .day, .week, .month, .year */ = .week
let maxComments /* min: 1, max: 1000 */ = 200

/* filters - increase to limit to more relevant subs */
let minCommentThreshold = 1
let minActiveDays = 1

class PhasesViewController: UIViewController {
    
    var comments = [Comment]()
    var plots = [Plot]()
    
    // view related
    var header: HeaderView!
    var loadingView: LoadingView!
    var selectedIndex: Int?
    
    // fetching
    let apiLimit = 100
    var remainingComments = 0
    var after: String?
    
    // graphing
    var chart: Chart!
    var axisLabels: [AxisLabel]!
    var legend: Legend!
    var cycleTimer: Timer!
    var maxDaysAgo = 0
    
    override func loadView() {
        let view = UIView()
        
        // create header (title, subtitle, buttons, icon)
        header = HeaderView(frame: CGRect(x: 0, y: 0, width: 750, height: 90))
        header.prevSubButton.addTarget(self, action: #selector(prevSub), for: .touchUpInside)
        header.nextSubButton.addTarget(self, action: #selector(nextSub), for: .touchUpInside)
        header.cycleButton.addTarget(self, action: #selector(cycleColors), for: .touchUpInside)
        view.addSubview(header)
        
        // add line chart for analysis
        chart = Chart(frame: CGRect(x: 30, y: 90, width: 720, height: 360))
        chart.minX = 0
        chart.minY = 0
        chart.hideHighlightLineOnTouchEnd = true
        chart.isHidden = true
        view.addSubview(chart)
        
        // add labels for each chart axis
        axisLabels = [AxisLabel(.x, period), AxisLabel(.y)]
        for label in axisLabels {
            label.isHidden = true
            view.addSubview(label)
        }
        
        // add legend for associated subreddits
        legend = Legend(frame: CGRect(x: 0, y: 465, width: 750, height: 285), padding: 10)
        legend.dataSource = self
        legend.delegate = self
        view.addSubview(legend)
        
        // create loading view to visualize progress
        loadingView = LoadingView(frame: CGRect(x: 300, y: 200, width: 150, height: 100))
        view.addSubview(loadingView)
        
        self.view = view
        
        fetchCommentsForUser(username, limit: maxComments) { comments in
            let groupedDataPoints = self.createGroupedDataPoints(for: comments, period)
            self.graphDataPoints(groupedDataPoints)
        }
    }
    
    func getCommentsUrl(username: String, limit: Int, after: String?) -> URL {
        var urlString = "https://www.reddit.com/user/\(username)/comments/.json?limit=\(limit)"
        if let after = after {  // subsequent calls
            urlString += "&after=\(after)"
        }
        return URL(string: urlString)!
    }
    
    func updateLoadingView(text: String, _ percentage: Int) {
        DispatchQueue.main.async {
            if !self.loadingView.indicator.isAnimating {
                self.loadingView.indicator.startAnimating()
            }
            self.loadingView.label.text = "\(text): \(percentage)%"
        }
    }
    
    func presentUserNotFoundAlert() {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "User Not Found", message: "Verify the entered username \(username) is correct and then reload the playground.", preferredStyle: .alert)
            self.present(alert, animated: true) {
                self.loadingView.removeFromSuperview()
            }
        }
    }
    
    // MARK: - STEP 1
    /// Fetch user comments from the reddit api, recursively called until complete
    func fetchCommentsForUser(_ username: String, limit maxComments: Int, completion: @escaping ([Comment]) -> ()) {
        let limit = maxComments.clamped(1, 1000)
        let fetchLimit = limit > apiLimit ? apiLimit : limit
        self.remainingComments = limit
        
        let url = getCommentsUrl(username: username, limit: fetchLimit, after: self.after)
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Error: \(error?.localizedDescription ?? "<nil>")")
                return
            }
            
            // decoding will fail if the username does not exist
            guard let parent = try? JSONDecoder().decode(JSONParent.self, from: data) else {
                self.presentUserNotFoundAlert()
                return
            }
            
            let comments = parent.data.children.map { $0.data }
            
            self.comments.append(contentsOf: comments)
            self.remainingComments -= fetchLimit
            self.after = parent.data.after
            
            let percentage = Int(((Double(fetchLimit) / Double(limit)) * 100) / 2.5)
            self.updateLoadingView(text: "Fetching", percentage)
            
            // nil if user has no more comments to fetch
            if self.after == nil {
                self.remainingComments = 0
            }
            
            if self.remainingComments == 0 {
                completion(self.comments)
            } else {
                self.fetchCommentsForUser(username, limit: self.remainingComments, completion: completion)
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
            
            // modify existing data point if available
            if let dataPoint = dataPoint {
                dataPoint.count += 1
            } else {
                dataPoints.append(newDataPoint)
            }
            
            // tracked so all series match in length when graphing
            if daysAgo > maxDaysAgo {
                maxDaysAgo = daysAgo
            }
            
            let percentage = 40 + Int(((Double(index) / Double(comments.count)) * 100) / 2.5)
            updateLoadingView(text: "Parsing", percentage)
        }
        
        let groupedDataPoints = Dictionary(grouping: dataPoints, by: { $0.subreddit })
        return groupedDataPoints
    }
    
    // MARK: - STEP 3
    /// Take a dictionary of graph points and plot each series on the chart
    func graphDataPoints(_ groupedDataPoints: [String : [DataPoint]]) {
        DispatchQueue.main.async {
            self.chart.isHidden = false
            self.axisLabels.forEach { $0.isHidden = false }
        }
        
        for (index, key) in groupedDataPoints.keys.enumerated() {
            let dataPoints = groupedDataPoints[key] ?? []
            var points = [Double]()
            var daysAgo = 0
            
            func addPoint(point: Double) {
                points.append(point)
                daysAgo += 1
            }
            
            /* begin filtering */
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
            /* end filtering */
            
            for dataPoint in dataPoints {
                // fill in points up to first data point
                while daysAgo < dataPoint.daysAgo {
                    addPoint(point: 0)
                }
                // add point (x: period ago, y: number of comments in sub for that period)
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
            
            let percentage = 80 + Int(((Double(index) / Double(groupedDataPoints.count)) * 100) / (20/3))
            updateLoadingView(text: "Graphing", percentage)
            
            // pair subreddit with series for legend
            plots.append(Plot(subreddit: key, series: series))
        }
        
        // sort subreddits to be in alphabetical order
        plots.sort(by: { $0.subreddit.lowercased() < $1.subreddit.lowercased() })
        
        // print data for easy viewing
        plots.forEach { print("\($0.subreddit): \(groupedDataPoints[$0.subreddit]!)") }
        
        prepareForInteraction()
    }
    
    func prepareForInteraction() {
        DispatchQueue.main.async {
            self.loadingView.label.text = "Finished: 100%"
            self.loadingView.indicator.stopAnimating()
            self.header.cycleButton.isEnabled = true
            self.legend.reloadData()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.legend.flashScrollIndicators()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.loadingView.removeFromSuperview()
        }
    }
    
    func selectPlot(at index: Int) {
        let selectedPlot = plots[index]
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
        
        header.prevSubButton.isEnabled = index != 0
        header.nextSubButton.isEnabled = index != plots.count - 1
        selectedIndex = index
    }
    
    func switchToSub(at index: Int) {
        legend.selectItem(at: IndexPath(row: index, section: 0), animated: true, scrollPosition: .left)
        selectPlot(at: index)
    }
    
    @objc func prevSub() {
        // do nothing if no sub is currently selected
        guard var index = selectedIndex else { return }
        index -= 1
        switchToSub(at: index)
    }
    
    @objc func nextSub() {
        guard var index = selectedIndex else { return }
        index += 1
        switchToSub(at: index)
    }
    
    // UIButton action to cycle colors
    // collection view is reloaded after delay for UI responsiveness
    @objc func cycleColors() {
        for plot in plots {
            plot.series.color = generateRandomColor()
            plot.series.areaAlphaComponent = 0.1
            
            // clear selected subreddit, if any
            if let index = selectedIndex {
                legend.deselectItem(at: IndexPath(row: index, section: 0), animated: true)
                clearSelection()
            }
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
    
    func clearSelection() {
        header.prevSubButton.isEnabled = false
        header.nextSubButton.isEnabled = false
        selectedIndex = nil
    }
    
    func generateRandomColor() -> UIColor {
        return UIColor(red: CGFloat(drand48()), green: CGFloat(drand48()), blue: CGFloat(drand48()), alpha: 1)
    }
}

// MARK: - Chart Legend
extension PhasesViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return plots.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! LegendCell
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
        let size = label.intrinsicContentSize  // size cell based off label width
        return CGSize(width: size.width + 25, height: size.height)
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        if let selectedIndexPath = collectionView.indexPathsForSelectedItems?.first,
            selectedIndexPath == indexPath {
            collectionView.deselectItem(at: indexPath, animated: true)
            clearSelection()
            
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
        selectPlot(at: indexPath.row)
    }
}

// Present the view controller in the Live View window
let vc = PhasesViewController()
vc.view.frame = CGRect(x: 0, y: 0, width: 750, height: 750)
PlaygroundPage.current.liveView = vc
