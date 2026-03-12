# Performance Learnings

- **CoreData/SwiftData Fetch Optimization**: Replaced in-memory filtering with database-level `#Predicate` in `FetchDescriptor`. This reduces memory allocation and execution time by offloading filtering to SQLite.
