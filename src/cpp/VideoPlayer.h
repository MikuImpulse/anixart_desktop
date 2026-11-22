#ifndef VIDEOPLAYER_H
#define VIDEOPLAYER_H

#include <QQuickPaintedItem>
#include <QImage>
#include <QMutex>
#include <QTimer>
#include <atomic>
#include <gst/gst.h>
#include <gst/app/gstappsink.h>

class VideoPlayer : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY playingChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 seekPosition READ seekPosition NOTIFY seekPositionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool isBuffering READ isBuffering NOTIFY bufferingChanged)
    Q_PROPERTY(int bufferingPercent READ bufferingPercent NOTIFY bufferingChanged)
    Q_PROPERTY(bool isReady READ isReady NOTIFY readyChanged)
    Q_PROPERTY(int videoHeight READ videoHeight NOTIFY videoHeightChanged)

public:
    explicit VideoPlayer(QQuickItem *parent = nullptr);
    ~VideoPlayer() override;

    void paint(QPainter *painter) override;

    QString source() const { return m_source; }
    void setSource(const QString &source);

    bool isPlaying() const { return m_isPlaying; }
    qint64 position() const { return m_position; }
    qint64 seekPosition() const;
    qint64 duration() const { return m_duration; }
    qreal volume() const { return m_volume; }
    Q_INVOKABLE void setVolume(qreal volume);

    bool isBuffering() const { return m_isBuffering; }
    int bufferingPercent() const { return m_bufferingPercent; }
    bool isReady() const { return m_isReady; }
    int videoHeight() const { return m_videoHeight; }

    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void togglePlay();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void load(const QString &source, qint64 position, bool autoplay, bool preserveFrame = false);
    Q_INVOKABLE void seek(qint64 ms);
    Q_INVOKABLE void skip(qint64 deltaMs);

signals:
    void sourceChanged();
    void playingChanged();
    void positionChanged();
    void seekPositionChanged();
    void durationChanged();
    void volumeChanged();
    void bufferingChanged();
    void readyChanged();
    void videoHeightChanged();
    void endOfStream();
    void errorOccurred(const QString &message, bool retryable);
    void frameReady();

private slots:
    void onFrameReady();
    void updatePlaybackState();

private:
    void initPipeline(qint64 position, bool autoplay, bool preserveFrame = false);
    void destroyPipeline(bool preserveFrame = false);
    void updatePipelineState();
    void setBuffering(int percent);
    void setReady(bool ready);
    void resetSeek();
    void reportError(const QString &message, bool retryable = false);
    void presentSample(GstSample *sample);
    static GstFlowReturn onNewPreroll(GstAppSink *sink, gpointer userData);
    static GstFlowReturn onNewSample(GstAppSink *sink, gpointer userData);
    void processBusMessages();
    void handleBusMessage(GstMessage *message);

    QString m_source;
    bool m_isPlaying;
    qint64 m_position;
    qint64 m_duration;
    qreal m_volume;
    bool m_isBuffering;
    int m_bufferingPercent;

    bool m_isSeeking;
    bool m_isReady;
    bool m_finished = false;
    bool m_isNetworkSource = false;
    qint64 m_seekTargetMs;
    qint64 m_pendingSeekMs;

    GstElement *m_pipeline;
    GstElement *m_appsink;
    GstBus *m_bus = nullptr;
    QImage m_currentFrame;
    QMutex m_frameMutex;
    bool m_frameUpdatePending = false;
    std::atomic_bool m_awaitingInitialSeek{false};
    int m_videoHeight = 0;
    QTimer *m_pollTimer;
    QTimer m_seekTimer;
    QTimer m_busTimer;
};

#endif
