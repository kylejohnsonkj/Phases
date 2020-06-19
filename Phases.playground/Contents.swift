//: View your reddit comment history by phases of subreddit activity
  
import UIKit
import PlaygroundSupport

// MARK: - JSONParent
struct JSONParent: Codable {
    let data: JSONData
}

// MARK: - JSONData
struct JSONData: Codable {
    let children: [JSONChild]
    let after: String
}

// MARK: - JSONChild
struct JSONChild: Codable {
    let data: Comment
}

// MARK: - Comment
struct Comment: Codable {
    let subreddit: String
    let createdUTC: Int
    
    enum CodingKeys: String, CodingKey {
        case subreddit
        case createdUTC = "created_utc"
    }
}

class DataPoint: Equatable, CustomStringConvertible {
    let daysAgo: Int
    let subreddit: String
    var count: Int
    
    init(daysAgo: Int, subreddit: String, count: Int) {
        self.daysAgo = daysAgo
        self.subreddit = subreddit
        self.count = count
    }
    
    static func == (lhs: DataPoint, rhs: DataPoint) -> Bool {
        return lhs.daysAgo == rhs.daysAgo && lhs.subreddit == rhs.subreddit
    }
    
    var description: String {
        return "(\(daysAgo), \(count))"
    }
}

enum Period: Int {
    case hour = 3600
    case day = 86400
    case week = 604800
    case month = 2629743
    case year = 31556926
}

//extension Date {
//    var today: Date {
//        return Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: self)!
//    }
//    var dayAfter: Date {
//        return Calendar.current.date(byAdding: .day, value: 1, to: today)!
//    }
//}

class MyViewController : UIViewController {
    
    func getCommentsUrl(username: String, limit: Int) -> URL {
        return URL(string: "https://www.reddit.com/user/\(username)/comments/.json?limit=\(limit)")!
    }
    
    func getCommentsForUser(username: String, limit: Int, completion: @escaping ([Comment]) -> ()) {
        let url = getCommentsUrl(username: username, limit: limit)
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                return
            }
            if let data = data {
                if let parent = try? JSONDecoder().decode(JSONParent.self, from: data) {
                    let comments = parent.data.children.map { $0.data }
                    completion(comments)
                }
            }
        }.resume()
    }
    
    var maxDaysAgo = 0

    override func loadView() {
        let view = UIView()
        
        let chart = Chart()
        chart.minX = 0
        chart.minY = 0
        chart.frame = CGRect(x: 0, y: 0, width: 750, height: 375)
        view.addSubview(chart)
        
        let colors: [Int: UIColor] = [
            0: UIColor.red,
            1: UIColor.orange,
            2: UIColor.yellow,
            3: UIColor.green,
            4: UIColor.blue,
            5: UIColor.purple,
            6: ChartColors.purpleColor(),
            7: ChartColors.maroonColor(),
            8: ChartColors.pinkColor(),
            9: ChartColors.greyColor(),
            10: ChartColors.cyanColor(),
            11: ChartColors.goldColor(),
            12: ChartColors.yellowColor(),
        ]
        
        self.view = view
        
        // TODO: after param to get more than 100
        getCommentsForUser(username: "YOUR_REDDIT_USERNAME", limit: 100) { comments in
            let groupedDataPoints = self.groupByPeriod(comments, period: .week)
            var index = 0

            for key in groupedDataPoints.keys {
                let dataPoints = groupedDataPoints[key] ?? []
                var daysAgo = 0
                var points = [Double]()
                for dataPoint in dataPoints {
                    while daysAgo < dataPoint.daysAgo {
                        points.append(0)
                        daysAgo += 1
                    }
                    points.append(Double(dataPoint.count))
                    daysAgo += 1
                }
                while daysAgo <= self.maxDaysAgo {
                    points.append(0)
                    daysAgo += 1
                }
                let series = ChartSeries(points)
                series.color = colors[index] ?? UIColor.black
                series.area = true
                chart.add(series)
                
                index += 1
            }
            print(groupedDataPoints)
        }
    }
    
    func groupByPeriod(_ comments: [Comment], period: Period) -> [String : [DataPoint]] {
        var dataPoints = [DataPoint]()
        
        let now = Int(Date().timeIntervalSince1970)
        var daysAgo = 0
        var offset = period.rawValue

        for comment in comments {
            let date = comment.createdUTC
            while date < now - offset {
                daysAgo += 1
                offset = period.rawValue + (daysAgo * period.rawValue)
            }
            
            let subreddit = comment.subreddit
            let newDataPoint = DataPoint(daysAgo: daysAgo, subreddit: subreddit, count: 1)
            let dataPoint = dataPoints.filter { $0 == newDataPoint }.first
            
            if let dataPoint = dataPoint {
                dataPoint.count += 1
            } else {
                dataPoints.append(newDataPoint)
            }
            
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
vc.preferredContentSize = CGSize(width: 750, height: 375)
PlaygroundPage.current.liveView = vc

// TODO: Future Plans
// list all fields as comparable filters
// show multiple users if added
