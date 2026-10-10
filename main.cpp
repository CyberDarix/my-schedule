#include <QGuiApplication>
#include <QDir>
#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QObject>
#include <QQmlApplicationEngine>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>
#include <QVariantList>
#include <QVariantMap>
#include <QWindow>

class AgendaStore final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit AgendaStore(QObject *parent = nullptr)
        : QObject(parent)
    {
        const QString directory = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
        if (directory.isEmpty() || !QDir().mkpath(directory))
            setError(QStringLiteral("Could not create the schedule data folder."));
        m_directory = directory;
    }

    QString lastError() const
    {
        return m_lastError;
    }

    Q_INVOKABLE QVariantList loadNotes()
    {
        clearError();
        QFile file(notesFilePath());
        if (!file.exists())
            return {};
        if (!file.open(QIODevice::ReadOnly)) {
            setError(file.errorString());
            return {};
        }

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isArray()) {
            setError(QStringLiteral("The notes file is unreadable: %1").arg(parseError.errorString()));
            return {};
        }
        return document.array().toVariantList();
    }

    Q_INVOKABLE bool saveNote(const QVariantMap &note)
    {
        clearError();
        QVariantMap savedNote = note;
        QString id = savedNote.value(QStringLiteral("id")).toString();
        if (id.isEmpty())
            id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        savedNote.insert(QStringLiteral("id"), id);

        QVariantList notes = loadNotes();
        if (!m_lastError.isEmpty())
            return false;

        bool replaced = false;
        for (QVariant &existing : notes) {
            QVariantMap existingNote = existing.toMap();
            if (existingNote.value(QStringLiteral("id")).toString() == id) {
                existing = savedNote;
                replaced = true;
                break;
            }
        }
        if (!replaced)
            notes.append(savedNote);

        QSaveFile file(notesFilePath());
        if (!file.open(QIODevice::WriteOnly)) {
            setError(file.errorString());
            return false;
        }
        const QByteArray data = QJsonDocument(QJsonArray::fromVariantList(notes)).toJson(QJsonDocument::Compact);
        if (file.write(data) != data.size()) {
            setError(file.errorString());
            file.cancelWriting();
            return false;
        }
        if (!file.commit()) {
            setError(file.errorString());
            return false;
        }
        clearError();
        return true;
    }

    Q_INVOKABLE bool deleteNote(const QString &id)
    {
        clearError();
        QVariantList notes = loadNotes();
        if (!m_lastError.isEmpty())
            return false;

        const qsizetype previousSize = notes.size();
        for (qsizetype i = notes.size(); i > 0; --i) {
            if (notes.at(i - 1).toMap().value(QStringLiteral("id")).toString() == id)
                notes.removeAt(i - 1);
        }
        if (notes.size() == previousSize) {
            setError(QStringLiteral("This note no longer exists."));
            return false;
        }

        QSaveFile file(notesFilePath());
        if (!file.open(QIODevice::WriteOnly)) {
            setError(file.errorString());
            return false;
        }
        const QByteArray data = QJsonDocument(QJsonArray::fromVariantList(notes)).toJson(QJsonDocument::Compact);
        if (file.write(data) != data.size()) {
            setError(file.errorString());
            file.cancelWriting();
            return false;
        }
        if (!file.commit()) {
            setError(file.errorString());
            return false;
        }
        clearError();
        return true;
    }

    Q_INVOKABLE QString copyImage(const QUrl &sourceUrl)
    {
        clearError();
        const QString sourcePath = sourceUrl.isLocalFile() ? sourceUrl.toLocalFile() : QString();
        const QFileInfo sourceInfo(sourcePath);
        if (sourcePath.isEmpty() || !sourceInfo.isFile()) {
            setError(QStringLiteral("The selected image file could not be found."));
            return {};
        }

        const QString imageDirectory = QDir(m_directory).filePath(QStringLiteral("images"));
        if (!QDir().mkpath(imageDirectory)) {
            setError(QStringLiteral("Could not create the images folder."));
            return {};
        }

        QString suffix = sourceInfo.suffix().toLower();
        if (suffix.isEmpty())
            suffix = QStringLiteral("png");
        const QString destination = QDir(imageDirectory).filePath(
            QUuid::createUuid().toString(QUuid::WithoutBraces) + u'.' + suffix);
        if (!QFile::copy(sourcePath, destination)) {
            setError(QStringLiteral("Could not copy image: %1").arg(sourceInfo.fileName()));
            return {};
        }
        return QUrl::fromLocalFile(destination).toString(QUrl::FullyEncoded);
    }

    Q_INVOKABLE QVariantMap loadAgendaState()
    {
        clearError();
        QFile file(stateFilePath());
        if (!file.exists())
            return {};
        if (!file.open(QIODevice::ReadOnly)) {
            setError(file.errorString());
            return {};
        }

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setError(QStringLiteral("The schedule data is unreadable: %1")
                         .arg(parseError.errorString()));
            return {};
        }
        return document.object().toVariantMap();
    }

    Q_INVOKABLE bool saveAgendaState(const QVariantMap &state)
    {
        clearError();
        QSaveFile file(stateFilePath());
        if (!file.open(QIODevice::WriteOnly)) {
            setError(file.errorString());
            return false;
        }

        const QByteArray data = QJsonDocument(QJsonObject::fromVariantMap(state))
                                    .toJson(QJsonDocument::Compact);
        if (file.write(data) != data.size()) {
            setError(file.errorString());
            file.cancelWriting();
            return false;
        }
        if (!file.commit()) {
            setError(file.errorString());
            return false;
        }
        clearError();
        return true;
    }

signals:
    void lastErrorChanged();

private:
    QString notesFilePath() const
    {
        return QDir(m_directory).filePath(QStringLiteral("notes.json"));
    }

    QString stateFilePath() const
    {
        return QDir(m_directory).filePath(QStringLiteral("agenda.json"));
    }

    void setError(const QString &error)
    {
        if (m_lastError == error)
            return;
        m_lastError = error;
        emit lastErrorChanged();
    }

    void clearError()
    {
        setError({});
    }

    QString m_directory;
    QString m_lastError;
};

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("DarkShell"));
    app.setApplicationDisplayName(QStringLiteral("My Schedule"));
    app.setOrganizationName(QStringLiteral("Agenda"));
    const QIcon appIcon(QStringLiteral(":/app/assets/my_schedule_logo.png"));
    app.setWindowIcon(appIcon);

    AgendaStore agendaStore;
    QQmlApplicationEngine engine;
    engine.loadFromModule("DarkShell", "Main");

    if (engine.rootObjects().isEmpty())
        return -1;

    QObject *mainWindow = engine.rootObjects().constFirst();
    if (auto *window = qobject_cast<QWindow *>(mainWindow))
        window->setIcon(appIcon);

    if (!mainWindow->setProperty("agendaStorage", QVariant::fromValue(static_cast<QObject *>(&agendaStore)))) {
        qCritical() << "Could not initialize the local agenda storage.";
        return -1;
    }
    if (!QMetaObject::invokeMethod(mainWindow, "restoreAppData", Qt::DirectConnection)) {
        qCritical() << "Could not load the saved agenda.";
        return -1;
    }

    return app.exec();
}

#include "main.moc"
