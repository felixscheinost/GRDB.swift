//
//  ValueObservation.swift
//  GRDB
//
//  Created by Gwendal Roué on 23/10/2018.
//  Copyright © 2018 Gwendal Roué. All rights reserved.
//

import Dispatch

// MARK: - ValueScheduling

/// ValueScheduling controls how ValueObservation schedules the notifications
/// of fresh values to your application.
///
/// See ValueObservation.
public enum ValueScheduling {
    /// All values are notified on the main queue.
    ///
    /// If the observation starts on the main queue, initial values are
    /// notified right upon subscription, synchronously:
    ///
    ///     // On main queue
    ///     let observation = ValueObservation.trackingAll(Player.all())
    ///     let observer = try dbQueue.start(observation) { players: [Player] in
    ///         print("fresh players: /(players)")
    ///     }
    ///     // <- here "fresh players" is already printed.
    ///
    /// If the observation does not start on the main queue, initial values
    /// are asynchronously notified on the main queue:
    ///
    ///     // Not on the main queue: "fresh players" is eventually printed
    ///     // on the main queue.
    ///     let observation = ValueObservation.trackingAll(Player.all())
    ///     let observer = try dbQueue.start(observation) { players: [Player] in
    ///         print("fresh players: /(players)")
    ///     }
    ///
    /// When the database changes, fresh values are asynchronously notified:
    ///
    ///     // Eventually prints "fresh players" on the main queue
    ///     try dbQueue.write { db in
    ///         try Player(...).insert(db)
    ///     }
    case mainQueue
    
    /// All values are asychronously notified on the specified queue.
    /// Initial values are only fetched and notified if `startImmediately`
    /// is true.
    case onQueue(DispatchQueue, startImmediately: Bool)
}

extension DispatchQueue {
    private static var mainKey: DispatchSpecificKey<()> = {
        let key = DispatchSpecificKey<()>()
        DispatchQueue.main.setSpecific(key: key, value: ())
        return key
    }()
    
    static var isMain: Bool {
        return DispatchQueue.getSpecific(key: mainKey) != nil
    }
}

// MARK: - ValueReducer

/// TODO: doc
public protocol ValueReducer {
    associatedtype Fetched
    associatedtype Value
    func fetch(_ db: Database) throws -> Fetched
    mutating func value(_ fetched: Fetched) -> Value?
}

/// TODO: doc
public struct AnyValueReducer<Fetched, Value>: ValueReducer {
    var _fetch: (Database) throws -> Fetched
    var _value: (Fetched) -> Value?
    
    /// TODO: doc
    public init(fetch: @escaping (Database) throws -> Fetched, value: @escaping (Fetched) -> Value?) {
        self._fetch = fetch
        self._value = value
    }
    
    public init<Reducer: ValueReducer>(_ reducer: Reducer) where Reducer.Fetched == Fetched, Reducer.Value == Value {
        var reducer = reducer
        self._fetch = { try reducer.fetch($0) }
        self._value = { reducer.value($0) }
    }
    
    /// :nodoc:
    public func fetch(_ db: Database) throws -> Fetched {
        return try _fetch(db)
    }
    
    /// :nodoc:
   public func value(_ fetched: Fetched) -> Value? {
        return _value(fetched)
    }
}

public enum ValueReducers {
    /// TODO
    public struct Raw<Value>: ValueReducer {
        let _fetch: (Database) throws -> Value
        
        /// TODO
        public init(_ fetch: @escaping (Database) throws -> Value) {
            self._fetch = fetch
        }
        
        /// :nodoc:
        public func fetch(_ db: Database) throws -> Value {
            return try _fetch(db)
        }
        
        /// :nodoc:
        public func value(_ fetched: Value) -> Value? {
            return fetched
        }
    }
    
    public struct Unique<Value: Equatable>: ValueReducer {
        let _fetch: (Database) throws -> Value
        var value: Value??
        
        /// TODO
        public init(_ fetch: @escaping (Database) throws -> Value) {
            self._fetch = fetch
        }
        
        /// :nodoc:
        public func fetch(_ db: Database) throws -> Value {
            return try _fetch(db)
        }
        
        /// :nodoc:
        public mutating func value(_ newValue: Value) -> Value? {
            if let value = value, value == newValue {
                return nil
            }
            self.value = newValue
            return newValue
        }
    }
    
    public struct UniqueRecords<Record: FetchableRecord>: ValueReducer {
        let _fetch: (Database) throws -> [Row]
        var rows: [Row]?
        
        /// TODO
        public init(_ fetch: @escaping (Database) throws -> [Row]) {
            self._fetch = fetch
        }
        
        /// :nodoc:
        public func fetch(_ db: Database) throws -> [Row] {
            return try _fetch(db)
        }
        
        /// :nodoc:
        public mutating func value(_ newRows: [Row]) -> [Record]? {
            if let rows = rows, rows == newRows {
                return nil
            }
            self.rows = newRows
            return newRows.map(Record.init(row:))
        }
    }
    
    public struct UniqueRecord<Record: FetchableRecord>: ValueReducer {
        let _fetch: (Database) throws -> Row?
        var row: Row??
        
        /// TODO
        public init(_ fetch: @escaping (Database) throws -> Row?) {
            self._fetch = fetch
        }
        
        /// :nodoc:
        public func fetch(_ db: Database) throws -> Row? {
            return try _fetch(db)
        }
        
        /// :nodoc:
        public mutating func value(_ newRow: Row?) -> Record?? {
            if let row = row, row == newRow {
                return nil
            }
            self.row = newRow
            return .some(newRow.map(Record.init(row:)))
        }
    }
    
    public struct UniqueValues<T: DatabaseValueConvertible>: ValueReducer {
        let _fetch: (Database) throws -> [DatabaseValue]
        var dbValues: [DatabaseValue]?
        
        /// TODO
        public init(_ fetch: @escaping (Database) throws -> [DatabaseValue]) {
            self._fetch = fetch
        }
        
        /// :nodoc:
        public func fetch(_ db: Database) throws -> [DatabaseValue] {
            return try _fetch(db)
        }
        
        /// :nodoc:
        public mutating func value(_ newDbValues: [DatabaseValue]) -> [T]? {
            if let dbValues = dbValues, dbValues == newDbValues {
                return nil
            }
            self.dbValues = newDbValues
            return newDbValues.map { T.decode(from: $0, conversionContext: nil) }
        }
    }
    
    public struct UniqueValue<T: DatabaseValueConvertible>: ValueReducer {
        let _fetch: (Database) throws -> DatabaseValue?
        var dbValue: DatabaseValue??
        
        /// TODO
        public init(_ fetch: @escaping (Database) throws -> DatabaseValue?) {
            self._fetch = fetch
        }
        
        /// :nodoc:
        public func fetch(_ db: Database) throws -> DatabaseValue? {
            return try _fetch(db)
        }
        
        /// :nodoc:
        public mutating func value(_ newDbValue: DatabaseValue?) -> T?? {
            if let dbValue = dbValue, dbValue == newDbValue {
                return nil
            }
            self.dbValue = newDbValue
            return .some(newDbValue.map { T.decode(from: $0, conversionContext: nil) })
        }
    }
    
    public struct UniqueOptionalValues<T: DatabaseValueConvertible>: ValueReducer {
        let _fetch: (Database) throws -> [DatabaseValue]
        var dbValues: [DatabaseValue]?
        
        /// TODO
        public init(_ fetch: @escaping (Database) throws -> [DatabaseValue]) {
            self._fetch = fetch
        }
        
        /// :nodoc:
        public func fetch(_ db: Database) throws -> [DatabaseValue] {
            return try _fetch(db)
        }
        
        /// :nodoc:
        public mutating func value(_ newDbValues: [DatabaseValue]) -> [T?]? {
            if let dbValues = dbValues, dbValues == newDbValues {
                return nil
            }
            self.dbValues = newDbValues
            return newDbValues.map { T.decodeIfPresent(from: $0, conversionContext: nil) }
        }
    }
}

// MARK: - ValueObservation

/// TODO: doc
/// TODO: refresh region after each fetch
public struct ValueObservation<Reducer> {
    /// A closure that is evaluated when the observation starts, and returns
    /// the observed database region.
    var observedRegion: (Database) throws -> DatabaseRegion
    
    /// A closure that fetches a value from the database. It is called upon
    /// each database change, and also when the observatioin starts, depending
    /// on the *initialDispatch* property.
    ///
    /// When this closure needs to write in the database, set the *isReadOnly*
    /// flag to false.
    var reducer: Reducer
    
    /// Default is true. Set this property to false when the *fetch* closure
    /// requires write access, and should be executed inside a savepoint.
    public var isReadOnly: Bool = true
    
    /// The extent of the database observation. The default is
    /// `.observerLifetime`: once started, the observation lasts until the
    /// observer is deallocated.
    public var extent = Database.TransactionObservationExtent.observerLifetime
    
    /// `scheduling` controls how fresh values are notified.
    /// Default is `.mainQueue`:
    ///
    /// - `.mainQueue`: all values are notified on the main queue.
    ///
    ///     If the observation starts on the main queue, initial values are
    ///     notified right upon subscription, synchronously:
    ///
    ///         // On main queue
    ///         let observation = ValueObservation.trackingAll(Player.all())
    ///         let observer = try dbQueue.start(observation) { players: [Player] in
    ///             print("fresh players: /(players)")
    ///         }
    ///         // <- here "fresh players" is already printed.
    ///
    ///     If the observation does not start on the main queue, initial values
    ///     are asynchronously notified on the main queue:
    ///
    ///         // Not on the main queue: "fresh players" is eventually printed
    ///         // on the main queue.
    ///         let observation = ValueObservation.trackingAll(Player.all())
    ///         let observer = try dbQueue.start(observation) { players: [Player] in
    ///             print("fresh players: /(players)")
    ///         }
    ///
    ///     When the database changes, fresh values are asynchronously notified:
    ///
    ///         // Eventually prints "fresh players" on the main queue
    ///         try dbQueue.write { db in
    ///             try Player(...).insert(db)
    ///         }
    ///
    /// - `.onQueue(_:startImmediately:)`: all values are asychronously notified
    /// on the specified queue. Initial values are only fetched and notified if
    /// `startImmediately` is true.
    public var scheduling: ValueScheduling = .mainQueue
    
    /// The dispatch queue where change callbacks are called.
    public var notificationQueue: DispatchQueue {
        switch scheduling {
        case .mainQueue:
            return DispatchQueue.main
        case .onQueue(let queue, startImmediately: _):
            return queue
        }
    }
    
    // This initializer is not public. See ValueObservation.tracking(_:reducer:)
    init(
        tracking region: @escaping (Database) throws -> DatabaseRegion,
        reducer: Reducer)
    {
        self.observedRegion = region
        self.reducer = reducer
    }
    
    /// Returs a ValueObservation which observes *regions*, and notifies the
    /// values returned by the *reducer* whenever the observed region is
    /// impacted by a database transaction.
    ///
    /// This method is the most fundamental way to create a ValueObservation.
    ///
    /// For example:
    ///
    ///     let reducer = AnyValueReducer(
    ///         fetch: { db in try Player.fetchAll(db) },
    ///         value: { player in players })
    ///     let observation = ValueObservation(
    ///         tracking: Player.all(),
    ///         reducer: reducer)
    ///
    ///     let observer = try dbQueue.start(observation) { player: [Player] in
    ///         print("players have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter region: a closure that returns the observed region.
    /// - parameter fetch: a closure that fetches a value.
    public static func tracking(
        _ regions: DatabaseRegionConvertible...,
        reducer: Reducer)
        -> ValueObservation
    {
        return ValueObservation(tracking: union(regions), reducer: reducer)
    }
}

extension ValueObservation where Reducer == Void {
    /// Creates a ValueObservation which observes *regions*, and notifies the
    /// values returned by the *fetch* closure whenever one of the observed
    /// regions is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let observation = ValueObservation.tracking(
    ///         Player.all(),
    ///         fetch: { db in return try Player.fetchAll(db) })
    ///
    ///     let observer = try dbQueue.start(observation) { player: [Player] in
    ///         print("players have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter regions: one or more observed requests.
    /// - parameter fetch: a closure that fetches a value.
    public static func tracking<Value>(
        _ regions: DatabaseRegionConvertible...,
        fetch: @escaping (Database) throws -> Value)
        -> ValueObservation<ValueReducers.Raw<Value>>
    {
        return ValueObservation<ValueReducers.Raw<Value>>(
            tracking: union(regions),
            reducer: ValueReducers.Raw(fetch))
    }
    
    /// Creates a ValueObservation which observes *regions*, and notifies the
    /// values returned by the *fetch* closure whenever one of the observed
    /// regions is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let observation = ValueObservation.tracking(
    ///         withUniquing: Player.all(),
    ///         fetch: { db in return try Player.fetchAll(db) })
    ///
    ///     let observer = try dbQueue.start(observation) { player: [Player] in
    ///         print("players have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter regions: one or more observed requests.
    /// - parameter fetch: a closure that fetches a value.
    public static func tracking<Value>(
        withUniquing regions: DatabaseRegionConvertible...,
        fetch: @escaping (Database) throws -> Value)
        -> ValueObservation<ValueReducers.Unique<Value>>
        where Value: Equatable
    {
        return ValueObservation<ValueReducers.Unique<Value>>(
            tracking: union(regions),
            reducer: ValueReducers.Unique(fetch))
    }
}

private func union(_ regions: [DatabaseRegionConvertible]) -> (Database) throws -> DatabaseRegion {
    return { db in
        try regions.reduce(into: DatabaseRegion()) { union, region in
            try union.formUnion(region.databaseRegion(db))
        }
    }
}


// MARK: - Count Observation

extension ValueObservation where Reducer == Void {
    /// Creates a ValueObservation which observes *request*, and notifies a
    /// fresh count whenever the request is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.all()
    ///     let observation = ValueObservation.trackingCount(request)
    ///
    ///     let observer = try dbQueue.start(observation) { count: Int in
    ///         print("number of players has changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingCount<Request: FetchRequest>(_ request: Request)
        -> ValueObservation<ValueReducers.Raw<Int>>
    {
        return ValueObservation<ValueReducers.Raw<Int>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Raw(request.fetchCount))
    }
    
    /// Creates a ValueObservation which observes *request*, and notifies a
    /// fresh count whenever the request is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.all()
    ///     let observation = ValueObservation.trackingCount(withUniquing: request)
    ///
    ///     let observer = try dbQueue.start(observation) { count: Int in
    ///         print("number of players has changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingCount<Request: FetchRequest>(withUniquing request: Request)
        -> ValueObservation<ValueReducers.Unique<Int>>
    {
        return ValueObservation<ValueReducers.Unique<Int>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Unique(request.fetchCount))
    }
}

// MARK: - Row Observation

extension ValueObservation where Reducer == Void {
    /// Creates a ValueObservation which observes *request*, and notifies
    /// fresh rows whenever the request is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let request = SQLRequest<Row>("SELECT * FROM player")
    ///     let observation = ValueObservation.trackingAll(request)
    ///
    ///     let observer = try dbQueue.start(observation) { rows: [Row] in
    ///         print("players have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingAll<Request: FetchRequest>(_ request: Request)
        -> ValueObservation<ValueReducers.Raw<[Row]>>
        where Request.RowDecoder == Row
    {
        return ValueObservation<ValueReducers.Raw<[Row]>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Raw(request.fetchAll))
    }

    /// Creates a ValueObservation which observes *request*, and notifies
    /// fresh rows whenever the request is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let request = SQLRequest<Row>("SELECT * FROM player")
    ///     let observation = ValueObservation.trackingAll(withUniquing: request)
    ///
    ///     let observer = try dbQueue.start(observation) { rows: [Row] in
    ///         print("players have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingAll<Request: FetchRequest>(withUniquing request: Request)
        -> ValueObservation<ValueReducers.Unique<[Row]>>
        where Request.RowDecoder == Row
    {
        return ValueObservation<ValueReducers.Unique<[Row]>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Unique(request.fetchAll))
    }
    
    /// Creates a ValueObservation which observes *request*, and notifies a
    /// fresh row whenever the request is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let request = SQLRequest<Row>("SELECT * FROM player WHERE id = ?", arguments: [1])
    ///     let observation = ValueObservation.trackingOne(request)
    ///
    ///     let observer = try dbQueue.start(observation) { row: Row? in
    ///         print("players have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a new ValueObservation<Int>.
    public static func trackingOne<Request: FetchRequest>(_ request: Request)
        -> ValueObservation<ValueReducers.Raw<Row?>>
        where Request.RowDecoder == Row
    {
        return ValueObservation<ValueReducers.Raw<Row?>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Raw(request.fetchOne))
    }

    /// Creates a ValueObservation which observes *request*, and notifies a
    /// fresh row whenever the request is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let request = SQLRequest<Row>("SELECT * FROM player WHERE id = ?", arguments: [1])
    ///     let observation = ValueObservation.trackingOne(withUniquing: request)
    ///
    ///     let observer = try dbQueue.start(observation) { row: Row? in
    ///         print("players have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a new ValueObservation<Int>.
    public static func trackingOne<Request: FetchRequest>(withUniquing request: Request)
        -> ValueObservation<ValueReducers.Unique<Row?>>
        where Request.RowDecoder == Row
    {
        return ValueObservation<ValueReducers.Unique<Row?>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Unique(request.fetchOne))
    }
}

// MARK: - FetchableRecord Observation

extension ValueObservation where Reducer == Void {
    /// Creates a ValueObservation which observes *request*, and notifies
    /// fresh records whenever the request is impacted by a
    /// database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.all()
    ///     let observation = ValueObservation.trackingAll(request)
    ///
    ///     let observer = try dbQueue.start(observation) { players: [Player] in
    ///         print("players have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingAll<Request: FetchRequest>(_ request: Request)
        -> ValueObservation<ValueReducers.Raw<[Request.RowDecoder]>>
        where Request.RowDecoder: FetchableRecord
    {
        return ValueObservation<ValueReducers.Raw<[Request.RowDecoder]>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Raw(request.fetchAll))
    }
    
    /// Creates a ValueObservation which observes *request*, and notifies
    /// fresh records whenever the request is impacted by a
    /// database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.all()
    ///     let observation = ValueObservation.trackingAll(withUniquing: request)
    ///
    ///     let observer = try dbQueue.start(observation) { players: [Player] in
    ///         print("players have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingAll<Request: FetchRequest>(withUniquing request: Request)
        -> ValueObservation<ValueReducers.UniqueRecords<Request.RowDecoder>>
        where Request.RowDecoder: FetchableRecord
    {
        return ValueObservation<ValueReducers.UniqueRecords<Request.RowDecoder>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.UniqueRecords { try Row.fetchAll($0, request) })
    }
    
    /// Creates a ValueObservation which observes *request*, and notifies a
    /// fresh record whenever the request is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.filter(key: 1)
    ///     let observation = ValueObservation.trackingOne(request)
    ///
    ///     let observer = try dbQueue.start(observation) { player: Player? in
    ///         print("player has changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingOne<Request: FetchRequest>(_ request: Request) ->
        ValueObservation<ValueReducers.Raw<Request.RowDecoder?>>
        where Request.RowDecoder: FetchableRecord
    {
        return ValueObservation<ValueReducers.Raw<Request.RowDecoder?>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Raw(request.fetchOne))
    }
    
    /// Creates a ValueObservation which observes *request*, and notifies a
    /// fresh record whenever the request is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.filter(key: 1)
    ///     let observation = ValueObservation.trackingOne(withUniquing: request)
    ///
    ///     let observer = try dbQueue.start(observation) { player: Player? in
    ///         print("player has changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingOne<Request: FetchRequest>(withUniquing request: Request) ->
        ValueObservation<ValueReducers.UniqueRecord<Request.RowDecoder>>
        where Request.RowDecoder: FetchableRecord
    {
        return ValueObservation<ValueReducers.UniqueRecord<Request.RowDecoder>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.UniqueRecord { try Row.fetchOne($0, request) })
    }
}

// MARK: - DatabaseValueConvertible Observation

extension ValueObservation where Reducer == Void {
    /// Creates a ValueObservation which observes *request*, and notifies
    /// fresh values whenever the request is impacted by a
    /// database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.select(Column("name"), as: String.self)
    ///     let observation = ValueObservation.trackingAll(request)
    ///
    ///     let observer = try dbQueue.start(observation) { names: [String] in
    ///         print("player name have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingAll<Request: FetchRequest>(_ request: Request)
        -> ValueObservation<ValueReducers.Raw<[Request.RowDecoder]>>
        where Request.RowDecoder: DatabaseValueConvertible
    {
        return ValueObservation<ValueReducers.Raw<[Request.RowDecoder]>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Raw(request.fetchAll))
    }
    
    /// Creates a ValueObservation which observes *request*, and notifies
    /// fresh values whenever the request is impacted by a
    /// database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.select(Column("name"), as: String.self)
    ///     let observation = ValueObservation.trackingAll(withUniquing: request)
    ///
    ///     let observer = try dbQueue.start(observation) { names: [String] in
    ///         print("player name have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingAll<Request: FetchRequest>(withUniquing request: Request)
        -> ValueObservation<ValueReducers.UniqueValues<Request.RowDecoder>>
        where Request.RowDecoder: DatabaseValueConvertible
    {
        return ValueObservation<ValueReducers.UniqueValues<Request.RowDecoder>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.UniqueValues { try DatabaseValue.fetchAll($0, request) })
    }
    
    /// Creates a ValueObservation which observes *request*, and notifies a
    /// fresh value whenever the request is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.select(max(Column("score")), as: Int.self)
    ///     let observation = ValueObservation.trackingOne(request)
    ///
    ///     let observer = try dbQueue.start(observation) { maxScore: Int? in
    ///         print("maximum score has changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingOne<Request: FetchRequest>(_ request: Request)
        -> ValueObservation<ValueReducers.Raw<Request.RowDecoder?>>
        where Request.RowDecoder: DatabaseValueConvertible
    {
        return ValueObservation<ValueReducers.Raw<Request.RowDecoder?>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Raw(request.fetchOne))
    }
    
    /// Creates a ValueObservation which observes *request*, and notifies a
    /// fresh value whenever the request is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.select(max(Column("score")), as: Int.self)
    ///     let observation = ValueObservation.trackingOne(withUniquing: request)
    ///
    ///     let observer = try dbQueue.start(observation) { maxScore: Int? in
    ///         print("maximum score has changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingOne<Request: FetchRequest>(withUniquing request: Request)
        -> ValueObservation<ValueReducers.UniqueValue<Request.RowDecoder>>
        where Request.RowDecoder: DatabaseValueConvertible
    {
        return ValueObservation<ValueReducers.UniqueValue<Request.RowDecoder>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.UniqueValue { try DatabaseValue.fetchOne($0, request) })
    }
}

// MARK: - DatabaseValueConvertible & StatementColumnConvertible Observation

extension ValueObservation where Reducer == Void {
    /// Creates a ValueObservation which observes *request*, and notifies
    /// fresh values whenever the request is impacted by a
    /// database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.select(Column("name"), as: String.self)
    ///     let observation = ValueObservation.trackingAll(request)
    ///
    ///     let observer = try dbQueue.start(observation) { names: [String] in
    ///         print("player name have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingAll<Request: FetchRequest>(_ request: Request)
        -> ValueObservation<ValueReducers.Raw<[Request.RowDecoder]>>
        where Request.RowDecoder: DatabaseValueConvertible & StatementColumnConvertible
    {
        return ValueObservation<ValueReducers.Raw<[Request.RowDecoder]>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Raw(request.fetchAll))
    }
    
    /// Creates a ValueObservation which observes *request*, and notifies a
    /// fresh value whenever the request is impacted by a database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.select(max(Column("score")), as: Int.self)
    ///     let observation = ValueObservation.trackingOne(request)
    ///
    ///     let observer = try dbQueue.start(observation) { maxScore: Int? in
    ///         print("maximum score has changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingOne<Request: FetchRequest>(_ request: Request)
        -> ValueObservation<ValueReducers.Raw<Request.RowDecoder?>>
        where Request.RowDecoder: DatabaseValueConvertible & StatementColumnConvertible
    {
        return ValueObservation<ValueReducers.Raw<Request.RowDecoder?>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Raw(request.fetchOne))
    }
}

// MARK: - Optional DatabaseValueConvertible Observation

extension ValueObservation where Reducer == Void {
    /// Creates a ValueObservation which observes *request*, and notifies
    /// fresh values whenever the request is impacted by a
    /// database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.select(Column("name"), as: String.self)
    ///     let observation = ValueObservation.trackingAll(request)
    ///
    ///     let observer = try dbQueue.start(observation) { names: [String] in
    ///         print("player name have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingAll<Request: FetchRequest>(_ request: Request)
        -> ValueObservation<ValueReducers.Raw<[Request.RowDecoder._Wrapped?]>>
        where Request.RowDecoder: _OptionalProtocol,
        Request.RowDecoder._Wrapped: DatabaseValueConvertible
    {
        return ValueObservation<ValueReducers.Raw<[Request.RowDecoder._Wrapped?]>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Raw(request.fetchAll))
    }
    
    /// Creates a ValueObservation which observes *request*, and notifies
    /// fresh values whenever the request is impacted by a
    /// database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.select(Column("name"), as: String.self)
    ///     let observation = ValueObservation.trackingAll(withUniquing: request)
    ///
    ///     let observer = try dbQueue.start(observation) { names: [String] in
    ///         print("player name have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingAll<Request: FetchRequest>(withUniquing request: Request)
        -> ValueObservation<ValueReducers.UniqueOptionalValues<Request.RowDecoder._Wrapped>>
        where Request.RowDecoder: _OptionalProtocol,
        Request.RowDecoder._Wrapped: DatabaseValueConvertible
    {
        return ValueObservation<ValueReducers.UniqueOptionalValues<Request.RowDecoder._Wrapped>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.UniqueOptionalValues { try DatabaseValue.fetchAll($0, request) })
    }
}

// MARK: - Optional DatabaseValueConvertible & StatementColumnConvertible Observation

extension ValueObservation where Reducer == Void {
    /// Creates a ValueObservation which observes *request*, and notifies
    /// fresh values whenever the request is impacted by a
    /// database transaction.
    ///
    /// For example:
    ///
    ///     let request = Player.select(Column("name"), as: String.self)
    ///     let observation = ValueObservation.trackingAll(request)
    ///
    ///     let observer = try dbQueue.start(observation) { names: [String] in
    ///         print("player name have changed")
    ///     }
    ///
    /// The returned observation has the default configuration:
    ///
    /// - When started with the `start(_:onError:onChage:)` method, a fresh
    /// value is immediately notified on the dispatch queue which starts
    /// the observation.
    /// - Upon subsequent database changes, fresh values are notified on the
    /// main queue.
    /// - The observation lasts until the observer returned by
    /// `start` is deallocated.
    ///
    /// See ValueObservation for more information.
    ///
    /// - parameter request: the observed request.
    /// - returns: a ValueObservation.
    public static func trackingAll<Request: FetchRequest>(_ request: Request)
        -> ValueObservation<ValueReducers.Raw<[Request.RowDecoder._Wrapped?]>>
        where Request.RowDecoder: _OptionalProtocol,
        Request.RowDecoder._Wrapped: DatabaseValueConvertible & StatementColumnConvertible
    {
        return ValueObservation<ValueReducers.Raw<[Request.RowDecoder._Wrapped?]>>(
            tracking: request.databaseRegion,
            reducer: ValueReducers.Raw(request.fetchAll))
    }
}
