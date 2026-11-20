import CoreGraphics
import Testing
@testable import DeckOutKit

// m1ddc's `display list detailed`, shaped like the owner's two identical monitors (serials and ids invented).
let detailedFixture = """
[1] LG HDR 4K (11111111-2222-3333-4444-555555555555)
 - Product name:  LG HDR 4K
 - Manufacturer:  GSM
 - AN Serial:     AAA111TEST
 - Vendor:        7789 (0x1e6d)
 - Display ID:    5
 - IO Location:   IOService:/x
[2] LG HDR 4K (66666666-7777-8888-9999-000000000000)
 - Product name:  LG HDR 4K
 - Manufacturer:  GSM
 - AN Serial:     BBB222TEST
 - Display ID:    4
"""

@Test func parsesDetailedList() {   // T-144
    let monitors = MonitorList.parse(detailedFixture)
    #expect(monitors == [Monitor(number: 1, name: "LG HDR 4K", serial: "AAA111TEST", displayID: 5),
                         Monitor(number: 2, name: "LG HDR 4K", serial: "BBB222TEST", displayID: 4)])
    #expect(MonitorList.parse("") == [])
    #expect(MonitorList.parse("[1] Odd (x)\n - Product name: Odd\n") == [])     // no serial: can't be named
}

@Test func placesFromScreens() {   // T-145
    // Two the same: told apart by where they sit.
    #expect(MonitorList.places([5: CGRect(x: -2560, y: 0, width: 2560, height: 1440),
                                4: CGRect(x: 0, y: 0, width: 2560, height: 1440)]) == [5: "Left", 4: "Right"])
    #expect(MonitorList.places([1: CGRect(x: 0, y: 0, width: 100, height: 100),
                                2: CGRect(x: 100, y: 0, width: 100, height: 100),
                                3: CGRect(x: 200, y: 0, width: 100, height: 100)]) == [1: "Left", 2: "Middle", 3: "Right"])
    // Stacked: above and below (screen coordinates: y up).
    #expect(MonitorList.places([1: CGRect(x: 0, y: 1000, width: 100, height: 100),
                                2: CGRect(x: 0, y: 0, width: 100, height: 100)]) == [1: "Top", 2: "Bottom"])
    #expect(MonitorList.places([9: CGRect(x: 0, y: 0, width: 100, height: 100)]) == [9: ""])
    // A monitor macOS doesn't show as a screen (mirrored, asleep): no place.
    #expect(MonitorList.places([:]) == [:])
}
