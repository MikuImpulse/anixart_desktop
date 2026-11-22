#ifndef STREAMRESOLVER_H
#define STREAMRESOLVER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QVariantMap>

class StreamResolver : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isResolving READ isResolving NOTIFY resolvingChanged)

public:
    explicit StreamResolver(QObject *parent = nullptr);

    bool isResolving() const { return m_isResolving; }

    Q_INVOKABLE void resolve(const QString &rawEpisodeUrl);
    Q_INVOKABLE void resetConnections();

signals:
    void resolvingChanged(bool resolving);
    void streamsReady(const QVariantMap &streams, const QString &defaultStream);
    void resolveFailed(const QString &reason, bool retryable = false);

private slots:
    void onReplyFinished();

private:
    void setResolving(bool resolving);
    void requestLibria(const QUrl &url, bool retry);
    void requestLiberty(const QUrl &embedUrl, int releaseId, int episode);
    void publishStreams(const QVariantMap &streams);

    QNetworkAccessManager *m_manager;
    bool m_isResolving;
};

#endif
