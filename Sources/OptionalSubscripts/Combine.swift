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
        private var subscriber: Subscriber
        private var isCancelled = false

        private var lock = NSRecursiveLock()
        private var demand: Subscribers.Demand = .none
        private var task: Task<Void, Error>?

        init(subscriber: Subscriber, sequence: S) {
            self.sequence = sequence
            self.subscriber = subscriber
        }
//
        func request(_ __demand: Subscribers.Demand) {
            precondition(__demand > 0)
            lock.withLock { demand = __demand }
            guard task == nil else { return }
            lock.lock(); defer { lock.unlock() }
            task = Task { [self] in
                var iterator = lock.withLock { self.sequence.makeAsyncIterator() }
                while lock.withLock({ !self.isCancelled && self.demand > 0 }) {
                    let element: S.Element?
                    do {
                        element = try await iterator.next()
                    } catch is CancellationError {
                        lock.withLock { self.subscriber }.receive(completion: .finished)
                        return
                    } catch let error as Failure {
                        lock.withLock { self.subscriber }.receive(completion: .failure(error))
                        throw CancellationError()
                    } catch {
//                        assertionFailure("Expected \(Failure.self) but got \(type(of: error))")
                        throw CancellationError()
                    }
                    guard let element else {
                        lock.withLock { self.subscriber }.receive(completion: .finished)
                        throw CancellationError()
                    }
                    try Task.checkCancellation()
                    lock.withLock { self.demand -= 1 }
                    let newDemand = lock.withLock { self.subscriber }.receive(element)
                    lock.withLock { self.demand += newDemand }
                    await Task.yield()
                }
                task = nil
            }
        }
//
        func cancel() {
            lock.withLock {
                task?.cancel()
                isCancelled = true
            }
        }
//
        deinit {
            lock.withLock {
                task?.cancel()
                isCancelled = true
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
