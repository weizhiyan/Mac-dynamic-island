ObjC.import('Foundation');

function run(arguments) {
    try {
        var framework = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework');
        if (!framework || !framework.load) return JSON.stringify({error: '当前系统无法连接媒体服务'});
        var request = $.NSClassFromString('MRNowPlayingRequest');
        if (!request || request.isNil()) return JSON.stringify({error: '当前系统暂不支持读取媒体信息'});
        var action = arguments[0] || 'state';
        var expectedBundle = arguments[1];

        function unwrap(value) {
            return value && !value.isNil() ? ObjC.unwrap(value) : null;
        }

        function snapshot() {
            var path = request.localNowPlayingPlayerPath;
            if (!path || path.isNil() || !path.client) return null;
            var client = path.client;
            var bundle = unwrap(client.parentApplicationBundleIdentifier) || unwrap(client.bundleIdentifier);
            if (bundle !== expectedBundle) return null;
            var item = request.localNowPlayingItem;
            if (!item || item.isNil() || !item.nowPlayingInfo) return null;
            var info = item.nowPlayingInfo;
            function field(name) { return info.objectForKey('kMRMediaRemoteNowPlayingInfo' + name); }
            var title = unwrap(field('Title'));
            if (!title) return null;
            var timestamp = field('Timestamp');
            var duration = Number(unwrap(field('Duration')) || 0);
            var elapsed = Number(unwrap(field('ElapsedTime')) || 0);
            var playing = !!request.localIsPlaying;
            var rate = Number(unwrap(field('PlaybackRate')) || 0);
            if (playing && rate > 0 && timestamp && !timestamp.isNil() && timestamp.isKindOfClass($.NSDate)) {
                elapsed += Math.max(0, Date.now() / 1000 - Number(timestamp.timeIntervalSince1970)) * rate;
            }
            var result = {
                title: String(title), artist: String(unwrap(field('Artist')) || ''),
                album: String(unwrap(field('Album')) || ''), isPlaying: playing,
                progress: Math.max(0, duration > 0 ? Math.min(elapsed, duration) : elapsed),
                duration: Math.max(0, duration), bundleIdentifier: bundle,
                identifier: String(unwrap(field('ContentItemIdentifier')) || title)
            };
            var artwork = field('ArtworkData');
            if (artwork && !artwork.isNil() && artwork.isKindOfClass($.NSData) && artwork.length <= 4 * 1024 * 1024) {
                result.artworkBase64 = ObjC.unwrap(artwork.base64EncodedStringWithOptions(0));
            }
            return result;
        }

        var before = snapshot();
        if (action === 'state') return JSON.stringify({snapshot: before});
        if (!before) return JSON.stringify({error: '汽水音乐尚未提供可控制的歌曲，请确认已登录并有可播放的歌曲'});
        var expectedPlaying = action === 'pause' ? false : action === 'play' ? true : !before.isPlaying;
        var command = action === 'next' ? 4 : action === 'previous' ? 5 : expectedPlaying ? 0 : 1;
        if ((action === 'play' || action === 'pause') && before.isPlaying === expectedPlaying) {
            return JSON.stringify({snapshot: before, confirmed: true});
        }
        ObjC.bindFunction('MRMediaRemoteSendCommand', ['bool', ['int', 'id']]);
        if (!$.MRMediaRemoteSendCommand(command, $())) return JSON.stringify({error: '播放器未接受操作，请稍后重试'});
        var after;
        for (var attempt = 0; attempt < 12; attempt++) {
            delay(0.1);
            after = snapshot();
            if (!after) continue;
            var confirmed = action === 'next' || action === 'previous'
                ? after.identifier !== before.identifier || after.progress + 1 < before.progress
                : after.isPlaying === expectedPlaying;
            if (confirmed) return JSON.stringify({snapshot: after, confirmed: true});
        }
        return JSON.stringify({snapshot: after, error: '播放器尚未确认操作结果，请稍后重试'});
    } catch (error) {
        return JSON.stringify({error: '媒体服务暂时不可用，请重试'});
    }
}
