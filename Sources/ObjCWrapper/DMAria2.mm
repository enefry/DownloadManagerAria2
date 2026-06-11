#import "DMAria2.h"

#include <aria2/aria2.h>

#include <memory>
#include <string>
#include <vector>

NSErrorDomain const DMAria2ErrorDomain = @"DMAria2ErrorDomain";
NSString *const DMAria2GIDKey = @"gid";
NSString *const DMAria2StatusKey = @"status";
NSString *const DMAria2TotalLengthKey = @"totalLength";
NSString *const DMAria2CompletedLengthKey = @"completedLength";
NSString *const DMAria2DownloadSpeedKey = @"downloadSpeed";
NSString *const DMAria2UploadSpeedKey = @"uploadSpeed";
NSString *const DMAria2ErrorCodeKey = @"errorCode";
NSString *const DMAria2FilesKey = @"files";

namespace {

constexpr NSInteger DMAria2ErrorInvalidArgument = -1000;
constexpr NSInteger DMAria2ErrorSessionCreate = -1002;
constexpr NSInteger DMAria2ErrorMissingSession = -1003;
constexpr NSInteger DMAria2ErrorMissingDownload = -1004;

NSString *DMAria2StringFromStdString(const std::string &value) {
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

std::string DMAria2StdStringFromNSString(NSString *value) {
    if (value.length == 0) {
        return std::string();
    }
    const char *utf8 = value.UTF8String;
    return utf8 ? std::string(utf8) : std::string();
}

aria2::KeyVals DMAria2KeyValsFromDictionary(NSDictionary<NSString *, NSString *> *options) {
    aria2::KeyVals result;
    if (!options) {
        return result;
    }

    result.reserve(options.count);
    for (NSString *key in options) {
        NSString *value = options[key];
        if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class]) {
            continue;
        }
        result.emplace_back(DMAria2StdStringFromNSString(key), DMAria2StdStringFromNSString(value));
    }
    return result;
}

std::vector<std::string> DMAria2StringVectorFromArray(NSArray<NSString *> *values) {
    std::vector<std::string> result;
    result.reserve(values.count);
    for (NSString *value in values) {
        if (![value isKindOfClass:NSString.class]) {
            continue;
        }
        result.emplace_back(DMAria2StdStringFromNSString(value));
    }
    return result;
}

NSError *DMAria2Error(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:DMAria2ErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

BOOL DMAria2AssignError(NSError **error, NSInteger code, NSString *description) {
    if (error) {
        *error = DMAria2Error(code, description);
    }
    return NO;
}

DMAria2DownloadStatus DMAria2StatusFromAria2Status(aria2::DownloadStatus status) {
    switch (status) {
    case aria2::DOWNLOAD_ACTIVE:
        return DMAria2DownloadStatusActive;
    case aria2::DOWNLOAD_WAITING:
        return DMAria2DownloadStatusWaiting;
    case aria2::DOWNLOAD_PAUSED:
        return DMAria2DownloadStatusPaused;
    case aria2::DOWNLOAD_COMPLETE:
        return DMAria2DownloadStatusComplete;
    case aria2::DOWNLOAD_ERROR:
        return DMAria2DownloadStatusError;
    case aria2::DOWNLOAD_REMOVED:
        return DMAria2DownloadStatusRemoved;
    }
    return DMAria2DownloadStatusUnknown;
}

NSArray<NSDictionary<NSString *, id> *> *DMAria2FilesFromDownloadHandle(aria2::DownloadHandle *handle) {
    NSMutableArray<NSDictionary<NSString *, id> *> *files = [NSMutableArray array];
    for (const auto &file : handle->getFiles()) {
        [files addObject:@{
            @"index" : @(file.index),
            @"path" : DMAria2StringFromStdString(file.path),
            @"length" : @(file.length),
            @"completedLength" : @(file.completedLength),
            @"selected" : @(file.selected),
        }];
    }
    return files;
}

int DMAria2LibraryInitResult() {
    static int result = aria2::libraryInit();
    return result;
}

} // namespace

NSString *DMAria2Version(void) {
    return @"1.37.0";
}

@implementation DMAria2Session {
    aria2::Session *_session;
    BOOL _finished;
}

- (nullable instancetype)initWithOptions:(NSDictionary<NSString *, NSString *> *)options
                                   error:(NSError **)error {
    self = [super init];
    if (!self) {
        return nil;
    }

    int initResult = DMAria2LibraryInitResult();
    if (initResult != 0) {
        DMAria2AssignError(error, initResult, @"Failed to initialize aria2 library.");
        return nil;
    }

    aria2::SessionConfig config;
    config.keepRunning = true;
    config.useSignalHandler = false;

    aria2::KeyVals keyVals = DMAria2KeyValsFromDictionary(options);
    _session = aria2::sessionNew(keyVals, config);
    if (!_session) {
        DMAria2AssignError(error, DMAria2ErrorSessionCreate, @"Failed to create aria2 session.");
        return nil;
    }
    return self;
}

- (void)dealloc {
    if (_session && !_finished) {
        aria2::shutdown(_session, true);
        while (aria2::run(_session, aria2::RUN_ONCE) > 0) {
        }
        aria2::sessionFinal(_session);
    }
    _session = nullptr;
}

- (BOOL)addURI:(NSString *)uri
       options:(NSDictionary<NSString *, NSString *> *)options
           gid:(NSString **)gid
         error:(NSError **)error {
    if (!uri) {
        return DMAria2AssignError(error, DMAria2ErrorInvalidArgument, @"URI is required.");
    }
    return [self addURIs:@[uri] options:options gid:gid error:error];
}

- (BOOL)addURIs:(NSArray<NSString *> *)uris
        options:(NSDictionary<NSString *, NSString *> *)options
            gid:(NSString **)gid
          error:(NSError **)error {
    if (!_session) {
        return DMAria2AssignError(error, DMAria2ErrorMissingSession, @"Session is already finished.");
    }
    if (uris.count == 0) {
        return DMAria2AssignError(error, DMAria2ErrorInvalidArgument, @"At least one URI is required.");
    }

    aria2::A2Gid outputGID = 0;
    int result = aria2::addUri(_session, &outputGID, DMAria2StringVectorFromArray(uris),
                               DMAria2KeyValsFromDictionary(options));
    if (result < 0) {
        return DMAria2AssignError(error, result, @"aria2 addUri failed.");
    }
    if (gid) {
        *gid = DMAria2StringFromStdString(aria2::gidToHex(outputGID));
    }
    return YES;
}

- (BOOL)addTorrentAtPath:(NSString *)torrentPath
             webSeedURIs:(NSArray<NSString *> *)webSeedURIs
                 options:(NSDictionary<NSString *, NSString *> *)options
                     gid:(NSString **)gid
                   error:(NSError **)error {
    if (!_session) {
        return DMAria2AssignError(error, DMAria2ErrorMissingSession, @"Session is already finished.");
    }
    if (torrentPath.length == 0) {
        return DMAria2AssignError(error, DMAria2ErrorInvalidArgument, @"Torrent path is required.");
    }

    aria2::A2Gid outputGID = 0;
    int result = aria2::addTorrent(_session, &outputGID,
                                   DMAria2StdStringFromNSString(torrentPath),
                                   DMAria2StringVectorFromArray(webSeedURIs ?: @[]),
                                   DMAria2KeyValsFromDictionary(options));
    if (result < 0) {
        return DMAria2AssignError(error, result, @"aria2 addTorrent failed.");
    }
    if (gid) {
        *gid = DMAria2StringFromStdString(aria2::gidToHex(outputGID));
    }
    return YES;
}

- (NSInteger)run:(DMAria2RunMode)mode error:(NSError **)error {
    if (!_session) {
        DMAria2AssignError(error, DMAria2ErrorMissingSession, @"Session is already finished.");
        return -1;
    }

    aria2::RUN_MODE runMode = mode == DMAria2RunModeDefault ? aria2::RUN_DEFAULT : aria2::RUN_ONCE;
    int result = aria2::run(_session, runMode);
    if (result < 0) {
        DMAria2AssignError(error, result, @"aria2 run failed.");
    }
    return result;
}

- (BOOL)removeDownloadWithGID:(NSString *)gid force:(BOOL)force error:(NSError **)error {
    return [self performGIDAction:gid
                            error:error
                           action:^(aria2::A2Gid value) {
                               return aria2::removeDownload(_session, value, force);
                           }
                  failureMessage:@"aria2 removeDownload failed."];
}

- (BOOL)pauseDownloadWithGID:(NSString *)gid force:(BOOL)force error:(NSError **)error {
    return [self performGIDAction:gid
                            error:error
                           action:^(aria2::A2Gid value) {
                               return aria2::pauseDownload(_session, value, force);
                           }
                  failureMessage:@"aria2 pauseDownload failed."];
}

- (BOOL)unpauseDownloadWithGID:(NSString *)gid error:(NSError **)error {
    return [self performGIDAction:gid
                            error:error
                           action:^(aria2::A2Gid value) {
                               return aria2::unpauseDownload(_session, value);
                           }
                  failureMessage:@"aria2 unpauseDownload failed."];
}

- (BOOL)changeOptions:(NSDictionary<NSString *, NSString *> *)options
               forGID:(NSString *)gid
                error:(NSError **)error {
    return [self performGIDAction:gid
                            error:error
                           action:^(aria2::A2Gid value) {
                               return aria2::changeOption(_session, value, DMAria2KeyValsFromDictionary(options));
                           }
                  failureMessage:@"aria2 changeOption failed."];
}

- (BOOL)changeGlobalOptions:(NSDictionary<NSString *, NSString *> *)options
                      error:(NSError **)error {
    if (!_session) {
        return DMAria2AssignError(error, DMAria2ErrorMissingSession, @"Session is already finished.");
    }

    int result = aria2::changeGlobalOption(_session, DMAria2KeyValsFromDictionary(options));
    if (result < 0) {
        return DMAria2AssignError(error, result, @"aria2 changeGlobalOption failed.");
    }
    return YES;
}

- (NSArray<NSString *> *)activeDownloadGIDs {
    if (!_session) {
        return @[];
    }

    NSMutableArray<NSString *> *gids = [NSMutableArray array];
    for (aria2::A2Gid gid : aria2::getActiveDownload(_session)) {
        [gids addObject:DMAria2StringFromStdString(aria2::gidToHex(gid))];
    }
    return gids;
}

- (NSDictionary<NSString *, id> *)statusForGID:(NSString *)gid error:(NSError **)error {
    if (!_session) {
        DMAria2AssignError(error, DMAria2ErrorMissingSession, @"Session is already finished.");
        return nil;
    }
    if (gid.length == 0) {
        DMAria2AssignError(error, DMAria2ErrorInvalidArgument, @"GID is required.");
        return nil;
    }

    aria2::A2Gid value = aria2::hexToGid(DMAria2StdStringFromNSString(gid));
    std::unique_ptr<aria2::DownloadHandle, void (*)(aria2::DownloadHandle *)> handle(
        aria2::getDownloadHandle(_session, value), aria2::deleteDownloadHandle);
    if (!handle) {
        DMAria2AssignError(error, DMAria2ErrorMissingDownload, @"Download was not found.");
        return nil;
    }

    return @{
        DMAria2GIDKey : gid,
        DMAria2StatusKey : @(DMAria2StatusFromAria2Status(handle->getStatus())),
        DMAria2TotalLengthKey : @(handle->getTotalLength()),
        DMAria2CompletedLengthKey : @(handle->getCompletedLength()),
        DMAria2DownloadSpeedKey : @(handle->getDownloadSpeed()),
        DMAria2UploadSpeedKey : @(handle->getUploadSpeed()),
        DMAria2ErrorCodeKey : @(handle->getErrorCode()),
        DMAria2FilesKey : DMAria2FilesFromDownloadHandle(handle.get()),
    };
}

- (NSDictionary<NSString *, NSNumber *> *)globalStat {
    if (!_session) {
        return @{};
    }

    aria2::GlobalStat stat = aria2::getGlobalStat(_session);
    return @{
        @"downloadSpeed" : @(stat.downloadSpeed),
        @"uploadSpeed" : @(stat.uploadSpeed),
        @"numActive" : @(stat.numActive),
        @"numWaiting" : @(stat.numWaiting),
        @"numStopped" : @(stat.numStopped),
    };
}

- (BOOL)shutdown:(BOOL)force error:(NSError **)error {
    if (!_session) {
        return DMAria2AssignError(error, DMAria2ErrorMissingSession, @"Session is already finished.");
    }

    int result = aria2::shutdown(_session, force);
    if (result < 0) {
        return DMAria2AssignError(error, result, @"aria2 shutdown failed.");
    }
    return YES;
}

- (NSInteger)finish:(NSError **)error {
    if (!_session) {
        return 0;
    }

    int result = aria2::sessionFinal(_session);
    _session = nullptr;
    _finished = YES;
    if (result != 0) {
        DMAria2AssignError(error, result, @"aria2 sessionFinal failed.");
    }
    return result;
}

- (BOOL)performGIDAction:(NSString *)gid
                   error:(NSError **)error
                  action:(int (^)(aria2::A2Gid value))action
          failureMessage:(NSString *)failureMessage {
    if (!_session) {
        return DMAria2AssignError(error, DMAria2ErrorMissingSession, @"Session is already finished.");
    }
    if (gid.length == 0) {
        return DMAria2AssignError(error, DMAria2ErrorInvalidArgument, @"GID is required.");
    }

    int result = action(aria2::hexToGid(DMAria2StdStringFromNSString(gid)));
    if (result < 0) {
        return DMAria2AssignError(error, result, failureMessage);
    }
    return YES;
}

@end
