#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const DMAria2ErrorDomain;
FOUNDATION_EXPORT NSString *const DMAria2GIDKey;
FOUNDATION_EXPORT NSString *const DMAria2StatusKey;
FOUNDATION_EXPORT NSString *const DMAria2TotalLengthKey;
FOUNDATION_EXPORT NSString *const DMAria2CompletedLengthKey;
FOUNDATION_EXPORT NSString *const DMAria2DownloadSpeedKey;
FOUNDATION_EXPORT NSString *const DMAria2UploadSpeedKey;
FOUNDATION_EXPORT NSString *const DMAria2ErrorCodeKey;
FOUNDATION_EXPORT NSString *const DMAria2FilesKey;

FOUNDATION_EXPORT NSString *DMAria2Version(void);

typedef NS_CLOSED_ENUM(NSInteger, DMAria2RunMode) {
    DMAria2RunModeDefault = 0,
    DMAria2RunModeOnce = 1,
};

typedef NS_CLOSED_ENUM(NSInteger, DMAria2DownloadStatus) {
    DMAria2DownloadStatusActive = 0,
    DMAria2DownloadStatusWaiting = 1,
    DMAria2DownloadStatusPaused = 2,
    DMAria2DownloadStatusComplete = 3,
    DMAria2DownloadStatusError = 4,
    DMAria2DownloadStatusRemoved = 5,
    DMAria2DownloadStatusUnknown = -1,
};

@interface DMAria2Session : NSObject

- (nullable instancetype)initWithOptions:(nullable NSDictionary<NSString *, NSString *> *)options
                                   error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (BOOL)addURI:(NSString *)uri
       options:(nullable NSDictionary<NSString *, NSString *> *)options
           gid:(NSString *_Nullable *_Nullable)gid
         error:(NSError **)error;

- (BOOL)addURIs:(NSArray<NSString *> *)uris
        options:(nullable NSDictionary<NSString *, NSString *> *)options
            gid:(NSString *_Nullable *_Nullable)gid
          error:(NSError **)error;

- (BOOL)addTorrentAtPath:(NSString *)torrentPath
             webSeedURIs:(nullable NSArray<NSString *> *)webSeedURIs
                 options:(nullable NSDictionary<NSString *, NSString *> *)options
                     gid:(NSString *_Nullable *_Nullable)gid
                   error:(NSError **)error;

- (NSInteger)run:(DMAria2RunMode)mode error:(NSError **)error;
- (BOOL)removeDownloadWithGID:(NSString *)gid force:(BOOL)force error:(NSError **)error;
- (BOOL)pauseDownloadWithGID:(NSString *)gid force:(BOOL)force error:(NSError **)error;
- (BOOL)unpauseDownloadWithGID:(NSString *)gid error:(NSError **)error;
- (BOOL)changeOptions:(NSDictionary<NSString *, NSString *> *)options
               forGID:(NSString *)gid
                error:(NSError **)error;
- (BOOL)changeGlobalOptions:(NSDictionary<NSString *, NSString *> *)options
                      error:(NSError **)error;
- (NSArray<NSString *> *)activeDownloadGIDs;
- (nullable NSDictionary<NSString *, id> *)statusForGID:(NSString *)gid error:(NSError **)error;
- (NSDictionary<NSString *, NSNumber *> *)globalStat;
- (BOOL)shutdown:(BOOL)force error:(NSError **)error;
- (NSInteger)finish:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

