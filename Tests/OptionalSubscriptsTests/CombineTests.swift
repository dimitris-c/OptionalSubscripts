import XCTest
import Combine

// MARK: - AsyncSequencePublisherTests

final class AsyncSequencePublisherTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    // MARK: - Test Normal Sequence Emission

    func testNormalSequenceEmission() {
        // Given
        let expectation = XCTestExpectation(description: "Publisher emits all elements")
        let sequence = [1, 2, 3].async
        var receivedElements: [Int] = []

        // When
        sequence.publisher()
            .sink(receiveCompletion: { _ in
                expectation.fulfill()
            }, receiveValue: { value in
                receivedElements.append(value)
            })
            .store(in: &cancellables)

        // Then
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(receivedElements, [1, 2, 3])
    }

    // MARK: - Test Empty Sequence

    func testEmptySequence() {
        // Given
        let expectation = XCTestExpectation(description: "Publisher completes immediately")
        let sequence = [Int]().async
        var receivedElements: [Int] = []

        // When
        sequence.publisher()
            .sink(receiveCompletion: { completion in
                if case .finished = completion {
                    expectation.fulfill()
                }
            }, receiveValue: { value in
                receivedElements.append(value)
            })
            .store(in: &cancellables)

        // Then
        wait(for: [expectation], timeout: 1)
        XCTAssertTrue(receivedElements.isEmpty)
    }

    // MARK: - Test Cancellation

    func testCancellation() {
        // Given
        let expectation = XCTestExpectation(description: "Publisher stops emitting after cancellation")
        let sequence = [1, 2, 3].async
        var receivedElements: [Int] = []
        var subscription: AnyCancellable?

        // When
        subscription = sequence.publisher()
            .sink(receiveCompletion: { _ in }, receiveValue: { value in
                receivedElements.append(value)
                if value == 1 {
                    subscription?.cancel()
                }
            })

        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Verify that no additional elements were received after cancellation
            XCTAssertEqual(receivedElements, [1], "Should receive only the first element before cancellation")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Test Demand Management

    func testDemandManagement() {
        // Given
        let expectation = XCTestExpectation(description: "Publisher respects demand")
        let sequence = [1, 2, 3, 4, 5].async
        let receivedElements = ReceivedElements()

        // Custom subscriber to control demand
        final class TestSubscriber: Subscriber {
            typealias Input = Int
            typealias Failure = Never

            private let expectation: XCTestExpectation
            private let receivedElements: ReceivedElements

            var subscription: Subscription?

            init(expectation: XCTestExpectation, receivedElements: ReceivedElements) {
                self.expectation = expectation
                self.receivedElements = receivedElements
            }

            func receive(subscription: Subscription) {
                self.subscription = subscription
                subscription.request(.max(2)) // Request only 2 elements
            }

            func receive(_ input: Int) -> Subscribers.Demand {
                receivedElements.values.append(input)
                if receivedElements.values.count == 2 {
                    expectation.fulfill()
                    return .none // Stop receiving further elements
                }
                return .none
            }

            func receive(completion: Subscribers.Completion<Never>) {
                // Do nothing
            }
        }

        // When
        let subscriber = TestSubscriber(expectation: expectation, receivedElements: receivedElements)
        sequence.publisher().subscribe(subscriber)

        // Then
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(receivedElements.values, [1, 2], "Should receive only two elements as per demand")
    }

    // MARK: - Test Sequence Completion

    func testSequenceCompletion() {
        // Given
        let expectation = XCTestExpectation(description: "Publisher completes after emitting all elements")
        let sequence = [1, 2, 3].async
        var completionReceived = false

        // When
        sequence.publisher()
            .sink(receiveCompletion: { completion in
                if case .finished = completion {
                    completionReceived = true
                    expectation.fulfill()
                }
            }, receiveValue: { _ in })
            .store(in: &cancellables)

        // Then
        wait(for: [expectation], timeout: 1)
        XCTAssertTrue(completionReceived)
    }

    // MARK: - Test Multiple Subscribers

    func testMultipleSubscribers() {
        // Given
        let expectation1 = XCTestExpectation(description: "First subscriber receives all elements")
        let expectation2 = XCTestExpectation(description: "Second subscriber receives all elements")
        let sequence = [1, 2, 3].async
        var receivedElements1: [Int] = []
        var receivedElements2: [Int] = []

        // When
        sequence.publisher()
            .sink(receiveCompletion: { _ in
                expectation1.fulfill()
            }, receiveValue: { value in
                receivedElements1.append(value)
            })
            .store(in: &cancellables)

        sequence.publisher()
            .sink(receiveCompletion: { _ in
                expectation2.fulfill()
            }, receiveValue: { value in
                receivedElements2.append(value)
            })
            .store(in: &cancellables)

        // Then
        wait(for: [expectation1, expectation2], timeout: 1)
        XCTAssertEqual(receivedElements1, [1, 2, 3])
        XCTAssertEqual(receivedElements2, [1, 2, 3])
    }

    // MARK: - Test No Completion After Cancellation

    func testNoCompletionAfterCancellation() {
        // Given
        let expectation = XCTestExpectation(description: "Subscriber does not receive completion after cancellation")
        expectation.isInverted = true // We don't expect fulfillment
        let sequence = [1, 2, 3].async
        var completionReceived = false
        var subscription: AnyCancellable?

        // When
        subscription = sequence.publisher()
            .sink(receiveCompletion: { _ in
                completionReceived = true
                expectation.fulfill()
            }, receiveValue: { value in
                if value == 1 {
                    subscription?.cancel()
                }
            })

        // Then
        wait(for: [expectation], timeout: 1)
        XCTAssertFalse(completionReceived)
    }

    // MARK: - Test Slow Async Sequence

    func testSlowAsyncSequence() {
        // Given
        let expectation = XCTestExpectation(description: "Publisher handles slow async sequences")
        let sequence = SlowAsyncSequence(elements: [1, 2, 3], delay: 0.1)
        var receivedElements: [Int] = []

        // When
        sequence.publisher()
            .sink(receiveCompletion: { _ in
                expectation.fulfill()
            }, receiveValue: { value in
                receivedElements.append(value)
            })
            .store(in: &cancellables)

        // Then
        wait(for: [expectation], timeout: 1.5)
        XCTAssertEqual(receivedElements, [1, 2, 3])
    }

    // MARK: - Test Failing Async Sequence

    func testFailingAsyncSequence() {
        // Given
        let expectation = XCTestExpectation(description: "Publisher handles failing async sequence gracefully")
        let sequence = FailingAsyncSequence<Int>(failAtIndex: 2)
        var receivedElements: [Int] = []

        // When
        sequence.publisher()
            .sink(receiveCompletion: { _ in
                expectation.fulfill()
            }, receiveValue: { value in
                receivedElements.append(value)
            })
            .store(in: &cancellables)

        // Then
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(receivedElements, [0, 1])
    }

    // MARK: - Test Repeated Subscription

    func testRepeatedSubscription() {
        // Given
        let expectation = XCTestExpectation(description: "Publisher can be subscribed to multiple times")
        expectation.expectedFulfillmentCount = 2
        let sequence = [1, 2, 3].async
        var receivedElementsFirst: [Int] = []
        var receivedElementsSecond: [Int] = []

        let publisher = sequence.publisher()

        // When
        publisher
            .sink(receiveCompletion: { _ in
                expectation.fulfill()
            }, receiveValue: { value in
                receivedElementsFirst.append(value)
            })
            .store(in: &cancellables)

        publisher
            .sink(receiveCompletion: { _ in
                expectation.fulfill()
            }, receiveValue: { value in
                receivedElementsSecond.append(value)
            })
            .store(in: &cancellables)

        // Then
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(receivedElementsFirst, [1, 2, 3])
        XCTAssertEqual(receivedElementsSecond, [1, 2, 3])
    }
}

// MARK: - Helper Extensions and Structs

class ReceivedElements {
    var values: [Int] = []
}

extension Array {
    var async: AsyncArraySequence<Element> {
        AsyncArraySequence(self)
    }
}

struct AsyncArraySequence<Element>: AsyncSequence {
    typealias Element = Element
    typealias AsyncIterator = Iterator

    let elements: [Element]

    init(_ elements: [Element]) {
        self.elements = elements
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(elements)
    }

    struct Iterator: AsyncIteratorProtocol {
        var currentIndex = 0
        let elements: [Element]

        init(_ elements: [Element]) {
            self.elements = elements
        }

        mutating func next() async throws -> Element? {
            guard currentIndex < elements.count else {
                return nil
            }
            let element = elements[currentIndex]
            currentIndex += 1
            // Simulate async delay
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            return element
        }
    }
}

struct SlowAsyncSequence<Element>: AsyncSequence {
    typealias Element = Element
    typealias AsyncIterator = Iterator

    let elements: [Element]
    let delay: TimeInterval

    func makeAsyncIterator() -> Iterator {
        Iterator(elements: elements, delay: delay)
    }

    struct Iterator: AsyncIteratorProtocol {
        var currentIndex = 0
        let elements: [Element]
        let delay: TimeInterval

        mutating func next() async throws -> Element? {
            guard currentIndex < elements.count else {
                return nil
            }
            let element = elements[currentIndex]
            currentIndex += 1
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return element
        }
    }
}

struct FailingAsyncSequence<Element>: AsyncSequence {
    typealias Element = Element
    typealias AsyncIterator = Iterator

    let failAtIndex: Int

    func makeAsyncIterator() -> Iterator {
        Iterator(currentIndex: 0, failAtIndex: failAtIndex)
    }

    struct Iterator: AsyncIteratorProtocol {
        var currentIndex: Int
        let failAtIndex: Int

        mutating func next() async throws -> Element? {
            if currentIndex == failAtIndex {
                throw NSError(domain: "TestError", code: 1, userInfo: nil)
            }
            let element = currentIndex as! Element
            currentIndex += 1
            return element
        }
    }
}
