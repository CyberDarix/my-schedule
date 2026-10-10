pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Dialogs

Window {
    id: app

    width: 1440
    height: 900
    minimumWidth: 1050
    minimumHeight: 700
    visible: true
    visibility: Window.FullScreen
    title: "My Schedule"
    color: "#f5f7fb"

    readonly property color ink: "#202735"
    readonly property color secondaryInk: "#758097"
    readonly property color faintInk: "#a1a9b8"
    readonly property color line: "#edf0f5"
    readonly property color blue: "#5278ed"
    readonly property color paleBlue: "#edf2ff"
    readonly property int hourHeight: 72

    property date selectedDate: new Date()
    property date displayedMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property bool dayView: false
    property bool sidebarOpen: true
    property bool eventDialogOpen: false
    property bool settingsOpen: false
    property bool clockOpen: false
    property bool clockClosing: false
    property date clockNow: new Date()
    property bool notesLibraryOpen: false
    property bool notesLibraryClosing: false
    property bool noteEditorOpen: false
    property bool noteEditorClosing: false
    property string activeNoteId: ""
    property string noteDraftTitle: ""
    property string noteDraftHtml: ""
    property string noteStatusMessage: ""
    property bool noteStatusError: false
    property bool notePaletteOpen: false
    property string notePaletteTarget: "color"
    property bool noteLinkDialogOpen: false
    property string noteLinkDraft: ""
    property string noteLinkSelection: ""
    property int noteLinkSelectionStart: 0
    property int noteLinkSelectionEnd: 0
    property var savedNotes: []
    property bool noteDeleteDialogOpen: false
    property string pendingNoteDeleteId: ""
    property bool dialogForTask: false
    property int wallpaperPreset: -1
    property string wallpaperImage: ""
    property bool restoringAppData: false
    property string storageError: ""
    property string reminderMessage: ""
    property string lastReminderKey: ""
    property int editingAppointmentIndex: -1
    property bool contextMenuOpen: false
    property int contextMenuX: 0
    property int contextMenuY: 0
    property int contextAppointmentIndex: -1
    property string eventTitle: ""
    property int eventStartMinute: 570
    property int currentMinute: new Date().getHours() * 60 + new Date().getMinutes()
    property var appointments: []
    property var taskList: []
    property var agendaStorage: null
    property var notesStorage: agendaStorage

    readonly property bool wallpaperActive: wallpaperPreset >= 0 || wallpaperImage.length > 0

    onAppointmentsChanged: saveAppData()
    onTaskListChanged: saveAppData()
    onWallpaperPresetChanged: saveAppData()
    onWallpaperImageChanged: saveAppData()
    onDayViewChanged: saveAppData()
    onSidebarOpenChanged: saveAppData()
    onSelectedDateChanged: saveAppData()

    Shortcut {
        sequence: "Ctrl+,"
        context: Qt.WindowShortcut
        onActivated: app.settingsOpen = true
    }

    Shortcut {
        sequence: "Ctrl+N"
        context: Qt.WindowShortcut
        onActivated: {
            if (app.settingsOpen)
                return
            app.dialogForTask = false
            app.editingAppointmentIndex = -1
            app.eventTitle = ""
            app.eventStartMinute = 570
            app.eventDialogOpen = true
        }
    }

    Shortcut {
        sequence: "Ctrl+T"
        context: Qt.WindowShortcut
        onActivated: {
            if (app.settingsOpen)
                return
            app.dialogForTask = true
            app.editingAppointmentIndex = -1
            app.eventTitle = ""
            app.eventDialogOpen = true
        }
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: {
            if (app.eventDialogOpen) {
                app.eventDialogOpen = false
                app.editingAppointmentIndex = -1
            } else if (app.contextMenuOpen) {
                app.contextMenuOpen = false
            } else if (app.clockOpen) {
                app.closeClock()
            } else {
                app.settingsOpen = false
            }
        }
    }

    FileDialog {
        id: wallpaperFileDialog
        title: "Choose a background image"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Images (*.png *.jpg *.jpeg *.bmp *.webp)"]
        onAccepted: {
            var imageUrl = app.agendaStorage.copyImage(selectedFile)
            if (imageUrl.length) {
                app.wallpaperImage = imageUrl
                app.wallpaperPreset = -1
                app.storageError = ""
            } else {
                app.storageError = app.agendaStorage.lastError
            }
        }
    }

    FileDialog {
        id: noteImageDialog
        title: "Insert an image into the note"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Images (*.png *.jpg *.jpeg *.bmp *.webp *.gif)"]
        onAccepted: {
            var imageUrl = app.notesStorage.copyImage(selectedFile)
            if (imageUrl.length) {
                app.noteStatusError = false
                noteEditor.insert(noteEditor.cursorPosition,
                                  "<br><img src=\"" + imageUrl + "\" width=\""
                                  + Math.max(180, Math.min(640, noteEditor.width - 16)) + "\"/><br>")
                app.noteStatusMessage = "Image inserted"
            } else {
                app.noteStatusMessage = app.notesStorage.lastError
                app.noteStatusError = true
            }
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            var now = new Date()
            app.currentMinute = now.getHours() * 60 + now.getMinutes()
            app.checkUpcomingReminder(now)
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: app.clockOpen
        onTriggered: app.clockNow = new Date()
    }

    Timer {
        id: clockCloseTimer
        interval: 190
        onTriggered: {
            app.clockOpen = false
            app.clockClosing = false
        }
    }

    Timer {
        id: noteEditorCloseTimer
        interval: 190
        onTriggered: {
            app.noteEditorOpen = false
            app.noteEditorClosing = false
            if (app.notesLibraryOpen) {
                notesLibraryWindow.raise()
                notesLibraryWindow.requestActivate()
            }
        }
    }

    Timer {
        id: notesLibraryCloseTimer
        interval: 180
        onTriggered: {
            app.notesLibraryOpen = false
            app.notesLibraryClosing = false
        }
    }

    function pad(number) {
        return number < 10 ? "0" + number : "" + number
    }

    function dateKey(value) {
        return value.getFullYear() + "-" + pad(value.getMonth() + 1) + "-" + pad(value.getDate())
    }

    function dayStart(value) {
        return new Date(value.getFullYear(), value.getMonth(), value.getDate())
    }

    function mondayOf(value) {
        var date = dayStart(value)
        date.setDate(date.getDate() - ((date.getDay() + 6) % 7))
        return date
    }

    function weekDates() {
        var dates = []
        var start = mondayOf(selectedDate)
        var count = dayView ? 1 : 7
        for (var i = 0; i < count; ++i) {
            var date = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
            dates.push(date)
        }
        if (dayView)
            dates[0] = dayStart(selectedDate)
        return dates
    }

    function monthDates() {
        var first = new Date(displayedMonth.getFullYear(), displayedMonth.getMonth(), 1)
        var firstMonday = new Date(first.getFullYear(), first.getMonth(), 1)
        firstMonday.setDate(firstMonday.getDate() - ((firstMonday.getDay() + 6) % 7))
        var dates = []
        for (var i = 0; i < 42; ++i)
            dates.push(new Date(firstMonday.getFullYear(), firstMonday.getMonth(), firstMonday.getDate() + i))
        return dates
    }

    function monthName(value) {
        return Qt.locale("en_US").toString(value, "MMMM yyyy")
    }

    function longDate(value) {
        var result = Qt.locale("en_US").toString(value, "dddd, MMMM d")
        return result.length ? result.charAt(0).toUpperCase() + result.slice(1) : result
    }

    function changeSelectedDay(amount) {
        var updated = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate() + amount)
        selectedDate = updated
        displayedMonth = new Date(updated.getFullYear(), updated.getMonth(), 1)
    }

    function closeClock() {
        if (!clockOpen || clockClosing)
            return
        clockClosing = true
        clockCloseTimer.restart()
    }

    function shiftMonth(amount) {
        displayedMonth = new Date(displayedMonth.getFullYear(), displayedMonth.getMonth() + amount, 1)
    }

    function pickDate(value) {
        selectedDate = dayStart(value)
        displayedMonth = new Date(value.getFullYear(), value.getMonth(), 1)
    }

    function saveAppData() {
        if (restoringAppData || !agendaStorage)
            return
        var saved = agendaStorage.saveAgendaState({
            appointments: appointments,
            tasks: taskList,
            wallpaperPreset: wallpaperPreset,
            wallpaperImage: wallpaperImage,
            dayView: dayView,
            sidebarOpen: sidebarOpen,
            selectedDate: dateKey(selectedDate)
        })
        storageError = saved ? "" : agendaStorage.lastError
    }

    function checkUpcomingReminder(now) {
        var today = dateKey(now)
        var minute = now.getHours() * 60 + now.getMinutes()
        for (var i = 0; i < appointments.length; ++i) {
            var appointment = appointments[i]
            var minutesUntil = appointment.startMinute - minute
            var reminderKey = appointment.date + "|" + appointment.startMinute + "|" + appointment.title
            if (appointment.date === today && minutesUntil >= 0 && minutesUntil <= 10
                    && reminderKey !== lastReminderKey) {
                lastReminderKey = reminderKey
                reminderMessage = minutesUntil === 0
                        ? "It's time: " + appointment.title
                        : "In " + minutesUntil + " min: " + appointment.title
                return
            }
        }
    }

    function restoreAppData() {
        if (!agendaStorage)
            return

        restoringAppData = true
        var state = agendaStorage.loadAgendaState()
        if (agendaStorage.lastError.length) {
            storageError = agendaStorage.lastError
        } else if (Object.keys(state).length) {
            appointments = Array.isArray(state.appointments) ? state.appointments : []
            taskList = Array.isArray(state.tasks) ? state.tasks : []
            wallpaperPreset = Number.isInteger(state.wallpaperPreset) ? state.wallpaperPreset : -1
            wallpaperImage = typeof state.wallpaperImage === "string" ? state.wallpaperImage : ""
            dayView = state.dayView === true
            sidebarOpen = state.sidebarOpen !== false
            if (typeof state.selectedDate === "string") {
                var parts = state.selectedDate.split("-")
                if (parts.length === 3) {
                    var restoredDate = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
                    if (!isNaN(restoredDate.getTime())) {
                        selectedDate = dayStart(restoredDate)
                        displayedMonth = new Date(restoredDate.getFullYear(), restoredDate.getMonth(), 1)
                    }
                }
            }
        }
        restoringAppData = false
        if (!agendaStorage.lastError.length) {
            saveAppData()
            checkUpcomingReminder(new Date())
        }
    }

    function addAppointment() {
        var cleanTitle = eventTitle.trim()
        if (!cleanTitle)
            return
        if (dialogForTask) {
            taskList = taskList.concat([{
                id: Date.now() + Math.floor(Math.random() * 1000000),
                name: cleanTitle,
                done: false,
                color: "#6785ed"
            }])
            eventTitle = ""
            eventDialogOpen = false
            editingAppointmentIndex = -1
            return
        }
        if (editingAppointmentIndex >= 0 && editingAppointmentIndex < appointments.length) {
            var updatedAppointments = appointments.slice()
            var existing = updatedAppointments[editingAppointmentIndex]
            updatedAppointments[editingAppointmentIndex] = {
                id: existing.id,
                title: cleanTitle,
                date: dateKey(selectedDate),
                startMinute: eventStartMinute,
                duration: existing.duration,
                color: existing.color,
                accent: existing.accent
            }
            appointments = updatedAppointments
            editingAppointmentIndex = -1
            eventTitle = ""
            eventDialogOpen = false
            return
        }
        var colorSet = [
            { background: "#e8eeff", accent: "#5576e8" },
            { background: "#e7f5ef", accent: "#399374" },
            { background: "#fff2df", accent: "#d48b39" },
            { background: "#f3eafb", accent: "#9668c1" }
        ]
        var palette = colorSet[appointments.length % colorSet.length]
        appointments = appointments.concat([{
            id: Date.now() + Math.floor(Math.random() * 1000000),
            title: cleanTitle,
            date: dateKey(selectedDate),
            startMinute: eventStartMinute,
            duration: 60,
            color: palette.background,
            accent: palette.accent
        }])
        eventTitle = ""
        eventDialogOpen = false
    }

    function openAppointmentMenu(index, x, y) {
        contextAppointmentIndex = index
        contextMenuX = x
        contextMenuY = y
        contextMenuOpen = true
    }

    function editAppointment(index) {
        if (index < 0 || index >= appointments.length)
            return
        var appointment = appointments[index]
        var dateParts = appointment.date.split("-")
        selectedDate = new Date(Number(dateParts[0]), Number(dateParts[1]) - 1, Number(dateParts[2]))
        displayedMonth = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1)
        editingAppointmentIndex = index
        dialogForTask = false
        eventTitle = appointment.title
        eventStartMinute = appointment.startMinute
        contextMenuOpen = false
        eventDialogOpen = true
    }

    function deleteAppointment(index) {
        if (index < 0 || index >= appointments.length)
            return
        var updatedAppointments = appointments.slice()
        updatedAppointments.splice(index, 1)
        appointments = updatedAppointments
        contextMenuOpen = false
        contextAppointmentIndex = -1
    }

    function timeString(value) {
        return pad(Math.floor(value / 60)) + ":" + pad(value % 60)
    }

    function upcomingSummary() {
        var today = dateKey(new Date())
        var now = new Date()
        var minute = now.getHours() * 60 + now.getMinutes()
        var upcoming = appointments.filter(function(item) {
            return item.date > today || (item.date === today && item.startMinute >= minute)
        }).slice().sort(function(a, b) {
            return a.date === b.date ? a.startMinute - b.startMinute : a.date.localeCompare(b.date)
        })
        var nextAppointment = upcoming.length ? upcoming[0] : null
        var openTasks = taskList.filter(function(task) { return !task.done }).length
        if (!nextAppointment && !openTasks)
            return "Nothing planned yet"
        if (!nextAppointment)
            return openTasks + (openTasks === 1 ? " task to do" : " tasks to do")
        var nextDate = nextAppointment.date === today ? "today" : nextAppointment.date
        var summary = "Next event " + nextDate + " at " + timeString(nextAppointment.startMinute)
        if (openTasks)
            summary += " · " + openTasks + (openTasks === 1 ? " task" : " tasks")
        return summary
    }

    function refreshNotes() {
        savedNotes = notesStorage.loadNotes()
        if (notesStorage.lastError.length)
            noteStatusMessage = notesStorage.lastError
        noteStatusError = notesStorage.lastError.length > 0
    }

    function openNewNote() {
        activeNoteId = "note-" + Date.now() + "-" + Math.floor(Math.random() * 1000000)
        noteDraftTitle = ""
        noteDraftHtml = ""
        noteStatusMessage = ""
        noteStatusError = false
        noteEditorClosing = false
        noteEditorCloseTimer.stop()
        notePaletteOpen = false
        noteLinkDialogOpen = false
        noteEditor.text = ""
        noteTitleInput.text = ""
        notesLibraryClosing = false
        notesLibraryCloseTimer.stop()
        notesLibraryOpen = false
        noteEditorOpen = true
        noteEditorWindow.raise()
        noteEditorWindow.requestActivate()
    }

    function openSavedNote(note) {
        activeNoteId = note.id
        noteDraftTitle = note.title || ""
        noteDraftHtml = note.html || ""
        noteStatusMessage = ""
        noteStatusError = false
        noteEditorClosing = false
        noteEditorCloseTimer.stop()
        notePaletteOpen = false
        noteLinkDialogOpen = false
        noteEditor.text = noteDraftHtml
        noteTitleInput.text = noteDraftTitle
        notesLibraryClosing = false
        notesLibraryCloseTimer.stop()
        notesLibraryOpen = false
        noteEditorOpen = true
        noteEditorWindow.raise()
        noteEditorWindow.requestActivate()
    }

    function saveCurrentNote() {
        var html = noteEditor.text
        var plain = html.replace(/<[^>]*>/g, " ").replace(/&nbsp;/g, " ").trim()
        var cleanTitle = noteDraftTitle.trim()
        if (!plain.length && !/<img\b/i.test(html) && !cleanTitle.length) {
            noteStatusMessage = "Write something before saving."
            noteStatusError = true
            noteEditor.forceActiveFocus()
            return
        }

        if (!cleanTitle)
            cleanTitle = "Note from " + Qt.locale("en_US").toString(new Date(), "MMM d, yyyy · HH:mm")

        var saved = notesStorage.saveNote({
            id: activeNoteId,
            title: cleanTitle,
            html: html,
            updated: new Date().toISOString()
        })
        if (!saved) {
            noteStatusMessage = notesStorage.lastError
            noteStatusError = true
            return
        }

        noteDraftTitle = cleanTitle
        noteDraftHtml = noteEditor.text
        noteStatusMessage = "Note saved"
        noteStatusError = false
        refreshNotes()
        notesLibraryOpen = true
        closeNoteEditor()
    }

    function closeNoteEditor() {
        if (!noteEditorOpen || noteEditorClosing)
            return
        notePaletteOpen = false
        noteLinkDialogOpen = false
        noteEditorClosing = true
        noteEditorCloseTimer.restart()
    }

    function deleteSavedNote(noteId) {
        if (!notesStorage.deleteNote(noteId)) {
            noteStatusMessage = notesStorage.lastError
            noteStatusError = true
            return
        }
        refreshNotes()
        noteStatusMessage = ""
        noteStatusError = false
    }

    function requestDeleteNote(noteId) {
        pendingNoteDeleteId = noteId
        noteDeleteDialogOpen = true
    }

    function confirmDeleteNote() {
        noteDeleteDialogOpen = false
        deleteSavedNote(pendingNoteDeleteId)
        pendingNoteDeleteId = ""
    }

    function escapeHtml(value) {
        return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function replaceNoteSelection(replacement, emptyCursorOffset) {
        var start = noteEditor.selectionStart
        var end = noteEditor.selectionEnd
        var selected = noteEditor.selectedText
        var result = replacement(selected)
        noteEditor.remove(start, end)
        noteEditor.insert(start, result)
        noteEditor.cursorPosition = start + (selected.length ? result.length
                                                              : (emptyCursorOffset === undefined
                                                                 ? result.indexOf(">") + 1
                                                                 : emptyCursorOffset))
        noteEditor.forceActiveFocus()
    }

    function formatNoteSelection(openTag, closeTag) {
        replaceNoteSelection(function(selected) {
            return openTag + (selected.length ? escapeHtml(selected) : "") + closeTag
        }, openTag.length)
    }

    function formatNoteList(ordered) {
        replaceNoteSelection(function(selected) {
            var items = selected.split(/\r?\n/).filter(function(line) { return line.length > 0 })
            if (!items.length)
                items = [""]
            var tag = ordered ? "ol" : "ul"
            return "<" + tag + ">" + items.map(function(line) {
                return "<li>" + escapeHtml(line) + "</li>"
            }).join("") + "</" + tag + ">"
        }, 8)
    }

    function alignNoteSelection(alignment) {
        formatNoteSelection('<div style="text-align:' + alignment + '">', "</div>")
    }

    function applyNoteColor(color) {
        if (notePaletteTarget === "highlight")
            formatNoteSelection('<span style="background-color:' + color + '">', "</span>")
        else
            formatNoteSelection('<span style="color:' + color + '">', "</span>")
        notePaletteOpen = false
    }

    function insertNoteLink() {
        var url = noteLinkDraft.trim()
        if (!url.length) {
            noteStatusMessage = "Enter a link address."
            noteStatusError = true
            return
        }
        if (/^(javascript|data|vbscript):/i.test(url)) {
            noteStatusMessage = "This type of address is not allowed."
            noteStatusError = true
            return
        }
        if (/^[a-z][a-z0-9+.-]*:/i.test(url) && !/^(https?|mailto|tel):/i.test(url)) {
            noteStatusMessage = "Use an http, https, mailto, or tel link."
            noteStatusError = true
            return
        }
        var safeUrl = url.replace(/&/g, "&amp;").replace(/"/g, "&quot;")
                          .replace(/</g, "&lt;").replace(/>/g, "&gt;")
        var label = noteLinkSelection.length ? escapeHtml(noteLinkSelection) : escapeHtml(url)
        var start = noteLinkSelectionStart
        var end = noteLinkSelectionEnd
        noteEditor.remove(start, end)
        var html = '<a href="' + safeUrl + '" style="color:#5278ed;text-decoration:underline">' + label + "</a>"
        noteEditor.insert(start, html)
        noteEditor.cursorPosition = start + html.length
        noteEditor.forceActiveFocus()
        noteLinkDialogOpen = false
        noteStatusMessage = ""
        noteStatusError = false
    }

    function noteWordCount() {
        var plain = noteEditor.text.replace(/<[^>]*>/g, " ").replace(/&nbsp;/g, " ").trim()
        return plain.length ? plain.split(/\s+/).length : 0
    }

    function notePreview(html) {
        var plain = (html || "")
        plain = plain.replace(/<!--[\s\S]*?-->/g, "")
        plain = plain.replace(/<(style|script|head)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, " ")
        plain = plain.replace(/<br\s*\/?\s*>/gi, "\n")
        plain = plain.replace(/<\/(p|div|li|h[1-6]|tr|blockquote)\s*>/gi, "\n")
        plain = plain.replace(/<img\b[^>]*>/gi, " [image] ")
        plain = plain.replace(/<[^>]*>/g, " ")
        plain = plain.replace(/&#x([0-9a-f]+);/gi, function(match, code) {
            return String.fromCharCode(parseInt(code, 16))
        })
        plain = plain.replace(/&#([0-9]+);/g, function(match, code) {
            return String.fromCharCode(parseInt(code, 10))
        })
        plain = plain.replace(/&nbsp;|&#160;/gi, " ")
        plain = plain.replace(/&amp;/gi, "&").replace(/&lt;/gi, "<")
                     .replace(/&gt;/gi, ">").replace(/&quot;/gi, '"')
                     .replace(/&apos;|&#39;/gi, "'")
        plain = plain.replace(/[ \t]+\n/g, "\n").replace(/\n{2,}/g, "\n")
        return plain.trim()
    }

    Item {
        id: wallpaperLayer
        anchors.fill: parent
        z: 0

        Canvas {
            id: landscapeBackground
            anchors.fill: parent
            opacity: app.wallpaperPreset >= 0 && app.wallpaperImage.length === 0 ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 220 }
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            Connections {
                target: app
                function onWallpaperPresetChanged() {
                    landscapeBackground.requestPaint()
                }
            }

            onPaint: {
                var context = getContext("2d")
                var palettes = [
                    { skyTop: "#dceeff", skyBottom: "#f8fafc", sun: "#fff0ca", far: "#b8cbd5", mid: "#829fa7", near: "#66847c" },
                    { skyTop: "#d9eee7", skyBottom: "#f6f8f2", sun: "#fff3d6", far: "#a9c6ac", mid: "#779b83", near: "#587564" },
                    { skyTop: "#cce8f6", skyBottom: "#f5fafb", sun: "#fff5dc", far: "#a3c7d5", mid: "#75a8b6", near: "#568b98" },
                    { skyTop: "#f7dfc6", skyBottom: "#fcf6ed", sun: "#ffedc2", far: "#d9bb9f", mid: "#b99b7e", near: "#8f977c" }
                ]
                var palette = palettes[Math.max(0, app.wallpaperPreset) % palettes.length]
                var sky = context.createLinearGradient(0, 0, 0, height)
                sky.addColorStop(0, palette.skyTop)
                sky.addColorStop(1, palette.skyBottom)
                context.fillStyle = sky
                context.fillRect(0, 0, width, height)

                context.beginPath()
                context.arc(width * 0.78, height * 0.22, Math.min(width, height) * 0.055, 0, Math.PI * 2)
                context.fillStyle = palette.sun
                context.fill()

                context.beginPath()
                context.moveTo(0, height * 0.67)
                context.quadraticCurveTo(width * 0.16, height * 0.45, width * 0.31, height * 0.66)
                context.quadraticCurveTo(width * 0.49, height * 0.4, width * 0.67, height * 0.65)
                context.quadraticCurveTo(width * 0.86, height * 0.46, width, height * 0.64)
                context.lineTo(width, height)
                context.lineTo(0, height)
                context.closePath()
                context.fillStyle = palette.far
                context.fill()

                context.beginPath()
                context.moveTo(0, height * 0.78)
                context.quadraticCurveTo(width * 0.25, height * 0.58, width * 0.48, height * 0.79)
                context.quadraticCurveTo(width * 0.76, height * 0.57, width, height * 0.77)
                context.lineTo(width, height)
                context.lineTo(0, height)
                context.closePath()
                context.fillStyle = palette.mid
                context.fill()

                context.beginPath()
                context.moveTo(0, height * 0.88)
                context.quadraticCurveTo(width * 0.2, height * 0.74, width * 0.43, height * 0.9)
                context.quadraticCurveTo(width * 0.7, height * 0.72, width, height * 0.88)
                context.lineTo(width, height)
                context.lineTo(0, height)
                context.closePath()
                context.fillStyle = palette.near
                context.fill()
            }
        }

        Image {
            anchors.fill: parent
            opacity: app.wallpaperImage.length > 0 ? 1 : 0
            source: app.wallpaperImage
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false

            Behavior on opacity {
                NumberAnimation { duration: 220 }
            }
        }
    }

    Rectangle {
        id: calendarSurface
        anchors.fill: parent
        anchors.margins: 0
        z: 1
        color: "transparent"

        Row {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                id: sidebar
                width: app.sidebarOpen ? 300 : 0
                height: parent.height
                clip: true
                enabled: app.sidebarOpen
                color: app.wallpaperActive ? "#b8fbfcfe" : "#fbfcfe"
                border.color: "#e9edf4"
                border.width: 1
                Behavior on width {
                    NumberAnimation { duration: 260; easing.type: Easing.InOutCubic }
                }
                Behavior on color {
                    ColorAnimation { duration: 220 }
                }

                Column {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    anchors.topMargin: 24
                    spacing: 22
                    opacity: app.sidebarOpen ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    Column {
                        width: parent.width
                        spacing: 15

                        Row {
                            width: parent.width
                            height: 26
                            spacing: 8

                            Text {
                                width: parent.width - 68
                                text: app.monthName(app.displayedMonth)
                                color: app.ink
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Rectangle {
                                width: 26
                                height: 30
                                radius: 8
                                color: "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "‹"
                                    color: app.secondaryInk
                                    font.pixelSize: 23
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: app.shiftMonth(-1)
                                }
                            }

                            Rectangle {
                                width: 26
                                height: 30
                                radius: 8
                                color: "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "›"
                                    color: app.secondaryInk
                                    font.pixelSize: 23
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: app.shiftMonth(1)
                                }
                            }
                        }

                        Grid {
                            width: parent.width
                            columns: 7
                            spacing: 0

                            Repeater {
                                model: ["M", "T", "W", "T", "F", "S", "S"]
                                delegate: Item {
                                    required property string modelData
                                    width: parent.width / 7
                                    height: 27
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        color: app.faintInk
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Repeater {
                                model: app.monthDates()
                                delegate: Rectangle {
                                    id: miniCell
                                    required property var modelData
                                    width: parent.width / 7
                                    height: 34
                                    radius: 10
                                    color: app.dateKey(modelData) === app.dateKey(app.selectedDate)
                                           ? app.paleBlue : "transparent"
                                    Behavior on color {
                                        ColorAnimation { duration: 180 }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: miniCell.modelData.getDate()
                                        color: miniCell.modelData.getMonth() !== app.displayedMonth.getMonth()
                                               || miniCell.modelData.getFullYear() !== app.displayedMonth.getFullYear()
                                               ? "#c2c8d2"
                                               : (app.dateKey(miniCell.modelData) === app.dateKey(app.selectedDate)
                                                  ? app.blue : app.ink)
                                        font.pixelSize: 12
                                        font.weight: app.dateKey(miniCell.modelData) === app.dateKey(app.selectedDate)
                                                     ? Font.DemiBold : Font.Normal
                                    }

                                    Rectangle {
                                        width: 4
                                        height: 4
                                        radius: 2
                                        color: "#55ad91"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 2
                                        visible: app.appointments.some(function(event) {
                                            return event.date === app.dateKey(miniCell.modelData)
                                        })
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: app.pickDate(miniCell.modelData)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: app.line
                    }

                    Column {
                        width: parent.width
                        spacing: 13

                        Row {
                            width: parent.width
                            height: 22

                            Text {
                                text: "My tasks"
                                color: app.ink
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Item { width: parent.width - 105; height: 1 }

                            Rectangle {
                                width: 30
                                height: 30
                                radius: 8
                                color: "#eff3ff"
                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: app.blue
                                    font.pixelSize: 20
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        app.editingAppointmentIndex = -1
                                        app.dialogForTask = true
                                        app.eventTitle = ""
                                        app.eventStartMinute = 570
                                        app.eventDialogOpen = true
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: app.upcomingSummary()
                            color: app.secondaryInk
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Repeater {
                            model: app.taskList.map(function(task, index) {
                                return { task: task, sourceIndex: index }
                            }).filter(function(entry) {
                                return !entry.task.done
                            })
                            delegate: Row {
                                id: taskRow
                                required property int index
                                required property var modelData
                                width: parent.width
                                height: 36
                                spacing: 12

                                Rectangle {
                                    width: 19
                                    height: 19
                                    radius: 6
                                    color: "#ffffff"
                                    border.color: "#d8deea"
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        visible: false
                                        text: ""
                                        color: "#399374"
                                        font.pixelSize: 12
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var updated = app.taskList.slice()
                                            var sourceIndex = taskRow.modelData.sourceIndex
                                            var task = taskRow.modelData.task
                                            updated[sourceIndex] = {
                                                id: task.id,
                                                name: task.name,
                                                done: true,
                                                color: task.color
                                            }
                                            app.taskList = updated
                                        }
                                    }
                                }

                                Text {
                                    width: parent.width - 38
                                    text: taskRow.modelData.task.name
                                    color: "#4b566a"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.strikeout: false
                                }
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width - sidebar.width
                height: parent.height
                spacing: 0

                Rectangle {
                    width: parent.width
                    height: 72
                    color: app.wallpaperActive ? "#d9ffffff" : "#ffffff"
                    border.color: app.line
                    border.width: 1
                    Behavior on color {
                        ColorAnimation { duration: 220 }
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 28
                        anchors.rightMargin: 28
                        spacing: 12

                        Rectangle {
                            id: sidebarToggleButton
                            width: 38
                            height: 36
                            radius: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: sidebarToggleMouse.containsMouse ? app.paleBlue : "transparent"
                            Accessible.name: app.sidebarOpen ? "Hide sidebar"
                                                              : "Show sidebar"
                            Behavior on color {
                                ColorAnimation { duration: 140 }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        required property int index
                                        width: 17
                                        height: 2
                                        radius: 1
                                        color: app.sidebarOpen ? app.secondaryInk : app.blue
                                    }
                                }
                            }

                            MouseArea {
                                id: sidebarToggleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.sidebarOpen = !app.sidebarOpen
                            }
                        }

                        Rectangle {
                            width: 88
                            height: 36
                            radius: 10
                            color: "#ffffff"
                            border.color: "#e4e8f0"
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                anchors.centerIn: parent
                                text: "Today"
                                color: app.ink
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    app.selectedDate = new Date()
                                    app.displayedMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1)
                                }
                            }
                        }

                        Row {
                            height: parent.height
                            spacing: 2

                            Repeater {
                                model: [
                                    { symbol: "‹", direction: -1 },
                                    { symbol: "›", direction: 1 }
                                ]
                                delegate: Rectangle {
                                    id: arrowButton
                                    required property var modelData
                                    width: 32
                                    height: 36
                                    radius: 9
                                    color: "transparent"
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        text: arrowButton.modelData.symbol
                                        color: app.secondaryInk
                                        font.pixelSize: 24
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: app.changeSelectedDay(arrowButton.modelData.direction * (app.dayView ? 1 : 7))
                                    }
                                }
                            }
                        }

                        Text {
                            text: app.dayView ? app.longDate(app.selectedDate) : app.monthName(app.selectedDate)
                            color: app.ink
                            font.pixelSize: 19
                            font.weight: Font.DemiBold
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Item {
                            width: Math.max(0, parent.width - 38 - 88 - 66 - 150 - 129 - 144 - 72)
                            height: 1
                        }

                        Row {
                            width: 129
                            height: 34
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Repeater {
                                model: [
                                    { text: "Day", isDay: true },
                                    { text: "Week", isDay: false }
                                ]
                                delegate: Rectangle {
                                    id: viewButton
                                    required property var modelData
                                    width: 63
                                    height: 32
                                    radius: 9
                                    color: app.dayView === viewButton.modelData.isDay ? app.paleBlue : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: viewButton.modelData.text
                                        color: app.dayView === viewButton.modelData.isDay ? app.blue : app.secondaryInk
                                        font.pixelSize: 12
                                        font.weight: app.dayView === viewButton.modelData.isDay ? Font.DemiBold : Font.Normal
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: app.dayView = viewButton.modelData.isDay
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: 40
                            height: 36
                            radius: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: app.notesLibraryOpen ? "#fff5cf" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "💡"
                                font.pixelSize: 18
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    app.refreshNotes()
                                    app.notesLibraryClosing = false
                                    notesLibraryCloseTimer.stop()
                                    app.notesLibraryOpen = true
                                    notesLibraryWindow.raise()
                                    notesLibraryWindow.requestActivate()
                                }
                            }
                        }

                        Rectangle {
                            id: clockButton
                            width: 40
                            height: 36
                            radius: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: app.clockOpen ? app.paleBlue : "transparent"
                            Accessible.name: "Open clock"

                            Text {
                                anchors.centerIn: parent
                                text: "◷"
                                color: app.clockOpen ? app.blue : app.secondaryInk
                                font.pixelSize: 22
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    app.clockNow = new Date()
                                    app.clockClosing = false
                                    app.clockOpen = true
                                    clockWindow.raise()
                                    clockWindow.requestActivate()
                                }
                            }
                        }

                        Rectangle {
                            width: 40
                            height: 36
                            radius: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: app.settingsOpen ? app.paleBlue : "transparent"
                            border.color: app.settingsOpen ? "#dce5ff" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "⚙"
                                color: app.settingsOpen ? app.blue : app.secondaryInk
                                font.pixelSize: 19
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.settingsOpen = true
                            }
                        }

                    }
                }

                Column {
                    width: parent.width
                    height: parent.height - 72
                    spacing: 0

                    Item {
                        width: parent.width
                        height: 84

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 28
                            anchors.rightMargin: 28
                            spacing: 12

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                Text {
                                    text: app.dayView ? "Day view" : "Your week"
                                    color: app.ink
                                    font.pixelSize: 22
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    text: app.longDate(app.selectedDate)
                                    color: app.secondaryInk
                                    font.pixelSize: 13
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: app.line
                    }

                    Row {
                        id: weekdayHeader
                        width: parent.width
                        height: 68
                        spacing: 0

                        Item {
                            width: 57
                            height: parent.height
                            Text {
                                anchors.centerIn: parent
                                text: "GMT"
                                color: app.faintInk
                                font.pixelSize: 10
                            }
                        }

                        Repeater {
                            model: app.weekDates()
                            delegate: Rectangle {
                                id: weekdayCell
                                required property var modelData
                                width: (parent.width - 57) / (app.dayView ? 1 : 7)
                                height: parent.height
                                color: "transparent"

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Qt.locale("en_US").toString(weekdayCell.modelData, "ddd").toUpperCase()
                                        color: app.dateKey(weekdayCell.modelData) === app.dateKey(app.selectedDate)
                                               ? app.blue : app.secondaryInk
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    Rectangle {
                                        width: 36
                                        height: 36
                                        radius: 11
                                        color: app.dateKey(weekdayCell.modelData) === app.dateKey(app.selectedDate)
                                               ? app.blue : "transparent"
                                        Behavior on color {
                                            ColorAnimation { duration: 180 }
                                        }
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        Text {
                                            anchors.centerIn: parent
                                            text: weekdayCell.modelData.getDate()
                                            color: app.dateKey(weekdayCell.modelData) === app.dateKey(app.selectedDate)
                                                   ? "#ffffff" : app.ink
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: app.pickDate(weekdayCell.modelData)
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: app.line
                    }

                    Flickable {
                        id: scheduleScroll
                        width: parent.width
                        height: parent.height - 154
                        clip: true
                        contentWidth: width
                        contentHeight: 10 * app.hourHeight + 22
                        boundsBehavior: Flickable.StopAtBounds

                        Item {
                            width: scheduleScroll.width
                            height: scheduleScroll.contentHeight

                            Column {
                                id: hourLabels
                                x: 0
                                y: 0
                                width: 57
                                height: parent.height
                                Repeater {
                                    model: 10
                                    delegate: Item {
                                        id: hourSlot
                                        required property int index
                                        width: parent.width
                                        height: app.hourHeight
                                        Text {
                                            anchors.top: parent.top
                                            anchors.topMargin: -6
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: app.pad(hourSlot.index + 8) + ":00"
                                            color: app.faintInk
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                            }

                            Item {
                                id: scheduleGrid
                                x: 57
                                y: 0
                                width: parent.width - 57
                                height: parent.height

                                Repeater {
                                    model: app.weekDates()
                                    delegate: Rectangle {
                                        id: scheduleDay
                                        required property var modelData
                                        required property int index
                                        x: scheduleDay.index * (scheduleGrid.width / (app.dayView ? 1 : 7))
                                        y: 0
                                        width: scheduleGrid.width / (app.dayView ? 1 : 7)
                                        height: scheduleGrid.height
                                        color: app.dateKey(modelData) === app.dateKey(new Date())
                                               ? (app.wallpaperActive ? "#aafbfcff" : "#fbfcff")
                                               : (app.wallpaperActive ? "#8cffffff" : "#ffffff")
                                        border.color: app.line
                                        border.width: 1
                                        Behavior on color {
                                            ColorAnimation { duration: 220 }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onDoubleClicked: {
                                                app.pickDate(scheduleDay.modelData)
                                                app.editingAppointmentIndex = -1
                                                app.dialogForTask = false
                                                app.eventStartMinute = 570
                                                app.eventTitle = ""
                                                app.eventDialogOpen = true
                                            }
                                        }
                                    }
                                }

                                Repeater {
                                    model: 11
                                    delegate: Rectangle {
                                        required property int index
                                        x: 0
                                        y: index * app.hourHeight
                                        width: scheduleGrid.width
                                        height: 1
                                        color: app.line
                                    }
                                }

                                Repeater {
                                    model: app.appointments
                                    delegate: Rectangle {
                                        id: appointmentCard
                                        required property int index
                                        required property var modelData
                                        property int weekdayIndex: {
                                            var visibleDates = app.weekDates()
                                            for (var i = 0; i < visibleDates.length; ++i) {
                                                if (app.dateKey(visibleDates[i]) === modelData.date)
                                                    return i
                                            }
                                            return -1
                                        }

                                        x: weekdayIndex < 0 ? -1000
                                           : weekdayIndex * (scheduleGrid.width / (app.dayView ? 1 : 7)) + 4
                                        y: (modelData.startMinute - 480) / 60 * app.hourHeight + 4
                                        width: scheduleGrid.width / (app.dayView ? 1 : 7) - 8
                                        height: Math.max(42, modelData.duration / 60 * app.hourHeight - 7)
                                        radius: 9
                                        color: modelData.color
                                        visible: weekdayIndex >= 0
                                        clip: true

                                        Rectangle {
                                            width: 3
                                            height: parent.height - 12
                                            radius: 2
                                            color: appointmentCard.modelData.accent
                                            anchors.left: parent.left
                                            anchors.leftMargin: 6
                                            anchors.top: parent.top
                                            anchors.topMargin: 6
                                        }

                                        Column {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 5
                                            anchors.topMargin: 7
                                            spacing: 4

                                            Text {
                                                width: parent.width
                                                text: appointmentCard.modelData.title
                                                color: "#384257"
                                                font.pixelSize: app.dayView ? 14 : 12
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                                maximumLineCount: 2
                                                wrapMode: Text.Wrap
                                            }

                                            Text {
                                                text: app.timeString(appointmentCard.modelData.startMinute)
                                                color: appointmentCard.modelData.accent
                                                font.pixelSize: 11
                                                visible: appointmentCard.height > 42
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: Qt.PointingHandCursor

                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    var point = appointmentCard.mapToItem(calendarSurface, mouse.x, mouse.y)
                                                    app.openAppointmentMenu(appointmentCard.index, point.x, point.y)
                                                } else {
                                                    app.contextMenuOpen = false
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: app.weekDates().some(function(date) {
                                        return app.dateKey(date) === app.dateKey(new Date())
                                    }) && app.currentMinute >= 480 && app.currentMinute <= 1080
                                    x: 0
                                    y: (app.currentMinute - 480) / 60 * app.hourHeight
                                    width: scheduleGrid.width
                                    height: 2
                                    color: "#ec6670"
                                    z: 3

                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: parent.color
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            Item {
                                x: 0
                                y: 10 * app.hourHeight
                                width: parent.width
                                height: 22
                            }
                        }

                        Rectangle {
                            id: scheduleScrollbar
                            width: 4
                            height: scheduleScroll.height * scheduleScroll.height / scheduleScroll.contentHeight
                            radius: 2
                            color: "#dfe4ed"
                            anchors.right: parent.right
                            anchors.rightMargin: 3
                            visible: scheduleScroll.contentHeight > scheduleScroll.height

                            Binding {
                                target: scheduleScrollbar
                                property: "y"
                                value: scheduleScroll.contentY / scheduleScroll.contentHeight * scheduleScroll.height
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        z: 20
        visible: app.storageError.length > 0 || app.reminderMessage.length > 0
        width: Math.min(380, app.width - 36)
        height: 66
        radius: 14
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 22
        anchors.bottomMargin: 20
        color: app.storageError.length > 0 ? "#fff0f0" : "#ffffff"
        border.color: app.storageError.length > 0 ? "#f1c8c8" : "#e5e9f0"

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            anchors.rightMargin: 42
            anchors.verticalCenter: parent.verticalCenter
            text: app.storageError.length > 0 ? "Save error: " + app.storageError
                                             : app.reminderMessage
            color: app.storageError.length > 0 ? "#a53e45" : app.ink
            font.pixelSize: 13
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Text {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 12
            anchors.topMargin: 8
            text: "×"
            color: app.secondaryInk
            font.pixelSize: 19
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                app.storageError = ""
                app.reminderMessage = ""
            }
        }
    }

    Window {
        id: clockWindow
        width: 300
        height: 390
        minimumWidth: 300
        maximumWidth: 300
        minimumHeight: 390
        maximumHeight: 390
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        title: "Clock"
        color: "#f7f9fc"
        visible: app.clockOpen || app.clockClosing
        transientParent: app
        modality: Qt.NonModal

        onVisibleChanged: {
            if (visible) {
                app.clockNow = new Date()
                requestActivate()
            }
        }
        onClosing: function(close) {
            close.accepted = false
            app.closeClock()
        }

        Rectangle {
            id: clockContent
            anchors.fill: parent
            color: "#f7f9fc"
            opacity: app.clockClosing ? 0 : 1
            scale: app.clockClosing ? 0.96 : 1

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Column {
                anchors.fill: parent
                anchors.topMargin: 12
                spacing: 8

                Row {
                    width: parent.width - 28
                    height: 32
                    anchors.horizontalCenter: parent.horizontalCenter

                    Text {
                        width: 60
                        text: "Clock"
                        color: app.ink
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Item { width: parent.width - 92; height: 1 }

                    Rectangle {
                        id: closeClockButton
                        width: 32
                        height: 32
                        radius: 10
                        color: closeClockMouse.containsMouse ? "#ffe3e5" : "#fff0f1"
                        anchors.verticalCenter: parent.verticalCenter
                        Accessible.name: "Close clock"

                        Behavior on color {
                            ColorAnimation { duration: 130 }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: "#d94d59"
                            font.pixelSize: 24
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: closeClockMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.closeClock()
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "LOCAL TIME"
                    color: app.secondaryInk
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    font.letterSpacing: 1.5
                }

                Item {
                    width: 230
                    height: 230
                    anchors.horizontalCenter: parent.horizontalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "#ffffff"
                        border.color: "#e7ebf3"
                        border.width: 1
                    }

                    Canvas {
                        id: clockFace
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            var center = width / 2
                            var radius = width * 0.43
                            ctx.clearRect(0, 0, width, height)
                            ctx.textAlign = "center"
                            ctx.textBaseline = "middle"
                            for (var tick = 0; tick < 60; ++tick) {
                                var angle = (tick * Math.PI / 30) - Math.PI / 2
                                var major = tick % 5 === 0
                                var outer = radius
                                var inner = radius - (major ? 12 : 5)
                                ctx.beginPath()
                                ctx.moveTo(center + Math.cos(angle) * inner,
                                           center + Math.sin(angle) * inner)
                                ctx.lineTo(center + Math.cos(angle) * outer,
                                           center + Math.sin(angle) * outer)
                                ctx.strokeStyle = major ? "#758097" : "#d8deea"
                                ctx.lineWidth = major ? 2 : 1
                                ctx.stroke()
                            }
                            ctx.fillStyle = "#4c566b"
                            ctx.font = "13px sans-serif"
                            for (var number = 1; number <= 12; ++number) {
                                var numberAngle = (number * Math.PI / 6) - Math.PI / 2
                                ctx.fillText(number.toString(),
                                             center + Math.cos(numberAngle) * (radius - 25),
                                             center + Math.sin(numberAngle) * (radius - 25))
                            }
                        }
                    }

                    Rectangle {
                        width: 6
                        height: 56
                        radius: 3
                        color: "#354052"
                        x: parent.width / 2 - width / 2
                        y: parent.height / 2 - height
                        transformOrigin: Item.Bottom
                        rotation: {
                            var d = app.clockNow
                            return ((d.getHours() % 12) + d.getMinutes() / 60
                                    + (d.getSeconds() + d.getMilliseconds() / 1000) / 3600) * 30
                        }
                    }

                    Rectangle {
                        width: 4
                        height: 78
                        radius: 2
                        color: app.blue
                        x: parent.width / 2 - width / 2
                        y: parent.height / 2 - height
                        transformOrigin: Item.Bottom
                        rotation: {
                            var d = app.clockNow
                            return (d.getMinutes()
                                    + (d.getSeconds() + d.getMilliseconds() / 1000) / 60) * 6
                        }
                    }

                    Rectangle {
                        width: 2
                        height: 89
                        radius: 1
                        color: "#e46d78"
                        x: parent.width / 2 - width / 2
                        y: parent.height / 2 - height
                        transformOrigin: Item.Bottom
                        rotation: (app.clockNow.getSeconds()
                                   + app.clockNow.getMilliseconds() / 1000) * 6
                    }

                    Rectangle {
                        width: 12
                        height: 12
                        radius: 6
                        color: app.blue
                        anchors.centerIn: parent
                    }
                }

                Text {
                    width: parent.width
                    text: Qt.locale("en_US").toString(app.clockNow, "HH:mm:ss")
                    color: app.ink
                    font.pixelSize: 31
                    font.weight: Font.DemiBold
                    font.family: "Consolas"
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width
                    text: Qt.locale("en_US").toString(app.clockNow, "dddd, MMMM d, yyyy")
                    color: app.secondaryInk
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Window {
        id: notesLibraryWindow
        width: 360
        height: 480
        minimumWidth: 360
        maximumWidth: 360
        minimumHeight: 480
        maximumHeight: 480
        x: app.x + app.width - width - 24
        y: app.y + 92
        title: "My Notes"
        color: "#f7f9fc"
        visible: app.notesLibraryOpen || app.notesLibraryClosing
        transientParent: app
        modality: Qt.NonModal

        onVisibleChanged: {
            if (visible) {
                requestActivate()
                notesLibraryContent.opacity = 0
                notesLibraryContent.scale = 0.97
                Qt.callLater(function() {
                    notesLibraryContent.opacity = 1
                    notesLibraryContent.scale = 1
                })
            }
        }
        onClosing: function(close) {
            close.accepted = false
            if (!app.notesLibraryClosing) {
                app.notesLibraryClosing = true
                notesLibraryContent.opacity = 0
                notesLibraryContent.scale = 0.97
                notesLibraryCloseTimer.restart()
            }
        }

        Rectangle {
            id: notesLibraryContent
            anchors.fill: parent
            color: "#f7f9fc"
            opacity: 1
            scale: 1

            Behavior on opacity {
                NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
            }

            Column {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    width: parent.width
                    height: 64
                    color: "#ffffff"
                    border.color: "#edf0f5"
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 14
                        spacing: 10

                        Rectangle {
                            width: 36
                            height: 36
                            radius: 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#fff4cb"
                            Text {
                                anchors.centerIn: parent
                                text: "💡"
                                font.pixelSize: 18
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text {
                                text: "Notes"
                                color: app.ink
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: app.noteStatusError ? app.noteStatusMessage
                                      : app.savedNotes.length === 1 ? "1 note saved"
                                      : app.savedNotes.length + " notes saved"
                                color: app.noteStatusError ? "#c84f5b" : app.secondaryInk
                                font.pixelSize: 10
                            }
                        }

                        Item { width: Math.max(0, parent.width - 310); height: 1 }

                        Rectangle {
                            width: 124
                            height: 34
                            radius: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: app.blue
                            Text {
                                anchors.centerIn: parent
                                text: "+ Create note"
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.openNewNote()
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: parent.height - 64

                    Column {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 36, 300)
                        spacing: 12
                        visible: app.savedNotes.length === 0

                        Rectangle {
                            width: 92
                            height: 92
                            radius: 46
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: "#fff7df"
                            Text {
                                anchors.centerIn: parent
                                text: "📁"
                                font.pixelSize: 38
                            }
                        }

                        Text {
                            width: parent.width
                            text: "No notes yet"
                            color: app.ink
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Text {
                            width: parent.width
                            text: "Create a note to keep your ideas, lists, and images in one place."
                            color: app.secondaryInk
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            width: 132
                            height: 36
                            radius: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: app.blue
                            Text {
                                anchors.centerIn: parent
                                text: "Create note"
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.openNewNote()
                            }
                        }
                    }

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 12
                        visible: app.savedNotes.length > 0
                        clip: true
                        contentWidth: width
                        contentHeight: noteCards.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        Flow {
                            id: noteCards
                            width: parent.width
                            spacing: 10

                            Repeater {
                                model: app.savedNotes
                                delegate: Rectangle {
                                    id: noteCard
                                    required property int index
                                    required property var modelData
                                    width: noteCards.width
                                    height: 112
                                    radius: 12
                                    color: "#ffffff"
                                    border.color: "#e9edf4"
                                    opacity: 0
                                    scale: 0.97

                                    NumberAnimation {
                                        id: noteCardEntrance
                                        target: noteCard
                                        property: "opacity"
                                        from: 0
                                        to: 1
                                        duration: 180
                                        easing.type: Easing.OutCubic
                                    }

                                    Behavior on scale {
                                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                    }

                                    Component.onCompleted: {
                                        noteCardEntrance.start()
                                        noteCard.scale = 1
                                    }

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        anchors.rightMargin: 42
                                        spacing: 6

                                        Text {
                                            width: parent.width
                                            text: noteCard.modelData.title
                                            color: app.ink
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width
                                            height: 38
                                            text: app.notePreview(noteCard.modelData.html)
                                            color: app.secondaryInk
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                            maximumLineCount: 3
                                            wrapMode: Text.Wrap
                                        }

                                        Text {
                                            width: parent.width
                                            text: Qt.locale("en_US").toString(new Date(noteCard.modelData.updated), "MMM d, yyyy · HH:mm")
                                            color: app.faintInk
                                            font.pixelSize: 9
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: app.openSavedNote(noteCard.modelData)
                                    }

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 8
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 9
                                        color: deleteNoteMouse.containsMouse ? "#fff0f0" : "#f7f8fb"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "×"
                                            color: "#c84f5b"
                                            font.pixelSize: 19
                                        }
                                        MouseArea {
                                            id: deleteNoteMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: app.requestDeleteNote(noteCard.modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            z: 2
            visible: app.noteDeleteDialogOpen
            color: "#660f172a"

            MouseArea {
                anchors.fill: parent
                onClicked: app.noteDeleteDialogOpen = false
            }

            Rectangle {
                width: 360
                height: 188
                radius: 18
                anchors.centerIn: parent
                color: "#ffffff"
                border.color: "#e8ecf3"

                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) { mouse.accepted = true }
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12

                    Text {
                        text: "Delete this note?"
                        color: app.ink
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }

                    Text {
                        width: parent.width
                        text: "This action is permanent. The note will be deleted from this device."
                        color: app.secondaryInk
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Item { width: 1; height: 2 }

                    Row {
                        width: parent.width
                        height: 38
                        spacing: 9

                        Rectangle {
                            width: (parent.width - 9) / 2
                            height: 38
                            radius: 10
                            color: "#f3f5f9"
                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: app.secondaryInk
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.noteDeleteDialogOpen = false
                            }
                        }

                        Rectangle {
                            width: (parent.width - 9) / 2
                            height: 38
                            radius: 10
                            color: "#c84f5b"
                            Text {
                                anchors.centerIn: parent
                                text: "Delete"
                                color: "#ffffff"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.confirmDeleteNote()
                            }
                        }
                    }
                }
            }
        }
    }

    Window {
        id: noteEditorWindow
        width: 480
        height: 420
        minimumWidth: 480
        maximumWidth: 480
        minimumHeight: 420
        maximumHeight: 420
        x: app.x + (app.width - width) / 2
        y: app.y + (app.height - height) / 2
        title: "Note Editor"
        color: "#f3f5f9"
        visible: app.noteEditorOpen || app.noteEditorClosing
        transientParent: app
        modality: Qt.NonModal

        onVisibleChanged: {
            if (visible) {
                requestActivate()
                Qt.callLater(function() {
                    noteEditor.forceActiveFocus()
                })
            }
        }
        onClosing: function(close) {
            close.accepted = false
            var plain = noteEditor.text.replace(/<[^>]*>/g, " ").replace(/&nbsp;/g, " ").trim()
            if (plain.length || /<img\b/i.test(noteEditor.text))
                app.saveCurrentNote()
            else
                app.closeNoteEditor()
        }

        Shortcut {
            sequence: "Ctrl+S"
            context: Qt.WindowShortcut
            onActivated: app.saveCurrentNote()
        }

        Rectangle {
            anchors.fill: parent
            color: "#f3f5f9"
            opacity: app.noteEditorClosing ? 0 : 1
            scale: app.noteEditorClosing ? 0.97 : 1

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Column {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    width: parent.width
                    height: 76
                    color: "#ffffff"
                    border.color: "#edf0f5"
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 22
                        anchors.rightMargin: 22
                        spacing: 14

                        Rectangle {
                            width: 40
                            height: 40
                            radius: 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#f3f5f9"
                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: app.ink
                                font.pixelSize: 29
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    app.notesLibraryOpen = true
                                    app.closeNoteEditor()
                                }
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Text {
                                text: "Note Editor"
                                color: app.ink
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }
                        }

                        Item { width: Math.max(0, parent.width - 380); height: 1 }

                        Rectangle {
                            width: 150
                            height: 39
                            radius: 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: app.blue
                            Text {
                                anchors.centerIn: parent
                                text: "Save and close"
                                color: "#ffffff"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.saveCurrentNote()
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 0
                    visible: false
                    color: "transparent"

                    Flickable {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        contentWidth: noteToolbarRow.implicitWidth
                        contentHeight: height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Row {
                            id: noteToolbarRow
                            height: parent.height
                            spacing: 4

                            Repeater {
                                model: [
                                    { label: "↶", action: "undo" },
                                    { label: "↷", action: "redo" },
                                    { label: "B", action: "bold" },
                                    { label: "I", action: "italic" },
                                    { label: "U", action: "underline" },
                                    { label: "S", action: "strike" },
                                    { label: "H1", action: "heading1" },
                                    { label: "H2", action: "heading2" },
                                    { label: "•", action: "bullet" },
                                    { label: "1.", action: "numbered" },
                                    { label: "≡", action: "left" },
                                    { label: "☰", action: "center" },
                                    { label: "☷", action: "right" },
                                    { label: "A", action: "textColor" },
                                    { label: "▰", action: "highlight" },
                                    { label: "↗", action: "link" }
                                ]

                                delegate: Rectangle {
                                    id: editorTool
                                    required property var modelData
                                    width: 34
                                    height: 34
                                    radius: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: editorToolMouse.containsMouse ? "#edf2ff" : "transparent"
                                    Accessible.name: editorTool.modelData.action

                                    Text {
                                        anchors.centerIn: parent
                                        text: editorTool.modelData.label
                                        color: editorTool.modelData.action === "textColor" ? app.blue
                                               : editorTool.modelData.action === "highlight" ? "#d49b32" : app.ink
                                        font.pixelSize: editorTool.modelData.action === "bullet" ? 19 : 13
                                        font.weight: ["bold", "heading1", "heading2"].indexOf(editorTool.modelData.action) >= 0
                                                     ? Font.Bold : Font.Medium
                                        font.italic: editorTool.modelData.action === "italic"
                                        font.underline: editorTool.modelData.action === "underline"
                                        font.strikeout: editorTool.modelData.action === "strike"
                                    }

                                    MouseArea {
                                        id: editorToolMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var action = editorTool.modelData.action
                                            if (action === "undo")
                                                noteEditor.undo()
                                            else if (action === "redo")
                                                noteEditor.redo()
                                            else if (action === "bold")
                                                app.formatNoteSelection("<b>", "</b>")
                                            else if (action === "italic")
                                                app.formatNoteSelection("<i>", "</i>")
                                            else if (action === "underline")
                                                app.formatNoteSelection("<u>", "</u>")
                                            else if (action === "strike")
                                                app.formatNoteSelection("<s>", "</s>")
                                            else if (action === "heading1")
                                                app.formatNoteSelection("<h1>", "</h1>")
                                            else if (action === "heading2")
                                                app.formatNoteSelection("<h2>", "</h2>")
                                            else if (action === "bullet")
                                                app.formatNoteList(false)
                                            else if (action === "numbered")
                                                app.formatNoteList(true)
                                            else if (action === "left")
                                                app.alignNoteSelection("left")
                                            else if (action === "center")
                                                app.alignNoteSelection("center")
                                            else if (action === "right")
                                                app.alignNoteSelection("right")
                                            else if (action === "textColor" || action === "highlight") {
                                                app.notePaletteTarget = action === "highlight" ? "highlight" : "color"
                                                app.notePaletteOpen = !app.notePaletteOpen
                                                app.noteLinkDialogOpen = false
                                            } else if (action === "link") {
                                                app.noteLinkSelection = noteEditor.selectedText
                                                app.noteLinkSelectionStart = noteEditor.selectionStart
                                                app.noteLinkSelectionEnd = noteEditor.selectionEnd
                                                app.noteLinkDraft = ""
                                                app.noteLinkDialogOpen = true
                                                app.notePaletteOpen = false
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: 1
                                height: 23
                                color: "#e9edf3"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Rectangle {
                                width: 82
                                height: 34
                                radius: 8
                                anchors.verticalCenter: parent.verticalCenter
                                color: imageToolMouse.containsMouse ? "#edf2ff" : "transparent"

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: "▧"
                                        color: app.blue
                                        font.pixelSize: 16
                                    }
                                    Text {
                                        text: "Image"
                                        color: app.ink
                                        font.pixelSize: 12
                                    }
                                }

                                MouseArea {
                                    id: imageToolMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: noteImageDialog.open()
                                }
                            }
                        }
                    }
                }

                Flickable {
                    id: noteEditorScroll
                    width: parent.width
                    height: parent.height - 106
                    contentWidth: width
                    contentHeight: editorPaper.y + Math.max(editorPaper.implicitHeight, noteEditor.contentHeight + 210) + 38
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Rectangle {
                        id: editorPaper
                        width: Math.min(noteEditorScroll.width - 32, 760)
                        x: (noteEditorScroll.width - width) / 2
                        y: 24
                        height: Math.max(310, noteEditor.contentHeight + 150)
                        radius: 13
                        color: "#ffffff"
                        border.color: "#e9edf3"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 22
                            spacing: 10

                            TextInput {
                                id: noteTitleInput
                                width: parent.width
                                height: 30
                                text: ""
                                onTextChanged: app.noteDraftTitle = text
                                verticalAlignment: TextInput.AlignVCenter
                                color: app.ink
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                                selectByMouse: true
                                clip: true

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: "Title"
                                    color: "#a4adbd"
                                    font: noteTitleInput.font
                                    visible: !noteTitleInput.text.length
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: "#edf0f5"
                            }

                            TextEdit {
                                id: noteEditor
                                width: parent.width
                                height: Math.max(200, contentHeight + 40)
                                text: ""
                                textFormat: TextEdit.RichText
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                persistentSelection: true
                                color: "#3c4658"
                                font.pixelSize: 15
                                font.family: "Segoe UI"
                                selectionColor: "#cbd8ff"
                                selectedTextColor: "#202735"
                                onTextChanged: app.noteDraftHtml = text

                                Text {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    width: parent.width
                                    text: "Write your ideas here… You can also paste text or an image with Ctrl + V."
                                    color: "#a4adbd"
                                    font.pixelSize: 15
                                    wrapMode: Text.WordWrap
                                    visible: !noteEditor.text.length
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: app.noteStatusError ? 30 : 0
                    visible: app.noteStatusError
                    color: "#ffffff"
                    border.color: "#edf0f5"
                    border.width: 1

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 22
                        anchors.rightMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        text: app.noteStatusMessage
                        color: "#c84f5b"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Rectangle {
            id: noteColorPalette
            z: 5
            visible: app.notePaletteOpen
            width: 244
            height: 116
            x: Math.max(18, Math.min(parent.width - width - 18, (parent.width - width) / 2 + 125))
            y: 134
            radius: 14
            color: "#ffffff"
            border.color: "#e4e8f0"

            Column {
                anchors.fill: parent
                anchors.margins: 13
                spacing: 10

                Text {
                    text: app.notePaletteTarget === "highlight" ? "Highlight color" : "Text color"
                    color: app.ink
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Flow {
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: ["#202735", "#d94d59", "#e67e22", "#e2b93b",
                                "#399374", "#2587a8", "#5278ed", "#7959c9",
                                "#d96bb2", "#778097", "#ffffff", "#f3f5f9"]

                        delegate: Rectangle {
                            id: noteColorSwatch
                            required property string modelData
                            width: 23
                            height: 23
                            radius: 7
                            color: noteColorSwatch.modelData
                            border.color: noteColorSwatch.modelData === "#ffffff" ? "#d7dce6" : "transparent"

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.applyNoteColor(noteColorSwatch.modelData)
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            z: 8
            anchors.fill: parent
            visible: app.noteLinkDialogOpen
            color: "#660f172a"

            MouseArea {
                anchors.fill: parent
                onClicked: app.noteLinkDialogOpen = false
            }

            Rectangle {
                width: 390
                height: 208
                radius: 18
                anchors.centerIn: parent
                color: "#ffffff"
                border.color: "#e8ecf3"

                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) { mouse.accepted = true }
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12

                    Text {
                        text: "Insert link"
                        color: app.ink
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: app.noteLinkSelection.length
                              ? "The link will be applied to the selected text."
                              : "The address will be inserted as clickable text."
                        color: app.secondaryInk
                        font.pixelSize: 12
                    }

                    Rectangle {
                        width: parent.width
                        height: 40
                        radius: 10
                        color: "#f7f9fc"
                        border.color: "#e4e8f0"

                        TextInput {
                            id: noteLinkInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            text: app.noteLinkDraft
                            onTextChanged: app.noteLinkDraft = text
                            selectByMouse: true
                            color: app.ink
                            font.pixelSize: 13
                            inputMethodHints: Qt.ImhUrlCharactersOnly
                            onAccepted: app.insertNoteLink()
                        }

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            text: "https://example.com"
                            color: app.faintInk
                            font.pixelSize: 13
                            visible: !noteLinkInput.text.length
                            MouseArea {
                                anchors.fill: parent
                                onClicked: noteLinkInput.forceActiveFocus()
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        height: 38
                        spacing: 10

                        Item { width: parent.width - 188; height: 1 }

                        Rectangle {
                            width: 86
                            height: 38
                            radius: 10
                            color: "#f3f5f9"
                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: app.secondaryInk
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.noteLinkDialogOpen = false
                            }
                        }

                        Rectangle {
                            width: 92
                            height: 38
                            radius: 10
                            color: app.blue
                            Text {
                                anchors.centerIn: parent
                                text: "Insert"
                                color: "#ffffff"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.insertNoteLink()
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: settingsPage
        anchors.fill: parent
        z: 20
        visible: true
        enabled: app.settingsOpen
        opacity: app.settingsOpen ? 1 : 0
        color: "#f7f9fc"

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: settingsHeader
            width: parent.width
            height: 92
            color: "#ffffff"
            border.color: "#edf0f5"
            border.width: 1

            Row {
                anchors.fill: parent
                anchors.leftMargin: 32
                spacing: 17

                Rectangle {
                    width: 42
                    height: 42
                    radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: backButtonMouse.containsMouse ? "#edf2ff" : "#f4f6fa"

                    Text {
                        anchors.centerIn: parent
                        text: "‹"
                        color: app.ink
                        font.pixelSize: 30
                    }

                    MouseArea {
                        id: backButtonMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: app.settingsOpen = false
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Text {
                        text: "Settings"
                        color: app.ink
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: "Personalize your schedule"
                        color: app.secondaryInk
                        font.pixelSize: 12
                    }
                }
            }
        }

        Flickable {
            id: settingsScroll
            anchors.top: settingsHeader.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            clip: true
            contentWidth: width
            contentHeight: settingsContent.y + settingsContent.implicitHeight + 44
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: settingsContent
                width: Math.min(settingsScroll.width - 64, 1120)
                x: (settingsScroll.width - width) / 2
                y: 34
                spacing: 34

                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Wallpaper"
                        color: app.ink
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: "Choose a landscape or upload your own image."
                        color: app.secondaryInk
                        font.pixelSize: 13
                    }

                    Flow {
                        id: wallpaperChoices
                        width: parent.width
                        spacing: 14

                        Repeater {
                            model: [
                                { name: "Mountains", skyTop: "#dceeff", skyBottom: "#f8fafc", sun: "#fff0ca", far: "#b8cbd5", mid: "#829fa7", near: "#66847c" },
                                { name: "Forest", skyTop: "#d9eee7", skyBottom: "#f6f8f2", sun: "#fff3d6", far: "#a9c6ac", mid: "#779b83", near: "#587564" },
                                { name: "Ocean", skyTop: "#cce8f6", skyBottom: "#f5fafb", sun: "#fff5dc", far: "#a3c7d5", mid: "#75a8b6", near: "#568b98" },
                                { name: "Meadow", skyTop: "#f7dfc6", skyBottom: "#fcf6ed", sun: "#ffedc2", far: "#d9bb9f", mid: "#b99b7e", near: "#8f977c" }
                            ]

                            delegate: Rectangle {
                                id: wallpaperCard
                                required property int index
                                required property var modelData
                                width: (wallpaperChoices.width - 42) / 4
                                height: 164
                                radius: 16
                                color: "#ffffff"
                                border.color: app.wallpaperPreset === wallpaperCard.index && !app.wallpaperImage.length
                                              ? app.blue : "#e8edf4"
                                border.width: app.wallpaperPreset === wallpaperCard.index && !app.wallpaperImage.length ? 2 : 1

                                Behavior on border.color {
                                    ColorAnimation { duration: 160 }
                                }

                                Rectangle {
                                    id: wallpaperPreview
                                    x: 8
                                    y: 8
                                    width: parent.width - 16
                                    height: 112
                                    radius: 11
                                    clip: true

                                    Rectangle {
                                        anchors.fill: parent
                                        gradient: Gradient {
                                            GradientStop { position: 0; color: wallpaperCard.modelData.skyTop }
                                            GradientStop { position: 1; color: wallpaperCard.modelData.skyBottom }
                                        }
                                    }

                                    Rectangle {
                                        width: 35
                                        height: 35
                                        radius: 18
                                        x: parent.width * 0.72
                                        y: 16
                                        color: wallpaperCard.modelData.sun
                                    }

                                    Rectangle {
                                        width: parent.width * 0.82
                                        height: 66
                                        radius: 60
                                        x: -parent.width * 0.08
                                        y: 63
                                        color: wallpaperCard.modelData.far
                                    }

                                    Rectangle {
                                        width: parent.width * 0.82
                                        height: 66
                                        radius: 60
                                        x: parent.width * 0.36
                                        y: 60
                                        color: wallpaperCard.modelData.far
                                    }

                                    Rectangle {
                                        width: parent.width * 0.9
                                        height: 58
                                        radius: 55
                                        x: -parent.width * 0.16
                                        y: 79
                                        color: wallpaperCard.modelData.mid
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 48
                                        radius: 48
                                        x: parent.width * 0.34
                                        y: 82
                                        color: wallpaperCard.modelData.near
                                    }
                                }

                                Text {
                                    x: 14
                                    y: 128
                                    text: wallpaperCard.modelData.name
                                    color: app.ink
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        app.wallpaperPreset = wallpaperCard.index
                                        app.wallpaperImage = ""
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        spacing: 12

                        Rectangle {
                            width: 178
                            height: 42
                            radius: 12
                            color: app.wallpaperImage.length ? "#edf2ff" : app.blue

                            Text {
                                anchors.centerIn: parent
                                text: app.wallpaperImage.length ? "Change image" : "Upload image"
                                color: app.wallpaperImage.length ? app.blue : "#ffffff"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: wallpaperFileDialog.open()
                            }
                        }

                        Rectangle {
                            width: 114
                            height: 42
                            radius: 12
                            color: "#ffffff"
                            border.color: "#e4e8f0"
                            visible: app.wallpaperActive

                            Text {
                                anchors.centerIn: parent
                                text: "Reset"
                                color: app.secondaryInk
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    app.wallpaperPreset = -1
                                    app.wallpaperImage = ""
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Keyboard shortcuts"
                        color: app.ink
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: "Quickly access the main actions."
                        color: app.secondaryInk
                        font.pixelSize: 13
                    }

                    Column {
                        width: parent.width
                        spacing: 1

                        Item { width: 1; height: 8 }

                        Repeater {
                            model: [
                                { action: "New event", shortcut: "Ctrl + N" },
                                { action: "New task", shortcut: "Ctrl + T" },
                                { action: "Open settings", shortcut: "Ctrl + ," },
                                { action: "Save a note", shortcut: "Ctrl + S" },
                                { action: "Edit or delete an event", shortcut: "Right-click" },
                                { action: "Close / go back", shortcut: "Esc" }
                            ]

                            delegate: Rectangle {
                                id: shortcutRow
                                required property var modelData
                                width: parent.width
                                height: 48
                                radius: 9
                                color: "#ffffff"

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: shortcutRow.modelData.action
                                    color: app.ink
                                    font.pixelSize: 13
                                }

                                Rectangle {
                                    width: shortcutLabel.implicitWidth + 22
                                    height: 29
                                    radius: 8
                                    anchors.right: parent.right
                                    anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "#f4f6fa"
                                    border.color: "#e8ecf3"

                                    Text {
                                        id: shortcutLabel
                                        anchors.centerIn: parent
                                        text: shortcutRow.modelData.shortcut
                                        color: app.secondaryInk
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: app.contextMenuOpen
        color: "transparent"
        z: 8

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: app.contextMenuOpen = false
        }

        Rectangle {
            id: appointmentContextMenu
            width: 192
            height: 104
            x: Math.max(12, Math.min(app.contextMenuX, app.width - width - 12))
            y: Math.max(12, Math.min(app.contextMenuY, app.height - height - 12))
            radius: 13
            color: "#ffffff"
            border.color: "#e8ecf3"
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 7
                spacing: 4

                Rectangle {
                    id: editAppointmentAction
                    width: parent.width
                    height: 40
                    radius: 9
                    color: "transparent"
                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Edit"
                        color: app.ink
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: editAppointmentAction.color = "#f3f6fc"
                        onExited: editAppointmentAction.color = "transparent"
                        onClicked: app.editAppointment(app.contextAppointmentIndex)
                    }
                }

                Rectangle {
                    id: deleteAppointmentAction
                    width: parent.width
                    height: 40
                    radius: 9
                    color: "transparent"
                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Delete"
                        color: "#c84f5b"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: deleteAppointmentAction.color = "#fff2f2"
                        onExited: deleteAppointmentAction.color = "transparent"
                        onClicked: app.deleteAppointment(app.contextAppointmentIndex)
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: true
        enabled: app.eventDialogOpen
        opacity: app.eventDialogOpen ? 1 : 0
        color: "#45253042"
        z: 10

        Behavior on opacity {
            NumberAnimation { duration: 180 }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                app.eventDialogOpen = false
                app.editingAppointmentIndex = -1
            }
        }

        Rectangle {
            width: 390
            height: app.dialogForTask ? 304 : 378
            radius: 23
            color: "#ffffff"
            anchors.centerIn: parent
            scale: app.eventDialogOpen ? 1 : 0.96

            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: function(mouse) { mouse.accepted = true }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 25
                spacing: 17

                Text {
                    text: app.dialogForTask ? "New task"
                         : app.editingAppointmentIndex >= 0 ? "Edit event"
                         : "New event"
                    color: app.ink
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }

                Text {
                    visible: !app.dialogForTask
                    text: app.longDate(app.selectedDate)
                    color: app.secondaryInk
                    font.pixelSize: 12
                }

                Text {
                    text: app.dialogForTask ? "Task name" : "Event name"
                    color: "#536077"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    width: parent.width
                    height: 45
                    radius: 11
                    color: "#fafbfe"
                    border.color: "#e3e8f0"

                    TextInput {
                        id: titleInput
                        anchors.fill: parent
                        anchors.leftMargin: 13
                        anchors.rightMargin: 13
                        verticalAlignment: TextInput.AlignVCenter
                        text: ""
                        onTextChanged: app.eventTitle = text
                        onAccepted: app.addAppointment()
                        color: app.ink
                        font.pixelSize: 12
                        clip: true

                        Connections {
                            target: app
                            function onEventDialogOpenChanged() {
                                if (app.eventDialogOpen)
                                    titleInput.forceActiveFocus()
                            }
                            function onEventTitleChanged() {
                                if (titleInput.text !== app.eventTitle)
                                    titleInput.text = app.eventTitle
                            }
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "E.g. Meeting, appointment…"
                            color: "#a4adbd"
                            font: titleInput.font
                            visible: !titleInput.text.length
                        }
                    }
                }

                Text {
                    visible: !app.dialogForTask
                    text: "Start time"
                    color: "#536077"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Row {
                    visible: !app.dialogForTask
                    width: parent.width
                    height: 43
                    spacing: 8

                    Rectangle {
                        width: 42
                        height: 42
                        radius: 11
                        color: "#f2f5fa"
                        Text { anchors.centerIn: parent; text: "−"; color: app.secondaryInk; font.pixelSize: 21 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.eventStartMinute = Math.max(480, app.eventStartMinute - 30)
                        }
                    }

                    Rectangle {
                        width: 108
                        height: 42
                        radius: 11
                        color: "#f7f8fc"
                        Text {
                            anchors.centerIn: parent
                            text: app.timeString(app.eventStartMinute)
                            color: app.ink
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }

                    Rectangle {
                        width: 42
                        height: 42
                        radius: 11
                        color: "#f2f5fa"
                        Text { anchors.centerIn: parent; text: "+"; color: app.secondaryInk; font.pixelSize: 21 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.eventStartMinute = Math.min(1050, app.eventStartMinute + 30)
                        }
                    }
                }

                Item { width: 1; height: 1 }

                Row {
                    width: parent.width
                    height: 43
                    spacing: 9

                    Rectangle {
                        width: 126
                        height: 43
                        radius: 11
                        color: "#f3f5fa"
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: "#536077"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                app.eventDialogOpen = false
                                app.editingAppointmentIndex = -1
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width - 135
                        height: 43
                        radius: 11
                        color: app.blue
                        opacity: app.eventTitle.trim().length ? 1 : 0.56
                        Text {
                            anchors.centerIn: parent
                            text: app.dialogForTask ? "Add to my tasks"
                                 : app.editingAppointmentIndex >= 0 ? "Save"
                                 : "Add to schedule"
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: app.eventTitle.trim().length > 0
                            onClicked: app.addAppointment()
                        }
                    }
                }
            }
        }
    }
}
