/// What Add a Web App (`AddWebAppFeature`) needs of its window; tests stand
/// in for it.
@MainActor
protocol AddWebAppPresenting: AnyObject {
    var isOpen: Bool { get }
    func show()
    func close()
}
