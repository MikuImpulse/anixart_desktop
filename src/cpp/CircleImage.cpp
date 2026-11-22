#include "CircleImage.h"
#include <QPainter>
#include <QPainterPath>
#include <QCache>
#include <QBuffer>
#include <QFile>
#include <QImageReader>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QQmlEngine>
#include <QSaveFile>
#include <QtMath>

static QCache<QString, QImage> imageCache(48 * 1024);

CircleImage::CircleImage(QQuickItem *parent)
    : QQuickPaintedItem(parent)
    , m_cornerRadius(-1)
{
    setOpaquePainting(false);
}

void CircleImage::setSource(const QString &source)
{
    if (m_source == source) return;

    m_source = source;
    emit sourceChanged();
    loadImage();
}

void CircleImage::setCornerRadius(qreal radius)
{
    if (qFuzzyCompare(m_cornerRadius, radius)) return;

    m_cornerRadius = radius;
    emit cornerRadiusChanged();
    update();
}

void CircleImage::setSquareBottom(bool squareBottom)
{
    if (m_squareBottom == squareBottom) return;

    m_squareBottom = squareBottom;
    emit squareBottomChanged();
    update();
}

void CircleImage::saveOriginal(const QUrl &source, const QUrl &destination)
{
    if (!destination.isLocalFile() || destination.toLocalFile().isEmpty()) {
        emit originalSaved(tr("Выберите локальный файл для сохранения."));
        return;
    }

    const auto save = [this, path = destination.toLocalFile()](QIODevice &original) {
        if (QImageReader::imageFormat(&original).isEmpty() || !original.seek(0)) {
            emit originalSaved(tr("Не удалось прочитать изображение постера."));
            return;
        }

        const QByteArray data = original.readAll();
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size() || !file.commit()) {
            emit originalSaved(file.errorString());
            return;
        }
        emit originalSaved({});
    };

    if (source.isLocalFile() || source.scheme() == "qrc") {
        QFile file(source.isLocalFile() ? source.toLocalFile() : ':' + source.path());
        if (!file.open(QIODevice::ReadOnly)) {
            emit originalSaved(file.errorString());
            return;
        }
        save(file);
        return;
    }

    QQmlEngine *engine = qmlEngine(this);
    if (!engine || (source.scheme() != "https" && source.scheme() != "http")) {
        emit originalSaved(tr("Ссылка на постер недоступна."));
        return;
    }

    QNetworkRequest request(source);
    request.setHeader(QNetworkRequest::UserAgentHeader, "AnixartApp/11-beta-3");
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::PreferCache);
    request.setTransferTimeout(15000);
    QNetworkReply *reply = engine->networkAccessManager()->get(request);
    connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);
    connect(reply, &QNetworkReply::finished, this, [this, reply, save] {
        if (reply->error() != QNetworkReply::NoError) {
            emit originalSaved(tr("Не удалось скачать постер."));
            return;
        }

        QBuffer original;
        original.setData(reply->readAll());
        original.open(QIODevice::ReadOnly);
        save(original);
    });
}

void CircleImage::loadImage()
{
    m_image = QImage();
    update();
    if (m_source.isEmpty()) return;

    if (const QImage *image = imageCache.object(m_source)) {
        m_image = *image;
        update();
        return;
    }

    if (m_source.startsWith("http://") || m_source.startsWith("https://")) {
        QQmlEngine *engine = qmlEngine(this);
        if (!engine) return;

        QUrl url(m_source);
        QNetworkRequest req(url);
        req.setHeader(QNetworkRequest::UserAgentHeader, "AnixartApp/11-beta-3");
        QNetworkReply *reply = engine->networkAccessManager()->get(req);
        QString currentSrc = m_source;
        connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);
        QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, currentSrc]() {
            if (reply->error() != QNetworkReply::NoError || m_source != currentSrc) return;

            if (m_image.loadFromData(reply->readAll())) {
                imageCache.insert(currentSrc, new QImage(m_image), m_image.sizeInBytes() / 1024 + 1);
                update();
            }
        });
    } else {
        QString localPath = m_source;
        if (localPath.startsWith("qrc:")) {
            localPath = localPath.mid(3);
        } else if (localPath.startsWith("file:")) {
            localPath = QUrl(localPath).toLocalFile();
        }
        if (m_image.load(localPath)) {
            imageCache.insert(m_source, new QImage(m_image), m_image.sizeInBytes() / 1024 + 1);
            update();
        }
    }
}

void CircleImage::paint(QPainter *painter)
{
    if (m_image.isNull()) return;

    painter->setRenderHint(QPainter::Antialiasing, true);
    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);

    QRectF rect = boundingRect();
    QPainterPath path;
    if (m_cornerRadius > 0) {
        const qreal radius = qMin(m_cornerRadius, qMin(rect.width(), rect.height()) / 2);
        path.addRoundedRect(rect.adjusted(0, 0, 0, m_squareBottom ? radius : 0), radius, radius);
    } else {
        path.addEllipse(rect);
    }

    const QSizeF scaled = QSizeF(m_image.size()).scaled(rect.size(), Qt::KeepAspectRatioByExpanding);

    QRectF drawRect(
        rect.x() + (rect.width() - scaled.width()) / 2.0,
        rect.y() + (rect.height() - scaled.height()) / 2.0,
        scaled.width(),
        scaled.height()
    );

    if (drawRect.isEmpty()) return;

    const QRectF deviceRect = painter->deviceTransform().mapRect(drawRect);
    const QSize textureSize(qBound(1, qCeil(deviceRect.width()), m_image.width()),
                            qBound(1, qCeil(deviceRect.height()), m_image.height()));
    const QImage texture = textureSize == m_image.size()
        ? m_image : m_image.scaled(textureSize, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);

    painter->setBrushOrigin(drawRect.topLeft());
    QBrush imageBrush(texture);
    imageBrush.setTransform(QTransform::fromScale(drawRect.width() / texture.width(), drawRect.height() / texture.height()));
    painter->fillPath(path, imageBrush);
}
