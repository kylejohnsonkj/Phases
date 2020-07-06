import Foundation
import UIKit

// sanitize requested number of comments by keeping value in range
extension Comparable {
    public func clamped(_ low: Self, _ high: Self)  ->  Self {
        var num = self
        if num < low { num = low }
        if num > high { num = high }
        return num
    }
}

// avoid playground crash when setting layer.cornerRadius directly
extension UIView {
   public func roundCorners(corners: UIRectCorner, radius: CGFloat) {
        let path = UIBezierPath(roundedRect: bounds, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        layer.mask = mask
    }
}

// colored circle identifying subreddit series in each collection view cell
extension UIImage {
    public class func circle(diameter: CGFloat, color: UIColor) -> UIImage {
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
