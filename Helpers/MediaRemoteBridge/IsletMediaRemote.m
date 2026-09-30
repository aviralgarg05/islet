// IsletMediaRemote: system-wide Now Playing bridge.
//
// Since macOS 15.4, MediaRemote only answers Apple-signed clients. This library is loaded
// into /usr/bin/perl (an Apple platform binary) by islet-mediaremote.pl, and streams the
// Now Playing state as JSON lines on stdout. Commands arrive as lines on stdin:
//
//   get                 emit the current state now
//   cmd <n>             MRMediaRemoteSendCommand(n)  (0 play, 1 pause, 2 toggle, 4 next, 5 previous,
//                       6 toggle shuffle, 7 toggle repeat, 12 back 15 s, 13 forward 15 s)
//   seek <seconds>      MRMediaRemoteSetElapsedTime
//   shuffle <mode>      MRMediaRemoteSetShuffleMode  (1 off, 3 songs)
//   repeat <mode>       MRMediaRemoteSetRepeatMode   (1 off, 2 one, 3 all)
//
// The process exits when stdin closes, so it never outlives the app.
//
// Output lines:
//   {"type":"ready"}
//   {"type":"nowPlaying","empty":true}
//   {"type":"nowPlaying","title":…,"artist":…,"album":…,"duration":…,"elapsed":…,"rate":…,
//    "timestamp":<unix>,"playing":bool,"bundleID":…,"appName":…,"artworkHash":…,"artwork":<base64 when changed>,
//    "shuffleMode":<int, when the player reports it>,"repeatMode":<int, when the player reports it>}
//   {"type":"error","message":…}

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <stdio.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(BOOL));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef Boolean (*MRSendCommandFn)(int, NSDictionary *);
typedef void (*MRSetElapsedFn)(double);
typedef void (*MRSetModeFn)(int);

static void *gMR;
static MRGetInfoFn gGetInfo;
static MRRegisterFn gRegister;
static MRGetIsPlayingFn gIsPlaying;
static MRGetClientFn gGetClient;
static MRSendCommandFn gSend;
static MRSetElapsedFn gSetElapsed;
static MRSetModeFn gSetShuffle;
static MRSetModeFn gSetRepeat;
static dispatch_queue_t gQueue;
static NSUInteger gLastArtworkHash;
static BOOL gPending;

static NSString *MRConst(const char *name, NSString *fallback) {
    CFStringRef *p = (CFStringRef *)dlsym(gMR, name);
    return (p && *p) ? (__bridge NSString *)*p : fallback;
}

static void Emit(NSDictionary *obj) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!d) return;
    @synchronized([NSFileHandle class]) {
        fwrite(d.bytes, 1, d.length, stdout);
        fputc('\n', stdout);
        fflush(stdout);
    }
}

static id Call(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [obj performSelector:sel];
#pragma clang diagnostic pop
}

static void FetchAndEmit(void) {
    gGetInfo(gQueue, ^(NSDictionary *info) {
        gIsPlaying(gQueue, ^(BOOL playing) {
            gGetClient(gQueue, ^(id client) {
                NSMutableDictionary *out = [NSMutableDictionary dictionaryWithObject:@"nowPlaying" forKey:@"type"];
                NSString *title = info[MRConst("kMRMediaRemoteNowPlayingInfoTitle", @"kMRMediaRemoteNowPlayingInfoTitle")];
                if (info.count == 0 || title.length == 0) {
                    out[@"empty"] = @YES;
                    gLastArtworkHash = 0;
                    Emit(out);
                    return;
                }
                out[@"title"] = title;
                NSString *artist = info[MRConst("kMRMediaRemoteNowPlayingInfoArtist", @"kMRMediaRemoteNowPlayingInfoArtist")];
                NSString *album = info[MRConst("kMRMediaRemoteNowPlayingInfoAlbum", @"kMRMediaRemoteNowPlayingInfoAlbum")];
                NSNumber *duration = info[MRConst("kMRMediaRemoteNowPlayingInfoDuration", @"kMRMediaRemoteNowPlayingInfoDuration")];
                NSNumber *elapsed = info[MRConst("kMRMediaRemoteNowPlayingInfoElapsedTime", @"kMRMediaRemoteNowPlayingInfoElapsedTime")];
                NSNumber *rate = info[MRConst("kMRMediaRemoteNowPlayingInfoPlaybackRate", @"kMRMediaRemoteNowPlayingInfoPlaybackRate")];
                NSDate *stamp = info[MRConst("kMRMediaRemoteNowPlayingInfoTimestamp", @"kMRMediaRemoteNowPlayingInfoTimestamp")];
                NSData *art = info[MRConst("kMRMediaRemoteNowPlayingInfoArtworkData", @"kMRMediaRemoteNowPlayingInfoArtworkData")];
                if ([artist isKindOfClass:NSString.class] && artist.length) out[@"artist"] = artist;
                if ([album isKindOfClass:NSString.class] && album.length) out[@"album"] = album;
                if ([duration isKindOfClass:NSNumber.class]) out[@"duration"] = duration;
                if ([elapsed isKindOfClass:NSNumber.class]) out[@"elapsed"] = elapsed;
                if ([rate isKindOfClass:NSNumber.class]) out[@"rate"] = rate;
                NSNumber *shuffle = info[MRConst("kMRMediaRemoteNowPlayingInfoShuffleMode", @"kMRMediaRemoteNowPlayingInfoShuffleMode")];
                NSNumber *repeat = info[MRConst("kMRMediaRemoteNowPlayingInfoRepeatMode", @"kMRMediaRemoteNowPlayingInfoRepeatMode")];
                if ([shuffle isKindOfClass:NSNumber.class]) out[@"shuffleMode"] = shuffle;
                if ([repeat isKindOfClass:NSNumber.class]) out[@"repeatMode"] = repeat;
                out[@"timestamp"] = @([stamp isKindOfClass:NSDate.class] ? stamp.timeIntervalSince1970 : NSDate.date.timeIntervalSince1970);
                out[@"playing"] = @(playing);

                // Browser tabs report a WebKit/Chromium helper; prefer the parent app.
                NSString *bundle = Call(client, @"parentApplicationBundleIdentifier") ?: Call(client, @"bundleIdentifier");
                NSString *name = Call(client, @"displayName");
                if ([bundle isKindOfClass:NSString.class]) out[@"bundleID"] = bundle;
                if ([name isKindOfClass:NSString.class]) out[@"appName"] = name;

                if ([art isKindOfClass:NSData.class] && art.length > 0) {
                    NSUInteger h = (art.hash ^ art.length) & 0x7FFFFFFFFFFFFFFFULL;
                    out[@"artworkHash"] = @(h);
                    if (h != gLastArtworkHash) {
                        gLastArtworkHash = h;
                        out[@"artwork"] = [art base64EncodedStringWithOptions:0];
                    }
                } else {
                    gLastArtworkHash = 0;
                }
                Emit(out);
            });
        });
    });
}

// Several notifications fire per change; coalesce them into one fetch.
static void ScheduleFetch(void) {
    dispatch_async(gQueue, ^{
        if (gPending) return;
        gPending = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), gQueue, ^{
            gPending = NO;
            FetchAndEmit();
        });
    });
}

static void ReadCommands(void) {
    char line[256];
    while (fgets(line, sizeof line, stdin)) {
        NSString *s = [[NSString stringWithUTF8String:line] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSArray<NSString *> *parts = [s componentsSeparatedByString:@" "];
        if ([parts[0] isEqualToString:@"get"]) {
            FetchAndEmit();
        } else if ([parts[0] isEqualToString:@"cmd"] && parts.count > 1 && gSend) {
            int n = parts[1].intValue;
            Boolean ok = gSend(n, nil);
            Emit(@{@"type": @"ack", @"command": @(n), @"ok": @(ok)});
            // Mode and skip commands don't always post a change notification.
            if (n >= 6) ScheduleFetch();
        } else if ([parts[0] isEqualToString:@"seek"] && parts.count > 1 && gSetElapsed) {
            gSetElapsed(parts[1].doubleValue);
            ScheduleFetch();
        } else if ([parts[0] isEqualToString:@"shuffle"] && parts.count > 1) {
            if (gSetShuffle) gSetShuffle(parts[1].intValue); else if (gSend) gSend(6, nil);
            ScheduleFetch();
        } else if ([parts[0] isEqualToString:@"repeat"] && parts.count > 1) {
            if (gSetRepeat) gSetRepeat(parts[1].intValue); else if (gSend) gSend(7, nil);
            ScheduleFetch();
        }
    }
    exit(0); // stdin closed: the app is gone.
}

// Entry point, installed as a Perl XSUB. The two arguments (interpreter, CV) are unused.
__attribute__((visibility("default")))
void islet_mediaremote_main(void *interp, void *cv) {
    @autoreleasepool {
        gMR = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (!gMR) {
            Emit(@{@"type": @"error", @"message": @"MediaRemote.framework not found"});
            exit(2);
        }
        gGetInfo = (MRGetInfoFn)dlsym(gMR, "MRMediaRemoteGetNowPlayingInfo");
        gRegister = (MRRegisterFn)dlsym(gMR, "MRMediaRemoteRegisterForNowPlayingNotifications");
        gIsPlaying = (MRGetIsPlayingFn)dlsym(gMR, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        gGetClient = (MRGetClientFn)dlsym(gMR, "MRMediaRemoteGetNowPlayingClient");
        gSend = (MRSendCommandFn)dlsym(gMR, "MRMediaRemoteSendCommand");
        gSetElapsed = (MRSetElapsedFn)dlsym(gMR, "MRMediaRemoteSetElapsedTime");
        gSetShuffle = (MRSetModeFn)dlsym(gMR, "MRMediaRemoteSetShuffleMode");
        gSetRepeat = (MRSetModeFn)dlsym(gMR, "MRMediaRemoteSetRepeatMode");
        if (!gGetInfo || !gRegister || !gIsPlaying || !gGetClient) {
            Emit(@{@"type": @"error", @"message": @"MediaRemote symbols missing"});
            exit(3);
        }
        gQueue = dispatch_queue_create("islet.mediaremote", DISPATCH_QUEUE_SERIAL);
        gRegister(gQueue);

        NSArray *names = @[
            MRConst("kMRMediaRemoteNowPlayingInfoDidChangeNotification", @"kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            MRConst("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
            MRConst("kMRMediaRemoteNowPlayingApplicationDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
        ];
        for (NSString *n in names) {
            [NSNotificationCenter.defaultCenter addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) {
                ScheduleFetch();
            }];
        }
        Emit(@{@"type": @"ready"});
        FetchAndEmit();
        [NSThread detachNewThreadWithBlock:^{ ReadCommands(); }];
    }
    CFRunLoopRun();
}
