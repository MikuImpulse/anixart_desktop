#include "AuthManager.h"
#include <QBuffer>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QUrlQuery>
#include <QUuid>
#include <QDesktopServices>
#include <QUrl>
#include <QGuiApplication>
#include <QClipboard>
#include <QRegularExpression>
#include <memory>
#include <qrencode.h>

static QUrl phoneSignInQr(const QString &key)
{
    QUrl link("https://anixart-app.com/sign-in/qr");
    QUrlQuery query;
    query.addQueryItem("key", key);
    link.setQuery(query);

    const QByteArray encodedLink = link.toEncoded();
    const std::unique_ptr<QRcode, decltype(&QRcode_free)> code(
        QRcode_encodeString8bit(encodedLink.constData(), 0, QR_ECLEVEL_M), QRcode_free);
    if (!code) return {};

    constexpr int margin = 4;
    const int size = code->width + 2 * margin;
    QImage image(size, size, QImage::Format_Grayscale8);
    image.fill(255);
    for (int y = 0; y < code->width; ++y) {
        auto *row = image.scanLine(y + margin) + margin;
        for (int x = 0; x < code->width; ++x) {
            if (code->data[y * code->width + x] & 1) row[x] = 0;
        }
    }

    QByteArray png;
    QBuffer buffer(&png);
    buffer.open(QIODevice::WriteOnly);
    if (!image.save(&buffer, "PNG")) return {};
    return QUrl::fromEncoded("data:image/png;base64," + png.toBase64());
}

AuthManager::AuthManager(QObject *parent)
    : QObject(parent)
    , m_manager(new QNetworkAccessManager(this))
    , m_baseUrl("https://api-s.anixsekai.com")
    , m_isAuthenticating(false)
    , m_userId(0)
    , m_qrTimer(new QTimer(this))
    , m_isWaitingBrowserAuth(false)
    , m_tcpServer(nullptr)

{
    connect(m_qrTimer, &QTimer::timeout, this, &AuthManager::pollQrStatus);
    m_qrTimer->setSingleShot(true);
    loadSession();
}

AuthManager::~AuthManager()
{
    cancelQrAuth();
    cancelBrowserAuth();
}

void AuthManager::setAuthenticating(bool authenticating)
{
    if (m_isAuthenticating != authenticating) {
        m_isAuthenticating = authenticating;
        emit authenticatingChanged(m_isAuthenticating);
    }
}

QString AuthManager::sessionFilePath() const
{
#ifdef Q_OS_LINUX
    const QString configDir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/anixart_linux";
#else
    const QString configDir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
#endif
    QDir().mkpath(configDir);
    return configDir + "/session.json";
}

void AuthManager::loadSession()
{
    QFile file(sessionFilePath());
    if (!file.open(QIODevice::ReadOnly)) return;

    QByteArray data = file.readAll();
    file.close();

    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) return;

    QJsonObject obj = doc.object();
    m_token = obj["token"].toString();
    QJsonObject profile = obj["profile"].toObject();
    m_userLogin = profile["login"].toString();
    m_userAvatar = profile["avatar"].toString();
    m_userId = profile["id"].toVariant().toLongLong();

    emit authChanged();
}

void AuthManager::saveSession()
{
    QJsonObject profile;
    profile["login"] = m_userLogin;
    profile["avatar"] = m_userAvatar;
    profile["id"] = m_userId;

    QJsonObject obj;
    obj["token"] = m_token;
    obj["profile"] = profile;

    QFile file(sessionFilePath());
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(obj).toJson());
        file.close();
    }
}

void AuthManager::signOut()
{
    m_token.clear();
    m_userLogin.clear();
    m_userAvatar.clear();
    m_userId = 0;

    QFile::remove(sessionFilePath());
    emit authChanged();
}

QNetworkReply *AuthManager::postAuth(const QString &path, const QVariantMap &fields, const QString &action, bool longCode, const QString &sessionToken)
{
    QUrl url(m_baseUrl + path);
    if (!sessionToken.isEmpty()) {
        QUrlQuery query;
        query.addQueryItem("token", sessionToken);
        url.setQuery(query);
    }

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, "AnixartApp/11-beta-3");
    request.setRawHeader("API-Version", "3");
    if (longCode) request.setRawHeader("X-Long-Code", "1");
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    request.setTransferTimeout(15000);

    QByteArray body;
    for (auto it = fields.cbegin(); it != fields.cend(); ++it) {
        if (!body.isEmpty()) body += '&';
        body += QUrl::toPercentEncoding(it.key()) + '=' + QUrl::toPercentEncoding(it.value().toString());
    }

    QNetworkReply *reply = m_manager->post(request, body);
    reply->setProperty("action", action);
    connect(reply, &QNetworkReply::finished, this, &AuthManager::onReplyFinished);
    return reply;
}

void AuthManager::requestEmailCode(bool recovery, const QString &login, const QString &email, const QString &password)
{
    if (m_isAuthenticating || login.trimmed().isEmpty() || password.isEmpty() || (!recovery && email.trimmed().isEmpty())) return;

    setAuthenticating(true);
    if (recovery) {
        postAuth("/auth/restore", {{"data", login.trimmed()}}, "emailCode", true);
    } else {
        postAuth("/auth/signUp", {{"login", login.trimmed()}, {"email", email.trimmed()}, {"password", password}}, "emailCode", true);
    }
}

void AuthManager::confirmEmailCode(bool recovery, const QString &login, const QString &email, const QString &password, const QString &hash, const QString &code)
{
    if (m_isAuthenticating || hash.isEmpty()) return;

    QVariantMap fields{{"password", password}, {"hash", hash}};
    if (!code.isEmpty()) fields.insert("code", code);
    if (recovery) {
        fields.insert("data", login.trimmed());
    } else {
        fields.insert("login", login.trimmed());
        fields.insert("email", email.trimmed());
    }

    setAuthenticating(true);
    if (code.isEmpty()) {
        auto *reply = postAuth(recovery ? "/auth/restore/resend" : "/auth/resend", fields, "emailResend", true);
        reply->setProperty("verificationHash", hash);
    } else {
        postAuth(recovery ? "/auth/restore/verify" : "/auth/verify", fields, recovery ? "restoreVerify" : "signUpVerify");
    }
}

void AuthManager::signIn(const QString &login, const QString &password)
{
    const QString account = login.trimmed();
    if (m_isAuthenticating || m_isWaitingBrowserAuth || account.isEmpty() || password.isEmpty()) return;

    setAuthenticating(true);
    postAuth("/auth/signIn", {{"login", account}, {"password", password}}, "signIn");
}

static void sendBrowserResponse(QTcpSocket *socket, const QByteArray &status, const QByteArray &body, const QByteArray &type = "text/plain; charset=utf-8")
{
    socket->write("HTTP/1.1 " + status + "\r\nContent-Type: " + type + "\r\nCache-Control: no-store"
        "\r\nReferrer-Policy: no-referrer\r\nX-Frame-Options: DENY\r\nConnection: close"
        "\r\nContent-Length: " + QByteArray::number(body.size()) + "\r\n\r\n" + body);
    socket->disconnectFromHost();
}

void AuthManager::onTcpNewConnection()
{
    while (QTcpSocket *socket = m_tcpServer->nextPendingConnection()) {
        socket->setParent(this);
        socket->setReadBufferSize(32769);
        connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        QTimer::singleShot(10000, socket, &QTcpSocket::abort);

        connect(socket, &QTcpSocket::readyRead, this, [this, socket, buffer = QByteArray()]() mutable {
            buffer += socket->readAll();
            constexpr int maxRequestSize = 32768;
            if (buffer.size() > maxRequestSize) {
                sendBrowserResponse(socket, "413 Payload Too Large", {});
                return;
            }

            const qsizetype separator = buffer.indexOf("\r\n\r\n");
            if (separator < 0) return;

            const auto headers = buffer.left(separator).split('\n');
            const auto requestLine = headers.first().trimmed().split(' ');
            const QUrl callback(m_activeOAuthUrl);
            if (!m_isWaitingBrowserAuth || requestLine.size() != 3 || requestLine.at(1) != callback.path().toUtf8()) {
                sendBrowserResponse(socket, "404 Not Found", {});
                return;
            }

            if (requestLine.first() == "GET") {
                QFile html(":/auth/google.html");
                if (!html.open(QIODevice::ReadOnly)) {
                    sendBrowserResponse(socket, "500 Internal Server Error", {});
                    return;
                }
                sendBrowserResponse(socket, "200 OK", html.readAll(), "text/html; charset=utf-8");
                return;
            }

            QByteArray origin;
            int contentLength = -1;
            for (const QByteArray &header : headers) {
                const qsizetype colon = header.indexOf(':');
                if (colon < 0) continue;
                const QByteArray key = header.left(colon).toLower();
                if (key == "origin") origin = header.mid(colon + 1).trimmed();
                if (key == "content-length") {
                    bool valid = false;
                    contentLength = header.mid(colon + 1).trimmed().toInt(&valid);
                    if (!valid) contentLength = -1;
                }
            }

            const QByteArray expectedOrigin = "http://localhost:" + QByteArray::number(callback.port());
            if (requestLine.first() != "POST" || origin != expectedOrigin || contentLength <= 0
                || contentLength > 16384) {
                sendBrowserResponse(socket, "400 Bad Request", {});
                return;
            }

            const qsizetype bodyStart = separator + 4;
            if (buffer.size() - bodyStart < contentLength) return;

            const QByteArray token = buffer.mid(bodyStart, contentLength);
            static const QRegularExpression jwtPattern("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$");
            if (!jwtPattern.match(QString::fromLatin1(token)).hasMatch()) {
                sendBrowserResponse(socket, "400 Bad Request", {});
                return;
            }

            sendBrowserResponse(socket, "200 OK", {});
            const QString bindingSession = m_browserBindingSession;
            cancelBrowserAuth();
            if (!bindingSession.isEmpty() && bindingSession != m_token) {
                emit providerBindingFinished("google", false);
                return;
            }

            setAuthenticating(true);
            if (bindingSession.isEmpty()) {
                postAuth("/auth/google", {{"googleIdToken", QString::fromLatin1(token)}}, "signInGoogle");
            } else {
                postAuth("/profile/preference/google/bind", {{"idToken", QString::fromLatin1(token)}}, "providerBinding", false, bindingSession)
                    ->setProperty("provider", "google");
            }
        });
    }
}

void AuthManager::startBrowserAuth(bool bindGoogle)
{
    if (m_isAuthenticating || m_isWaitingBrowserAuth || (bindGoogle && m_token.isEmpty())) return;

    m_tcpServer = new QTcpServer(this);
    if (!m_tcpServer->listen(QHostAddress::LocalHost)) {
        cancelBrowserAuth();
        emit authFailed("Не удалось открыть локальный адрес для входа через Google.");
        return;
    }

    connect(m_tcpServer, &QTcpServer::newConnection, this, &AuthManager::onTcpNewConnection);
    m_activeOAuthUrl = QString("http://localhost:%1/auth/%2").arg(m_tcpServer->serverPort())
        .arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    m_browserBindingSession = bindGoogle ? m_token : QString{};
    m_isWaitingBrowserAuth = true;
    emit browserAuthChanged();

    QTimer::singleShot(600000, m_tcpServer, [this] {
        cancelBrowserAuth();
        emit authFailed("Время входа через Google истекло. Откройте вход снова.");
    });
    reopenBrowserAuth();
}

void AuthManager::reopenBrowserAuth()
{
    if (!m_isWaitingBrowserAuth || QDesktopServices::openUrl(QUrl(m_activeOAuthUrl))) return;

    cancelBrowserAuth();
    emit authFailed("Не удалось открыть браузер.");
}

void AuthManager::cancelBrowserAuth()
{
    if (m_tcpServer) {
        m_tcpServer->close();
        m_tcpServer->deleteLater();
        m_tcpServer = nullptr;
    }
    if (!m_isWaitingBrowserAuth) return;

    m_isWaitingBrowserAuth = false;
    m_activeOAuthUrl.clear();
    m_browserBindingSession.clear();
    emit browserAuthChanged();
}

void AuthManager::unlinkProvider(const QString &provider)
{
    if (m_isAuthenticating || m_isWaitingBrowserAuth || m_token.isEmpty()) return;
    if (provider != "google" && provider != "vk" && provider != "yandex" && provider != "telegram") return;

    setAuthenticating(true);
    postAuth("/profile/preference/" + provider + "/unbind", {}, "providerBinding", false, m_token)
        ->setProperty("provider", provider);
}

void AuthManager::copyToClipboard(const QString &text)
{
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (clipboard) {
        clipboard->setText(text);
    }
}

void AuthManager::startQrAuth()
{
    cancelQrAuth();
    m_qrPending = true;
    m_qrStatus = "Создание QR сессии...";
    emit qrUpdated();

    auto *reply = postAuth("/auth/qr/create", {{"device", "Anixart Desktop"}}, "qrCreate");
    reply->setProperty("qrAttempt", m_qrAttempt);
}

void AuthManager::cancelQrAuth()
{
    ++m_qrAttempt;
    m_qrTimer->stop();
    m_qrPending = false;
    m_qrKey.clear();
    m_qrSecret.clear();
    m_qrPin.clear();
    m_qrImage.clear();
    m_qrStatus.clear();
    emit qrUpdated();
}

void AuthManager::pollQrStatus()
{
    if (m_qrKey.isEmpty() || m_qrSecret.isEmpty()) return;
    if (m_qrExpiry.hasExpired()) {
        cancelQrAuth();
        m_qrStatus = "Срок действия кода истёк. Получите новый код.";
        emit qrUpdated();
        return;
    }

    auto *reply = postAuth("/auth/qr/status", {{"key", m_qrKey}, {"secret", m_qrSecret}}, "qrStatus");
    reply->setProperty("qrAttempt", m_qrAttempt);
}

void AuthManager::onReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();

    QString action = reply->property("action").toString();
    QByteArray data = reply->readAll();

    const bool qr = action == "qrCreate" || action == "qrStatus";
    if (qr && reply->property("qrAttempt").toULongLong() != m_qrAttempt) return;
    if (!qr) setAuthenticating(false);

    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject() || reply->error() != QNetworkReply::NoError
        || reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() / 100 != 2) {
        if (action == "providerBinding") {
            emit providerBindingFinished(reply->property("provider").toString(), false);
        } else if (action == "qrStatus" && !m_qrExpiry.hasExpired()) {
            m_qrStatus = "Связь прервалась. Проверяем подтверждение ещё раз…";
            emit qrUpdated();
            m_qrTimer->start();
        } else if (qr) {
            m_qrPending = false;
            m_qrImage.clear();
            m_qrPin.clear();
            m_qrStatus = "Не удалось связаться с Anixart. Обновите код.";
            emit qrUpdated();
        } else {
            emit authFailed("Не удалось связаться с сервером авторизации Anixart.");
        }
        return;
    }

    const QJsonObject obj = doc.object();
    const int code = obj["code"].toInt(-1);
    if (action == "providerBinding") {
        emit providerBindingFinished(reply->property("provider").toString(), code == 0);
        return;
    }

    if (action == "qrCreate") {
        m_qrKey = obj["key"].toString();
        m_qrSecret = obj["secret"].toString();
        m_qrPin = obj["pin"].toString();
        if (code == 0 && !m_qrKey.isEmpty() && !m_qrSecret.isEmpty() && !m_qrPin.isEmpty()) {
            m_qrImage = phoneSignInQr(m_qrKey);
        }
        if (!m_qrImage.isEmpty()) {
            m_qrExpiry = QDeadlineTimer(qBound(1, obj["expires_in"].toInt(600), 3600) * 1000);
            m_qrStatus = "Ожидание подтверждения на телефоне…";
            m_qrTimer->start(qBound(1, obj["poll_interval"].toInt(3), 60) * 1000);
        } else {
            m_qrPending = false;
            m_qrPin.clear();
            m_qrStatus = "Не удалось создать код входа.";
        }
        emit qrUpdated();
        return;
    }

    if (action == "qrStatus") {
        const int status = obj["status"].toInt(-1);
        if (code == 0 && (status == 0 || status == 1)) {
            m_qrStatus = status == 0 ? "Ожидание подтверждения на телефоне…" : "Подтвердите вход на телефоне.";
            emit qrUpdated();
            m_qrTimer->start();
        } else if (code == 0 && status == 2) {
            m_qrPending = false;
            m_qrStatus = "Вход подтверждён.";
            emit qrUpdated();
            processAuthResponse(obj);
        } else {
            m_qrPending = false;
            m_qrImage.clear();
            m_qrPin.clear();
            m_qrStatus = code == 2 ? "Срок действия кода истёк."
                : code == 3 ? "Вход отклонён на телефоне."
                : code == 4 ? "Слишком много попыток. Получите новый код." : "Не удалось подтвердить вход.";
            emit qrUpdated();
        }
        return;
    }

    if (action == "emailCode" || action == "emailResend") {
        const QString hash = obj["hash"].toString(reply->property("verificationHash").toString());
        if (hash.isEmpty() || (code != 0 && action == "emailResend")) {
            emit authFailed(obj["message"].toString("Не удалось отправить код (" + QString::number(code) + ")."));
            return;
        }
        emit emailCodeReady(hash, qBound(4, obj["code_length"].toInt(5), 12), qBound(30, obj["code_time_left"].toInt(60), 600));
        return;
    }

    if (action == "restoreVerify" && code == 0) {
        emit passwordRestored();
        return;
    }

    if (code == 0) {
        processAuthResponse(obj);
    } else {
        QString errorMsg = obj["message"].toString("Ошибка авторизации (" + QString::number(code) + ")");
        if (action == "signIn" && code == 2) errorMsg = "Anixart не нашёл аккаунт с таким логином или почтой.";
        if (action == "signIn" && code == 3) errorMsg = "Anixart отклонил пароль. Проверьте пароль от аккаунта Anixart.";
        if (action == "signInGoogle" && code == 2) errorMsg = "Anixart отклонил вход через Google. Попробуйте снова или войдите через QR/PIN.";
        if (action == "restoreVerify" || action == "signUpVerify") {
            const bool recovery = action == "restoreVerify";
            if (code == (recovery ? 4 : 7)) {
                errorMsg = "Неверный код.";
            } else if (code == (recovery ? 6 : 9)) {
                errorMsg = "Этот код больше не действует. Запросите новый.";
            } else {
                errorMsg = obj["message"].toString("Не удалось проверить код. Запросите новый и попробуйте ещё раз.");
            }
        }
        emit authFailed(errorMsg);
    }
}

void AuthManager::processAuthResponse(const QJsonObject &obj)
{
    QString token = obj["profileToken"].toObject()["token"].toString();
    if (token.isEmpty()) token = obj["profile_token"].toObject()["token"].toString();
    if (token.isEmpty()) token = obj["token"].toString();

    const QJsonObject profile = obj["profile"].toObject();
    const qint64 userId = profile["id"].toVariant().toLongLong();
    if (token.isEmpty() || userId <= 0) {
        emit authFailed("Anixart не вернул данные сеанса.");
        return;
    }

    m_token = token;
    m_userLogin = profile["login"].toString();
    m_userAvatar = profile["avatar"].toString();
    m_userId = userId;

    saveSession();
    emit authChanged();
    emit authSuccess(profile.toVariantMap());
}
