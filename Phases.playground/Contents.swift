//: View your reddit comment history by phases of subreddit activity
  
import UIKit
import PlaygroundSupport

// TODO:
// loading indicator (percent = limit/apiLimit)
// filters pane?
// < > to go through subs
// < > to expand/limit history

class MyViewController: UIViewController {
    
    // fetching
    var comments = [Comment]()
    var plots = [Plot]()
    var remainingComments = 0
    let apiLimit = 100
    var after = ""
    
    var maxDaysAgo = 0
    
    var chart: Chart!
    var button: UIButton!
    var legend: UICollectionView!
    
    override func loadView() {
        let view = UIView()
        
        // add a line chart for analysis
        chart = Chart(frame: CGRect(x: 30, y: 90, width: 720, height: 360))
        chart.minX = 0
        chart.minY = 0
        chart.hideHighlightLineOnTouchEnd = true
        view.addSubview(chart)
        
        let title = UILabel(frame: CGRect(x: 20, y: 20, width: 200, height: 30))
        title.font = .systemFont(ofSize: 30, weight: .medium)
        title.text = "Reddit Phases"
        view.addSubview(title)
        
        let subtitle = UILabel(frame: CGRect(x: 20, y: 45, width: 750, height: 30))
        subtitle.font = .systemFont(ofSize: 15, weight: .light)
        subtitle.text = "Enter your reddit username to visualize your subreddit activity"
        view.addSubview(subtitle)
        
        let imageView = UIImageView(frame: CGRect(x: 675, y: 15, width: 60, height: 60))
        imageView.image = UIImage(named: "reddit-logo")
        view.addSubview(imageView)
        
        button = UIButton(frame: CGRect(x: 560, y: 32.5, width: 95, height: 25))
        button.setTitleColor(.black, for: .normal)
        button.setTitleColor(.gray, for: .disabled)
        button.setTitle("Cycle Colors", for: .normal)
        button.backgroundColor = UIColor(white: 0.9, alpha: 1)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        button.addTarget(self, action: #selector(cycleColors), for: .touchUpInside)
        button.isEnabled = false
        view.addSubview(button)
        
        var flowLayout: AlignedCollectionViewFlowLayout {
            let layout = AlignedCollectionViewFlowLayout()
            layout.horizontalAlignment = .left
            layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
            layout.minimumInteritemSpacing = 10
            layout.minimumLineSpacing = 10
            return layout
        }
        
        let padding = 10
        legend = UICollectionView(frame: CGRect(x: 0 + padding, y: 465 + padding, width: 750 - (padding * 2), height: 285 - (padding * 2)), collectionViewLayout: flowLayout)
        legend.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "Cell")
        legend.dataSource = self
        legend.delegate = self
        legend.backgroundColor = .white
        view.addSubview(legend)
        
        let username = "YOUR_REDDIT_USERNAME"
        let period = Period.week
        
        let xAxisLabel = UILabel()
        xAxisLabel.font = .systemFont(ofSize: 13)
        xAxisLabel.frame = CGRect(x: 275, y: 448, width: 200, height: 20)
        xAxisLabel.text = "# of \(period)s ago"
        xAxisLabel.textAlignment = .center
        view.addSubview(xAxisLabel)
        
        let yAxisLabel = UILabel()
        yAxisLabel.font = .systemFont(ofSize: 13)
        yAxisLabel.frame = CGRect(x: -85, y: 250, width: 200, height: 20)
        yAxisLabel.text = "# of comments"
        yAxisLabel.textAlignment = .center
        yAxisLabel.transform = CGAffineTransform(rotationAngle: (-90 * .pi) / 180)
        view.addSubview(yAxisLabel)
        
        self.view = view
        
        fetchCommentsForUser(username, limit: 200) { comments in
            let groupedDataPoints = self.createGroupedDataPoints(for: comments, period)
            self.graphDataPoints(groupedDataPoints, self.chart)
        }
    }
    
    /// Take a dictionary of graph points and plot each series on the given chart
    func graphDataPoints(_ groupedDataPoints: [String : [DataPoint]], _ chart: Chart) {
        for key in groupedDataPoints.keys {
            let dataPoints = groupedDataPoints[key] ?? []
            var daysAgo = 0
            var points = [Double]()
            
            /* BEGIN FILTERS */
            let minCommentThreshold = 1
            let exceedsCommentThreshold = dataPoints
                .filter { $0.count >= minCommentThreshold }
                .count > 0
            if !exceedsCommentThreshold {
                continue
            }
            
            let minActiveDays = 1
            let exceedsActiveDaysThreshold = dataPoints.count >= minActiveDays
            if !exceedsActiveDaysThreshold {
                continue
            }
            /* END FILTERS */
            
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
            
            // pair subreddit with series for legend
            plots.append(Plot(subreddit: key, series: series))
        }
        
        // sort subreddits to be in alphabetical order
        plots.sort(by: { $0.subreddit.lowercased() < $1.subreddit.lowercased() })
        
        // helpful for debugging
        plots.forEach { print("\($0.subreddit): \(groupedDataPoints[$0.subreddit]!)") }
        
        // enable cycle colors button, generate legend
        DispatchQueue.main.async {
            self.button.isEnabled = true
            self.legend.reloadData()
        }
        // show legend scroll indicators
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.legend.flashScrollIndicators()
        }
    }
    
    var cycleTimer: Timer!
    
    func redrawChart() {
        chart.removeAllSeries()
        let series = plots.map { $0.series }
        chart.add(series)
    }
    
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
    
    func generateRandomColor() -> UIColor {
        return UIColor(red: CGFloat(drand48()), green: CGFloat(drand48()), blue: CGFloat(drand48()), alpha: 1)
    }
    
    func getCommentsUrl(username: String, limit: Int, after: String) -> URL {
        var urlString = "https://www.reddit.com/user/\(username)/comments/.json?limit=\(limit)"
        if !after.isEmpty {  // subsequent calls
            urlString += "&after=\(after)"
        }
        return URL(string: urlString)!
    }

    func fetchCommentsForUser(_ username: String, limit: Int, completion: @escaping ([Comment]) -> ()) {
        self.remainingComments = limit
        let adjustedLimit = limit > apiLimit ? apiLimit : limit
        
        let url = getCommentsUrl(username: username, limit: adjustedLimit, after: self.after)
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                return
            }
            if let data = data {
                if let parent = try? JSONDecoder().decode(JSONParent.self, from: data) {
                    let comments = parent.data.children.map { $0.data }
                    
                    self.comments.append(contentsOf: comments)
                    self.remainingComments -= adjustedLimit
                    self.after = parent.data.after
                    
                    if self.remainingComments > 0 {
                        self.fetchCommentsForUser(username, limit: self.remainingComments, completion: completion)
                    } else {
                        completion(self.comments)
                    }
                }
            }
        }.resume()
    }
    
    /// Creates data points grouped by given period (day, week, month) for each subreddit
    func createGroupedDataPoints(for comments: [Comment], _ period: Period) -> [String : [DataPoint]] {
        var dataPoints = [DataPoint]()
        
        let now = Int(Date().timeIntervalSince1970)
        var daysAgo = 0
        var offset = period.rawValue

        for comment in comments {
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
        }
        
        let groupedDataPoints = Dictionary(grouping: dataPoints, by: { $0.subreddit })
        return groupedDataPoints
    }
}

// Legend
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

extension UIImage {
    class func circle(diameter: CGFloat, color: UIColor) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: diameter, height: diameter), false, 0)
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.saveGState()

        let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: rect)

        ctx.restoreGState()
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        return img
    }
}

// Present the view controller in the Live View window
let vc = MyViewController()
vc.preferredContentSize = CGSize(width: 750, height: 750)
PlaygroundPage.current.liveView = vc
