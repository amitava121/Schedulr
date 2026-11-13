import Foundation

public struct EntityExtraction {
    public static func extract<T>(
        identifiers: [String],
        allEntities: [T],
        idProvider: (T) -> String
    ) -> [T] {
        identifiers.compactMap { id in
            allEntities.first(where: { idProvider($0) == id })
        }
    }
}
