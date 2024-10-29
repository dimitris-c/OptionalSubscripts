//
// github.com/screensailor 2021
//

#if canImport(Combine)

import Combine

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

public struct AsyncSequencePublisher<Sequence>: Publisher where Sequence: AsyncSequence {

    public typealias Output = Sequence.Element
    public typealias Failure = Never

    private var sequence: Sequence?

    actor Subscription<Subscriber: Combine.Subscriber>: Combine.Subscription where Subscriber.Input == Output, Subscriber.Failure == Failure {

        private var sequence: Sequence?
        private var subscriber: Subscriber?
        private var isCancelled = false

        private var demand: Subscribers.Demand = .none
        private var task: Task<(), Error>?

        init(subscriber: Subscriber, sequence: Sequence?) {
            self.sequence = sequence
            self.subscriber = subscriber
        }

        nonisolated func request(_ demand: Subscribers.Demand) {
            Task { await _request(demand) }
        }

        private func _request(_ more: Subscribers.Demand) async {
            demand += more
            guard demand > 0 else { return }
            if task == nil || task?.isCancelled == true {
                startTask()
            }
        }

        private func startTask() {
//            task?.cancel()
            task = Task {
                await self.processSequence()
            }
        }

        private func processSequence() async {
            guard var iterator = sequence?.makeAsyncIterator() else {
                finish()
                return
            }
            while !isCancelled, demand > 0 {
                do {
                    guard let element = try await iterator.next() else {
                        finish()
                        return
                    }
                    guard let subscriber = subscriber else { return }
                    demand -= 1
                    let additionalDemand = subscriber.receive(element)
                    demand += additionalDemand
                    await Task.yield()
                } catch {
                    finish()
                    return
                }
            }
        }

        nonisolated func cancel() {
            Task { await self._cancel() }
        }

        private func _cancel() {
            sequence = nil
            subscriber = nil
            isCancelled = true
        }

        private func finish() {
            sequence = nil
            subscriber?.receive(completion: .finished)
            subscriber = nil
            isCancelled = true
        }
    }
    
    public init(_ sequence: Sequence) {
        self.sequence = sequence
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, Output == S.Input {
        subscriber.receive(subscription: Subscription(subscriber: subscriber, sequence: sequence))
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
