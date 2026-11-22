#ifndef ANIXAPI_H
#define ANIXAPI_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QVariantMap>
#include <QVariantList>
#include <QJsonObject>
#include <QSet>
#include <QQueue>

class AnixApi : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isLoading READ isLoading NOTIFY loadingChanged)

public:
    explicit AnixApi(QObject *parent = nullptr);
    ~AnixApi() override;

    bool isLoading() const { return m_isLoading; }

    Q_INVOKABLE void fetchHub();
    Q_INVOKABLE void fetchBrowseSection(const QString &section, int page = 0, qint64 collectionId = 0, const QString &token = "", const QString &query = "");
    Q_INVOKABLE void addComment(const QString &section, qint64 id, const QString &message, bool spoiler, const QString &token);
    Q_INVOKABLE void addCommentReply(const QString &section, qint64 id, const QString &message, bool spoiler, qint64 parentCommentId = 0, qint64 replyToProfileId = 0, const QString &token = "");
    Q_INVOKABLE void search(const QString &query, int page = 0);
    Q_INVOKABLE void fetchCatalog(int page = 0, int sort = 0, int categoryId = 0, int statusId = 0);
    Q_INVOKABLE void fetchRelease(qint64 releaseId, const QString &token = "");
    Q_INVOKABLE void fetchEpisodeTypes(qint64 releaseId, const QString &token = "");
    Q_INVOKABLE void fetchEpisodeSources(qint64 releaseId, qint64 typeId);
    Q_INVOKABLE void fetchEpisodes(qint64 releaseId, qint64 typeId, qint64 sourceId, const QString &token = "");
    Q_INVOKABLE void fetchEpisodeTarget(qint64 releaseId, qint64 sourceId, int position);
    Q_INVOKABLE void fetchProfileList(const QString &token, int status, int page, int requestId, qint64 userId = 0);
    Q_INVOKABLE QVariantMap cachedProfileList(qint64 userId, int status) const;
    Q_INVOKABLE void cacheProfileList(qint64 userId, int status, const QVariantList &releases, int totalCount);
    Q_INVOKABLE void invalidateProfileListCache(qint64 userId, int status);
    Q_INVOKABLE void fetchUserProfile(qint64 userId, const QString &token = "");
    Q_INVOKABLE void saveProfilePreference(const QString &field, const QVariant &value, const QString &token);
    Q_INVOKABLE void saveReleaseAction(qint64 releaseId, const QString &action, qint64 value, const QString &token);
    Q_INVOKABLE QVariantMap cachedUserProfile(qint64 userId) const;
    Q_INVOKABLE QVariantList cachedReleaseGrid(const QString &query, qint64 userId) const;
    Q_INVOKABLE void cacheReleaseGrid(const QString &query, qint64 userId, const QVariantList &rows);
    Q_INVOKABLE void searchProfiles(const QString &query, int page = 0);
    Q_INVOKABLE void fetchProfileFriends(qint64 userId, int page = 0, const QString &token = "");
    Q_INVOKABLE void fetchProfileComments(qint64 userId, int page = 0, const QString &type = "release", const QString &token = "", int sort = 1);
    Q_INVOKABLE void fetchComments(const QString &section, qint64 entityId, int page = 0, int sort = 0, const QString &token = "");
    Q_INVOKABLE void fetchComment(const QString &section, qint64 commentId, const QString &token);
    Q_INVOKABLE void fetchReleaseComments(qint64 releaseId, int page = 0, int sort = 0, const QString &token = "");
    Q_INVOKABLE void fetchCommentReplies(const QString &section, qint64 commentId, int page = 0, int sort = 0, const QString &token = "");
    Q_INVOKABLE void sendCommentVote(const QString &section, qint64 commentId, int vote, const QString &token = "");
    Q_INVOKABLE void editComment(const QString &section, qint64 commentId, const QString &message, bool spoiler, const QString &token);
    Q_INVOKABLE void deleteComment(const QString &section, qint64 commentId, const QString &token);
    Q_INVOKABLE void fetchVoters(const QString &section, qint64 entityId, int page, int filter, const QString &token);
    Q_INVOKABLE void fetchReportReasons(const QString &section, const QString &token);
    Q_INVOKABLE void submitReport(const QString &section, qint64 entityId, qint64 reasonId, const QString &message, const QString &token);
    Q_INVOKABLE void sendArticleVote(qint64 articleId, int vote, const QString &token);
    Q_INVOKABLE void addReleaseComment(qint64 releaseId, const QString &message, bool isSpoiler, qint64 parentId, const QString &token);

    Q_INVOKABLE void addBookmark(qint64 releaseId, int listId, const QString &token = "");
    Q_INVOKABLE void removeBookmark(qint64 releaseId, const QString &token = "", int listId = 0);
    Q_INVOKABLE void recordEpisodeOpened(qint64 releaseId, qint64 typeId, qint64 sourceId, int position, const QString &token = "");
    Q_INVOKABLE void setEpisodeWatched(qint64 releaseId, qint64 typeId, qint64 sourceId, int position, bool watched, const QString &token = "");
    Q_INVOKABLE void saveEpisodeProgress(qint64 releaseId, qint64 typeId, qint64 sourceId, int position, qint64 playbackPosition, qint64 duration);
    Q_INVOKABLE bool isEpisodeWatched(qint64 releaseId, qint64 typeId, qint64 sourceId, int position) const;
    Q_INVOKABLE qint64 getEpisodePlaybackPosition(qint64 releaseId, qint64 typeId, qint64 sourceId, int position) const;
    Q_INVOKABLE qint64 getEpisodePlaybackDuration(qint64 releaseId, qint64 typeId, qint64 sourceId, int position) const;
    Q_INVOKABLE int getReleaseBookmarkStatus(qint64 releaseId) const;

signals:
    void loadingChanged(bool loading);
    void hubLoaded(const QVariantMap &data);
    void browseSectionLoaded(const QString &section, int page, qint64 collectionId, const QString &query, const QVariantMap &data);
    void commentAdded(const QString &section, qint64 id, const QVariantMap &data);
    void commentsLoaded(const QString &section, qint64 entityId, const QVariantList &comments, int page, int totalCount, int totalPageCount, bool success);
    void commentLoaded(const QString &section, qint64 commentId, const QVariantMap &comment);
    void searchLoaded(const QVariantList &releases);
    void catalogLoaded(const QVariantList &releases);
    void releaseLoaded(qint64 id, const QVariantMap &release);
    void episodeTypesLoaded(qint64 releaseId, const QVariantList &types);
    void episodeSourcesLoaded(qint64 releaseId, qint64 typeId, const QVariantList &sources);
    void episodesLoaded(qint64 releaseId, qint64 typeId, qint64 sourceId, const QVariantList &episodes);
    void episodeTargetLoaded(qint64 releaseId, qint64 sourceId, int position, const QVariantMap &target);
    void profileListLoaded(int requestId, int status, const QVariantList &releases, int page, int totalPages, int totalCount);
    void profileListFailed(int requestId, int status);
    void userProfileLoaded(qint64 id, const QVariantMap &profile);
    void profilePreferenceSaved(const QString &field, const QVariant &value, bool success);
    void profilePreferencesChanged();
    void releaseActionSaved(qint64 releaseId, const QString &action, bool success);
    void profilesSearchLoaded(const QVariantList &profiles, int page, int totalCount, const QString &query);
    void profileFriendsLoaded(qint64 userId, const QVariantList &friends, int page, int totalCount);
    void profileCommentsLoaded(qint64 userId, const QString &type, const QVariantList &comments, int page, int totalCount);
    void releaseCommentsLoaded(qint64 releaseId, const QVariantList &comments, int page, int totalCount);
    void commentRepliesLoaded(const QString &section, qint64 commentId, const QVariantList &replies, int page, int totalCount, int totalPageCount, bool success);
    void commentVoteProcessed(const QString &section, qint64 commentId, int vote, int code);
    void commentEditProcessed(const QString &section, qint64 commentId, const QString &message, bool spoiler, int code);
    void commentDeleteProcessed(const QString &section, qint64 commentId, int code);
    void votersLoaded(const QString &section, qint64 entityId, int page, int filter, const QVariantList &rows, int total, bool hasMore, bool success);
    void reportReasonsLoaded(const QString &section, const QVariantList &reasons);
    void reportSubmitted(const QString &section, qint64 entityId, int code);
    void articleVoteProcessed(qint64 articleId, int vote, int code);
    void releaseCommentAdded(qint64 releaseId, bool success);
    void episodeHistoryUpdated();
    void bookmarkListsChanged();
    void flushPlaybackProgress();
    void networkRouteChanged();
    void errorOccurred(const QString &error);
    void bookmarkUpdated(qint64 releaseId, int listId);
    void bookmarkUpdateFailed(qint64 releaseId);
    void episodeWatchUpdated(qint64 releaseId, qint64 typeId, qint64 sourceId, int position, bool watched, qint64 playbackPosition);
    void episodeWatchChangeFailed(qint64 releaseId, qint64 typeId, qint64 sourceId, int position, bool watched);

private slots:
    void onReplyFinished();

private:
    void setBookmark(qint64 releaseId, int listId, const QString &endpoint, const QString &token);
    void setLoading(bool loading);
    QNetworkRequest createRequest(const QString &endpoint, const QString &token = "");
    QNetworkReply *sendBrowseRequest(const QString &endpoint, const QString &token, const QJsonObject &body = {});
    QNetworkReply *sendCommentRequest(const QString &type, qint64 id, const QString &text, bool spoiler, qint64 parentCommentId, qint64 replyToProfileId, const QString &token);
    QNetworkReply *sendEpisodeWatchRequest(qint64 releaseId, qint64 sourceId, int position, bool watched, const QString &token);
    void sendNextEpisodeHistoryRequest();
    void loadUserData();
    void saveUserData();
    QString userDataFilePath() const;

    QNetworkAccessManager *m_manager;
    QString m_baseUrl;
    bool m_isLoading;
#ifdef Q_OS_WIN
    void *m_routeChangeHandle = nullptr;
#endif

    QJsonObject m_bookmarks;
    QSet<QString> m_watchedSet;
    QSet<QString> m_pendingWatchChanges;
    QQueue<QNetworkRequest> m_episodeHistoryRequests;
    bool m_episodeHistoryChanged = false;
    QJsonObject m_episodeProgress;
};

#endif
