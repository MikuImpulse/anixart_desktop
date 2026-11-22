#include "VideoPlayer.h"
#include <QByteArray>
#include <QPainter>
#include <QUrl>
#include <gst/app/gstappsink.h>
#include <gst/video/video.h>
#include <QDebug>
#include <algorithm>
#include <array>
#include <cstring>

namespace {
struct TsPaddingCorrection
{
    static constexpr gsize packetSize = 188;

    std::array<guint8, 8192> paddingCount{};
    QByteArray tail;

    static GstPadProbeReturn process(GstPad *, GstPadProbeInfo *info, gpointer userData)
    {
        auto &correction = *static_cast<TsPaddingCorrection *>(userData);
        if (GST_PAD_PROBE_INFO_TYPE(info) & GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM) {
            GstEvent *event = GST_PAD_PROBE_INFO_EVENT(info);
            if (GST_EVENT_TYPE(event) == GST_EVENT_STREAM_START || GST_EVENT_TYPE(event) == GST_EVENT_SEGMENT) {
                correction.paddingCount.fill(0);
                correction.tail.clear();
            }
            return GST_PAD_PROBE_OK;
        }

        GstBuffer *buffer = gst_buffer_make_writable(GST_PAD_PROBE_INFO_BUFFER(info));
        GST_PAD_PROBE_INFO_DATA(info) = buffer;
        if (!correction.tail.isEmpty()) {
            GstBuffer *prefix = gst_buffer_new_allocate(nullptr, correction.tail.size(), nullptr);
            gst_buffer_fill(prefix, 0, correction.tail.constData(), correction.tail.size());
            gst_buffer_copy_into(prefix, buffer, GST_BUFFER_COPY_METADATA, 0, -1);
            buffer = gst_buffer_append(prefix, buffer);
            GST_PAD_PROBE_INFO_DATA(info) = buffer;
            correction.tail.clear();
        }

        GstMapInfo mapped;
        if (!gst_buffer_map(buffer, &mapped, GST_MAP_WRITE)) return GST_PAD_PROBE_OK;

        const gsize completeSize = mapped.size - mapped.size % packetSize;
        for (gsize offset = 0; offset < completeSize; offset += packetSize) {
            if (mapped.data[offset] != 0x47) {
                correction.paddingCount.fill(0);
                gst_buffer_unmap(buffer, &mapped);
                return GST_PAD_PROBE_OK;
            }
        }

        for (gsize offset = 0; offset < completeSize; offset += packetSize) {
            guint8 *packet = mapped.data + offset;
            const guint pid = ((packet[1] & 0x1f) << 8) | packet[2];
            if (pid == 0x1fff) continue;

            auto &padding = correction.paddingCount[pid];
            const bool hasAdaptation = packet[3] & 0x20;
            if (hasAdaptation && packet[4] > 0 && (packet[5] & 0x80)) padding = 0;

            const bool emptyPayload = (packet[3] & 0x30) == 0x30 && packet[4] == 183 && packet[5] == 0
                && std::all_of(packet + 6, packet + packetSize, [](guint8 byte) { return byte == 0xff; });
            if (emptyPayload) {
                padding = (padding + 1) & 0x0f;
                packet[3] &= ~0x10;
            }
            packet[3] = (packet[3] & 0xf0) | ((packet[3] - padding) & 0x0f);
        }

        if (completeSize < mapped.size) {
            correction.tail = QByteArray(reinterpret_cast<const char *>(mapped.data + completeSize), mapped.size - completeSize);
        }
        gst_buffer_unmap(buffer, &mapped);
        if (completeSize == 0) return GST_PAD_PROBE_DROP;

        if (!correction.tail.isEmpty()) gst_buffer_set_size(buffer, completeSize);
        return GST_PAD_PROBE_OK;
    }
};

void installTsPaddingCorrection(GstBin *, GstBin *, GstElement *element, gpointer)
{
    GstElementFactory *factory = gst_element_get_factory(element);
    if (!factory || g_strcmp0(GST_OBJECT_NAME(factory), "tsdemux") != 0) return;

    GstPad *sink = gst_element_get_static_pad(element, "sink");
    if (!sink) return;

    gst_pad_add_probe(sink, GstPadProbeType(GST_PAD_PROBE_TYPE_BUFFER | GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM),
        TsPaddingCorrection::process, new TsPaddingCorrection, +[](gpointer data) { delete static_cast<TsPaddingCorrection *>(data); });
    gst_object_unref(sink);
}
}

VideoPlayer::VideoPlayer(QQuickItem *parent)
    : QQuickPaintedItem(parent)
    , m_isPlaying(false)
    , m_position(0)
    , m_duration(0)
    , m_volume(1.0)
    , m_isBuffering(false)
    , m_bufferingPercent(100)
    , m_isSeeking(false)
    , m_isReady(false)
    , m_seekTargetMs(0)
    , m_pendingSeekMs(-1)
    , m_pipeline(nullptr)
    , m_appsink(nullptr)
    , m_pollTimer(new QTimer(this))
{
    setOpaquePainting(true);
    connect(this, &VideoPlayer::frameReady, this, &VideoPlayer::onFrameReady, Qt::QueuedConnection);

    m_pollTimer->setInterval(250);
    connect(m_pollTimer, &QTimer::timeout, this, &VideoPlayer::updatePlaybackState);

    m_busTimer.setInterval(50);
    connect(&m_busTimer, &QTimer::timeout, this, &VideoPlayer::processBusMessages);

    m_seekTimer.setSingleShot(true);
    m_seekTimer.setInterval(20000);
    connect(&m_seekTimer, &QTimer::timeout, this, [this] {
        reportError(QStringLiteral("Источник не ответил на перемотку."), true);
    });
}

VideoPlayer::~VideoPlayer()
{
    destroyPipeline();
}

void VideoPlayer::initPipeline(qint64 position, bool autoplay, bool preserveFrame)
{
    destroyPipeline(preserveFrame);

    if (m_source.isEmpty()) return;

    if (m_position != position) {
        m_position = position;
        emit positionChanged();
    }
    if (!preserveFrame && m_duration != 0) {
        m_duration = 0;
        emit durationChanged();
    }

    const QUrl url(m_source);
    m_isNetworkSource = url.scheme() == "http" || url.scheme() == "https";
    const bool isHttpHls = m_isNetworkSource && url.path().endsWith(".m3u8", Qt::CaseInsensitive);
    if (isHttpHls) {
        GstElementFactory *hls = gst_element_factory_find("hlsdemux2");
        if (hls) {
            m_pipeline = gst_element_factory_make("playbin3", "anix_playbin");
            gst_object_unref(hls);
        }
    }
    if (!m_pipeline) {
        m_pipeline = gst_element_factory_make("playbin", "anix_playbin");
    }
    if (!m_pipeline) {
        reportError("Не удалось создать плеер GStreamer.");
        return;
    }

    const QString host = url.host();
    if (isHttpHls && (host == "solodcdn.com" || host.endsWith(".solodcdn.com"))) {
        g_signal_connect(m_pipeline, "deep-element-added", G_CALLBACK(installTsPaddingCorrection), nullptr);
    }

    GstElement *vsink = gst_parse_bin_from_description(
        "queue max-size-buffers=3 max-size-bytes=0 max-size-time=0 ! "
        "videoconvert ! video/x-raw,format=RGBA ! appsink name=anix_appsink max-buffers=2 drop=true enable-last-sample=false",
        TRUE, nullptr
    );

    if (!vsink) {
        destroyPipeline();
        reportError("Не удалось создать видеовыход GStreamer.");
        return;
    }

    g_object_set(m_pipeline, "video-sink", vsink, nullptr);
    g_object_set(m_pipeline, "uri", m_source.toUtf8().constData(), nullptr);
    g_object_set(m_pipeline, "volume", m_volume, nullptr);

    g_signal_connect(m_pipeline, "source-setup", G_CALLBACK(+[](GstElement *playbin, GstElement *source, gpointer) {
        auto *sourceClass = G_OBJECT_GET_CLASS(source);
        if (g_object_class_find_property(sourceClass, "location-trusted")) {
            g_object_set(source, "location-trusted", TRUE, nullptr);
        }
        if (g_object_class_find_property(sourceClass, "user-agent")) {
            g_object_set(source, "user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", nullptr);
        }
        if (g_object_class_find_property(sourceClass, "retries")) {
            g_object_set(source, "retries", 1, nullptr);
        }

        if (g_object_class_find_property(sourceClass, "extra-headers")) {
            gchar *uri = nullptr;
            g_object_get(playbin, "uri", &uri, nullptr);
            const QString host = QUrl(QString::fromUtf8(uri)).host();
            g_free(uri);
            if (host == "sibnet.ru" || host.endsWith(".sibnet.ru")) {
                GstStructure *headers = gst_structure_new("headers", "Referer", G_TYPE_STRING, "https://video.sibnet.ru/", nullptr);
                g_object_set(source, "extra-headers", headers, nullptr);
                gst_structure_free(headers);
            } else if (host.contains("solodcdn") || host.contains("kodik") || host.contains("aniqit")) {
                GstStructure *headers = gst_structure_new("headers",
                    "Referer", G_TYPE_STRING, "https://kodikplayer.com/",
                    "Origin", G_TYPE_STRING, "https://kodikplayer.com", nullptr);
                g_object_set(source, "extra-headers", headers, nullptr);
                gst_structure_free(headers);
            } else if (host.endsWith(".libria.fun")) {
                GstStructure *headers = gst_structure_new("headers",
                    "Referer", G_TYPE_STRING, "https://anixart.libria.fun/",
                    "Origin", G_TYPE_STRING, "https://anixart.libria.fun", nullptr);
                g_object_set(source, "extra-headers", headers, nullptr);
                gst_structure_free(headers);
            }
        }
    }), nullptr);

    g_signal_connect(m_pipeline, "element-setup", G_CALLBACK(+[](GstElement *, GstElement *element, gpointer) {
        auto *elementClass = G_OBJECT_GET_CLASS(element);
        if (!GST_IS_VIDEO_DECODER(element)) return;

        if (g_object_class_find_property(elementClass, "discard-corrupted-frames")) {
            g_object_set(element, "discard-corrupted-frames", TRUE, nullptr);
        }
        if (g_object_class_find_property(elementClass, "output-corrupt")) {
            g_object_set(element, "output-corrupt", FALSE, nullptr);
        }
    }), nullptr);

    m_appsink = gst_bin_get_by_name(GST_BIN(vsink), "anix_appsink");
    if (m_appsink) {
        GstAppSinkCallbacks callbacks = {};
        callbacks.new_preroll = VideoPlayer::onNewPreroll;
        callbacks.new_sample = VideoPlayer::onNewSample;
        gst_app_sink_set_callbacks(GST_APP_SINK(m_appsink), &callbacks, this, nullptr);
    }

    m_bus = gst_element_get_bus(m_pipeline);
    m_busTimer.start();

    m_awaitingInitialSeek = position > 0;
    if (position > 0) seek(position);
    if (autoplay) play();
    else updatePipelineState();
}

void VideoPlayer::destroyPipeline(bool preserveFrame)
{
    m_pollTimer->stop();
    m_busTimer.stop();
    gst_clear_object(&m_bus);
    m_finished = false;
    setReady(false);
    resetSeek();
    if (m_pipeline) {
        gst_element_set_state(m_pipeline, GST_STATE_NULL);
        if (m_appsink) {
            gst_object_unref(m_appsink);
            m_appsink = nullptr;
        }
        gst_object_unref(m_pipeline);
        m_pipeline = nullptr;
    }

    if (m_isPlaying) {
        m_isPlaying = false;
        emit playingChanged();
    }
    setBuffering(100);
    if (preserveFrame) return;

    {
        QMutexLocker locker(&m_frameMutex);
        m_currentFrame = QImage();
    }
    onFrameReady();
}

void VideoPlayer::setSource(const QString &source)
{
    if (m_source != source) load(source, 0, true);
}

void VideoPlayer::load(const QString &source, qint64 position, bool autoplay, bool preserveFrame)
{
    if (source != m_source) {
        m_source = source;
        emit sourceChanged();
    }
    initPipeline(position, autoplay, preserveFrame);
}

void VideoPlayer::setVolume(qreal volume)
{
    volume = qBound(0.0, volume, 1.0);
    if (!qFuzzyCompare(m_volume, volume)) {
        m_volume = volume;
        if (m_pipeline) {
            g_object_set(m_pipeline, "volume", m_volume, nullptr);
        }
        emit volumeChanged();
    }
}

void VideoPlayer::play()
{
    if (!m_pipeline || m_isPlaying) return;

    if (m_finished) {
        seek(0);
        if (m_finished) {
            initPipeline(0, true);
            return;
        }
    }

    m_isPlaying = true;
    m_busTimer.start();
    m_pollTimer->start();
    updatePipelineState();
    emit playingChanged();
}

void VideoPlayer::pause()
{
    if (!m_pipeline || !m_isPlaying) return;

    updatePlaybackState();
    m_isPlaying = false;
    m_pollTimer->stop();
    updatePipelineState();
    emit playingChanged();
}

void VideoPlayer::updatePipelineState()
{
    if (!m_pipeline) return;

    const bool shouldPlay = m_isPlaying && !m_isBuffering && m_isReady && seekPosition() < 0;
    const auto result = gst_element_set_state(m_pipeline, shouldPlay ? GST_STATE_PLAYING : GST_STATE_PAUSED);
    if (result == GST_STATE_CHANGE_NO_PREROLL && !m_isReady) {
        setReady(true);
        resetSeek();
        if (m_isPlaying && !m_isBuffering) gst_element_set_state(m_pipeline, GST_STATE_PLAYING);
    }
}

void VideoPlayer::togglePlay()
{
    if (m_isPlaying) {
        pause();
    } else {
        play();
    }
}

void VideoPlayer::stop()
{
    if (m_pipeline) {
        updatePlaybackState();
        m_busTimer.stop();
        gst_element_set_state(m_pipeline, GST_STATE_READY);
        gst_bus_set_flushing(m_bus, TRUE);
        gst_bus_set_flushing(m_bus, FALSE);
        resetSeek();
        m_finished = false;
        m_isPlaying = false;
        m_pollTimer->stop();
        setBuffering(100);
        setReady(false);
        emit playingChanged();
    }
}

void VideoPlayer::seek(qint64 ms)
{
    if (!m_pipeline) return;

    ms = qBound(0LL, ms, m_duration > 0 ? m_duration : G_MAXINT64 / GST_MSECOND);
    if (!m_isReady || m_isSeeking) {
        m_pendingSeekMs = ms;
        emit seekPositionChanged();
        return;
    }

    const auto flags = m_awaitingInitialSeek.exchange(false)
        ? GstSeekFlags(GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_ACCURATE) : GST_SEEK_FLAG_FLUSH;
    if (gst_element_seek_simple(m_pipeline, GST_FORMAT_TIME, flags, ms * GST_MSECOND)) {
        m_finished = false;
        m_isSeeking = true;
        m_seekTargetMs = ms;
        if (!m_isNetworkSource) m_seekTimer.start();
        emit seekPositionChanged();
    }
}

qint64 VideoPlayer::seekPosition() const
{
    return m_pendingSeekMs >= 0 ? m_pendingSeekMs : (m_isSeeking ? m_seekTargetMs : -1);
}

void VideoPlayer::skip(qint64 deltaMs)
{
    const qint64 target = seekPosition();
    const qint64 base = target >= 0 ? target : m_position;
    seek(base + qMin(deltaMs, qint64(G_MAXINT64) - base));
}

void VideoPlayer::updatePlaybackState()
{
    if (!m_pipeline) return;

    gint64 pos = 0;
    if (m_isReady && !m_isBuffering && seekPosition() < 0
        && gst_element_query_position(m_pipeline, GST_FORMAT_TIME, &pos) && pos / GST_MSECOND > m_position) {
        m_position = pos / GST_MSECOND;
        emit positionChanged();
    }

    gint64 dur = 0;
    if (gst_element_query_duration(m_pipeline, GST_FORMAT_TIME, &dur)) {
        qint64 durMs = dur / GST_MSECOND;
        if (m_duration != durMs && durMs > 0) {
            m_duration = durMs;
            emit durationChanged();
        }
    }
}

GstFlowReturn VideoPlayer::onNewPreroll(GstAppSink *sink, gpointer userData)
{
    static_cast<VideoPlayer*>(userData)->presentSample(gst_app_sink_pull_preroll(sink));
    return GST_FLOW_OK;
}

GstFlowReturn VideoPlayer::onNewSample(GstAppSink *sink, gpointer userData)
{
    static_cast<VideoPlayer*>(userData)->presentSample(gst_app_sink_pull_sample(sink));
    return GST_FLOW_OK;
}

void VideoPlayer::presentSample(GstSample *sample)
{
    if (!sample) return;

    if (m_awaitingInitialSeek) {
        gst_sample_unref(sample);
        return;
    }

    GstBuffer *buffer = gst_sample_get_buffer(sample);
    GstCaps *caps = gst_sample_get_caps(sample);
    GstVideoInfo info;
    GstVideoFrame mapped;
    QImage frame;
    if (buffer && !GST_BUFFER_FLAG_IS_SET(buffer, GST_BUFFER_FLAG_CORRUPTED) && caps
        && gst_video_info_from_caps(&info, caps) && GST_VIDEO_INFO_FORMAT(&info) == GST_VIDEO_FORMAT_RGBA
        && gst_video_frame_map(&mapped, &info, buffer, GST_MAP_READ)) {
        const int width = GST_VIDEO_FRAME_WIDTH(&mapped);
        const int height = GST_VIDEO_FRAME_HEIGHT(&mapped);
        const qsizetype stride = GST_VIDEO_FRAME_PLANE_STRIDE(&mapped, 0);
        const qsizetype rowBytes = qsizetype(width) * 4;
        const auto *pixels = static_cast<const uchar*>(GST_VIDEO_FRAME_PLANE_DATA(&mapped, 0));
        if (pixels && qAbs(stride) >= rowBytes) {
            frame = QImage(width, height, QImage::Format_RGBA8888);
            for (int y = 0; !frame.isNull() && y < height; ++y) {
                std::memcpy(frame.scanLine(y), pixels + y * stride, rowBytes);
            }
        }
        gst_video_frame_unmap(&mapped);
    }
    gst_sample_unref(sample);
    if (frame.isNull()) return;

    {
        QMutexLocker locker(&m_frameMutex);
        m_currentFrame.swap(frame);
        if (m_frameUpdatePending) return;
        m_frameUpdatePending = true;
    }
    emit frameReady();
}

void VideoPlayer::setBuffering(int percent)
{
    if (m_bufferingPercent == percent) return;

    m_bufferingPercent = percent;
    m_isBuffering = percent < 100;
    emit bufferingChanged();
}

void VideoPlayer::setReady(bool ready)
{
    if (m_isReady == ready) return;

    m_isReady = ready;
    emit readyChanged();
}

void VideoPlayer::resetSeek()
{
    const bool hadSeek = seekPosition() >= 0;
    m_seekTimer.stop();
    m_isSeeking = false;
    m_awaitingInitialSeek = false;
    m_pendingSeekMs = -1;
    if (hadSeek) emit seekPositionChanged();
}

void VideoPlayer::reportError(const QString &message, bool retryable)
{
    qWarning().noquote() << "GStreamer:" << message;
    m_pollTimer->stop();
    m_busTimer.stop();
    m_finished = false;
    setReady(false);
    resetSeek();
    if (m_pipeline) {
        gst_element_set_state(m_pipeline, GST_STATE_NULL);
    }
    if (m_isPlaying) {
        m_isPlaying = false;
        emit playingChanged();
    }
    setBuffering(100);
    emit errorOccurred(message, retryable);
}

void VideoPlayer::processBusMessages()
{
    if (!m_bus) return;

    GstBus *bus = GST_BUS(gst_object_ref(m_bus));
    while (bus == m_bus) {
        GstMessage *message = gst_bus_pop(bus);
        if (!message) break;

        handleBusMessage(message);
        gst_message_unref(message);
    }
    gst_object_unref(bus);
}

void VideoPlayer::handleBusMessage(GstMessage *message)
{
    switch (GST_MESSAGE_TYPE(message)) {
    case GST_MESSAGE_LATENCY:
        gst_bin_recalculate_latency(GST_BIN(m_pipeline));
        break;

    case GST_MESSAGE_CLOCK_LOST:
        if (m_isPlaying && !m_isBuffering) {
            gst_element_set_state(m_pipeline, GST_STATE_PAUSED);
            updatePipelineState();
        }
        break;

    case GST_MESSAGE_ASYNC_DONE:
        if (GST_MESSAGE_SRC(message) == GST_OBJECT(m_pipeline)) {
            const qint64 previousTarget = seekPosition();
            const bool completedSeek = m_isSeeking;
            m_isSeeking = false;
            setReady(true);
            if (m_pendingSeekMs >= 0) {
                const qint64 target = m_pendingSeekMs;
                m_pendingSeekMs = -1;
                seek(target);
            } else if (completedSeek && m_position != previousTarget) {
                m_position = previousTarget;
                emit positionChanged();
            }
            updatePlaybackState();
            if (previousTarget >= 0 && seekPosition() < 0) {
                m_seekTimer.stop();
                emit seekPositionChanged();
            }
            if (seekPosition() < 0) updatePipelineState();
        }
        break;

    case GST_MESSAGE_EOS:
        resetSeek();
        updatePlaybackState();
        m_pollTimer->stop();
        m_finished = true;
        m_isPlaying = false;
        emit playingChanged();
        emit endOfStream();
        break;

    case GST_MESSAGE_ERROR: {
        GError *err = nullptr;
        gst_message_parse_error(message, &err, nullptr);
        const QString error = err ? QString::fromUtf8(err->message) : QStringLiteral("Неизвестная ошибка GStreamer.");
        const bool retryable = err && ((err->domain == GST_RESOURCE_ERROR
            && (err->code == GST_RESOURCE_ERROR_FAILED || err->code == GST_RESOURCE_ERROR_READ || err->code == GST_RESOURCE_ERROR_OPEN_READ
                || err->code == GST_RESOURCE_ERROR_NOT_AUTHORIZED || err->code == GST_RESOURCE_ERROR_NOT_FOUND))
            || (err->domain == GST_STREAM_ERROR && err->code == GST_STREAM_ERROR_FAILED));
        if (err) g_error_free(err);
        reportError(error, retryable);
        break;
    }

    case GST_MESSAGE_BUFFERING: {
        gint percent = 0;
        gst_message_parse_buffering(message, &percent);
        GstBufferingMode mode;
        gst_message_parse_buffering_stats(message, &mode, nullptr, nullptr, nullptr);
        if (mode == GST_BUFFERING_LIVE) break;

        const bool wasBuffering = m_isBuffering;
        if (!wasBuffering && percent < 100) updatePlaybackState();
        setBuffering(percent);
        if (m_isPlaying && wasBuffering != m_isBuffering) {
            updatePipelineState();
        }
        break;
    }

    default:
        break;
    }
}

void VideoPlayer::onFrameReady()
{
    int height;
    {
        QMutexLocker locker(&m_frameMutex);
        m_frameUpdatePending = false;
        height = m_currentFrame.height();
    }
    if (height != m_videoHeight) {
        m_videoHeight = height;
        emit videoHeightChanged();
    }
    update();
}

void VideoPlayer::paint(QPainter *painter)
{
    painter->fillRect(boundingRect(), Qt::black);

    QImage frame;
    {
        QMutexLocker locker(&m_frameMutex);
        frame = m_currentFrame;
    }
    if (!frame.isNull()) {
        painter->setRenderHint(QPainter::Antialiasing, true);
        painter->setRenderHint(QPainter::SmoothPixmapTransform, true);

        QSizeF itemSize = boundingRect().size();
        QSizeF imgSize = frame.size();

        QSizeF scaled = imgSize.scaled(itemSize, Qt::KeepAspectRatio);
        QRectF targetRect(
            (itemSize.width() - scaled.width()) / 2.0,
            (itemSize.height() - scaled.height()) / 2.0,
            scaled.width(),
            scaled.height()
        );

        painter->drawImage(targetRect, frame);
    }
}
