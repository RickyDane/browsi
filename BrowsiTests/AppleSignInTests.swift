import Foundation
import Testing
@testable import Browsi

struct AppleSignInTests {
    @Test func detectsAuthorizeEndpoint() {
        #expect(AppleSignIn.isAuthorizeURL(URL(string: "https://appleid.apple.com/auth/authorize?client_id=x&response_mode=form_post")))
        #expect(AppleSignIn.isAuthorizeURL(URL(string: "https://account.apple.com/auth/authorize")))
        #expect(!AppleSignIn.isAuthorizeURL(URL(string: "http://appleid.apple.com/auth/authorize")), "HTTPS only")
        #expect(!AppleSignIn.isAuthorizeURL(URL(string: "https://appleid.apple.com/account/manage")))
        #expect(!AppleSignIn.isAuthorizeURL(URL(string: "https://appleid.apple.com.evil.example/auth/authorize")))
        #expect(!AppleSignIn.isAuthorizeURL(nil))
    }

    @Test func leavingAppleEndsInPlaceSheet() {
        #expect(AppleSignIn.leavesApple(URL(string: "https://example.com/auth/apple/callback")))
        #expect(!AppleSignIn.leavesApple(URL(string: "https://idmsa.apple.com/appleauth/auth/authorize/signin")))
        #expect(!AppleSignIn.leavesApple(URL(string: "https://iforgot.apple.com/password/verify")))
        #expect(!AppleSignIn.leavesApple(URL(string: "about:blank")), "only real web navigations count")
        #expect(AppleSignIn.leavesApple(URL(string: "https://notapple.com/")))
        #expect(AppleSignIn.leavesApple(URL(string: "https://apple.com.evil.example/")))
    }

    @Test func secretsOnlyGoToAppleIdentityFrames() {
        #expect(AppleSignIn.fillHosts.allSatisfy(AppleSignIn.isAppleHost))
        #expect(!AppleSignIn.fillHosts.contains("www.apple.com"))
    }
}
