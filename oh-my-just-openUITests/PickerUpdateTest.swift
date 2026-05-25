import XCTest

final class PickerUpdateTest: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPickerUpdatesRowLabelImmediately() throws {
        let app = XCUIApplication()
        app.launch()

        // Switch to "Files" tab (custom FigmaTabBar button)
        let filesTab = app.buttons["Files"]
        XCTAssertTrue(filesTab.waitForExistence(timeout: 5), "Files tab not found")
        filesTab.click()
        sleep(1)

        // Turn OFF "Only types with multiple available apps" (first switch in UI)
        let switches = app.switches
        if switches.count > 0 {
            let multi = switches.element(boundBy: 0)
            if (multi.value as? Int ?? 0) == 1 {
                multi.click()
                sleep(1)
            }
        }

        // Type "md" in search field
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        searchField.click()
        searchField.typeText("md")
        sleep(1)

        // Find all menu buttons (elementType 16) and locate one with title "None" in
        // a row whose adjacent static text reads ".md".
        // Strategy: find static text ".md", then walk siblings to find the picker
        // (a menu button) in the same row.
        let mdLabels = app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", ".md", ".md"))
        print("'.md' labels count: \(mdLabels.count)")

        // Easier alternative: enumerate all descendants once, find indices of '.md'
        // labels and the next menu button after each (rows are flat-ordered).
        let allWindow = app.windows.firstMatch
        let allEls = allWindow.descendants(matching: .any)
        let n = allEls.count
        print("Total descendants: \(n)")

        var rowPicker: XCUIElement? = nil
        var mdIndex = -1
        for i in 0..<n {
            let el = allEls.element(boundBy: i)
            // elementType 48 = staticText (per our prior probe).
            // Test value or label for ".md"
            let v = (el.value as? String) ?? ""
            let lbl = el.label
            let tt = el.title
            if v == ".md" || lbl == ".md" || tt == ".md" {
                mdIndex = i
                print("Found .md at index \(i)")
                // Look ahead for the menu button (elementType 16, title=None or app name)
                for j in (i+1)..<min(i+8, n) {
                    let nx = allEls.element(boundBy: j)
                    if nx.elementType == .menuButton {
                        rowPicker = nx
                        print("  Picker at index \(j): title='\(nx.title)' label='\(nx.label)'")
                        break
                    }
                }
                if rowPicker != nil { break }
            }
        }

        guard let picker = rowPicker else {
            // Fallback: find first menu button in the visible window other than the
            // "Currently set to" header menu (which has title "" / label "Currently set to:")
            var hits: [XCUIElement] = []
            for i in 0..<n {
                let el = allEls.element(boundBy: i)
                if el.elementType == .menuButton {
                    hits.append(el)
                    print("  candidate menuButton[\(hits.count - 1)] title='\(el.title)' label='\(el.label)'")
                }
            }
            XCTFail("Could not locate .md row picker. mdIndex=\(mdIndex), menuButton hits=\(hits.count)")
            return
        }

        let labelBefore = picker.title
        print("LABEL BEFORE: '\(labelBefore)'")

        // Click the picker to open its menu
        picker.click()
        sleep(1)

        // After opening, the menu items appear under the menu button. Look for AXMenuItem children.
        let items = picker.menuItems
        print("Menu items count: \(items.count)")
        for k in 0..<min(items.count, 20) {
            let mi = items.element(boundBy: k)
            print("  MI[\(k)] title='\(mi.title)' label='\(mi.label)'")
        }
        guard items.count > 0 else {
            // Try toggling "All apps" switch for this row (siblings between picker and next .md row)
            XCTFail("Picker opened but no menu items present")
            return
        }

        let chosen = items.element(boundBy: 0)
        let chosenName = chosen.title.isEmpty ? chosen.label : chosen.title
        print("CHOOSING: '\(chosenName)'")
        chosen.click()
        sleep(1)

        // If a confirmation sheet appears (alwaysConfirms is true for .md), accept it
        let confirmBtn = app.buttons["Confirm"]
        if confirmBtn.waitForExistence(timeout: 2) {
            print("Confirmation sheet detected, clicking Confirm")
            confirmBtn.click()
            sleep(1)
        }

        // Re-read picker title — should now reflect the chosen app immediately
        let labelAfter = picker.title
        print("LABEL AFTER: '\(labelAfter)'")

        XCTAssertNotEqual(labelBefore, labelAfter,
            "BUG 1 NOT FIXED: picker label did not update after selecting an app (before='\(labelBefore)' after='\(labelAfter)')")
    }
}
