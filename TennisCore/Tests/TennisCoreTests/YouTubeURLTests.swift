import Testing
@testable import TennisCore

@Suite struct YouTubeURLTests {
    @Test func parsesCommonForms() {
        #expect(YouTubeURL.videoID(from: "https://youtu.be/DN17Ar28dWA?si=KTvLMLnzC8uuBfG-") == "DN17Ar28dWA")
        #expect(YouTubeURL.videoID(from: "youtu.be/DN17Ar28dWA") == "DN17Ar28dWA")
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30s") == "dQw4w9WgXcQ")
        #expect(YouTubeURL.videoID(from: "https://m.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTubeURL.videoID(from: "https://music.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTubeURL.videoID(from: "youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTubeURL.videoID(from: "  https://youtu.be/DN17Ar28dWA  ") == "DN17Ar28dWA")
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/shorts/abcdef12345") == "abcdef12345")
    }

    @Test func rejectsNonYouTube() {
        #expect(YouTubeURL.videoID(from: "그냥 텍스트") == nil)
        #expect(YouTubeURL.videoID(from: "") == nil)
    }
}
