import Foundation

struct Colors {
    static let reset = "\u{001B}[0;0m"
    static let black = "\u{001B}[0;30m"
    static let red = "\u{001B}[0;31m"
    static let green = "\u{001B}[0;32m"
    static let yellow = "\u{001B}[0;33m"
    static let blue = "\u{001B}[0;34m"
    static let magenta = "\u{001B}[0;35m"
    static let cyan = "\u{001B}[0;36m"
    static let white = "\u{001B}[0;37m"
    static let bold = "\u{001B}[0;1m"
    static let blink = "\u{001B}[0;5m"
    static let clearscreen = "\u{001B}[2J"
}

func checkValues(_ profiles: [[String: Any]]) -> (Bool, Bool) {
    var sameValues = true
    var sameKeys = false

    var values = [Any]()
    var keys = Set<String>()

    for profile in profiles {
        for (key, value) in profile {
            values.append(value)
            if keys.contains(key) {
                sameKeys = true
            }
            keys.insert(key)
        }

        if let firstValue = values.first as? AnyHashable {
            for value in values {
                if let value = value as? AnyHashable, firstValue != value {
                    sameValues = false
                    break
                }
            }
        }
    }

    return (sameValues, sameKeys)
}

func main() {
    if geteuid() != 0 {
        fputs("\nThis binary must be run as root.\n", stderr)
        exit(1)
    }

    let cmd = "/usr/bin/profiles -P -o stdout-xml | /usr/bin/grep -v \"configuration profiles installed\""

    let process = Process()
    process.launchPath = "/bin/bash"
    process.arguments = ["-c", cmd]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.launch()

    let profilesData = pipe.fileHandleForReading.readDataToEndOfFile()

    guard let profilesDict = try? PropertyListSerialization.propertyList(from: profilesData, options: [], format: nil) as? [String: Any],
          let computerLevel = profilesDict["_computerlevel"] as? [[String: Any]] else {
        return
    }

    var keyDict = [String: [[String: Any]]]()

    for profile in computerLevel {
        guard let profileItems = profile["ProfileItems"] as? [[String: Any]] else {
            continue
        }
        
        for item in profileItems {
            guard let payloadContent = item["PayloadContent"] as? [String: Any] else {
                continue
            }
            
            for (key, value) in payloadContent {
                if key == "PayloadContentManagedPreferences",
                   let payloadContentManagedPreferences = value as? [String: Any],
                   let forced = payloadContentManagedPreferences["Forced"] as? [[String: Any]] {
                    for mcx in forced {
                        guard let mcxPreferenceSettings = mcx["mcx_preference_settings"] as? [String: Any] else {
                            continue
                        }
                        
                        for (mcxKey, mcxValue) in mcxPreferenceSettings {
                            if var existingItems = keyDict[mcxKey] {
                                existingItems.append([profile["ProfileDisplayName"] as? String ?? "": mcxValue])
                                keyDict[mcxKey] = existingItems
                            } else {
                                keyDict[mcxKey] = [[profile["ProfileDisplayName"] as? String ?? "": mcxValue]]
                            }
                        }
                    }
                } else {
                    if var existingItems = keyDict[key] {
                        existingItems.append([profile["ProfileDisplayName"] as? String ?? "": value])
                        keyDict[key] = existingItems
                    } else {
                        keyDict[key] = [[profile["ProfileDisplayName"] as? String ?? "": value]]
                    }
                }
            }
        }
    }

    for (key, value) in keyDict {
        if value.count > 1 {
            let (valuesMatch, keysMatch) = checkValues(value)

            if keysMatch {
                continue
            } else {
                print("\n\(Colors.yellow)\(key)\(Colors.reset)")
                
                if valuesMatch {
                    value.forEach{
                        if let configkey = $0.keys.first, let configvalue = $0.values.first {
                            let configString = String(describing: configvalue).removeExtraSpaces()
                
                            print("\(configkey) : \(Colors.green)\(configString.prefix(60))\(Colors.reset)")    
                        }
                    }
                } else {
                    value.forEach{
                        if let configkey = $0.keys.first, let configvalue = $0.values.first {
                            let configString = String(describing: configvalue).removeExtraSpaces()
                            print("\(configkey) : \(Colors.red)\(configString.prefix(60))\(Colors.reset)")    
                        }
                    }
                }
            }
        }
    }

    let infoBlob = """
    Output indicates that multiple configuration profiles are defining values for the duplicate keys.
    This may result in unexpected behavior. For any keys (\(Colors.yellow)yellow\(Colors.reset)) listed, the corresponding profile names,
    along with the values are provided. The values in \(Colors.green)green\(Colors.reset) are the same, while values in \(Colors.red)red\(Colors.reset) are different
    and may need review. Values have been truncated for readability.
    NOTE: There are a number of keys that can be defined in multiple profiles with differing values.
    These are typically in application-specific profiles, or seen in networking profiles or PPPC profiles.
    Red values in output do not necessarily indicate a problem, but rather listed to be reviewed.
    """

    print("\n\n***** INFORMATION *****")
    print(infoBlob)
}

main()

extension String {

    func removeExtraSpaces() -> String {
        var newString = self.replacingOccurrences(of: "\n", with: " ")
        newString = newString.replacingOccurrences(of: "[\\s\n]+", with: " ", options: .regularExpression, range: nil)
        
        return newString
    }

}