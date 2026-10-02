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
// Every command reaches only the player macOS gives the controls to (the "current" one below).
//
// The process exits when stdin closes, so it never outlives the app.
//
// Output lines:
//   {"type":"ready"}
//   {"type":"players","players":[<player>, ...]}
//       Every player macOS lists, the current one first, sent at start and whenever any of them
//       changes. An empty list means nothing is loaded anywhere. Each <player> is
//       {"title":…,"artist":…,"album":…,"duration":…,"elapsed":…,"rate":…,"timestamp":<unix>,
//        "playing":bool,"bundleID":…,"appName":…,"artworkHash":…,"artwork":<base64, only when this
//        player's artwork changed>,"shuffleMode":<int, when reported>,"repeatMode":<int, when reported>,
//        "current":true <only on the player macOS gives the controls to>}
//   {"type":"nowPlaying","empty":true}
//   {"type":"nowPlaying",<the fields of one player, without "current">}
//       Only on a macOS without the calls that list every player: the current player alone.
//   {"type":"ack","command":<n>,"ok":bool}
//   {"type":"error","message":…}
//
// Numbers JSON can't hold (an infinite duration, NaN) are left out, as if missing.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdio.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(BOOL));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef void (*MRGetClientsFn)(dispatch_queue_t, void (^)(NSArray *));
typedef void (*MRGetInfoForPlayerFn)(id, Boolean, dispatch_queue_t, void (^)(NSDictionary *));
typedef Boolean (*MRSendCommandFn)(int, NSDictionary *);
typedef void (*MRSetElapsedFn)(double);
typedef void (*MRSetModeFn)(int);

static void *gMR;
static MRGetInfoFn gGetInfo;
static MRRegisterFn gRegister;
static MRGetIsPlayingFn gIsPlaying;
static MRGetClientFn gGetClient;
static MRGetClientsFn gGetClients;
static MRGetInfoForPlayerFn gGetInfoForPlayer;
// Commands. Only these untargeted calls are ever used; see ReadCommands.
static MRSendCommandFn gSend;
static MRSetElapsedFn gSetElapsed;
static MRSetModeFn gSetShuffle;
static MRSetModeFn gSetRepeat;
static dispatch_queue_t gQueue;
// The artwork last sent for each player ({"hash", "id": its ArtworkIdentifier}), so its bytes go
// only when they change. Touched on gQueue only.
static NSDictionary<NSString *, NSDictionary *> *gArtworkSent;
static BOOL gPending;
// Whether this macOS has the calls that list every player.
static BOOL gListsPlayers;

static NSString *MRConst(const char *name, NSString *fallback) {
    CFStringRef *p = (CFStringRef *)dlsym(gMR, name);
    return (p && *p) ? (__bridge NSString *)*p : fallback;
}

#define INFO_KEY(suffix) MRConst("kMRMediaRemoteNowPlayingInfo" #suffix, @"kMRMediaRemoteNowPlayingInfo" #suffix)

// Players report what they like: a live stream or a browser video of unknown length gives an
// infinite duration. JSON has no infinity, and writing one raises an exception that ends the
// helper, and with it Now Playing for every app. A line that still can't be written is dropped.
// Returns whether the line was written.
static BOOL Emit(NSDictionary *obj) {
    if (![NSJSONSerialization isValidJSONObject:obj]) return NO;
    NSData *d = nil;
    @try {
        d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    } @catch (NSException *e) {
        return NO;
    }
    if (!d) return NO;
    @synchronized([NSFileHandle class]) {
        fwrite(d.bytes, 1, d.length, stdout);
        fputc('\n', stdout);
        fflush(stdout);
    }
    return YES;
}

// A number JSON can hold: not infinite, not NaN. Anything else reads as missing.
static NSNumber *Finite(id value) {
    if (![value isKindOfClass:NSNumber.class]) return nil;
    return isfinite([value doubleValue]) ? value : nil;
}

static id Call(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [obj performSelector:sel];
#pragma clang diagnostic pop
}

static NSString *NonEmptyString(id value) {
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : nil;
}

// The app a player belongs to. Browser tabs report a WebKit/Chromium helper; prefer the parent app.
static NSString *ClientBundle(id client) {
    return NonEmptyString(Call(client, @"parentApplicationBundleIdentifier")) ?: NonEmptyString(Call(client, @"bundleIdentifier"));
}

// One player's details from its Now Playing info, or nil when it has nothing loaded.
static NSMutableDictionary *Describe(NSDictionary *info) {
    if (![info isKindOfClass:NSDictionary.class]) return nil;
    NSString *title = NonEmptyString(info[INFO_KEY(Title)]);
    if (!title) return nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithObject:title forKey:@"title"];
    NSString *artist = NonEmptyString(info[INFO_KEY(Artist)]);
    NSString *album = NonEmptyString(info[INFO_KEY(Album)]);
    if (artist) out[@"artist"] = artist;
    if (album) out[@"album"] = album;
    // No duration means a live stream: the island shows it without a progress bar.
    if (Finite(info[INFO_KEY(Duration)])) out[@"duration"] = info[INFO_KEY(Duration)];
    if (Finite(info[INFO_KEY(ElapsedTime)])) out[@"elapsed"] = info[INFO_KEY(ElapsedTime)];
    if (Finite(info[INFO_KEY(PlaybackRate)])) out[@"rate"] = info[INFO_KEY(PlaybackRate)];
    if (Finite(info[INFO_KEY(ShuffleMode)])) out[@"shuffleMode"] = info[INFO_KEY(ShuffleMode)];
    if (Finite(info[INFO_KEY(RepeatMode)])) out[@"repeatMode"] = info[INFO_KEY(RepeatMode)];
    NSDate *stamp = info[INFO_KEY(Timestamp)];
    NSTimeInterval at = [stamp isKindOfClass:NSDate.class] ? stamp.timeIntervalSince1970 : NAN;
    out[@"timestamp"] = @(isfinite(at) ? at : NSDate.date.timeIntervalSince1970);
    return out;
}

// Adds the player's app, and its artwork when it changed since it was last sent under `key`.
// Records what was sent in `sent`.
static void AddClientAndArtwork(NSMutableDictionary *out, id client, NSDictionary *info, NSString *key,
                                NSMutableDictionary<NSString *, NSDictionary *> *sent) {
    NSString *bundle = ClientBundle(client);
    NSString *name = NonEmptyString(Call(client, @"displayName"));
    if (bundle) out[@"bundleID"] = bundle;
    if (name) out[@"appName"] = name;
    NSData *art = info[INFO_KEY(ArtworkData)];
    NSString *artID = NonEmptyString(info[INFO_KEY(ArtworkIdentifier)]);
    NSDictionary *last = gArtworkSent[key];
    if (![art isKindOfClass:NSData.class] || art.length == 0) {
        // Chrome posts its info twice: first naming the artwork, then with its bytes. Between the
        // two the same artwork stays, rather than blinking off.
        if (artID && [last[@"id"] isEqual:artID]) {
            out[@"artworkHash"] = last[@"hash"];
            sent[key] = last;
        }
        return;
    }
    NSNumber *h = @((art.hash ^ art.length) & 0x7FFFFFFFFFFFFFFFULL);
    out[@"artworkHash"] = h;
    if (![last[@"hash"] isEqual:h]) out[@"artwork"] = [art base64EncodedStringWithOptions:0];
    sent[key] = artID ? @{@"hash": h, @"id": artID} : @{@"hash": h};
}

// Writes a line that may carry artwork, and remembers what was sent. A line that couldn't be
// written sends every player's artwork again next time.
static void EmitWithArtwork(NSDictionary *line, NSDictionary<NSString *, NSDictionary *> *sent) {
    gArtworkSent = Emit(line) ? [sent copy] : @{};
}

// macOS 14 and earlier without the calls that list players: the current player alone, as before.
static void FetchCurrentAndEmit(void) {
    gGetInfo(gQueue, ^(NSDictionary *info) {
        gIsPlaying(gQueue, ^(BOOL playing) {
            gGetClient(gQueue, ^(id client) {
                NSMutableDictionary *out = Describe(info);
                NSMutableDictionary *sent = [NSMutableDictionary dictionary];
                if (!out) {
                    EmitWithArtwork(@{@"type": @"nowPlaying", @"empty": @YES}, sent);
                    return;
                }
                out[@"type"] = @"nowPlaying";
                out[@"playing"] = playing ? @YES : @NO;
                AddClientAndArtwork(out, client, info, @"", sent);
                EmitWithArtwork(out, sent);
            });
        });
    });
}

static id LocalOrigin(void) {
    Class origin = objc_getClass("MROrigin");
    SEL local = NSSelectorFromString(@"localOrigin");
    if (!origin || ![origin respondsToSelector:local]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(origin, local);
}

// The path MediaRemote reads one player's info by: this Mac, that app, its default player.
static id PlayerPath(id origin, id client) {
    Class cls = objc_getClass("MRPlayerPath");
    SEL init = NSSelectorFromString(@"initWithOrigin:client:player:");
    if (!cls || !origin || !client || ![cls instancesRespondToSelector:init]) return nil;
    return ((id (*)(id, SEL, id, id, id))objc_msgSend)([cls alloc], init, origin, client, nil);
}

// Every player macOS lists, read without touching any of them. The current player comes from the
// same calls as before (its info, whether it plays, its app); the others from their own info,
// where a rate above zero means playing.
static void FetchPlayersAndEmit(void) {
    gGetInfo(gQueue, ^(NSDictionary *currentInfo) {
        gIsPlaying(gQueue, ^(BOOL currentPlaying) {
            gGetClient(gQueue, ^(id currentClient) {
                gGetClients(gQueue, ^(NSArray *clients) {
                    NSString *currentBundle = ClientBundle(currentClient);
                    NSMutableArray<NSMutableDictionary *> *others = [NSMutableArray array];
                    NSMutableSet<NSString *> *seen = [NSMutableSet set];
                    if (currentBundle) [seen addObject:currentBundle];
                    id origin = LocalOrigin();
                    dispatch_group_t group = dispatch_group_create();
                    for (id client in [clients isKindOfClass:NSArray.class] ? clients : @[]) {
                        NSString *bundle = ClientBundle(client);
                        // One player per app; a player that names no app can't be told apart.
                        if (!bundle || [seen containsObject:bundle]) continue;
                        id path = PlayerPath(origin, client);
                        if (!path) continue;
                        [seen addObject:bundle];
                        NSMutableDictionary *slot = [NSMutableDictionary dictionaryWithObjectsAndKeys:bundle, @"key", client, @"client", nil];
                        [others addObject:slot];
                        dispatch_group_enter(group);
                        gGetInfoForPlayer(path, YES, gQueue, ^(NSDictionary *info) {
                            if ([info isKindOfClass:NSDictionary.class]) slot[@"info"] = info;
                            dispatch_group_leave(group);
                        });
                    }
                    // Everything runs on gQueue, so the answers and the deadline can't overlap. A
                    // player that never answers is left out rather than holding up the rest.
                    __block BOOL done = NO;
                    void (^finish)(void) = ^{
                        if (done) return;
                        done = YES;
                        NSMutableArray *players = [NSMutableArray array];
                        NSMutableDictionary *sent = [NSMutableDictionary dictionary];
                        NSMutableDictionary *current = Describe(currentInfo);
                        if (current) {
                            current[@"playing"] = currentPlaying ? @YES : @NO;
                            current[@"current"] = @YES;
                            AddClientAndArtwork(current, currentClient, currentInfo, currentBundle ?: @"", sent);
                            [players addObject:current];
                        }
                        for (NSMutableDictionary *slot in others) {
                            NSDictionary *info = slot[@"info"];
                            NSMutableDictionary *out = Describe(info);
                            if (!out) continue;
                            out[@"playing"] = [Finite(info[INFO_KEY(PlaybackRate)]) doubleValue] > 0 ? @YES : @NO;
                            AddClientAndArtwork(out, slot[@"client"], info, slot[@"key"], sent);
                            [players addObject:out];
                        }
                        EmitWithArtwork(@{@"type": @"players", @"players": players}, sent);
                    };
                    dispatch_group_notify(group, gQueue, finish);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), gQueue, finish);
                });
            });
        });
    });
}

static void FetchAndEmit(void) {
    if (gListsPlayers) FetchPlayersAndEmit(); else FetchCurrentAndEmit();
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

// Commands reach only the player macOS gives the controls to, through the untargeted calls.
//
// Never use MRMediaRemoteSendCommandToApp, ...ToClient, ...ToPlayer, ...ToPlayerWithResult or
// the *ForPlayer setters. From a process without Apple's entitlement, mediaremoted quietly sends a
// targeted command to the current player instead, and still answers "ok": a pause meant for a
// paused Safari tab would pause the video playing in Chrome. The app sends a command only for the
// current player and tells the user to use the other app's own window otherwise.
static void ReadCommands(void) {
    char line[256];
    while (fgets(line, sizeof line, stdin)) {
        NSString *s = [[NSString stringWithUTF8String:line] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSArray<NSString *> *parts = [s componentsSeparatedByString:@" "];
        if ([parts[0] isEqualToString:@"get"]) {
            dispatch_async(gQueue, ^{ FetchAndEmit(); });
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

static void Observe(NSString *name, void (^block)(void)) {
    [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
        block();
    }];
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
        gGetClients = (MRGetClientsFn)dlsym(gMR, "MRMediaRemoteGetNowPlayingClients");
        gGetInfoForPlayer = (MRGetInfoForPlayerFn)dlsym(gMR, "MRMediaRemoteGetNowPlayingInfoForPlayer");
        gSend = (MRSendCommandFn)dlsym(gMR, "MRMediaRemoteSendCommand");
        gSetElapsed = (MRSetElapsedFn)dlsym(gMR, "MRMediaRemoteSetElapsedTime");
        gSetShuffle = (MRSetModeFn)dlsym(gMR, "MRMediaRemoteSetShuffleMode");
        gSetRepeat = (MRSetModeFn)dlsym(gMR, "MRMediaRemoteSetRepeatMode");
        if (!gGetInfo || !gRegister || !gIsPlaying || !gGetClient) {
            Emit(@{@"type": @"error", @"message": @"MediaRemote symbols missing"});
            exit(3);
        }
        Class pathClass = objc_getClass("MRPlayerPath");
        gListsPlayers = gGetClients && gGetInfoForPlayer && LocalOrigin()
            && pathClass && [pathClass instancesRespondToSelector:NSSelectorFromString(@"initWithOrigin:client:player:")];
        gArtworkSent = @{};
        gQueue = dispatch_queue_create("islet.mediaremote", DISPATCH_QUEUE_SERIAL);
        gRegister(gQueue);

        NSArray *names = @[
            MRConst("kMRMediaRemoteNowPlayingInfoDidChangeNotification", @"kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            MRConst("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
            MRConst("kMRMediaRemoteNowPlayingApplicationDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
            // Per player, the current one or not, and the current player changing.
            MRConst("kMRMediaRemotePlayerNowPlayingInfoDidChangeNotification", @"kMRMediaRemotePlayerNowPlayingInfoDidChangeNotification"),
            MRConst("kMRMediaRemotePlayerIsPlayingDidChangeNotification", @"kMRMediaRemotePlayerIsPlayingDidChangeNotification"),
            MRConst("kMRMediaRemotePlayerPlaybackStateDidChangeNotification", @"kMRMediaRemotePlayerPlaybackStateDidChangeNotification"),
            MRConst("kMRMediaRemoteElectedPlayerDidChangeNotification", @"kMRMediaRemoteElectedPlayerDidChangeNotification"),
        ];
        for (NSString *n in names) Observe(n, ^{ ScheduleFetch(); });
        // mediaremoted restarted and the connection came back: register again and read afresh,
        // artwork included.
        Observe(MRConst("kMRMediaRemoteServiceClientDidRestoreConnectionNotification", @"kMRMediaRemoteServiceClientDidRestoreConnectionNotification"), ^{
            dispatch_async(gQueue, ^{
                gRegister(gQueue);
                gArtworkSent = @{};
            });
            ScheduleFetch();
        });
        Emit(@{@"type": @"ready"});
        dispatch_async(gQueue, ^{ FetchAndEmit(); });
        [NSThread detachNewThreadWithBlock:^{ ReadCommands(); }];
    }
    CFRunLoopRun();
}
