#include "StreamResolver.h"
#include <QUrlQuery>
#include <QRegularExpression>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace {
QString libriaEpisodeFile(const QString &html, const QUrl &url)
{
    static const QRegularExpression playlistPattern(R"(\bfile\s*:\s*(\[)\s*\{)");
    const auto playlist = playlistPattern.match(html);
    if (!playlist.hasMatch()) return QString(html).replace("\\/", "/");

    const qsizetype start = playlist.capturedStart(1);
    qsizetype end = start;
    int depth = 0;
    bool quoted = false;
    for (; end < html.size(); ++end) {
        const QChar ch = html.at(end);
        if (quoted && ch == QLatin1Char('\\')) {
            ++end;
        } else if (ch == QLatin1Char('"')) {
            quoted = !quoted;
        } else if (!quoted && ch == QLatin1Char('[')) {
            ++depth;
        } else if (!quoted && ch == QLatin1Char(']') && --depth == 0) {
            break;
        }
    }

    const auto entries = QJsonDocument::fromJson(html.mid(start, end - start + 1).toUtf8()).array();
    int episode = QUrlQuery(url).queryItemValue("ep").toInt();
    if (episode <= 0) {
        static const QRegularExpression episodePattern(R"(\bepisodeIndex\s*=\s*(\d+)\b)");
        episode = episodePattern.match(html).captured(1).toInt();
    }

    if (episode <= 0) return entries.at(0).toObject().value("file").toString();

    const QString episodeId = QStringLiteral("s%1").arg(episode);
    for (const QJsonValue &entry : entries) {
        const QJsonObject item = entry.toObject();
        if (item.value("id").toString() == episodeId) return item.value("file").toString();
    }

    return {};
}
}

StreamResolver::StreamResolver(QObject *parent)
    : QObject(parent)
    , m_manager(new QNetworkAccessManager(this))
    , m_isResolving(false)
{
}

void StreamResolver::setResolving(bool resolving)
{
    if (m_isResolving != resolving) {
        m_isResolving = resolving;
        emit resolvingChanged(m_isResolving);
    }
}

void StreamResolver::resetConnections()
{
    m_manager->clearConnectionCache();
}

void StreamResolver::requestLibria(const QUrl &url, bool retry)
{
    QNetworkRequest request(url);
    request.setTransferTimeout(15000);
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    request.setHeader(QNetworkRequest::UserAgentHeader, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
    request.setRawHeader("Referer", "https://anixart.libria.fun/");
    if (retry) request.setRawHeader("Connection", "close");

    QNetworkReply *reply = m_manager->get(request);
    reply->setProperty("provider", "libria");
    reply->setProperty("retry", retry);
    connect(reply, &QNetworkReply::finished, this, &StreamResolver::onReplyFinished);
}

void StreamResolver::requestLiberty(const QUrl &embedUrl, int releaseId, int episode)
{
    QUrl url(QStringLiteral("https://aniliberty.top/api/v1/anime/releases/%1").arg(releaseId));
    QUrlQuery query;
    query.addQueryItem("include", "id,is_blocked_by_geo,is_blocked_by_copyrights,episodes.ordinal,episodes.hls_480,episodes.hls_720,episodes.hls_1080");
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setTransferTimeout(10000);
    QNetworkReply *reply = m_manager->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, embedUrl, releaseId, episode] {
        reply->deleteLater();
        const QJsonObject release = QJsonDocument::fromJson(reply->readAll()).object();
        if (reply->error() == QNetworkReply::NoError && release.value("id").toInt() == releaseId) {
            if (release.value("is_blocked_by_geo").toBool() || release.value("is_blocked_by_copyrights").toBool()) {
                setResolving(false);
                emit resolveFailed("AniLiberty сообщает, что видео недоступно.");
                return;
            }

            const auto episodes = release.value("episodes").toArray();
            for (const QJsonValue &entry : episodes) {
                const QJsonObject item = entry.toObject();
                if (item.value("ordinal").toDouble() != episode) continue;

                QVariantMap streams;
                for (int quality : {480, 720, 1080}) {
                    const QUrl stream(item.value(QStringLiteral("hls_%1").arg(quality)).toString(), QUrl::StrictMode);
                    if (stream.isValid() && stream.scheme() == "https" && !stream.host().isEmpty()) {
                        streams.insert(QStringLiteral("%1p").arg(quality), stream.toString(QUrl::FullyEncoded));
                    }
                }
                if (!streams.isEmpty()) {
                    publishStreams(streams);
                    return;
                }
                break;
            }
        }

        requestLibria(embedUrl, false);
    });
}

void StreamResolver::publishStreams(const QVariantMap &streams)
{
    setResolving(false);
    const QString defaultStream = streams.value("720p", streams.value("1080p", streams.value("480p", streams.value("360p")))).toString();
    emit streamsReady(streams, defaultStream);
}

void StreamResolver::resolve(const QString &rawEpisodeUrl)
{
    if (rawEpisodeUrl.isEmpty()) {
        emit resolveFailed("Пустая ссылка на серию");
        return;
    }

    if (rawEpisodeUrl.contains(".m3u8") || rawEpisodeUrl.contains(".mp4")) {
        QVariantMap streams;
        streams["720p"] = rawEpisodeUrl;
        emit streamsReady(streams, rawEpisodeUrl);
        return;
    }

    if (rawEpisodeUrl.contains("sibnet.ru")) {
        setResolving(true);
        QUrl sibnetUrl(rawEpisodeUrl);
        QNetworkRequest request(sibnetUrl);
        request.setTransferTimeout(15000);
        request.setHeader(QNetworkRequest::UserAgentHeader, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
        request.setRawHeader("Referer", "https://video.sibnet.ru/");

        QNetworkReply *reply = m_manager->get(request);
        reply->setProperty("provider", "sibnet");
        connect(reply, &QNetworkReply::finished, this, &StreamResolver::onReplyFinished);
        return;
    }

    const QUrl episodeUrl(rawEpisodeUrl);
    const QString host = episodeUrl.host();
    if (host == "libria.fun" || host.endsWith(".libria.fun") || host == "aniliberty.top" || host.endsWith(".aniliberty.top")) {
        setResolving(true);
        const QUrlQuery query(episodeUrl);
        const int releaseId = query.queryItemValue("id").toInt();
        const int episode = query.queryItemValue("ep").toInt();
        if (host == "anixart.libria.fun" && episodeUrl.path() == "/public/iframe.php" && releaseId > 0 && episode > 0) {
            requestLiberty(episodeUrl, releaseId, episode);
        } else {
            requestLibria(episodeUrl, false);
        }
        return;
    }

    if (rawEpisodeUrl.contains("kodik")) {
        QUrl u(rawEpisodeUrl);
        QUrlQuery query(u);
        QString dVal = query.queryItemValue("d");
        QString sVal = query.queryItemValue("s");
        QString ipVal = query.queryItemValue("ip");

        QString base = u.host() + u.path();
        if (!base.startsWith("//")) {
            base.prepend("//");
        }

        if (!dVal.isEmpty()) {
            setResolving(true);
            QString kodikApiUrl = "https://kodikres.com/api/video-links?p=56a768d08f43091901c44b54fe970049&link=" + base + "&d=" + dVal;
            if (!sVal.isEmpty()) {
                kodikApiUrl += "&s=" + sVal;
            }
            if (!ipVal.isEmpty()) {
                kodikApiUrl += "&ip=" + ipVal;
            }

            QUrl apiUrl = QUrl::fromEncoded(kodikApiUrl.toUtf8());
            QNetworkRequest request(apiUrl);
            request.setTransferTimeout(15000);
            request.setHeader(QNetworkRequest::UserAgentHeader, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.198 Safari/537.36");
            request.setRawHeader("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9");

            QNetworkReply *reply = m_manager->get(request);
            reply->setProperty("provider", "kodik");
            connect(reply, &QNetworkReply::finished, this, &StreamResolver::onReplyFinished);
            return;
        }
    }

    QVariantMap streams;
    streams["default"] = rawEpisodeUrl;
    emit streamsReady(streams, rawEpisodeUrl);
}

void StreamResolver::onReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();

    const QString provider = reply->property("provider").toString();
    const auto error = reply->error();
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const bool transientError = (error >= QNetworkReply::ConnectionRefusedError && error <= QNetworkReply::OperationCanceledError)
        || error == QNetworkReply::TemporaryNetworkFailureError || error == QNetworkReply::NetworkSessionFailedError
        || status == 408 || status == 429 || status == 502 || status == 503 || status == 504;
    if (provider == "libria" && transientError && !reply->property("retry").toBool()) {
        requestLibria(reply->request().url(), true);
        return;
    }

    setResolving(false);
    if (error != QNetworkReply::NoError) {
        if (provider == "sibnet") {
            emit resolveFailed("Видео на Sibnet недоступно или заблокировано в регионе. Попробуйте выбрать другой источник.");
        } else if (provider == "libria") {
            if (transientError) {
                emit resolveFailed("Сервер видео не ответил после повторной попытки.", true);
            } else if (status == 404 || status == 410) {
                emit resolveFailed("Серия недоступна в источнике Liberty / Libria. Выберите другой источник, если он есть.");
            } else if (status > 0) {
                emit resolveFailed(QStringLiteral("Сервер источника Liberty / Libria вернул ошибку HTTP %1.").arg(status));
            } else {
                emit resolveFailed("Не удалось подключиться к источнику Liberty / Libria.");
            }
        } else {
            emit resolveFailed("Ошибка загрузки видео (" + provider + "): " + reply->errorString(), transientError);
        }
        return;
    }

    const QByteArray data = reply->readAll();

    if (provider == "sibnet") {
        QRegularExpression re(R"(src:\s*["']([^"']+\.mp4[^"']*)["'])");
        QRegularExpressionMatch match = re.match(QString::fromUtf8(data));
        if (match.hasMatch()) {
            QString mp4Path = match.captured(1).trimmed();
            QString fullUrl;
            if (mp4Path.startsWith("http")) {
                fullUrl = mp4Path;
            } else if (mp4Path.startsWith("//")) {
                fullUrl = "https:" + mp4Path;
            } else {
                fullUrl = "https://video.sibnet.ru" + (mp4Path.startsWith("/") ? mp4Path : "/" + mp4Path);
            }
            fullUrl.replace(":443", "");

            QVariantMap streams;
            streams["720p"] = fullUrl;
            emit streamsReady(streams, fullUrl);
        } else {
            emit resolveFailed("Видео на Sibnet удалено или недоступно. Переключите источник на Kodik или Libria.");
        }
        return;
    }

    if (provider == "libria") {
        static const QRegularExpression qualityPattern(R"(\[(360p|480p|720p|1080p)\]\s*((?:https?:)?//[^\s,"'<>]+))");
        const QString files = libriaEpisodeFile(QString::fromUtf8(data), reply->url());
        QVariantMap streams;
        auto matches = qualityPattern.globalMatch(files);
        while (matches.hasNext()) {
            const auto match = matches.next();
            const QUrl stream = reply->url().resolved(QUrl(match.captured(2), QUrl::StrictMode));
            if (stream.isValid() && !stream.host().isEmpty()
                && (stream.path().endsWith(".m3u8", Qt::CaseInsensitive) || stream.path().endsWith(".mp4", Qt::CaseInsensitive))) {
                streams.insert(match.captured(1), stream.toString(QUrl::FullyEncoded));
            }
        }

        if (streams.isEmpty()) {
            emit resolveFailed("Потоки Libria не найдены на странице.");
        } else {
            publishStreams(streams);
        }
        return;
    }

    const QJsonDocument document = QJsonDocument::fromJson(data);
    if (document.isNull()) {
        emit resolveFailed("Сервер Kodik вернул некорректный ответ.");
        return;
    }

    const QJsonValue links = document.isArray() ? QJsonValue(document.array()) : document.object().value("links");
    const QJsonObject linksByQuality = links.toObject();
    const QJsonArray linkEntries = links.toArray();
    QVariantMap streams;

    const QStringList qualities = {"360", "480", "720", "1080"};
    for (const QString &quality : qualities) {
        QJsonValue candidates = linksByQuality.value(quality);
        for (const QJsonValue &entry : linkEntries) {
            const QJsonObject object = entry.toObject();
            if (object.contains(quality)) {
                candidates = object.value(quality);
                break;
            }
            if (object.value("quality").toVariant().toString() == quality) {
                candidates = entry;
                break;
            }
        }

        const QJsonArray sources = candidates.isArray() ? candidates.toArray() : QJsonArray{candidates};
        for (const QJsonValue &source : sources) {
            const QJsonObject object = source.toObject();
            QString src = object.value("Src").toString().trimmed();
            if (src.isEmpty()) {
                src = object.value("src").toString().trimmed();
            }
            if (src.startsWith("//")) {
                src.prepend("https:");
            }
            src.replace(":hls:hls.m3u8", ":hls:manifest.m3u8");
            const QUrl url(src, QUrl::StrictMode);
            if (!url.isValid() || url.host().isEmpty() || (url.scheme() != "https" && url.scheme() != "http")) {
                continue;
            }
            streams.insert(quality + "p", url.toString(QUrl::FullyEncoded));
            break;
        }
    }

    if (streams.isEmpty()) {
        emit resolveFailed("Видеопотоки не найдены в источнике. Попробуйте сменить источник.");
    } else {
        publishStreams(streams);
    }
}
