import Foundation

/// A thread-safe circular buffer implementation that maintains a maximum size
/// and automatically removes old elements when capacity is reached
final class BoundedArray<T>: @unchecked Sendable {
    
    // MARK: - Properties
    
    private var items: [T] = []
    private let maxSize: Int
    private let queue = DispatchQueue(label: "com.flexa.bounded-array", attributes: .concurrent)
    
    // MARK: - Computed Properties
    
    /// Current number of elements in the array
    var count: Int {
        return queue.sync { items.count }
    }
    
    /// Whether the array is empty
    var isEmpty: Bool {
        return queue.sync { items.isEmpty }
    }
    
    /// Whether the array has reached its maximum capacity
    var isFull: Bool {
        return queue.sync { items.count >= maxSize }
    }
    
    /// All elements in the array (thread-safe copy)
    var allElements: [T] {
        return queue.sync { Array(items) }
    }
    
    /// First element in the array
    var first: T? {
        return queue.sync { items.first }
    }
    
    /// Last element in the array
    var last: T? {
        return queue.sync { items.last }
    }
    
    // MARK: - Initialization
    
    /// Initialize with maximum size
    /// - Parameter maxSize: Maximum number of elements to store
    init(maxSize: Int) {
        precondition(maxSize > 0, "maxSize must be greater than 0")
        self.maxSize = maxSize
    }
    
    // MARK: - Public Methods
    
    /// Append an element to the array
    /// If the array is at capacity, removes the oldest element first
    /// - Parameter element: Element to append
    func append(_ element: T) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Remove oldest element if at capacity
            if self.items.count >= self.maxSize {
                self.items.removeFirst()
            }
            
            self.items.append(element)
        }
    }
    
    /// Append multiple elements to the array
    /// - Parameter elements: Elements to append
    func append(contentsOf elements: [T]) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            for element in elements {
                // Remove oldest element if at capacity
                if self.items.count >= self.maxSize {
                    self.items.removeFirst()
                }
                self.items.append(element)
            }
        }
    }
    
    /// Remove all elements from the array
    func removeAll() {
        queue.async(flags: .barrier) { [weak self] in
            self?.items.removeAll()
        }
    }
    
    /// Remove all elements and deallocate capacity for memory cleanup
    func removeAllAndDeallocate() {
        queue.async(flags: .barrier) { [weak self] in
            self?.items.removeAll(keepingCapacity: false)
        }
    }
    
    /// Get element at specific index (thread-safe)
    /// - Parameter index: Index of element to retrieve
    /// - Returns: Element at index, or nil if index is out of bounds
    func element(at index: Int) -> T? {
        return queue.sync {
            guard index >= 0 && index < items.count else { return nil }
            return items[index]
        }
    }
    
    /// Get the last N elements from the array
    /// - Parameter count: Number of elements to retrieve
    /// - Returns: Array of last N elements
    func suffix(_ count: Int) -> [T] {
        return queue.sync {
            return Array(items.suffix(count))
        }
    }
    
    /// Get the first N elements from the array
    /// - Parameter count: Number of elements to retrieve
    /// - Returns: Array of first N elements
    func prefix(_ count: Int) -> [T] {
        return queue.sync {
            return Array(items.prefix(count))
        }
    }
    
    /// Execute a closure with thread-safe access to all elements
    /// - Parameter closure: Closure to execute with array elements
    /// - Returns: Result of the closure
    func withElements<Result>(_ closure: ([T]) -> Result) -> Result {
        return queue.sync {
            return closure(items)
        }
    }
    
    /// Execute a closure with thread-safe mutable access to all elements
    /// - Parameter closure: Closure to execute with mutable array elements
    /// - Returns: Result of the closure
    func withMutableElements<Result>(_ closure: (inout [T]) -> Result) -> Result {
        return queue.sync(flags: .barrier) {
            return closure(&items)
        }
    }
    
    /// Map elements to a new array (thread-safe)
    /// - Parameter transform: Transform function
    /// - Returns: New array with transformed elements
    func map<U>(_ transform: (T) -> U) -> [U] {
        return queue.sync {
            return items.map(transform)
        }
    }
    
    /// Filter elements (thread-safe)
    /// - Parameter predicate: Filter predicate
    /// - Returns: Filtered array
    func filter(_ predicate: (T) -> Bool) -> [T] {
        return queue.sync {
            return items.filter(predicate)
        }
    }
    
    /// Compact map elements (thread-safe)
    /// - Parameter transform: Transform function
    /// - Returns: Compact mapped array
    func compactMap<U>(_ transform: (T) -> U?) -> [U] {
        return queue.sync {
            return items.compactMap(transform)
        }
    }
    
    /// Reduce elements to a single value (thread-safe)
    /// - Parameters:
    ///   - initialResult: Initial value
    ///   - nextPartialResult: Reduction function
    /// - Returns: Reduced value
    func reduce<Result>(_ initialResult: Result, _ nextPartialResult: (Result, T) -> Result) -> Result {
        return queue.sync {
            return items.reduce(initialResult, nextPartialResult)
        }
    }
}

// MARK: - Collection Conformance

extension BoundedArray: Collection {
    
    typealias Index = Int
    
    var startIndex: Int {
        return queue.sync { items.startIndex }
    }
    
    var endIndex: Int {
        return queue.sync { items.endIndex }
    }
    
    func index(after i: Int) -> Int {
        return i + 1
    }
    
    subscript(position: Int) -> T {
        return queue.sync { items[position] }
    }
}

// MARK: - Sequence Conformance

extension BoundedArray: Sequence {
    
    func makeIterator() -> Array<T>.Iterator {
        return queue.sync { items.makeIterator() }
    }
}

// MARK: - CustomStringConvertible

extension BoundedArray: CustomStringConvertible {
    
    var description: String {
        return queue.sync {
            return "BoundedArray(maxSize: \(maxSize), count: \(items.count), elements: \(items))"
        }
    }
}

// MARK: - CustomDebugStringConvertible

extension BoundedArray: CustomDebugStringConvertible {
    
    var debugDescription: String {
        return queue.sync {
            return "BoundedArray<\(T.self)>(maxSize: \(maxSize), count: \(items.count), isFull: \(items.count >= maxSize))"
        }
    }
}