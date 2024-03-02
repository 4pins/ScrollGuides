//
//  AppDelegate.swift
//  ScrollGuides
//
//  Copyright © 2024 John W. Lovell
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
import Cocoa

// So we have reasonable defaults.
var sensitivityCutoff = 2  // Zero out scrol values than this (manipulated) value.
let sensitivityLevels = [0, 1, 6, 12, 0]  // Curated sensitivities based on point change.
var guideSelection = 1  // 0 = No Guide/Freehand, 1 = Cross Guides, 2 = Vertical Guide, 3 = Horizontal Guide

// So we know when the start of scrolling has been supressed.
var supressed = false

// So we can know when motion has been prevented due to sensitivity.
var prevented = false

// So we eliminate unitientional movements while scrolling.
// Callback for event tap, so it must be a "func" and not a class member.
func mouseEventHandler(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // So we make sure that we only change events as intended.
    if(.scrollWheel == type) {
        // So we know what input the OS believes it has received.
        var xDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let xPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        var yDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let yPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        var phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        
        // So we start each impactful set of scroll events with a beginning.
        if(supressed) {
            if(0 != phase) {
                phase = 1
            }
            supressed = false
        }
       
        // So we supress inertia if scrolling was NOT already occouring.
        if(prevented) {
            prevented = false
            if(0 != momentum) {
                xDelta = 0
                yDelta = 0
                prevented = true
            }
        }
        
        // Cross Guides:  So we only scroll in the predominate direction.
        if(1 == guideSelection) {
            if(abs(yPoint) >= abs(xPoint)) {
                xDelta = 0
            }
            else {
                yDelta = 0
            }
        }
        // Vertical Guide:  So we support only vertical scrolling.
        else if(2 == guideSelection) {
            xDelta = 0
        }
        // Horizontal Guide:  So we support only horizontal scrolling.
        else if(3 == guideSelection) {
            yDelta = 0
        }
        
        // Sensitivity:  So we control the scrolling sensitive while preserving inertia.
        let sensitivity = sensitivityLevels[sensitivityCutoff]
        if((abs(xPoint) <= sensitivity && abs(yPoint) <= sensitivity  && 0 == momentum) || 3 < sensitivityCutoff) {
            xDelta = 0
            yDelta = 0
            if(4 != phase) {  // So the last regular scroll event doesn't prevent the inertia events impacts.
                prevented = true
            }
        }
        
        // So we know when we have supressed a phase one event and need to restart.
        if(0 == xDelta && 0 == yDelta && 1 == phase) {
            supressed = true
        }
 
        // So we modify the event before passing it back to the OS.
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: xDelta)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: yDelta)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    }
    
    // So the system can handle the event normally
    return Unmanaged.passRetained(event)
}


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // So we can work with (especially cleanup) our event tap.
    var eventMask = 1 << CGEventType.scrollWheel.rawValue
    var eventTap: (CFMachPort?)
    var runLoopSource: (CFRunLoopSource?)
    
    // So we can control our application from the menu bar.
    let scrollGuidesItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)

    // So we have the menu to display when our button is pressed (prevents redraw/flash).
    let menu = NSMenu()
    
    // So we have easy access to our UI controls that might change.
    let sensitivitySlider = NSSlider()
    let freehandMenuItem = NSMenuItem(title: "Freehand", action: #selector(freehandSelected(_:)), keyEquivalent: "")
    let crossMenuItem = NSMenuItem(title: "Cross", action: #selector(crossSelected(_:)), keyEquivalent: "")
    let verticalMenuItem = NSMenuItem(title: "Vertical", action: #selector(verticalSelected(_:)), keyEquivalent: "")
    let horizontalMenuItem = NSMenuItem(title: "Horizontal", action: #selector(horizontalSelected(_:)), keyEquivalent: "")
   
    // So we can reuse our images easily, quickly, and efficiently.
    let freehandImage = NSImage(named:NSImage.Name("Freehand"))
    let crossImage = NSImage(named:NSImage.Name("Cross"))
    let verticalImage = NSImage(named:NSImage.Name("Vertical"))
    let horizontalImage = NSImage(named:NSImage.Name("Horizontal"))
    let noScrollingImage = NSImage(named:NSImage.Name("NoScrolling"))
    
    override init() {
        super.init()

        // So we can tap the events we may want to modify.
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                     place: .headInsertEventTap,
                                     options: .defaultTap,
                                     eventsOfInterest: CGEventMask(eventMask),
                                     callback: mouseEventHandler,
                                     userInfo: nil)
        // So we know if our event tap has be created and can continue.
        if(nil != eventTap) {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        }
        else {
            // So we don't help the user if macOS is already trying to.
            var helped = false
            sleep(1)  // So the helper window has a second to appear.
            if let windowInfoList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[ String : Any]] {
                for windowInfo in windowInfoList {
                    if let ownerName = windowInfo["kCGWindowOwnerName"] {
                        if("universalAccessAuthWarn" == ownerName as! String) {
                            helped = true
                        }
                    }
                }
            }
            // So we do what we can to help the user grant the needed access.
            if(!helped) {
                alertOk(title: "Failed to load ScrollGuides",
                info: "Please ensure that ScrollGuides is enabled in:\nSystem Settings -> Privacy & Security -> Accessibility.  \n\nIf it is, you will need to disable it and enable it again.",
                style: .critical)
            }
            // So the application can be relaunched with the proper permissions.
            exit(1)
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // So we display our menu bar icon.
        scrollGuidesItem.button?.image = freehandImage

        menu.minimumWidth = 190
        
        // So the user can control the sensitivity.
        menu.addItem(NSMenuItem(title: "Scroll Sensitivity:", action: nil, keyEquivalent: ""))
        let sensitivityMenuItem = NSMenuItem()
        sensitivityMenuItem.title = "Sensitivity"
        sensitivitySlider.setFrameSize(NSSize(width: 160, height: 16))
        sensitivitySlider.numberOfTickMarks = 5
        sensitivitySlider.allowsTickMarkValuesOnly = true
        sensitivitySlider.minValue = 0
        sensitivitySlider.maxValue = 4
        sensitivitySlider.action = #selector(sensitivityChanged(_:))
        // So we align the sensitivty control with its title.
        sensitivitySlider.setFrameOrigin(CGPoint(x: 20, y: 0))
        let sensitivityRect = NSMakeRect(0, 0, 190, 20)
        let sensitivityView = NSView(frame: sensitivityRect)
        sensitivityView.addSubview(sensitivitySlider)
        sensitivityMenuItem.view = sensitivityView
        menu.addItem(sensitivityMenuItem)
        
        // So the user can chose what guides they want.
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Scroll Guides:", action: nil, keyEquivalent: ""))
        // Freehand
        freehandMenuItem.image = freehandImage
        menu.addItem(freehandMenuItem)
        // Cross
        crossMenuItem.image = crossImage
        menu.addItem(crossMenuItem)
        // Vertical
        verticalMenuItem.image = verticalImage
        menu.addItem(verticalMenuItem)
        // Horizontal
        horizontalMenuItem.image = horizontalImage
        menu.addItem(horizontalMenuItem)
        
        // So the use can get information and support.
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About", action: #selector(aboutSelected(_:)), keyEquivalent: ""))
        
        // So the user can quite the application.
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        
        // So the application uses the menu we just defined.
        scrollGuidesItem.menu = menu
        
        // So we use the previous saved variable values.
        let defaults = UserDefaults.standard
        // So we only use defaults if previous settings failed to load.
        let previousSelection = UserDefaults.standard.object(forKey: "GuideSelection")
        if(nil != previousSelection) {
            guideSelection = previousSelection as! Int
        }
        else {
            let selection = ["GuideSelection" : guideSelection]
            defaults.register(defaults: selection)
        }
        let previousCutoff = UserDefaults.standard.object(forKey: "SensitivityCutoff")
        if(nil != previousCutoff) {
            sensitivityCutoff = previousCutoff as! Int
        }
        else {
            let cutoff = ["SensitivityCutoff" : sensitivityCutoff]
            defaults.register(defaults: cutoff)
        }

        // So we start with the loaded (or default) settings.
        updateMenu()
        
        // So we send the events we care about to our handler.
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    }

    // So we cleanup the resource we use before we leave.
    func applicationWillTerminate(_ aNotification: Notification) {
        // So we use our current settings the next time we are launched.
        let defaults = UserDefaults.standard
        defaults.set(guideSelection, forKey: "GuideSelection")
        defaults.set(sensitivityCutoff, forKey: "SensitivityCutoff")
        
        // So we cleanly remove current event tap.
        // Note:  If we don't do this the event will not let this app create another one.
        CFMachPortInvalidate(eventTap)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    }
    
    // So we can convert between NSSlider values and those we use.
    func cutoff2Position(cutoff: Int) -> Int {
        return abs(cutoff - Int(sensitivitySlider.maxValue))
    }
    func position2Cutoff(position: Int) -> Int {
        return abs(position - Int(sensitivitySlider.maxValue))
    }

    // So we handle the users input, one control at a time.
    @objc func sensitivityChanged(_ sender: Any?) {
        sensitivityCutoff = position2Cutoff(position: Int(sensitivitySlider.doubleValue))
        updateMenu()
    }
    @objc func freehandSelected(_ sender: Any?) {
        guideSelection = 0
        updateMenu()
    }
    @objc func crossSelected(_ sender: Any?) {
        guideSelection = 1
        updateMenu()
    }
    @objc func verticalSelected(_ sender: Any?) {
        guideSelection = 2
        updateMenu()
    }
    @objc func horizontalSelected(_ sender: Any?) {
        guideSelection = 3
        updateMenu()
    }
    @objc func aboutSelected(_ sender: Any?) {
        // So we have the same information at the app.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String
        let date = Bundle.main.object(forInfoDictionaryKey: "CFBuildDate") as! String
        let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as! String
        let license = Bundle.main.object(forInfoDictionaryKey: "CFLicense") as! String
        
        // So we display the information to the user.
        alertOk(title: "ScrollGuides",
                info: "Version:  " + version + "\n" +
                      "Build:  " + build + "\n" +
                      "Date:  " + date + "\n\n" +
                      "Web Site:  https://github.com/4pins/ScrollGuides\n\n" +
                      copyright + "\n" +
                      license,
                style: .informational)
    }
    
    // So the menu reflects the current values that impact the system.
    func updateMenu() {
        // So we have the correct scroll guide selected in the interface.
        freehandMenuItem.state = NSControl.StateValue.off
        crossMenuItem.state = NSControl.StateValue.off
        verticalMenuItem.state = NSControl.StateValue.off
        horizontalMenuItem.state = NSControl.StateValue.off
        switch guideSelection {
        case 0:
            freehandMenuItem.state = NSControl.StateValue.on
            scrollGuidesItem.button?.image = freehandImage
        case 1:
            crossMenuItem.state = NSControl.StateValue.on
            scrollGuidesItem.button?.image = crossImage
        case 2:
            verticalMenuItem.state = NSControl.StateValue.on
            scrollGuidesItem.button?.image = verticalImage
        case 3:
            horizontalMenuItem.state = NSControl.StateValue.on
            scrollGuidesItem.button?.image = horizontalImage
        default:
            break
        }
        
        // So we reflect the current sensitivity setting in the interface.
        sensitivitySlider.doubleValue =  Double(cutoff2Position(cutoff: sensitivityCutoff))
        if(3 < sensitivityCutoff) {
            scrollGuidesItem.button?.image = noScrollingImage
        }
    }
    
    // So we can let the user know when we where unable to register our evnt tap.
    func alertOk(title: String, info: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
}
