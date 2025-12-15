//
//  FolderPicker.swift
//  swiftTorrent
//
//  Created by Max Hewett on 15/12/2025.
//

import AppKit

enum FolderPicker {
    static func pickFolder(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        panel.begin { response in
            guard response == .OK else {
                completion(nil)
                return
            }
            completion(panel.url)
        }
    }
}
