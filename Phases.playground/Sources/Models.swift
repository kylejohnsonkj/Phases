import Foundation

public enum Period: Int {
    case hour = 3600
    case day = 86400
    case week = 604800
    case month = 2629743
    case year = 31556926
}

public class DataPoint: Equatable, CustomStringConvertible {
    public let daysAgo: Int
    public let subreddit: String
    public var count: Int
    
    public init(daysAgo: Int, subreddit: String, count: Int) {
        self.daysAgo = daysAgo
        self.subreddit = subreddit
        self.count = count
    }
    
    public static func == (lhs: DataPoint, rhs: DataPoint) -> Bool {
        return lhs.daysAgo == rhs.daysAgo && lhs.subreddit == rhs.subreddit
    }
    
    public var description: String {
        return "(\(daysAgo), \(count))"
    }
}

public class Plot: Equatable {
    public let subreddit: String
    public let series: ChartSeries
    
    public init(subreddit: String, series: ChartSeries) {
        self.subreddit = subreddit
        self.series = series
    }
    
    public static func == (lhs: Plot, rhs: Plot) -> Bool {
        return lhs.subreddit == rhs.subreddit
    }
}
