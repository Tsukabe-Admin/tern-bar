import QtQuick
import Qt.labs.folderlistmodel
import "../singletons"
import "../singletons/folderpath.js" as FolderPath

// A folder chooser drawn by the bar itself, over the window it sits in: where
// you are (the full path), the folders in there (click one to go in), Up and
// Home, and a field for typing or pasting a path. Files and hidden folders
// (a name starting with ".") are not listed. Nothing changes until "Use this
// folder"; Cancel and Esc only close it.
//
//   picker.open(start)    shows it at `start`, or at the nearest folder above
//                         it that still exists, or at home
//   onChosen: (path) =>   "Use this folder" was pressed; an absolute path
//   onClosed:             it closed, chosen or not: give the keyboard back
//
// The listing is Qt's FolderListModel, so no program is run to read a folder.
FocusScope {
    id: picker

    // The home folder: the Home button, and "~" in a typed path.
    property string home: ""
    property string title: "Choose a folder"

    // Where the picker is: a folder that existed when it was entered.
    property string path: ""
    // The names of the folders in `path`, in the order the list shows them.
    property var folders: []
    // `path` was asked for and its listing has not arrived yet.
    property bool loading: false
    // `path` could not be read (no permission), so its folders are unknown.
    property bool unreadable: false
    // Why the last place asked for was not gone to.
    property string message: ""
    property bool opened: false

    signal chosen(string path)
    signal closed

    visible: opacity > 0
    opacity: picker.opened ? 1 : 0
    enabled: picker.opened

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.motionFast
            easing.type: Easing.OutCubic
        }
    }

    // Esc anywhere in the picker closes the picker, never the window under it.
    Keys.onEscapePressed: (event) => {
        event.accepted = picker.opened;
        picker.close();
    }

    function open(start) {
        const candidates = FolderPath.startCandidates(start, picker.home);
        const target = candidates.find((candidate) => picker.isFolder(candidate)) || "/";
        picker.show(target);
        // The folder in use is gone (deleted, or on a drive that is not
        // plugged in): say so rather than silently starting somewhere else.
        if (target !== candidates[0] && typeof start === "string" && start.indexOf("/") === 0)
            picker.message = "No folder at " + candidates[0];
        picker.opened = true;
        field.forceActiveFocus();
    }

    function close() {
        if (!picker.opened)
            return;
        picker.opened = false;
        picker.closed();
    }

    // What the field holds, typed or pasted: Enter, and "Use this folder"
    // with something still in the field.
    function go(text) {
        const target = FolderPath.resolve(text, picker.path, picker.home);
        return target !== "" && picker.goTo(target);
    }

    function enter(name) {
        picker.goTo(FolderPath.join(picker.path, name));
    }

    function up() {
        picker.goTo(FolderPath.parent(picker.path));
    }

    function goHome() {
        picker.goTo(FolderPath.normalize(picker.home));
    }

    function useFolder() {
        // A path typed but not yet entered is the one meant.
        if (field.text.trim() !== "" && !picker.go(field.text))
            return;
        const chosenPath = picker.path;
        picker.close();
        picker.chosen(chosenPath);
    }

    // Goes to `target` if it is a folder; otherwise says so and stays put.
    function goTo(target) {
        if (!picker.isFolder(target)) {
            picker.message = "No folder at " + target;
            return false;
        }
        picker.show(target);
        return true;
    }

    function show(target) {
        field.text = "";
        picker.message = "";
        // Asking the model for the folder it already has does nothing, so the
        // list it shows is kept as it is.
        if (target === picker.path)
            return;
        picker.path = target;
        picker.folders = [];
        picker.unreadable = false;
        picker.loading = true;
        listing.folder = FolderPath.toUrl(target);
    }

    // ── Is it a folder? ────────────────────────────────────────────────────
    // Handed something that is not a folder (missing, a file, inside a folder
    // that cannot be entered), FolderListModel gives up before the assignment
    // returns and ends the model reset it began. Handed a folder, it starts
    // reading it in the background and the reset stays open until that
    // arrives. Its `status` cannot tell the two apart at that moment (it still
    // holds the answer about the folder before); the open reset can. This model
    // is only ever asked, never shown.
    FolderListModel {
        id: checker

        property bool waiting: false

        showFiles: false
        onModelAboutToBeReset: checker.waiting = true
        onModelReset: checker.waiting = false
    }

    function isFolder(path) {
        checker.folder = "";
        checker.waiting = false;
        checker.folder = FolderPath.toUrl(path);
        const found = checker.waiting;
        // Let go of it again: the model watches the folder it is given.
        checker.folder = "";
        return found;
    }

    // ── The listing ────────────────────────────────────────────────────────
    FolderListModel {
        id: listing

        showFiles: false
        // "." is what tells an empty folder from one that cannot be read: a
        // folder that can be read always lists it, one that cannot lists
        // nothing at all. The list leaves "." and ".." out again.
        showDotAndDotDot: true

        // A folder added, renamed or removed in there while the picker is
        // open arrives through these as well.
        onStatusChanged: picker.refresh()
        onCountChanged: picker.refresh()
        onDataChanged: picker.refresh()
    }

    function refresh() {
        if (listing.status !== FolderListModel.Ready || picker.path === "")
            return;
        const names = [];
        for (let i = 0; i < listing.count; i++)
            names.push(String(listing.get(i, "fileName")));
        // The model does not say which folder a listing is of, and the one
        // for a folder left a moment ago can still arrive: it is dropped, and
        // the right one follows.
        if (names.length > 0 && String(listing.get(0, "filePath")) !== FolderPath.join(picker.path, names[0]))
            return;
        picker.unreadable = names.length === 0;
        picker.folders = FolderPath.visibleFolders(names);
        picker.loading = false;
    }

    // ── What it looks like ─────────────────────────────────────────────────
    // The page under it is dimmed and takes no clicks, hovering or scrolling
    // while the picker is up.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.card, 0.8)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onWheel: (wheel) => wheel.accepted = true
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(640, parent.width - 48)
        height: Math.min(560, parent.height - 48)
        radius: Theme.radiusCard
        color: Theme.popBg
        border.width: 1
        border.color: Theme.rim

        Text {
            textFormat: Text.PlainText
            id: titleText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            text: picker.title
            elide: Text.ElideRight
            color: Theme.t1
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
        }

        // Where you are, in full: a long path wraps rather than being cut.
        Text {
            textFormat: Text.PlainText
            id: whereText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleText.bottom
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 6
            text: picker.path
            wrapMode: Text.WrapAnywhere
            color: Theme.t2
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Chip {
            id: upChip
            anchors.left: parent.left
            anchors.top: whereText.bottom
            anchors.leftMargin: 20
            anchors.topMargin: 14
            text: "Up"
            enabled: picker.path !== "/"
            onClicked: picker.up()
        }

        Chip {
            id: homeChip
            anchors.left: upChip.right
            anchors.leftMargin: 8
            anchors.verticalCenter: upChip.verticalCenter
            text: "Home"
            enabled: picker.home.indexOf("/") === 0
            onClicked: picker.goHome()
        }

        Rectangle {
            id: fieldBox
            anchors.left: homeChip.right
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 20
            anchors.verticalCenter: upChip.verticalCenter
            height: 32
            radius: Theme.isFramed ? Theme.itemRadius : height / 2
            color: Theme.popBg
            border.width: 1
            border.color: field.activeFocus ? Theme.accent : Theme.rim

            Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: field.text === ""
                text: "Type or paste a path, then Enter"
                elide: Text.ElideRight
                color: Theme.t3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            TextInput {
                id: field
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                selectByMouse: true
                color: Theme.t1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize

                onAccepted: picker.go(field.text)
                // A message about the last path goes once you change it.
                onTextChanged: picker.message = ""
            }
        }

        Text {
            textFormat: Text.PlainText
            id: messageText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: upChip.bottom
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 10
            visible: picker.message !== ""
            text: picker.message
            wrapMode: Text.WrapAnywhere
            color: Theme.bad
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Rectangle {
            id: listBox
            anchors.left: parent.left
            anchors.right: parent.right
            // Wrapped text has no fixed height to bind to 0 when it is empty (a
            // binding loop), so the list moves up past it instead.
            anchors.top: picker.message !== "" ? messageText.bottom : upChip.bottom
            anchors.bottom: buttons.top
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 10
            anchors.bottomMargin: 16
            radius: Theme.itemRadius
            color: Qt.alpha(Theme.t1, 0.03)
            border.width: 1
            border.color: Theme.rim

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 2
                model: picker.folders

                delegate: DeviceRow {
                    required property string modelData
                    width: ListView.view.width
                    label: modelData
                    onTapped: picker.enter(modelData)
                }
            }

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                width: parent.width - 40
                visible: list.count === 0 && !picker.loading && picker.path !== ""
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: picker.unreadable
                    ? "Can't read this folder. You may not have permission to open it."
                    : "No folders in here"
                color: Theme.t2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }

        Row {
            id: buttons
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 20
            spacing: 8

            Chip {
                text: "Cancel"
                onClicked: picker.close()
            }

            // A folder that cannot be read would leave the wallpaper grid empty.
            Chip {
                text: "Use this folder"
                selected: true
                enabled: !picker.unreadable
                onClicked: picker.useFolder()
            }
        }
    }
}
