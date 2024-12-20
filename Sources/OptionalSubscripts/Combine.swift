//
// github.com/screensailor 2021
//

#if canImport(Combine)

import Combine
import Foundation

public extension Optional.Pond where Wrapped == Any {

    @inlinable func publisher(for route: Location..., bufferingPolicy: BufferingPolicy = .bufferingNewest(1)) -> AnyPublisher<Any?, Never> {
        stream(route, bufferingPolicy: bufferingPolicy).publisher().eraseToAnyPublisher()
    }

    @inlinable func publisher<Route>(for route: Route, bufferingPolicy: BufferingPolicy = .bufferingNewest(1)) -> AnyPublisher<Any?, Never> where Route: Collection, Route.Index == Int, Route.Element == Location {
        stream(route, bufferingPolicy: bufferingPolicy).publisher().eraseToAnyPublisher()
    }
}

public extension Optional.Store where Wrapped == Any {

    @inlinable func publisher(for route: Location..., bufferingPolicy: BufferingPolicy = .bufferingNewest(1)) -> AnyPublisher<Any?, Never> {
        stream(route, bufferingPolicy: bufferingPolicy).publisher().eraseToAnyPublisher()
    }

    @inlinable func publisher<Route>(for route: Route, bufferingPolicy: BufferingPolicy = .bufferingNewest(1)) -> AnyPublisher<Any?, Never> where Route: Collection, Route.Index == Int, Route.Element == Location {
        stream(route, bufferingPolicy: bufferingPolicy).publisher().eraseToAnyPublisher()
    }
}

public extension Dictionary.Store {

    @inlinable func publisher(for key: Key, bufferingPolicy: BufferingPolicy = .bufferingNewest(1)) -> AnyPublisher<Value?, Never> {
        stream(key, bufferingPolicy: bufferingPolicy).publisher().eraseToAnyPublisher()
    }
}

public extension AsyncSequence {

    func publisher() -> AsyncSequencePublisher<Self> {
        .init(self)
    }
}

public struct AsyncSequencePublisher<S: AsyncSequence>: Combine.Publisher {

    public typealias Output = S.Element
    public typealias Failure = Never

    private var sequence: S

    public init(_ sequence: S) {
        self.sequence = sequence
    }

    public func receive<Subscriber>(
        subscriber: Subscriber
    ) where Subscriber: Combine.Subscriber, Failure == Subscriber.Failure, Output == Subscriber.Input {
        subscriber.receive(
            subscription: Subscription(subscriber: subscriber, sequence: sequence)
        )
    }

    final class Subscription<
        Subscriber: Combine.Subscriber
    >: Combine.Subscription where Subscriber.Input == Output, Subscriber.Failure == Failure {

        private var sequence: S
        private var subscriber: Subscriber?
        private var isCancelled = false

        private var lock = NSRecursiveLock()
        private var demand: Subscribers.Demand = .none
        private var task: Task<Void, Error>?

        init(subscriber: Subscriber, sequence: S) {
            self.sequence = sequence
            self.subscriber = subscriber
        }

        func request(_ __demand: Subscribers.Demand) {
            precondition(__demand > 0)
            lock.withLock { demand = __demand }
            guard task == nil else { return }
            lock.lock(); defer { lock.unlock() }
            task = Task { [weak self] in
                guard let self = self else { return }
                var iterator = self.lock.withLock { self.sequence.makeAsyncIterator() }
                while self.lock.withLock({ !self.isCancelled && self.demand > 0 }) {
                    do {
                        let element = try await iterator.next()
                        guard let element = element else {
                            self.finishAndCleanUp()
                            return
                        }

                        try Task.checkCancellation()

                        self.lock.withLock { self.demand -= 1 }
                        let newDemand = self.lock.withLock {
                            self.subscriber?.receive(element) ?? .none
                        }

                        self.lock.withLock {
                            self.demand += newDemand
                        }

                        await Task.yield()

                    } catch is CancellationError {
                        self.finishAndCleanUp()
                        return
                    } catch {
                        // Since Failure == Never, we didn't expect an error here.
                        // Just finish and clean up, as we can't send a failure.
                        Swift.print("Unexpected error encountered: \(error)")
                        self.finishAndCleanUp()
                        return
                    }
                }
                self.lock.withLock {
                    self.task = nil
                }
            }
        }

        func cancel() {
            lock.withLock {
                performCleanup()
            }
        }

        deinit {
            lock.withLock {
                performCleanup()
            }
        }

        private func performCleanup() {
            if !isCancelled {
                task?.cancel()
                isCancelled = true
            }
            subscriber = nil
            task = nil
        }

        private func finishAndCleanUp() {
            lock.withLock {
                subscriber?.receive(completion: .finished)
                subscriber = nil
                task = nil
            }
        }
    }
}


public extension Publisher {

    @inlinable func filter<A>(_: A.Type = A.self) -> Publishers.CompactMap<Self, A> {
        compactMap{ $0 as? A }
    }

    @inlinable func cast<A>(to: A.Type = A.self) -> Publishers.TryMap<Self, A> {
        tryMap { o in
            guard let a = o as? A else {
                throw CastingError(value: self, to: A.self)
            }
            return a
        }
    }
}
#endif
