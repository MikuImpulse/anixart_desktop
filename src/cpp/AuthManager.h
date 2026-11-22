#ifndef AUTHMANAGER_H
#define AUTHMANAGER_H

#include <QObject>
#include <QDeadlineTimer>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QTimer>
#include <QTcpServer>
#include <QTcpSocket>
#include <QUrl>
#include <QVariantMap>

class AuthManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isLoggedIn READ isLoggedIn NOTIFY authChanged)
    Q_PROPERTY(bool isAuthenticating READ isAuthenticating NOTIFY authenticatingChanged)
    Q_PROPERTY(QString token READ token NOTIFY authChanged)
    Q_PROPERTY(QString userLogin READ userLogin NOTIFY authChanged)
    Q_PROPERTY(QString userAvatar READ userAvatar NOTIFY authChanged)
    Q_PROPERTY(qint64 userId READ userId NOTIFY authChanged)
    Q_PROPERTY(QString qrPin READ qrPin NOTIFY qrUpdated)
    Q_PROPERTY(QUrl qrImage READ qrImage NOTIFY qrUpdated)
    Q_PROPERTY(QString qrStatus READ qrStatus NOTIFY qrUpdated)
    Q_PROPERTY(bool qrPending READ qrPending NOTIFY qrUpdated)
    Q_PROPERTY(bool isWaitingBrowserAuth READ isWaitingBrowserAuth NOTIFY browserAuthChanged)

public:
    explicit AuthManager(QObject *parent = nullptr);
    ~AuthManager();

    bool isLoggedIn() const { return !m_token.isEmpty(); }
    bool isAuthenticating() const { return m_isAuthenticating; }
    QString token() const { return m_token; }
    QString userLogin() const { return m_userLogin; }
    QString userAvatar() const { return m_userAvatar; }
    qint64 userId() const { return m_userId; }
    QString qrPin() const { return m_qrPin; }
    QUrl qrImage() const { return m_qrImage; }
    QString qrStatus() const { return m_qrStatus; }
    bool qrPending() const { return m_qrPending; }
    bool isWaitingBrowserAuth() const { return m_isWaitingBrowserAuth; }

    Q_INVOKABLE void signIn(const QString &login, const QString &password);
    Q_INVOKABLE void requestEmailCode(bool recovery, const QString &login, const QString &email, const QString &password);
    Q_INVOKABLE void confirmEmailCode(bool recovery, const QString &login, const QString &email, const QString &password, const QString &hash, const QString &code);

    Q_INVOKABLE void startBrowserAuth(bool bindGoogle = false);
    Q_INVOKABLE void unlinkProvider(const QString &provider);
    Q_INVOKABLE void reopenBrowserAuth();
    Q_INVOKABLE void cancelBrowserAuth();
    Q_INVOKABLE void copyToClipboard(const QString &text);

    Q_INVOKABLE void startQrAuth();
    Q_INVOKABLE void cancelQrAuth();

    Q_INVOKABLE void signOut();
    Q_INVOKABLE void loadSession();
    Q_INVOKABLE void saveSession();

signals:
    void authChanged();
    void authenticatingChanged(bool authenticating);
    void authSuccess(const QVariantMap &profile);
    void authFailed(const QString &reason);
    void emailCodeReady(const QString &hash, int length, int retryAfter);
    void passwordRestored();
    void qrUpdated();
    void browserAuthChanged();
    void providerBindingFinished(const QString &provider, bool success);

private slots:
    void onReplyFinished();
    void pollQrStatus();
    void onTcpNewConnection();

private:
    void setAuthenticating(bool authenticating);
    void processAuthResponse(const QJsonObject &obj);
    QString sessionFilePath() const;
    QNetworkReply *postAuth(const QString &path, const QVariantMap &fields, const QString &action, bool longCode = false, const QString &sessionToken = {});

    QNetworkAccessManager *m_manager;
    QString m_baseUrl;
    bool m_isAuthenticating;

    QString m_token;
    QString m_userLogin;
    QString m_userAvatar;
    qint64 m_userId;

    QString m_qrKey;
    QString m_qrSecret;
    QString m_qrPin;
    QUrl m_qrImage;
    QString m_qrStatus;
    QTimer *m_qrTimer;
    QDeadlineTimer m_qrExpiry;
    bool m_qrPending = false;
    qulonglong m_qrAttempt = 0;

    bool m_isWaitingBrowserAuth;
    QString m_activeOAuthUrl;
    QString m_browserBindingSession;
    QTcpServer *m_tcpServer;
};

#endif
