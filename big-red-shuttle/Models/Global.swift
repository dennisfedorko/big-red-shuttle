//
//  Global.swift
//  big-red-shuttle
//
//  Created by Annie Cheng on 11/21/16.
//  Copyright © 2016 cuappdev. All rights reserved.
//

import Foundation
import SwiftyJSON
import SystemConfiguration

struct Constants {
    static let brsStackBaseURL = "https://raw.githubusercontent.com/cuappdev/big-red-shuttle-stack/master/"
}

// Check if Internet is available on device
public func connectedToInternet() -> Bool {
    var zeroAddress = sockaddr_in()
    zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    zeroAddress.sin_family = sa_family_t(AF_INET)
    
    guard let defaultRouteReachability = withUnsafePointer(to: &zeroAddress, {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            SCNetworkReachabilityCreateWithAddress(nil, $0)
        }
    }) else {
        return false
    }
    
    var flags: SCNetworkReachabilityFlags = []
    if !SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) {
        return false
    }
    
    let isReachable = flags.contains(.reachable)
    let needsConnection = flags.contains(.connectionRequired)
    
    return isReachable && !needsConnection
}

// Display warning if user is not connected to Internet
public func displayNoInternetAlert(vc: UIViewController) {
    if !connectedToInternet() {
        let alert = UIAlertController(title: "No Internet Connection!", message: "The bus schedule displayed may be outdated. You should connect to the Internet for the most accurate bus stop and route information.", preferredStyle: .alert)
        let connectAction = UIAlertAction(title: "Connect", style: .default, handler: { _ in
            guard let settingsUrl = URL(string: UIApplicationOpenSettingsURLString) else { return }
            
            if UIApplication.shared.canOpenURL(settingsUrl) {
                UIApplication.shared.open(settingsUrl, completionHandler: nil)
            }
        })
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        alert.addAction(connectAction)
        alert.addAction(cancelAction)
        vc.present(alert, animated: true, completion: nil)
    }
}

// MARK: - Information retrieval methods for Big Red Shuttle Stack

// Get BRS stops with name, location, dates, and times
public func getStops() ->  [Stop] {
    let stopJsonURLString = "\(Constants.brsStackBaseURL)brs-schedule-testing.json"
    let backupURL = Bundle.main.url(forResource: "brs-stops", withExtension: "json")!
    let url = URL(string: stopJsonURLString) ?? backupURL
    
    var stops = [Stop]()
    var json: JSON!
    
    if let data = try? Data(contentsOf: url) {
        json = JSON(data: data)
    } else {
        let backupData = try? Data(contentsOf: backupURL)
        json = JSON(data: backupData!)
    }
    
    for stop in json["stops"].arrayValue {
        var dayArray = [Days]()
        let name = stop["name"].stringValue
        let lat = stop["lat"].floatValue
        let long = stop["long"].floatValue
        let days = stop["days"].arrayObject!
        let timeStrings = stop["times"].arrayObject! as! [String]
        
        var times:[Time] = []
        for day in days {
            let dayObject = Days(rawValue: day as! String)!
            dayArray.append(Days(rawValue: day as! String)!)
            for tStr in timeStrings {
                times.append(Time(time: tStr, technicallyNightBefore: dayObject.number))
            }
        }
        
        stops.append(Stop(name: name, lat: lat, long: long, days: dayArray, times: times))
    }
    
    return stops
}

// Get BRS emergency contacts with service and name
public func getEmergencyContacts() -> [EmergencyContact] {
    let emergencyContactsURLString = "\(Constants.brsStackBaseURL)brs-emergency-contacts.json"
    let backupURL = Bundle.main.url(forResource: "brs-emergency-contacts", withExtension: "json")!
    let url = URL(string: emergencyContactsURLString) ?? backupURL
    
    var emergencyContacts = [EmergencyContact]()
    var json: JSON!
    
    if let data = try? Data(contentsOf: url) {
        json = JSON(data: data)
    } else {
        let backupData = try? Data(contentsOf: backupURL)
        json = JSON(data: backupData!)
    }
    
    for contact in json["contacts"].arrayValue {
        let service = contact["service"].stringValue
        let number = contact["number"].stringValue
        
        emergencyContacts.append(EmergencyContact(service: service, number: number))
    }
    
    return emergencyContacts
}

// Get descriptions for BRS About View
public func getAboutSections() -> [AboutSection] {
    let aboutSectionsURLString = "\(Constants.brsStackBaseURL)brs-about-sections.json"
    let backupURL = Bundle.main.url(forResource: "brs-about-sections", withExtension: "json")!
    let url = URL(string: aboutSectionsURLString) ?? backupURL
    
    var aboutSections = [AboutSection]()
    var json: JSON!
    
    if let data = try? Data(contentsOf: url) {
        json = JSON(data: data)
    } else {
        let backupData = try? Data(contentsOf: backupURL)
        json = JSON(data: backupData!)
    }
    
    for section in json["sections"].arrayValue {
        let title = section["title"].stringValue
        let summary = section["summary"].stringValue
        let link = section["link"].stringValue
        
        aboutSections.append(AboutSection(title: title, summary: summary, link: link))
    }
    
    return aboutSections
}

// MARK: - Date and Time Methods

// Get the current day of the week in int format
public func getDayOfWeek(today: Date) -> Int {
    return Calendar(identifier: .gregorian).component(.weekday, from: today)
}

// Create time from JSON string, where time string must have format H:mm a
public func getTime(time: String) -> (Int, Int) {
    var hourArr = time.components(separatedBy: ":") // ["h","mm a"]
    let minArr = hourArr[1].components(separatedBy: " ") // ["mm","a"]
    let timeArr = [hourArr[0]] + minArr // ["h","mm","a"]
    
    let minute = Int(timeArr[1])!
    let hour12 = Int(hourArr[0])!
    
    var hour = 0
    let aa = timeArr[2].lowercased()
    if aa == "am" && hour12 == 12 { // 12:xx am = 0:xx
        hour = 0
    } else if aa == "pm" && hour12 != 12 { // 12:xx pm = 12:xx
        hour = hour12 + 12 // h:xx pm = (h+12):xx
    } else {
        hour = hour12
    }
    
    return (hour, minute)
}

// Get minutes from now until given time (HH:mm a)
public func getMinutesUntilTime(time: String) -> Int {
    let todayString = DateFormatter.dateTimeFormatter.string(from: Date())
    let currDate = DateFormatter.dateTimeFormatter.date(from: todayString)
    
    let todayDateString = DateFormatter.yearMonthDayFormatter.string(from: Date())
    let timeString = "\(todayDateString) \(time)"
    let toDate = DateFormatter.dateTimeFormatter.date(from: timeString)
    
    if let currDate = currDate, var toDate = toDate {
        if currDate > toDate {
            toDate = Calendar.current.date(byAdding: .day, value: 1, to: toDate)!
        }
        
        return minutes(from: currDate, to: toDate)
    } else {
        return -1
    }
}

// Return the number of minutes from one date to another date
public func minutes(from date1: Date, to date2: Date) -> Int {
    return Calendar.current.dateComponents([.minute], from: date1, to: date2).minute ?? 0
}
