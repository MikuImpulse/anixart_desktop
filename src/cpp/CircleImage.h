#ifndef CIRCLEIMAGE_H
#define CIRCLEIMAGE_H

#include <QQuickPaintedItem>
#include <QImage>
#include <QUrl>

class CircleImage : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(qreal cornerRadius READ cornerRadius WRITE setCornerRadius NOTIFY cornerRadiusChanged)
    Q_PROPERTY(bool squareBottom READ squareBottom WRITE setSquareBottom NOTIFY squareBottomChanged)

public:
    explicit CircleImage(QQuickItem *parent = nullptr);
    ~CircleImage() override = default;

    QString source() const { return m_source; }
    void setSource(const QString &source);

    qreal cornerRadius() const { return m_cornerRadius; }
    void setCornerRadius(qreal radius);

    bool squareBottom() const { return m_squareBottom; }
    void setSquareBottom(bool squareBottom);
    Q_INVOKABLE void saveOriginal(const QUrl &source, const QUrl &destination);

    void paint(QPainter *painter) override;

signals:
    void sourceChanged();
    void cornerRadiusChanged();
    void squareBottomChanged();
    void originalSaved(const QString &error);

private:
    void loadImage();

    QString m_source;
    qreal m_cornerRadius;
    bool m_squareBottom = false;
    QImage m_image;
};

#endif
