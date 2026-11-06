import XCTest
@testable import Pythilo

/// Hard-fails internet access while exercising the actual embedded interpreter.
/// Loopback and local IPC remain available for local web-server lessons.
@MainActor enum OfflineTestSupport {
    private static func execute(_ code: String) async throws -> String {
        let session = RunSession.shared
        let idleDeadline = Date().addingTimeInterval(30)
        if session.phase != .idle { session.stop() }
        while session.phase != .idle {
            guard Date() < idleDeadline else { throw ContentFailure.invalid("Python did not stop before offline audit cleanup") }
            try await Task.sleep(for: .milliseconds(20))
        }
        session.clearOutput()
        let root = FileManager.default.temporaryDirectory
        let path = root.appending(path: "offline-audit-\(UUID().uuidString).py")
        try code.write(to: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: path) }
        let id = try XCTUnwrap(session.submit(["kind": "script", "path": path.path, "root": root.path, "cwd": root.path], label: "offline audit"))
        let deadline = Date().addingTimeInterval(30)
        while session.lastOutcome?.id != id || session.phase != .idle {
            guard Date() < deadline else { throw ContentFailure.invalid("Offline audit timed out") }
            try await Task.sleep(for: .milliseconds(20))
        }
        let output = session.output.map(\.text).joined()
        guard session.lastOutcome?.code == 0 else {
            XCTFail(output)
            throw ContentFailure.invalid("Offline guard failed: \(output)")
        }
        return output
    }

    static func start(diagnoseSlowRun: Bool = false) async throws {
        let output = try await execute(#"""
        import builtins, socket, ipaddress
        assert not hasattr(builtins, '_pythilo_offline_audit')
        state = {'attempts': [], 'original': {name: getattr(socket, name) for name in ('getaddrinfo',)}}
        state['methods'] = {name: getattr(socket.socket, name) for name in ('connect', 'connect_ex', 'sendto')}
        builtins._pythilo_offline_audit = state
        def local(host):
            if host in (None, '', 'localhost'): return True
            try: return ipaddress.ip_address(host).is_loopback
            except ValueError: return False
        def deny(operation, address, _state=state):
            _state['attempts'].append((operation, str(address)))
            raise OSError('Offline audit blocked internet access: ' + operation)
        def resolve(host, *args, _original=socket.getaddrinfo, **kwargs):
            if not local(host): deny('DNS', host)
            return _original(host, *args, **kwargs)
        def connect(sock, address, _original=socket.socket.connect):
            if sock.family in (socket.AF_INET, socket.AF_INET6) and not local(address[0]): deny('connect', address)
            return _original(sock, address)
        def connect_ex(sock, address, _original=socket.socket.connect_ex):
            if sock.family in (socket.AF_INET, socket.AF_INET6) and not local(address[0]): deny('connect_ex', address)
            return _original(sock, address)
        def sendto(sock, *args, _original=socket.socket.sendto):
            if sock.family in (socket.AF_INET, socket.AF_INET6) and not local(args[-1][0]): deny('sendto', args[-1])
            return _original(sock, *args)
        socket.getaddrinfo = resolve
        socket.socket.connect, socket.socket.connect_ex, socket.socket.sendto = connect, connect_ex, sendto
        state['guards'] = {'connect': connect, 'connect_ex': connect_ex, 'sendto': sendto, 'getaddrinfo': resolve}
        try: socket.getaddrinfo('offline-audit.invalid', 443)
        except OSError: pass
        else: raise AssertionError('Internet guard is not active')
        assert len(state['attempts']) == 1
        state['attempts'].clear()
        print('OFFLINE_AUDIT_ACTIVE')
        """#)
        XCTAssertTrue(output.contains("OFFLINE_AUDIT_ACTIVE"), output)
        if diagnoseSlowRun {
            _ = try await execute("import builtins, faulthandler\ns = builtins._pythilo_offline_audit\ns['trace_file'] = open('offline-scale-stack.txt', 'w')\nfaulthandler.dump_traceback_later(10, file=s['trace_file'])\n")
        }
    }

    static func stop() async throws {
        let output = try await execute(#"""
        import builtins, socket
        state = getattr(builtins, '_pythilo_offline_audit', None)
        assert state is not None, 'Offline guard disappeared between jobs'
        if 'trace_file' in state:
            import faulthandler
            faulthandler.cancel_dump_traceback_later()
            state['trace_file'].close()
        attempts = list(state['attempts'])
        intact = socket.getaddrinfo is state['guards']['getaddrinfo'] and all(getattr(socket.socket, name) is state['guards'][name] for name in state['methods'])
        for name, original in state['original'].items(): setattr(socket, name, original)
        for name, original in state['methods'].items(): setattr(socket.socket, name, original)
        del builtins._pythilo_offline_audit
        assert intact, 'A program removed the offline network guard'
        assert not attempts, 'Unexpected internet requests: ' + repr(attempts)
        print('OFFLINE_AUDIT_PASSED: zero internet requests')
        """#)
        XCTAssertTrue(output.contains("OFFLINE_AUDIT_PASSED: zero internet requests"), output)
    }
}
