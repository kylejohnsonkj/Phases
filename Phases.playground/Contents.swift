//: View your reddit comment history by phases of subreddit activity
  
import UIKit
import PlaygroundSupport

class MyViewController: UIViewController {
    
    // fetching
    var comments = [Comment]()
    var remainingComments = 0
    let apiLimit = 100
    var after = ""
    
    var maxDaysAgo = 0
    
    override func loadView() {
        let view = UIView()
        
        // add a line chart for analysis
        let chart = Chart(frame: CGRect(x: 0, y: 90, width: 750, height: 375))
        chart.minX = 0
        chart.minY = 0
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
        
        self.view = view
        
        fetchCommentsForUser(username: "YOUR_REDDIT_USERNAME", limit: 200) { comments in
            let groupedDataPoints = self.createGroupedDataPoints(for: comments, period: .week)
            print(groupedDataPoints)  // helpful for debugging
            self.graphDataPoints(groupedDataPoints, chart)
        }
    }
    
    /// Take a dictionary of graph points and plot each series on the given chart
    func graphDataPoints(_ groupedDataPoints: [String : [DataPoint]], _ chart: Chart) {
        for key in groupedDataPoints.keys {
            let dataPoints = groupedDataPoints[key] ?? []
            var daysAgo = 0
            var points = [Double]()
            
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
        }
    }
    
    func generateRandomColor() -> UIColor {
        return UIColor(red: CGFloat(drand48()), green: CGFloat(drand48()), blue: CGFloat(drand48()), alpha: 1)
    }
    
    func getCommentsUrl(username: String, limit: Int, after: String) -> URL {
        if after.isEmpty {  // first call
            return URL(string: "https://www.reddit.com/user/\(username)/comments/.json?limit=\(limit)")!
        } else {
            return URL(string: "https://www.reddit.com/user/\(username)/comments/.json?limit=\(limit)&after=\(after)")!
        }
    }

    func fetchCommentsForUser(username: String, limit: Int, completion: @escaping ([Comment]) -> ()) {
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
                        self.fetchCommentsForUser(username: username, limit: self.remainingComments, completion: completion)
                    } else {
                        completion(self.comments)
                    }
                }
            }
        }.resume()
    }
    
    /// Creates data points grouped by given period (day, week, month) for each subreddit
    func createGroupedDataPoints(for comments: [Comment], period: Period) -> [String : [DataPoint]] {
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

// Present the view controller in the Live View window
let vc = MyViewController()
vc.preferredContentSize = CGSize(width: 750, height: 750)
PlaygroundPage.current.liveView = vc
