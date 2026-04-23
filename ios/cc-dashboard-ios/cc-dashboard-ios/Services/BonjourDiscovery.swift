import Foundation

@Observable
class BonjourDiscovery: NSObject {
    var discoveredServices: [BonjourService] = []
    var isScanning = false

    private var browser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []

    struct BonjourService: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let host: String
        let port: Int
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        discoveredServices = []

        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_cc-dashboard._tcp.", inDomain: "local.")
    }

    func stopScan() {
        browser?.stop()
        browser = nil
        isScanning = false
        resolvingServices.forEach { $0.stop() }
        resolvingServices = []
    }

    deinit {
        stopScan()
    }
}

extension BonjourDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        discoveredServices.removeAll { $0.name == service.name }
        if let index = resolvingServices.firstIndex(where: { $0.name == service.name }) {
            resolvingServices.remove(at: index)
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        isScanning = false
    }
}

extension BonjourDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses, let firstAddress = addresses.first else { return }

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        firstAddress.withUnsafeBytes { ptr in
            guard let sockaddrPtr = ptr.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return }
            _ = getnameinfo(sockaddrPtr, socklen_t(firstAddress.count), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
        }
        let host = String(cString: hostname)
        guard !host.isEmpty, host != "0.0.0.0" else { return }

        let service = BonjourService(name: sender.name, host: host, port: sender.port)
        if !discoveredServices.contains(where: { $0.name == service.name && $0.host == service.host }) {
            discoveredServices.append(service)
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        if let index = resolvingServices.firstIndex(where: { $0.name == sender.name }) {
            resolvingServices.remove(at: index)
        }
    }
}
