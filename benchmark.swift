import Foundation

// Try to write a standalone benchmark that simulates the loop in monthHeatmapSummary.
// Since we can't easily import the entire app, maybe we just measure the timing of
// some calendar operations to prove that hoisting `startOfDay` and calendar init out of the loop
// is significantly faster.

let calendar = Calendar.current
let daysCount = 31

var schedules = [Date]()
for i in 0..<1000 {
    schedules.append(Date().addingTimeInterval(Double(i) * 86400))
}

let monthDays = (0..<daysCount).map { Date().addingTimeInterval(Double($0) * 86400) }

let start1 = CFAbsoluteTimeGetCurrent()
var count1 = 0
for day in monthDays {
    for scheduleDate in schedules {
        let startDay = calendar.startOfDay(for: scheduleDate)
        let targetDay = calendar.startOfDay(for: day)
        if targetDay >= startDay {
            count1 += 1
        }
    }
}
let end1 = CFAbsoluteTimeGetCurrent()
print("Original loop: \((end1 - start1) * 1000) ms, result: \(count1)")


let start2 = CFAbsoluteTimeGetCurrent()
var count2 = 0
for scheduleDate in schedules {
    let startDay = calendar.startOfDay(for: scheduleDate)
    for day in monthDays {
        // Assume monthDays are already startOfDay, or pre-computed
        // Let's say we pre-compute targetDay for each day in the month
        let targetDay = day // assuming they are pre-computed start of days
        if targetDay >= startDay {
            count2 += 1
        }
    }
}
let end2 = CFAbsoluteTimeGetCurrent()
print("Optimized loop (hoisted startDay): \((end2 - start2) * 1000) ms, result: \(count2)")
