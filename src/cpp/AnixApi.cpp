#include "AnixApi.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUrlQuery>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QSaveFile>
#include <QDebug>
#include <QDateTime>
#include <QFileInfo>
#include <QTimer>
#ifdef Q_OS_LINUX
#include <QSocketNotifier>
#include <linux/rtnetlink.h>
#include <sys/socket.h>
#include <unistd.h>
#elif defined(Q_OS_WIN)
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>

static void CALLBACK routeChanged(PVOID context, PMIB_IPFORWARD_ROW2, MIB_NOTIFICATION_TYPE)
{
    auto *settle = static_cast<QTimer *>(context);
    QMetaObject::invokeMethod(settle, qOverload<>(&QTimer::start), Qt::QueuedConnection);
}
#endif

static QString cacheFilePath(const QString &key)
{
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/library/" + key + ".json";
}

static QString profileListCacheKey(qint64 userId, int status)
{
    return QString("bookmarks-by-added-date-%1-%2").arg(userId).arg(status);
}

static QVariantMap readCache(const QString &key)
{
    QFile file(cacheFilePath(key));
    if (!file.open(QIODevice::ReadOnly)) return {};

    return QJsonDocument::fromJson(file.readAll()).object().toVariantMap();
}

static void writeCache(const QString &key, const QVariantMap &payload)
{
    const QString path = cacheFilePath(key);
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    const QByteArray data = QJsonDocument(QJsonObject::fromVariantMap(payload)).toJson(QJsonDocument::Compact);
    if (file.open(QIODevice::WriteOnly) && file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner)
        && file.write(data) == data.size()) {
        file.commit();
    }
}

static bool apiSucceeded(QNetworkReply *reply)
{
    if (reply->error() != QNetworkReply::NoError) return false;

    return QJsonDocument::fromJson(reply->readAll()).object().value("code").toInt(-1) == 0;
}

static int apiResponseCode(QNetworkReply *reply)
{
    const int code = QJsonDocument::fromJson(reply->readAll()).object().value("code").toInt(-1);
    if (reply->error() == QNetworkReply::NoError || code > 0) return code;

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    return status >= 400 ? status : -1;
}

AnixApi::AnixApi(QObject *parent)
    : QObject(parent)
    , m_manager(new QNetworkAccessManager(this))
    , m_baseUrl("https://api-s.anixsekai.com")
    , m_isLoading(false)
{
    loadUserData();

#if defined(Q_OS_LINUX) || defined(Q_OS_WIN)
    auto *settle = new QTimer(this);
    settle->setInterval(1000);
    settle->setSingleShot(true);
    connect(settle, &QTimer::timeout, this, [this] {
        m_manager->clearConnectionCache();
        emit networkRouteChanged();
    });
#endif

#ifdef Q_OS_LINUX
    const int socketFd = socket(AF_NETLINK, SOCK_RAW | SOCK_NONBLOCK | SOCK_CLOEXEC, NETLINK_ROUTE);
    if (socketFd < 0) return;

    sockaddr_nl address = {};
    address.nl_family = AF_NETLINK;
    address.nl_groups = RTMGRP_LINK | RTMGRP_IPV4_IFADDR | RTMGRP_IPV6_IFADDR
        | RTMGRP_IPV4_ROUTE | RTMGRP_IPV6_ROUTE | RTMGRP_IPV4_RULE;
    if (bind(socketFd, reinterpret_cast<const sockaddr *>(&address), sizeof(address)) < 0) {
        close(socketFd);
        return;
    }
    const int ipv6Rules = RTNLGRP_IPV6_RULE;
    setsockopt(socketFd, SOL_NETLINK, NETLINK_ADD_MEMBERSHIP, &ipv6Rules, sizeof(ipv6Rules));

    auto *changes = new QSocketNotifier(socketFd, QSocketNotifier::Read, this);
    connect(changes, &QObject::destroyed, [socketFd] { close(socketFd); });
    connect(changes, &QSocketNotifier::activated, this, [socketFd, settle] {
        char message[8192];
        bool changed = false;
        while (recv(socketFd, message, sizeof(message), MSG_DONTWAIT) > 0) changed = true;
        if (changed) settle->start();
    });
#elif defined(Q_OS_WIN)
    HANDLE handle = nullptr;
    if (NotifyRouteChange2(AF_UNSPEC, routeChanged, settle, FALSE, &handle) == NO_ERROR) {
        m_routeChangeHandle = handle;
    }
#endif
}

AnixApi::~AnixApi()
{
#ifdef Q_OS_WIN
    if (m_routeChangeHandle) CancelMibChangeNotify2(m_routeChangeHandle);
#endif
}

QString AnixApi::userDataFilePath() const
{
#ifdef Q_OS_LINUX
    const QString configDir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/anixart_linux";
#else
    const QString configDir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
#endif
    QDir().mkpath(configDir);
    return configDir + "/user_data.json";
}

void AnixApi::loadUserData()
{
    QFile file(userDataFilePath());
    if (!file.open(QIODevice::ReadOnly)) return;

    QByteArray data = file.readAll();
    file.close();

    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) return;

    QJsonObject obj = doc.object();
    m_bookmarks = obj["bookmarks"].toObject();
    m_episodeProgress = obj["progress"].toObject();

    QJsonArray watchedArr = obj["watched"].toArray();
    m_watchedSet.clear();
    for (const QJsonValue &v : watchedArr) {
        m_watchedSet.insert(v.toString());
    }
}

void AnixApi::saveUserData()
{
    QJsonObject obj;
    obj["bookmarks"] = m_bookmarks;
    obj["progress"] = m_episodeProgress;

    QJsonArray watchedArr;
    for (const QString &w : m_watchedSet) {
        watchedArr.append(w);
    }
    obj["watched"] = watchedArr;

    QSaveFile file(userDataFilePath());
    const QByteArray data = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size() || !file.commit()) {
        qWarning() << "Could not save user data:" << file.errorString();
    }
}

void AnixApi::addBookmark(qint64 releaseId, int listId, const QString &token)
{
    setBookmark(releaseId, listId, QString("/profile/list/add/%1/%2").arg(listId).arg(releaseId), token);
}

void AnixApi::removeBookmark(qint64 releaseId, const QString &token, int listId)
{
    const int currentStatus = listId >= 1 && listId <= 5 ? listId : getReleaseBookmarkStatus(releaseId);
    setBookmark(releaseId, 0, QString("/profile/list/delete/%1/%2").arg(qMax(1, currentStatus)).arg(releaseId), token);
}

void AnixApi::setBookmark(qint64 releaseId, int listId, const QString &endpoint, const QString &token)
{
    const auto save = [this, releaseId, listId] {
        const QString key = QString::number(releaseId);
        if (listId > 0) m_bookmarks[key] = listId;
        else m_bookmarks.remove(key);

        saveUserData();
        emit bookmarkUpdated(releaseId, listId);
    };

    if (token.isEmpty()) {
        save();
        return;
    }

    QNetworkReply *reply = sendBrowseRequest(endpoint, token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, releaseId, save] {
        const bool success = apiSucceeded(reply);
        reply->deleteLater();
        if (success) {
            save();
            emit bookmarkListsChanged();
        } else {
            emit bookmarkUpdateFailed(releaseId);
        }
    });
}

int AnixApi::getReleaseBookmarkStatus(qint64 releaseId) const
{
    QString key = QString::number(releaseId);
    if (m_bookmarks.contains(key)) {
        return m_bookmarks[key].toInt();
    }
    return 0;
}

static QString episodeKey(qint64 releaseId, qint64 typeId, qint64 sourceId, int position)
{
    return QString("%1_%2_%3_%4").arg(releaseId).arg(typeId).arg(sourceId).arg(position);
}

QNetworkReply *AnixApi::sendEpisodeWatchRequest(qint64 releaseId, qint64 sourceId, int position, bool watched, const QString &token)
{
    const QString endpoint = QString("/episode/%1/%2/%3/%4").arg(watched ? "watch" : "unwatch").arg(releaseId).arg(sourceId).arg(position);
    QNetworkRequest request = createRequest(endpoint, token);
    request.setTransferTimeout(15000);

    return m_manager->post(request, QByteArray());
}

void AnixApi::recordEpisodeOpened(qint64 releaseId, qint64 typeId, qint64 sourceId, int position, const QString &token)
{
    m_watchedSet.insert(episodeKey(releaseId, typeId, sourceId, position));
    saveUserData();
    emit episodeWatchUpdated(releaseId, typeId, sourceId, position, true, getEpisodePlaybackPosition(releaseId, typeId, sourceId, position));

    if (token.isEmpty() || sourceId <= 0) return;

    QNetworkReply *watchReply = sendEpisodeWatchRequest(releaseId, sourceId, position, true, token);
    connect(watchReply, &QNetworkReply::finished, this, [watchReply] {
        watchReply->deleteLater();
        if (!apiSucceeded(watchReply)) qWarning() << "Could not sync watched episode:" << watchReply->error();
    });

    const QString episode = QString("%1/%2/%3").arg(releaseId).arg(sourceId).arg(position);
    QNetworkRequest history = createRequest("/history/add/" + episode, token);
    history.setTransferTimeout(15000);
    m_episodeHistoryRequests.enqueue(history);
    if (m_episodeHistoryRequests.size() == 1) sendNextEpisodeHistoryRequest();
}

void AnixApi::sendNextEpisodeHistoryRequest()
{
    QNetworkReply *reply = m_manager->get(m_episodeHistoryRequests.head());
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (apiSucceeded(reply)) {
            m_episodeHistoryChanged = true;
        } else {
            qWarning() << "Could not sync episode history:" << reply->error();
        }

        m_episodeHistoryRequests.dequeue();
        if (!m_episodeHistoryRequests.isEmpty()) {
            sendNextEpisodeHistoryRequest();
        } else if (m_episodeHistoryChanged) {
            m_episodeHistoryChanged = false;
            emit episodeHistoryUpdated();
        }
    });
}

void AnixApi::setEpisodeWatched(qint64 releaseId, qint64 typeId, qint64 sourceId, int position, bool watched, const QString &token)
{
    const QString key = episodeKey(releaseId, typeId, sourceId, position);
    if (m_pendingWatchChanges.contains(key)) return;

    const auto applyChange = [this, key, releaseId, typeId, sourceId, position, watched] {
        if (watched) {
            m_watchedSet.insert(key);
        } else {
            m_watchedSet.remove(key);
        }
        m_episodeProgress.remove(key);
        saveUserData();
        emit episodeWatchUpdated(releaseId, typeId, sourceId, position, watched, 0);
    };
    if (token.isEmpty() || sourceId <= 0) {
        applyChange();
        return;
    }

    m_pendingWatchChanges.insert(key);
    QNetworkReply *reply = sendEpisodeWatchRequest(releaseId, sourceId, position, watched, token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, key, applyChange, releaseId, typeId, sourceId, position, watched] {
        reply->deleteLater();
        m_pendingWatchChanges.remove(key);
        if (apiSucceeded(reply)) {
            applyChange();
        } else {
            emit episodeWatchChangeFailed(releaseId, typeId, sourceId, position, watched);
        }
    });
}

void AnixApi::saveEpisodeProgress(qint64 releaseId, qint64 typeId, qint64 sourceId, int position, qint64 playbackPosition, qint64 duration)
{
    QString key = episodeKey(releaseId, typeId, sourceId, position);
    QJsonObject prog;
    prog["position"] = playbackPosition;
    prog["duration"] = duration;
    if (m_episodeProgress.value(key) == prog && m_watchedSet.contains(key)) return;

    m_episodeProgress[key] = prog;
    m_watchedSet.insert(key);

    saveUserData();
    emit episodeWatchUpdated(releaseId, typeId, sourceId, position, true, playbackPosition);
}

bool AnixApi::isEpisodeWatched(qint64 releaseId, qint64 typeId, qint64 sourceId, int position) const
{
    return m_watchedSet.contains(episodeKey(releaseId, typeId, sourceId, position));
}

qint64 AnixApi::getEpisodePlaybackPosition(qint64 releaseId, qint64 typeId, qint64 sourceId, int position) const
{
    QString key = episodeKey(releaseId, typeId, sourceId, position);
    if (m_episodeProgress.contains(key)) {
        return m_episodeProgress[key].toObject()["position"].toVariant().toLongLong();
    }
    return 0;
}

qint64 AnixApi::getEpisodePlaybackDuration(qint64 releaseId, qint64 typeId, qint64 sourceId, int position) const
{
    QString key = episodeKey(releaseId, typeId, sourceId, position);
    if (m_episodeProgress.contains(key)) {
        return m_episodeProgress[key].toObject()["duration"].toVariant().toLongLong();
    }
    return 0;
}

void AnixApi::setLoading(bool loading)
{
    if (m_isLoading != loading) {
        m_isLoading = loading;
        emit loadingChanged(m_isLoading);
    }
}

QNetworkRequest AnixApi::createRequest(const QString &endpoint, const QString &token)
{
    QString urlStr = endpoint.startsWith("http") ? endpoint : m_baseUrl + (endpoint.startsWith("/") ? endpoint : "/" + endpoint);
    if (!token.isEmpty() && !urlStr.contains("token=")) {
        QUrl url(urlStr);
        QUrlQuery query(url);
        query.addQueryItem("token", token);
        url.setQuery(query);
        urlStr = url.toString();
    }

    QUrl parsedUrl(urlStr);
    QNetworkRequest request(parsedUrl);
    request.setHeader(QNetworkRequest::UserAgentHeader, "AnixartApp/11-beta-3");
    request.setRawHeader("API-Version", "3");
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setTransferTimeout(15000);
    return request;
}

void AnixApi::fetchHub()
{
    QNetworkReply *reply = sendBrowseRequest("/discover/hub", {});
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        const QJsonObject data = reply->error() == QNetworkReply::NoError ? QJsonDocument::fromJson(reply->readAll()).object() : QJsonObject{};
        emit hubLoaded(data.toVariantMap());
    });
}

void AnixApi::fetchBrowseSection(const QString &section, int page, qint64 collectionId, const QString &token, const QString &query)
{
    QString endpoint;
    QJsonObject body;
    if (section == "schedule") {
        endpoint = "/schedule";
    } else if (section == "releaseGrid") {
        endpoint = QString("/filter/%1").arg(page);
        if (query.startsWith("my:")) {
            body = QJsonDocument::fromJson(query.mid(3).toUtf8()).object();
        } else {
            body["sort"] = query == "popular" ? 6 : 0;
            if (query == "anime") body["country"] = "Япония";
            if (query == "donghua") body["country"] = "Китай";
            if (query == "finished") body["status_id"] = 1;
            if (query == "ongoing") body["status_id"] = 2;
            if (query == "announced") body["status_id"] = 3;
            if (query == "movies") body["category_id"] = 2;
            if (query == "ova") body["category_id"] = 3;
        }
    } else if (section == "random") {
        endpoint = "/release/random";
    } else if (section == "collection" && collectionId > 0) {
        endpoint = QString("/collection/%1/releases/%2").arg(collectionId).arg(page);
    } else if (section == "releaseCollections" && collectionId > 0) {
        endpoint = QString("/collection/all/release/%1/%2").arg(collectionId).arg(page);
    } else if (section == "myReleaseCollections" && collectionId > 0 && !token.isEmpty()) {
        endpoint = QString("/collectionMy/all/release/%1/%2?sort=0").arg(collectionId).arg(page);
    } else if (section == "profileRatings" && collectionId > 0) {
        endpoint = QString("/profile/vote/release/voted/%1/%2?sort=1").arg(collectionId).arg(page);
    } else if (section == "profileLoginHistory" && collectionId > 0) {
        endpoint = QString("/profile/login/history/all/%1/%2").arg(collectionId).arg(page);
    } else if (section == "profileBadges" && collectionId > 0) {
        endpoint = QString("/profile/%1/badge/list").arg(collectionId);
    } else if (section == "profileBlog" && collectionId > 0) {
        endpoint = QString("/channel/blog/%1").arg(collectionId);
    } else if (section == "profileSocial" && collectionId > 0) {
        endpoint = QString("/profile/social/%1").arg(collectionId);
    } else if (section == "profilePreferences" && !token.isEmpty()) {
        endpoint = "/profile/preference/my";
    } else if (section == "profilePrivateSocial" && !token.isEmpty()) {
        endpoint = "/profile/preference/social";
    } else if (section == "myFeed") {
        endpoint = QString("/feed/all/%1?date=%2").arg(page).arg(query.isEmpty() ? QDateTime::currentSecsSinceEpoch() : query.toLongLong());
    } else if (section == "channelFeed" && collectionId > 0) {
        endpoint = QString("/feed/all/%1?date=%2&channel_id=%3").arg(page).arg(query.toLongLong()).arg(collectionId);
    } else if (section == "latestFeed") {
        endpoint = QString("/feed/latest/all/%1").arg(page);
    } else if (section == "feedSearch") {
        endpoint = QString("/search/feed/%1").arg(page);
        body["query"] = query;
    } else if (collectionId > 0 && (section == "article" || section == "channel")) {
        endpoint = QString("/%1/%2").arg(section).arg(collectionId);
    } else if (collectionId > 0 && (section == "articleComments" || section == "releaseComments")) {
        const QString type = section == "articleComments" ? "article" : "release";
        endpoint = QString("/%1/comment/all/%2/%3?sort=0").arg(type).arg(collectionId).arg(page);
    } else if (section == "subscriptions") {
        endpoint = QString("/channel/subscription/all/%1").arg(page);
    } else {
        return;
    }

    QNetworkReply *reply = sendBrowseRequest(endpoint, token, body);
    connect(reply, &QNetworkReply::finished, this, [this, reply, section, page, collectionId, query] {
        reply->deleteLater();
        QVariantMap data;
        if (reply->error() == QNetworkReply::NoError) {
            const QJsonObject object = QJsonDocument::fromJson(reply->readAll()).object();
            if (object.value("code").toInt(-1) == 0) data = object.toVariantMap();
        }
        emit browseSectionLoaded(section, page, collectionId, query, data);
    });
}

QNetworkReply *AnixApi::sendBrowseRequest(const QString &endpoint, const QString &token, const QJsonObject &body)
{
    QNetworkRequest request = createRequest(endpoint, token);
    request.setTransferTimeout(15000);
    return body.isEmpty() ? m_manager->get(request) : m_manager->post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
}

void AnixApi::addComment(const QString &section, qint64 id, const QString &message, bool spoiler, const QString &token)
{
    addCommentReply(section, id, message, spoiler, 0, 0, token);
}

void AnixApi::addCommentReply(const QString &section, qint64 id, const QString &message, bool spoiler, qint64 parentCommentId, qint64 replyToProfileId, const QString &token)
{
    const QString text = message.trimmed();
    if ((section != "articleComments" && section != "releaseComments") || id <= 0 || text.isEmpty() || token.isEmpty()) {
        emit commentAdded(section, id, {});
        return;
    }

    const QString type = section == "articleComments" ? "article" : "release";
    QNetworkReply *reply = sendCommentRequest(type, id, text, spoiler, parentCommentId, replyToProfileId, token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, section, id] {
        QJsonObject data = QJsonDocument::fromJson(reply->readAll()).object();
        if (reply->error() != QNetworkReply::NoError && data.value("code").toInt() <= 0) {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            data["code"] = status >= 400 ? status : -1;
        }
        reply->deleteLater();
        emit commentAdded(section, id, data.toVariantMap());
    });
}

QNetworkReply *AnixApi::sendCommentRequest(const QString &type, qint64 id, const QString &text, bool spoiler, qint64 parentCommentId, qint64 replyToProfileId, const QString &token)
{
    const QJsonObject body{
        {"message", text},
        {"spoiler", spoiler},
        {"parentCommentId", parentCommentId > 0 ? QJsonValue(parentCommentId) : QJsonValue(QJsonValue::Null)},
        {"replyToProfileId", replyToProfileId > 0 ? QJsonValue(replyToProfileId) : QJsonValue(QJsonValue::Null)}
    };
    QNetworkRequest request = createRequest(QString("/%1/comment/add/%2").arg(type).arg(id), token);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json; charset=UTF-8");
    request.setTransferTimeout(15000);

    return m_manager->post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
}

void AnixApi::search(const QString &query, int page)
{
    setLoading(true);
    QNetworkRequest request = createRequest(QString("/search/releases/%1").arg(page));
    QJsonObject body;
    body["query"] = query;
    QByteArray jsonData = QJsonDocument(body).toJson(QJsonDocument::Compact);

    QNetworkReply *reply = m_manager->post(request, jsonData);
    reply->setProperty("action", "search");
    connect(reply, &QNetworkReply::finished, this, &AnixApi::onReplyFinished);
}

void AnixApi::fetchCatalog(int page, int sort, int categoryId, int statusId)
{
    setLoading(true);
    QNetworkRequest request = createRequest(QString("/filter/%1").arg(page));
    QJsonObject body;
    body["sort"] = sort;
    if (categoryId > 0) body["category_id"] = categoryId;
    if (statusId > 0) body["status_id"] = statusId;
    QByteArray jsonData = QJsonDocument(body).toJson(QJsonDocument::Compact);

    QNetworkReply *reply = m_manager->post(request, jsonData);
    reply->setProperty("action", "catalog");
    connect(reply, &QNetworkReply::finished, this, &AnixApi::onReplyFinished);
}

void AnixApi::fetchRelease(qint64 releaseId, const QString &token)
{
    QNetworkReply *reply = sendBrowseRequest(QString("/release/%1").arg(releaseId), token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, releaseId] {
        reply->deleteLater();
        const QJsonObject data = reply->error() == QNetworkReply::NoError ? QJsonDocument::fromJson(reply->readAll()).object() : QJsonObject{};
        emit releaseLoaded(releaseId, data.value("release").toObject().toVariantMap());
    });
}

void AnixApi::fetchEpisodeTypes(qint64 releaseId, const QString &token)
{
    setLoading(true);
    QNetworkRequest request = createRequest(QString("/episode/%1").arg(releaseId), token);
    QNetworkReply *reply = m_manager->get(request);
    reply->setProperty("action", "episodeTypes");
    reply->setProperty("releaseId", releaseId);
    connect(reply, &QNetworkReply::finished, this, &AnixApi::onReplyFinished);
}

void AnixApi::fetchEpisodeSources(qint64 releaseId, qint64 typeId)
{
    setLoading(true);
    QNetworkRequest request = createRequest(QString("/episode/%1/%2").arg(releaseId).arg(typeId));
    QNetworkReply *reply = m_manager->get(request);
    reply->setProperty("action", "episodeSources");
    reply->setProperty("releaseId", releaseId);
    reply->setProperty("typeId", typeId);
    connect(reply, &QNetworkReply::finished, this, &AnixApi::onReplyFinished);
}

void AnixApi::fetchEpisodes(qint64 releaseId, qint64 typeId, qint64 sourceId, const QString &token)
{
    setLoading(true);
    QNetworkRequest request = createRequest(QString("/episode/%1/%2/%3").arg(releaseId).arg(typeId).arg(sourceId), token);
    QNetworkReply *reply = m_manager->get(request);
    reply->setProperty("action", "episodes");
    reply->setProperty("releaseId", releaseId);
    reply->setProperty("typeId", typeId);
    reply->setProperty("sourceId", sourceId);
    connect(reply, &QNetworkReply::finished, this, &AnixApi::onReplyFinished);
}

void AnixApi::fetchEpisodeTarget(qint64 releaseId, qint64 sourceId, int position)
{
    setLoading(true);
    QNetworkRequest request = createRequest(QString("/episode/target/%1/%2/%3").arg(releaseId).arg(sourceId).arg(position));
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    QNetworkReply *reply = m_manager->get(request);
    reply->setProperty("action", "episodeTarget");
    reply->setProperty("releaseId", releaseId);
    reply->setProperty("sourceId", sourceId);
    reply->setProperty("position", position);
    connect(reply, &QNetworkReply::finished, this, &AnixApi::onReplyFinished);
}

void AnixApi::fetchProfileList(const QString &token, int status, int page, int requestId, qint64 userId)
{
    setLoading(true);
    constexpr int newestBookmarksFirst = 1;
    const QString endpoint = status == 0 ? QString("/history/%1").arg(page)
        : (status == 6 ? QString("/favorite/all/%1").arg(page)
            : status == 7 ? QString("/collection/all/profile/%1/%2?sort=%3").arg(userId).arg(page).arg(newestBookmarksFirst)
                          : QString("/profile/list/all/%1/%2?sort=%3").arg(status).arg(page).arg(newestBookmarksFirst));
    QNetworkRequest request = createRequest(endpoint, token);
    request.setTransferTimeout(15000);
    QNetworkReply *reply = m_manager->get(request);
    reply->setProperty("action", "profileList");
    reply->setProperty("requestId", requestId);
    reply->setProperty("status", status);
    reply->setProperty("page", page);
    connect(reply, &QNetworkReply::finished, this, &AnixApi::onReplyFinished);
}

QVariantMap AnixApi::cachedProfileList(qint64 userId, int status) const
{
    return readCache(profileListCacheKey(userId, status));
}

void AnixApi::cacheProfileList(qint64 userId, int status, const QVariantList &releases, int totalCount)
{
    writeCache(profileListCacheKey(userId, status),
               {{"releases", releases}, {"totalCount", totalCount}, {"updatedAt", QDateTime::currentMSecsSinceEpoch()}});
}

void AnixApi::invalidateProfileListCache(qint64 userId, int status)
{
    const QString key = profileListCacheKey(userId, status);
    QVariantMap cache = readCache(key);
    if (cache.isEmpty()) return;

    cache["updatedAt"] = 0;
    writeCache(key, cache);
}

QVariantMap AnixApi::cachedUserProfile(qint64 userId) const
{
    return readCache(QString("profile-%1").arg(userId));
}

static QString releaseGridCacheKey(const QString &query, qint64 userId)
{
    if (query.startsWith("my:")) return userId > 0 ? QString("home-grid-my-%1").arg(userId) : QString();

    static const QStringList categories = {"anime", "donghua", "latest", "ongoing", "announced", "finished", "movies", "ova"};
    return categories.contains(query) ? QString("home-grid-%1").arg(query) : QString();
}

QVariantList AnixApi::cachedReleaseGrid(const QString &query, qint64 userId) const
{
    const QString key = releaseGridCacheKey(query, userId);
    if (key.isEmpty()) return {};

    const QVariantMap cache = readCache(key);
    return cache.value("query").toString() == query ? cache.value("rows").toList() : QVariantList{};
}

void AnixApi::cacheReleaseGrid(const QString &query, qint64 userId, const QVariantList &rows)
{
    const QString key = releaseGridCacheKey(query, userId);
    if (key.isEmpty()) return;

    static const QStringList fields = {"id", "title_ru", "title_original", "image", "grade", "year", "genres"};
    QVariantList entries;
    for (const QVariant &row : rows) {
        const QVariantMap release = row.toMap();
        QVariantMap entry;
        for (const QString &field : fields) entry.insert(field, release.value(field));
        entries.append(entry);
    }

    writeCache(key, {{"query", query}, {"rows", entries}});
}

void AnixApi::fetchUserProfile(qint64 userId, const QString &token)
{
    QNetworkReply *reply = sendBrowseRequest(QString("/profile/%1").arg(userId), token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, userId] {
        reply->deleteLater();
        const QJsonObject data = reply->error() == QNetworkReply::NoError ? QJsonDocument::fromJson(reply->readAll()).object() : QJsonObject{};
        const QVariantMap profile = data.value("profile").toObject().toVariantMap();
        if (data.value("is_my_profile").toBool() && !profile.isEmpty()) writeCache(QString("profile-%1").arg(userId), profile);
        emit userProfileLoaded(userId, profile);
    });
}

void AnixApi::saveProfilePreference(const QString &field, const QVariant &value, const QString &token)
{
    QString endpoint;
    QJsonObject body;
    if (field == "badge" && value.toLongLong() > 0) {
        endpoint = QString("/profile/preference/badge/edit/%1").arg(value.toLongLong());
    } else if (field == "status" && value.toString().size() <= 80) {
        endpoint = "/profile/preference/status/edit";
        body["status"] = value.toString();
    } else if (field == "social") {
        endpoint = "/profile/preference/social/edit";
        const QVariantMap pages = value.toMap();
        for (const QString &key : {QStringLiteral("vkPage"), QStringLiteral("tgPage"), QStringLiteral("instPage"),
                                   QStringLiteral("ttPage"), QStringLiteral("discordPage")}) {
            body[key] = pages.value(key).toString().trimmed();
        }
    } else if (field == "stats" || field == "counts" || field == "socialPrivacy" || field == "friendRequests") {
        bool valid;
        const int permission = value.toInt(&valid);
        if (valid && permission >= 0 && permission <= 2) {
            const QString name = field == "socialPrivacy" ? "social" : field;
            endpoint = QString("/profile/preference/privacy/%1/edit").arg(name);
            body["permission"] = permission;
        }
    }

    if (endpoint.isEmpty() || token.isEmpty()) {
        emit profilePreferenceSaved(field, value, false);
        return;
    }

    QNetworkReply *reply = sendBrowseRequest(endpoint, token, body);
    connect(reply, &QNetworkReply::finished, this, [this, reply, field, value] {
        reply->deleteLater();
        const bool ok = apiSucceeded(reply);
        if (ok) emit profilePreferencesChanged();
        emit profilePreferenceSaved(field, value, ok);
    });
}

void AnixApi::saveReleaseAction(qint64 releaseId, const QString &action, qint64 value, const QString &token)
{
    QString endpoint;
    if (action == "favorite" && (value == 0 || value == 1)) {
        endpoint = QString("/favorite/%1/%2").arg(value ? "add" : "delete").arg(releaseId);
    } else if (action == "rating" && value >= 0 && value <= 5) {
        endpoint = value ? QString("/release/vote/add/%1/%2").arg(releaseId).arg(value)
                         : QString("/release/vote/delete/%1").arg(releaseId);
    } else if (action == "collection" && value > 0) {
        endpoint = QString("/collectionMy/release/add/%1?release_id=%2").arg(value).arg(releaseId);
    }

    if (releaseId <= 0 || endpoint.isEmpty() || token.isEmpty()) {
        emit releaseActionSaved(releaseId, action, false);
        return;
    }

    QNetworkReply *reply = sendBrowseRequest(endpoint, token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, releaseId, action] {
        const bool success = apiSucceeded(reply);
        reply->deleteLater();
        if (success && action == "favorite") emit bookmarkListsChanged();
        emit releaseActionSaved(releaseId, action, success);
    });
}

void AnixApi::searchProfiles(const QString &query, int page)
{
    QJsonObject body;
    body["query"] = query;
    QNetworkReply *reply = sendBrowseRequest(QString("/search/profiles/%1").arg(page), "", body);
    connect(reply, &QNetworkReply::finished, this, [this, reply, page, query] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit profilesSearchLoaded({}, page, 0, query);
            return;
        }
        QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
        QJsonArray arr = obj["content"].toArray();
        int total = obj["total_count"].toInt();
        emit profilesSearchLoaded(arr.toVariantList(), page, total, query);
    });
}

void AnixApi::fetchProfileFriends(qint64 userId, int page, const QString &token)
{
    QNetworkReply *reply = sendBrowseRequest(QString("/profile/friend/all/%1/%2").arg(userId).arg(page), token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, userId, page] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit profileFriendsLoaded(userId, {}, page, 0);
            return;
        }
        QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
        QJsonArray arr = obj["content"].toArray();
        int total = obj["total_count"].toInt();
        emit profileFriendsLoaded(userId, arr.toVariantList(), page, total);
    });
}

void AnixApi::fetchProfileComments(qint64 userId, int page, const QString &type, const QString &token, int sort)
{
    const QString section = type == "article" || type == "collection" ? type : QStringLiteral("release");
    QNetworkReply *reply = sendBrowseRequest(QString("/%1/comment/all/profile/%2/%3?sort=%4").arg(section).arg(userId).arg(page).arg(sort), token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, userId, section, page] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit profileCommentsLoaded(userId, section, {}, page, 0);
            return;
        }
        QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
        QJsonArray arr = obj["content"].toArray();
        int total = obj["total_count"].toInt();
        emit profileCommentsLoaded(userId, section, arr.toVariantList(), page, total);
    });
}

void AnixApi::fetchComments(const QString &section, qint64 entityId, int page, int sort, const QString &token)
{
    const QString type = section == "articleComments" ? "article" : section == "releaseComments" ? "release" : QString();
    if (type.isEmpty() || entityId <= 0) {
        emit commentsLoaded(section, entityId, {}, page, 0, 0, false);
        return;
    }

    const QString endpoint = QString("/%1/comment/all/%2/%3?sort=%4").arg(type).arg(entityId).arg(page).arg(sort);
    QNetworkReply *reply = sendBrowseRequest(endpoint, token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, section, entityId, page] {
        const QJsonObject data = reply->error() == QNetworkReply::NoError ? QJsonDocument::fromJson(reply->readAll()).object() : QJsonObject{};
        const bool success = data.value("code").toInt(-1) == 0;
        reply->deleteLater();
        emit commentsLoaded(section, entityId, data.value("content").toArray().toVariantList(), page,
            data.value("total_count").toInt(), data.value("total_page_count").toInt(), success);
        if (section == "releaseComments") {
            emit releaseCommentsLoaded(entityId, data.value("content").toArray().toVariantList(), page, data.value("total_count").toInt());
        }
    });
}

void AnixApi::fetchReleaseComments(qint64 releaseId, int page, int sort, const QString &token)
{
    fetchComments("releaseComments", releaseId, page, sort, token);
}

void AnixApi::fetchComment(const QString &section, qint64 commentId, const QString &token)
{
    if (section != "releaseComments" || commentId <= 0) return;

    QNetworkReply *reply = sendBrowseRequest(QString("/release/comment/%1").arg(commentId), token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, section, commentId] {
        const QJsonObject data = reply->error() == QNetworkReply::NoError ? QJsonDocument::fromJson(reply->readAll()).object() : QJsonObject{};
        reply->deleteLater();
        emit commentLoaded(section, commentId, data.toVariantMap());
    });
}

void AnixApi::fetchCommentReplies(const QString &section, qint64 commentId, int page, int sort, const QString &token)
{
    const QString type = section == "articleComments" ? "article" : section == "releaseComments" ? "release" : QString();
    if (type.isEmpty() || commentId <= 0) {
        emit commentRepliesLoaded(section, commentId, {}, page, 0, 0, false);
        return;
    }

    QNetworkRequest request = createRequest(QString("/%1/comment/replies/%2/%3?sort=%4").arg(type).arg(commentId).arg(page).arg(sort), token);
    request.setTransferTimeout(15000);
    QNetworkReply *reply = m_manager->post(request, QByteArray());
    connect(reply, &QNetworkReply::finished, this, [this, reply, section, commentId, page] {
        const QJsonObject data = reply->error() == QNetworkReply::NoError ? QJsonDocument::fromJson(reply->readAll()).object() : QJsonObject{};
        const bool success = data.value("code").toInt(-1) == 0;
        reply->deleteLater();
        emit commentRepliesLoaded(section, commentId, data.value("content").toArray().toVariantList(), page,
            data.value("total_count").toInt(), data.value("total_page_count").toInt(), success);
    });
}

void AnixApi::sendCommentVote(const QString &section, qint64 commentId, int vote, const QString &token)
{
    const QString type = section == "articleComments" ? "article" : section == "releaseComments" ? "release" : QString();
    if (type.isEmpty() || commentId <= 0 || (vote != -1 && vote != 1) || token.isEmpty()) {
        emit commentVoteProcessed(section, commentId, vote, -1);
        return;
    }

    const int apiVote = vote > 0 ? 2 : 1;
    QNetworkReply *reply = sendBrowseRequest(QString("/%1/comment/vote/%2/%3").arg(type).arg(commentId).arg(apiVote), token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, section, commentId, vote] {
        const QJsonObject data = QJsonDocument::fromJson(reply->readAll()).object();
        int code = data.value("code").toInt(-1);
        if (reply->error() != QNetworkReply::NoError && code <= 0) {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            code = status >= 400 ? status : -1;
        }
        reply->deleteLater();
        emit commentVoteProcessed(section, commentId, vote, code);
    });
}

void AnixApi::editComment(const QString &section, qint64 commentId, const QString &message, bool spoiler, const QString &token)
{
    const QString type = section == "articleComments" ? "article" : section == "releaseComments" ? "release" : QString();
    const QString text = message.trimmed();
    if (type.isEmpty() || commentId <= 0 || text.isEmpty() || token.isEmpty()) {
        emit commentEditProcessed(section, commentId, text, spoiler, -1);
        return;
    }

    const QJsonObject body{{"message", text}, {"spoiler", spoiler}};
    QNetworkReply *reply = sendBrowseRequest(QString("/%1/comment/edit/%2").arg(type).arg(commentId), token, body);
    connect(reply, &QNetworkReply::finished, this, [this, reply, section, commentId, text, spoiler] {
        const int code = apiResponseCode(reply);
        reply->deleteLater();
        emit commentEditProcessed(section, commentId, text, spoiler, code);
    });
}

void AnixApi::deleteComment(const QString &section, qint64 commentId, const QString &token)
{
    const QString type = section == "articleComments" ? "article" : section == "releaseComments" ? "release" : QString();
    if (type.isEmpty() || commentId <= 0 || token.isEmpty()) {
        emit commentDeleteProcessed(section, commentId, -1);
        return;
    }

    QNetworkReply *reply = sendBrowseRequest(QString("/%1/comment/delete/%2").arg(type).arg(commentId), token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, section, commentId] {
        const int code = apiResponseCode(reply);
        reply->deleteLater();
        emit commentDeleteProcessed(section, commentId, code);
    });
}

void AnixApi::fetchVoters(const QString &section, qint64 entityId, int page, int filter, const QString &token)
{
    QString resource;
    if (section == "releaseComments") resource = "/release/comment";
    else if (section == "articleComments") resource = "/article/comment";
    else if (section == "article") resource = "/article";

    if (resource.isEmpty() || entityId <= 0 || page < 0 || filter < 0 || filter > 2) {
        emit votersLoaded(section, entityId, page, filter, {}, 0, false, false);
        return;
    }

    QNetworkRequest request = createRequest(QString("%1/votes/%2/%3?sort=%4").arg(resource).arg(entityId).arg(page).arg(filter), token);
    QNetworkReply *reply = section == "releaseComments" ? m_manager->get(request) : m_manager->post(request, QByteArray());
    connect(reply, &QNetworkReply::finished, this, [this, reply, section, entityId, page, filter] {
        const QJsonObject data = QJsonDocument::fromJson(reply->readAll()).object();
        const bool success = reply->error() == QNetworkReply::NoError && data.value("code").toInt(-1) == 0;
        reply->deleteLater();
        emit votersLoaded(section, entityId, page, filter, data.value("content").toArray().toVariantList(),
            data.value("total_count").toInt(), page < data.value("total_page_count").toInt(), success);
    });
}

static QString reportEndpoint(const QString &section)
{
    if (section == "releaseComments") return "/report/comment/release";
    if (section == "articleComments") return "/report/comment/article";
    if (section == "article") return "/report/article";
    return {};
}

void AnixApi::fetchReportReasons(const QString &section, const QString &token)
{
    const QString endpoint = reportEndpoint(section);
    if (endpoint.isEmpty() || token.isEmpty()) {
        emit reportReasonsLoaded(section, {});
        return;
    }

    QNetworkReply *reply = sendBrowseRequest(endpoint + "/reasons", token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, section] {
        const QJsonDocument data = QJsonDocument::fromJson(reply->readAll());
        const QVariantList reasons = reply->error() == QNetworkReply::NoError ? data.array().toVariantList() : QVariantList{};
        reply->deleteLater();
        emit reportReasonsLoaded(section, reasons);
    });
}

void AnixApi::submitReport(const QString &section, qint64 entityId, qint64 reasonId, const QString &message, const QString &token)
{
    const QString endpoint = reportEndpoint(section);
    const QString text = message.trimmed();
    if (endpoint.isEmpty() || entityId <= 0 || reasonId <= 0 || text.size() < 3 || text.size() > 400 || token.isEmpty()) {
        emit reportSubmitted(section, entityId, -1);
        return;
    }

    QNetworkReply *reply = sendBrowseRequest(endpoint, token, {{"entity_id", entityId}, {"reason", reasonId}, {"message", text}});
    connect(reply, &QNetworkReply::finished, this, [this, reply, section, entityId] {
        const QJsonObject data = QJsonDocument::fromJson(reply->readAll()).object();
        int code = data.value("code").toInt(-1);
        if (reply->error() != QNetworkReply::NoError && code <= 0) {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            code = status >= 400 ? status : -1;
        }
        reply->deleteLater();
        emit reportSubmitted(section, entityId, code);
    });
}

void AnixApi::sendArticleVote(qint64 articleId, int vote, const QString &token)
{
    if (articleId <= 0 || (vote != -1 && vote != 1) || token.isEmpty()) {
        emit articleVoteProcessed(articleId, vote, -1);
        return;
    }

    const int apiVote = vote > 0 ? 2 : 1;
    QNetworkReply *reply = sendBrowseRequest(QString("/article/vote/%1/%2").arg(articleId).arg(apiVote), token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, articleId, vote] {
        const QJsonObject data = QJsonDocument::fromJson(reply->readAll()).object();
        int code = data.value("code").toInt(-1);
        if (reply->error() != QNetworkReply::NoError && code <= 0) {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            code = status >= 400 ? status : -1;
        }
        reply->deleteLater();
        emit articleVoteProcessed(articleId, vote, code);
    });
}

void AnixApi::addReleaseComment(qint64 releaseId, const QString &message, bool isSpoiler, qint64 parentId, const QString &token)
{
    const QString text = message.trimmed();
    if (releaseId <= 0 || text.isEmpty() || token.isEmpty()) {
        emit releaseCommentAdded(releaseId, false);
        return;
    }

    QNetworkReply *reply = sendCommentRequest("release", releaseId, text, isSpoiler, parentId, 0, token);
    connect(reply, &QNetworkReply::finished, this, [this, reply, releaseId] {
        const QJsonObject data = reply->error() == QNetworkReply::NoError ? QJsonDocument::fromJson(reply->readAll()).object() : QJsonObject{};
        reply->deleteLater();
        emit releaseCommentAdded(releaseId, data.value("code").toInt(-1) == 0);
    });
}

void AnixApi::onReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();

    setLoading(false);

    const QString action = reply->property("action").toString();
    const qint64 releaseId = reply->property("releaseId").toLongLong();
    const qint64 sourceId = reply->property("sourceId").toLongLong();
    const int position = reply->property("position").toInt();
    if (reply->error() != QNetworkReply::NoError) {
        if (action == "episodeTarget") {
            const auto error = reply->error();
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const bool retryable = status == 408 || status == 429 || status == 502 || status == 503 || status == 504
                || (error >= QNetworkReply::ConnectionRefusedError && error <= QNetworkReply::OperationCanceledError)
                || error == QNetworkReply::TemporaryNetworkFailureError || error == QNetworkReply::NetworkSessionFailedError;
            emit episodeTargetLoaded(releaseId, sourceId, position, {{"retryable", retryable}});
        }
        if (action == "profileList") emit profileListFailed(reply->property("requestId").toInt(), reply->property("status").toInt());
        emit errorOccurred(reply->errorString());
        return;
    }

    QByteArray data = reply->readAll();
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) {
        if (action == "episodeTarget") emit episodeTargetLoaded(releaseId, sourceId, position, {});
        if (action == "profileList") emit profileListFailed(reply->property("requestId").toInt(), reply->property("status").toInt());
        return;
    }

    QJsonObject obj = doc.object();

    if (action == "search") {
        QJsonArray arr = obj.contains("content") ? obj["content"].toArray() : obj["releases"].toArray();
        emit searchLoaded(arr.toVariantList());
    } else if (action == "catalog") {
        QJsonArray arr = obj.contains("content") ? obj["content"].toArray() : obj["releases"].toArray();
        emit catalogLoaded(arr.toVariantList());
    } else if (action == "episodeTypes") {
        QVariantList types = obj["types"].toArray().toVariantList();
        emit episodeTypesLoaded(releaseId, types);
    } else if (action == "episodeSources") {
        QVariantList sources = obj["sources"].toArray().toVariantList();
        if (sources.isEmpty() && obj.contains("episodes")) {
            sources = obj["episodes"].toArray().toVariantList();
        }
        emit episodeSourcesLoaded(releaseId, reply->property("typeId").toLongLong(), sources);
    } else if (action == "episodes") {
        QVariantList eps = obj["episodes"].toArray().toVariantList();
        emit episodesLoaded(releaseId, reply->property("typeId").toLongLong(), sourceId, eps);
    } else if (action == "episodeTarget") {
        QJsonObject targetObj;
        if (obj.contains("episode") && obj["episode"].isObject()) {
            targetObj = obj["episode"].toObject();
        } else if (obj.contains("target") && obj["target"].isObject()) {
            targetObj = obj["target"].toObject();
        } else {
            targetObj = obj;
        }
        QVariantMap target = targetObj.toVariantMap();
        emit episodeTargetLoaded(releaseId, sourceId, position, target);
    } else if (action == "profileList") {
        int status = reply->property("status").toInt();
        if (obj.value("code").toInt(-1) != 0 || (!obj["content"].isArray() && !obj["releases"].isArray())) {
            emit profileListFailed(reply->property("requestId").toInt(), status);
            return;
        }
        int page = reply->property("page").toInt();
        QJsonArray arr = obj.contains("content") ? obj["content"].toArray() : obj["releases"].toArray();
        int totalCount = obj.contains("total_count") ? obj["total_count"].toInt() : arr.size();
        int totalPages = qMax(1, obj["total_page_count"].toInt() + 1);
        emit profileListLoaded(reply->property("requestId").toInt(), status, arr.toVariantList(), page, totalPages, totalCount);
    }
}
