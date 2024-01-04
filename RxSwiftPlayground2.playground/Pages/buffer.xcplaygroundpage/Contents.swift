import RxCocoa
import RxSwift
import UIKit
import PlaygroundSupport

extension UIStackView {
    public class func makeVertical(_ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fill
        stack.axis = .vertical
        stack.spacing = 15
        return stack
    }

    public func insert(_ view: UIView, at index: Int) {
        insertArrangedSubview(view, at: index)
    }

    public func keep(atMost: Int) {
        while arrangedSubviews.count > atMost {
            let view = arrangedSubviews.last!
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

extension UILabel {
    public class func make(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    public class func makeTitle(_ title: String) -> UILabel {
        let label = make(title)
        label.font = UIFont.boldSystemFont(ofSize: UIFont.systemFontSize * 2.0)
        label.textAlignment = .center
        return label
    }
}

func setupHostView() -> UIView {
    let hostView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 400, height: 640)))
    hostView.backgroundColor = .white
    return hostView
}

public extension DispatchSource {
    class func timer(interval: Double, queue: DispatchQueue, handler: @escaping () -> Void) -> DispatchSourceTimer {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.setEventHandler(handler: handler)
        source.schedule(deadline: .now(), repeating: interval, leeway: .nanoseconds(0))
        source.resume()
        return source
    }
}

struct TimelineEvent  {
    enum EventType {
        case next(String)
        case completed(Bool)
        case error
    }
    let date: Date
    let event: EventType
    fileprivate var view: UIView? = nil

    public static func next(_ text: String) -> TimelineEvent {
        return TimelineEvent(.next(text))
    }
    public static func next(_ value: Int) -> TimelineEvent {
        return TimelineEvent(.next(String(value)))
    }
    public static func completed(_ keepRunning: Bool = false) -> TimelineEvent {
        return TimelineEvent(.completed(keepRunning))
    }
    public static func error() -> TimelineEvent {
        return TimelineEvent(.error)
    }

    var text: String {
        switch self.event {
        case .next(let s):
            return s
        case .completed(_):
            return "C"
        case .error:
            return "X"
        }
    }

    init(_ event: EventType) {
        // lose some precision to show nearly-simultaneous items at same position
        let ti = round(Date().timeIntervalSinceReferenceDate * 10) / 10
        date = Date(timeIntervalSinceReferenceDate: ti)
        self.event = event
    }
}

let BOX_WIDTH: CGFloat = 40

class TimelineViewBase : UIView {
    var timeSpan: Double = 10.0
    var events: [TimelineEvent] = []
    var displayLink: CADisplayLink?

    public convenience init(width: CGFloat, height: CGFloat) {
        self.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported here")
    }

    public func setup() {
        self.backgroundColor = .white
        self.widthAnchor.constraint(equalToConstant: CGFloat(frame.width)).isActive = true
        self.heightAnchor.constraint(equalToConstant: CGFloat(frame.height)).isActive = true
    }

    public func add(_ event: TimelineEvent) {
        let label = UILabel()
        label.isHidden = true
        label.textAlignment = .center
        label.text = event.text

        switch event.event {
        case .next(_):
            label.backgroundColor = .green

        case .completed(let keepRunning):
            label.backgroundColor = .black
            label.textColor = .white
            if !keepRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.detachDisplayLink() }
            }

        case .error:
            label.backgroundColor = .red
            label.textColor = .white
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.detachDisplayLink() }
        }

        label.layer.borderColor = UIColor.lightGray.cgColor
        label.layer.borderWidth = 1.0
        label.sizeToFit()

        var r = label.frame
        r.size.width = BOX_WIDTH
        label.frame = r

        var newEvent = event
        newEvent.view = label
        events.append(newEvent)
        addSubview(label)
    }

    func detachDisplayLink() {
        displayLink?.remove(from: RunLoop.main, forMode: .common)
        displayLink = nil
    }

    override open func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        self.backgroundColor = .white
        if newSuperview == nil {
            detachDisplayLink()
        } else {
            displayLink = CADisplayLink(target: self, selector: #selector(update(_:)))
            displayLink?.add(to: RunLoop.main, forMode: .common)
        }
    }

    override open func draw(_ rect: CGRect) {
        UIColor.lightGray.set()
        UIRectFrame(CGRect(x: 0, y: rect.height/2, width: rect.width, height: 1))
        super.draw(rect)
    }

    @objc func update(_ sender: CADisplayLink) {
        let now = Date()
        let start = now.addingTimeInterval(-11)
        let width = frame.width
        let increment = (width - BOX_WIDTH) / 10.0
        events
            .filter { $0.date < start }
            .forEach { $0.view?.removeFromSuperview() }
        var eventsAt = [Int:Int]()
        events = events.filter { $0.date >= start }
        events.forEach { box in
            if let view = box.view {
                var r = view.frame
                let interval = CGFloat(box.date.timeIntervalSince(now))
                let origin = Int(width - BOX_WIDTH + interval * increment)
                let count = (eventsAt[origin] ?? 0) + 1
                eventsAt[origin] = count
                r.origin.x = CGFloat(origin)
                r.origin.y = (frame.height - r.height) / 2 + CGFloat(12 * (count - 1))
                view.frame = r
                view.isHidden = false
                //print("[\(eventsAt[origin]!)]: \"\(box.text)\" x=\(origin) y=\(r.origin.y)")
            }
        }
    }
}

let bufferTimeSpan: RxTimeInterval = .seconds(4)
let bufferMaxCount = 2

let sourceObservable = PublishSubject<String>()

let sourceTimeline = TimelineView<String>.make()
let bufferedTimeline = TimelineView<Int>.make()

let stack = UIStackView.makeVertical([
  UILabel.makeTitle("buffer"),
  UILabel.make("Emitted elements:"),
  sourceTimeline,
  UILabel.make("Buffered elements (at most \(bufferMaxCount) every \(bufferTimeSpan) seconds):"),
  bufferedTimeline])

_ = sourceObservable.subscribe(sourceTimeline)

sourceObservable
  .buffer(timeSpan: bufferTimeSpan, count: bufferMaxCount, scheduler: MainScheduler.instance)
  .map(\.count)
  .subscribe(bufferedTimeline)

let hostView = setupHostView()
hostView.addSubview(stack)


let elementsPerSecond = 0.7
let timer = DispatchSource.timer(interval: 1.0 / Double(elementsPerSecond), queue: .main) {
  sourceObservable.onNext("🐱")
}

class MyViewController : UIViewController {
    override func loadView() {
        let view = UIView()
        view.backgroundColor = .white
        view.addSubview(hostView)
        self.view = view
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        print("foo")
        hostView.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }
}

PlaygroundPage.current.liveView = MyViewController()


// Support code -- DO NOT REMOVE
class TimelineView<E>: TimelineViewBase, ObserverType where E: CustomStringConvertible {
  static func make() -> TimelineView<E> {
    let view = TimelineView(frame: CGRect(x: 0, y: 0, width: 400, height: 100))
    view.setup()
    return view
  }
  public func on(_ event: Event<E>) {
    switch event {
    case .next(let value):
      add(.next(String(describing: value)))
    case .completed:
      add(.completed())
    case .error(_):
      add(.error())
    }
  }
}
