import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

ShellRoot {
  // Main Panel
  PanelWindow {
    id: mainPanel
    anchors {
      top: true
      left: true
      right: true
    }

    implicitHeight: appLauncherDropdown.visible ? 442 : 42

    Rectangle {
      anchors.fill: parent
      color: "#1e1e1e"
      radius: 0
      border.color: "#333333"
      border.width: 1

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: "#0d1117"
      }

      // App Launcher Button
      Button {
        id: launcherButton
        x: 5
        y: 5
        width: 40
        height: 32

        background: Rectangle {
          color: parent.pressed ? "#555555" : (parent.hovered ? "#333333" : "#222222")
          radius: 4
          border.color: "#444444"
          border.width: 1
        }

        contentItem: Text {
          text: "⚡"
          font.pixelSize: 18
          color: "#ffffff"
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        onClicked: {
          console.log("LAUNCHER BUTTON CLICKED!")
          debugText.text = "Clicked: " + Date.now()
          if (appLauncherDropdown.visible) {
            appLauncherDropdown.visible = false
          } else {
            appLauncherDropdown.visible = true
            focusTimer.start()
            appDiscovery.running = true
          }
        }
        
        onPressed: console.log("Button pressed")
        onReleased: console.log("Button released")
        onHoveredChanged: console.log("Button hover:", hovered)
      }

      // Debug text to show button interactions
      Text {
        id: debugText
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: appLauncherDropdown.visible ? "Menu: ON" : "Menu: OFF"
        color: "#888888"
        font.pixelSize: 10
      }

      // Fallback simple button
      Rectangle {
        id: fallbackButton
        x: 50
        y: 5
        width: 40
        height: 32
        color: fallbackMouse.pressed ? "#555555" : (fallbackMouse.containsMouse ? "#333333" : "#444444")
        radius: 4
        border.color: "#666666"
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "🚀"
          font.pixelSize: 18
          color: "#ffffff"
        }

        MouseArea {
          id: fallbackMouse
          anchors.fill: parent
          hoverEnabled: true
          
          onClicked: {
            console.log("FALLBACK BUTTON CLICKED!")
            debugText.text = "Fallback: " + Date.now()
            appLauncherDropdown.visible = !appLauncherDropdown.visible
            if (appLauncherDropdown.visible) {
              focusTimer.start()
              appDiscovery.running = true
            }
          }
          
          onPressed: console.log("Fallback pressed")
          onReleased: console.log("Fallback released")
          onEntered: console.log("Fallback entered")
          onExited: console.log("Fallback exited")
        }
      }

      // Clock in center
      Text {
        id: clock
        anchors.centerIn: parent
        font.pixelSize: 14
        font.bold: true
        color: "#ffffff"
        font.family: "Inter, Sans-serif"

        Process {
          id: dateProc
          command: ["date", "+%a %b %d  %H:%M"]
          running: true
          stdout: StdioCollector {
            onStreamFinished: clock.text = this.text
          }
        }

        Timer {
          interval: 1000
          running: true
          repeat: true
          onTriggered: dateProc.running = true
        }
      }

      // App Launcher Dropdown (integrated into panel)
      Rectangle {
        id: appLauncherDropdown
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 42
        height: 400
        visible: false
        color: "#1e1e1e"
        border.color: "#444444"
        border.width: 1
        z: 10

        onVisibleChanged: {
          if (visible) {
            // Use a timer to ensure the field is properly focused after the dropdown is shown
            focusTimer.start()
            if (dropdownAppListModel.count === 0) {
              discoverAllApplications()
            }
          }
        }

        Timer {
          id: focusTimer
          interval: 50
          repeat: false
          onTriggered: {
            dropdownSearchField.forceActiveFocus()
          }
        }

        Column {
          anchors.fill: parent
          spacing: 0

          // Search Field (rofi-style)
          Rectangle {
            width: parent.width
            height: 50
            color: "#2a2a2a"
            border.color: "#444444"
            border.width: 1

            MouseArea {
              anchors.fill: parent
              onClicked: {
                dropdownSearchField.forceActiveFocus()
              }
            }

            Row {
              anchors.fill: parent
              anchors.margins: 15
              spacing: 10

              Text {
                text: "❯"
                font.pixelSize: 16
                color: "#0078d4"
                anchors.verticalCenter: parent.verticalCenter
              }

              TextInput {
                id: dropdownSearchField
                width: parent.width - 40
                height: parent.height
                font.pixelSize: 16
                color: "#ffffff"
                selectByMouse: true
                anchors.verticalCenter: parent.verticalCenter
                focus: true
                activeFocusOnTab: true
                cursorVisible: true

                Keys.onPressed: (event) => {
                  if (event.key === Qt.Key_Escape) {
                    appLauncherDropdown.visible = false
                    dropdownSearchField.text = ""
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    // Find the first visible item and launch it
                    for (var i = 0; i < dropdownAppListModel.count; i++) {
                      var item = dropdownAppListView.itemAtIndex(i)
                      if (item && item.visible) {
                        launchApp(dropdownAppListModel.get(i).exec)
                        appLauncherDropdown.visible = false
                        dropdownSearchField.text = ""
                        break
                      }
                    }
                    event.accepted = true
                  } else if (event.key === Qt.Key_Down) {
                    // Find next visible item
                    for (var i = dropdownAppListView.currentIndex + 1; i < dropdownAppListModel.count; i++) {
                      var item = dropdownAppListView.itemAtIndex(i)
                      if (item && item.visible) {
                        dropdownAppListView.currentIndex = i
                        break
                      }
                    }
                    event.accepted = true
                  } else if (event.key === Qt.Key_Up) {
                    // Find previous visible item
                    for (var i = dropdownAppListView.currentIndex - 1; i >= 0; i--) {
                      var item = dropdownAppListView.itemAtIndex(i)
                      if (item && item.visible) {
                        dropdownAppListView.currentIndex = i
                        break
                      }
                    }
                    event.accepted = true
                  }
                }

                Text {
                  visible: parent.text.length === 0
                  text: "Type to search applications..."
                  color: "#888888"
                  font.pixelSize: 16
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                onTextChanged: {
                  // Reset to first visible item when search changes
                  dropdownAppListView.currentIndex = 0
                  for (var i = 0; i < dropdownAppListModel.count; i++) {
                    var item = dropdownAppListView.itemAtIndex(i)
                    if (item && item.visible) {
                      dropdownAppListView.currentIndex = i
                      break
                    }
                  }
                }
              }
            }
          }

          // App List (rofi-style)
          ListView {
            id: dropdownAppListView
            width: parent.width
            height: parent.height - 50
            model: ListModel {
              id: dropdownAppListModel
            }
            currentIndex: 0
            keyNavigationEnabled: true
            highlightFollowsCurrentItem: true

            highlight: Rectangle {
              color: "#0078d4"
              radius: 0
            }

                          delegate: Rectangle {
                width: dropdownAppListView.width
                height: visible ? 40 : 0
                color: ListView.isCurrentItem ? "#0078d4" : (dropdownMouseArea.containsMouse ? "#333333" : "transparent")
                visible: {
                if (dropdownSearchField.text.length === 0) return true
                
                var searchText = dropdownSearchField.text.toLowerCase()
                var name = (model.name || "").toLowerCase()
                var description = (model.description || "").toLowerCase()
                var exec = (model.exec || "").toLowerCase()
                
                return name.includes(searchText) || 
                       description.includes(searchText) || 
                       exec.includes(searchText)
              }

              MouseArea {
                id: dropdownMouseArea
                anchors.fill: parent
                hoverEnabled: true
                                  onClicked: {
                    dropdownAppListView.currentIndex = index
                    launchApp(model.exec)
                    appLauncherDropdown.visible = false
                    dropdownSearchField.text = ""
                  }
                  onEntered: dropdownAppListView.currentIndex = index
              }

              Row {
                anchors.left: parent.left
                anchors.leftMargin: 15
                anchors.verticalCenter: parent.verticalCenter
                spacing: 15

                // Icon display - handle both image icons and emoji
                Item {
                  width: 24
                  height: 24
                  anchors.verticalCenter: parent.verticalCenter
                  
                  // Try to load as image first
                  Image {
                    id: dropdownIconImage
                    anchors.fill: parent
                    source: {
                      var iconStr = model.icon || "📱"
                      // If it looks like an icon name (no emoji), try to load from theme
                      if (iconStr && !iconStr.match(/[\u{1F000}-\u{1F6FF}]|[\u{1F300}-\u{1F5FF}]|[\u{1F600}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]/u)) {
                        // Try different icon paths
                        return "image://icon/" + iconStr
                      }
                      return ""
                    }
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                    asynchronous: true
                  }
                  
                  // Fallback to text/emoji
                  Text {
                    anchors.centerIn: parent
                    text: model.icon || "📱"
                    font.pixelSize: 16
                    visible: dropdownIconImage.status !== Image.Ready
                  }
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 2

                  Text {
                    text: model.name || "Unknown"
                    font.pixelSize: 14
                    font.bold: true
                    color: parent.parent.parent.ListView.isCurrentItem ? "#ffffff" : "#ffffff"
                  }

                  Text {
                    text: model.description || ""
                    font.pixelSize: 11
                    color: parent.parent.parent.ListView.isCurrentItem ? "#dddddd" : "#aaaaaa"
                    width: appLauncherDropdown.width - 80
                    elide: Text.ElideRight
                    visible: text.length > 0
                  }
                }
              }
            }
          }
        }
      }

      // App Discovery Process  
      Process {
        id: appDiscovery
        
        command: ["bash", "-c", "find /usr/share/applications /usr/local/share/applications /home/ghost/.local/share/applications ~/.local/share/applications -name '*.desktop' 2>/dev/null | sort | uniq | head -500"]
        running: false

        stdout: StdioCollector {
          onStreamFinished: {
            console.log("Found", this.text.split('\n').length, "desktop files")
            parseAllDesktopFiles(this.text)
          }
        }
      }
    }
  }



  // Global functions
  function discoverAllApplications() {
    console.log("Starting comprehensive app discovery...")
    dropdownAppListModel.clear()
    appDiscovery.running = true
  }

  function parseAllDesktopFiles(fileList) {
    var files = fileList.trim().split("\n")
    console.log("Parsing", files.length, "desktop files...")
    
    // Process each file
    for (var i = 0; i < files.length && i < 500; i++) {
      if (files[i].length > 0) {
        parseDesktopFile(files[i])
      }
    }
  }

  function parseDesktopFile(filepath) {
    // Create a process to read each desktop file
    var reader = Qt.createQmlObject(`
      import Quickshell.Io
      Process {
        property string filepath: ""
        command: ["cat", filepath]
        running: false
        
        stdout: StdioCollector {
          onStreamFinished: {
            var content = this.text
            var lines = content.split("\\n")
            var name = ""
            var exec = ""
            var description = ""
            var icon = ""
            var iconName = ""
            var hidden = false
            var terminal = false
            
            for (var i = 0; i < lines.length; i++) {
              var line = lines[i].trim()
              if (line.startsWith("Name=") && !line.includes("[")) {
                name = line.substring(5)
              } else if (line.startsWith("Exec=")) {
                exec = line.substring(5)
              } else if (line.startsWith("Comment=") && !line.includes("[")) {
                description = line.substring(8)
              } else if (line.startsWith("Icon=")) {
                iconName = line.substring(5)
              } else if (line.startsWith("NoDisplay=true") || line.startsWith("Hidden=true")) {
                hidden = true
              } else if (line.startsWith("Terminal=true")) {
                terminal = true
              }
            }
            
            if (name && exec && !hidden) {
              // Clean up exec command
              exec = exec.replace(/%[uUfFdDnNickvm]/g, "").trim()
              
              // Use actual icon from desktop file first
              if (iconName) {
                // Try to resolve icon path
                if (iconName.startsWith("/")) {
                  // Absolute path
                  icon = "file://" + iconName
                } else {
                  // Icon name - try common icon theme paths
                  var iconPaths = [
                    "/usr/share/icons/hicolor/48x48/apps/" + iconName + ".png",
                    "/usr/share/icons/hicolor/scalable/apps/" + iconName + ".svg",
                    "/usr/share/pixmaps/" + iconName + ".png",
                    "/usr/share/pixmaps/" + iconName + ".svg",
                    "/usr/share/pixmaps/" + iconName + ".xpm",
                    "/usr/share/icons/Adwaita/48x48/apps/" + iconName + ".png"
                  ]
                  
                  // For now, we'll use a simple approach - just pass the icon name
                  // QuickShell should handle icon theme resolution
                  icon = iconName
                }
              }
              
              // Fallback to emoji icons if no icon found
              if (!icon) {
                var nameLower = name.toLowerCase()
                if (nameLower.includes("firefox") || nameLower.includes("chrome") || nameLower.includes("browser")) icon = "🌐"
                else if (nameLower.includes("terminal") || nameLower.includes("konsole") || nameLower.includes("alacritty")) icon = "💻"
                else if (nameLower.includes("file") || nameLower.includes("thunar") || nameLower.includes("nautilus")) icon = "📁"
                else if (nameLower.includes("text") || nameLower.includes("edit") || nameLower.includes("code") || nameLower.includes("vim")) icon = "📝"
                else if (nameLower.includes("music") || nameLower.includes("audio") || nameLower.includes("spotify")) icon = "🎵"
                else if (nameLower.includes("video") || nameLower.includes("vlc") || nameLower.includes("mpv")) icon = "🎬"
                else if (nameLower.includes("image") || nameLower.includes("photo") || nameLower.includes("gimp")) icon = "🖼️"
                else if (nameLower.includes("game") || nameLower.includes("steam")) icon = "🎮"
                else if (nameLower.includes("settings") || nameLower.includes("control") || nameLower.includes("config")) icon = "⚙️"
                else if (nameLower.includes("mail") || nameLower.includes("thunderbird")) icon = "📧"
                else if (nameLower.includes("chat") || nameLower.includes("discord") || nameLower.includes("telegram")) icon = "💬"
                else if (nameLower.includes("office") || nameLower.includes("writer") || nameLower.includes("calc")) icon = "📄"
                else if (nameLower.includes("calculator")) icon = "🧮"
                else if (terminal) icon = "💻"
                else icon = "📱" // Final fallback
              }
              
              dropdownAppListModel.append({
                name: name,
                description: description || "",
                exec: exec,
                icon: icon
              })
            }
            
            parent.destroy()
          }
        }
      }
    `, mainPanel, "desktopReader")
    
    reader.filepath = filepath
    reader.command = ["cat", filepath]
    reader.running = true
  }

  function launchApp(execCommand) {
    if (!execCommand) return
    
    console.log("Launching:", execCommand)
    
    // Split command and handle complex cases
    var parts = execCommand.split(" ")
    var command = parts[0]
    
    var launcher = Qt.createQmlObject(`
      import Quickshell.Io
      Process {
        command: ["${command}"]
        running: true
      }
    `, mainPanel, "appLauncher")
  }
}