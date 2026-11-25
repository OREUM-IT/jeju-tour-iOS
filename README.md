# 오름잇 iOS 앱 (Swift)

오름잇 웹([www.oreumit.com](https://www.oreumit.com))을 여는 SwiftUI 앱이다. 웹 기능은 그대로 쓰고, 아래 기능은 앱이 직접 처리한다. 웹 코드는 [OREUM-IT/jeju-tour](https://github.com/OREUM-IT/jeju-tour)에 있다.

| 앱이 처리 | 내용 |
|---|---|
| 소셜 로그인 | 구글 · 카카오 · 네이버 · LINE 로그인을 시스템 로그인 창(ASWebAuthenticationSession)에서 연다. 구글은 앱 안 웹 화면의 로그인을 막기 때문이다. 로그인이 끝나면 웹이 원래 가려던 주소(`/?account=1`)로 돌아간다 |
| 바깥 링크 | 다른 사이트는 앱 안 Safari 화면으로, `tel:` · `mailto:` · 지도 앱 주소는 iOS로 연다 |
| 공유 | 웹의 `navigator.share`(없으면 새로 만든다)와 `window.OreumitApp.share({ title, text, url })`가 iOS 공유 시트를 연다 |
| 알림 창 | 웹의 `alert` · `confirm`을 iOS 알림 창으로 보여 준다(앱이 그리지 않으면 아무것도 보이지 않는다) |
| 오프라인 | 인터넷이 끊기면 앱 화면과 「다시 시도」를 보여 준다 |
| 앱 표시 | 사용자 에이전트 끝에 `OreumitApp/1.0`을 붙인다. 웹은 `navigator.userAgent.includes('OreumitApp')`로 앱 안인지 안다 |

## 1. 구조

| 파일 | 내용 |
|---|---|
| `App/OreumitApp.swift` | 앱 시작과 첫 화면 |
| `App/WebContainer.swift` | 웹 화면과 위 처리 |
| `App/OfflineView.swift` | 오프라인 화면 |
| `App/Info.plist` | 이름(오름잇), 위치 · 카메라 권한 문구, 세로 화면, 암호화 신고 면제 |
| `App/Assets.xcassets` | 앱 아이콘. **지금은 160px 로고를 1024px로 키운 임시본이라 원본 1024px로 바꿔야 한다** |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) 설정. `.xcodeproj`는 저장소에 넣지 않고 빌드할 때 만든다 |
| `.github/workflows/build.yml` | 푸시마다 macOS에서 서명 없이 컴파일한다(비밀값 필요 없음) |
| `.github/workflows/testflight.yml` | 수동 실행. 보관(archive) 뒤 TestFlight에 올린다 |
| `ExportOptions.plist` | App Store Connect 업로드 설정 |

iPhone 전용(`TARGETED_DEVICE_FAMILY: "1"`)이고 iOS 16 이상이다. iPad에서는 iPhone 앱으로 돈다.

## 2. Mac 없이 출시하는 순서

1. [Apple Developer Program](https://developer.apple.com/programs/)에 가입한다(연 99달러). 개인으로 가입하면 D-U-N-S 번호가 필요 없다.
2. developer.apple.com → Certificates, Identifiers & Profiles → Identifiers에 번들 ID `com.oreumit.app`을 등록한다. 다른 ID를 쓰면 `project.yml`의 `PRODUCT_BUNDLE_IDENTIFIER`도 바꾼다.
3. App Store Connect → 앱 → 새로운 앱: 그 번들 ID, 이름 「오름잇」, 기본 언어 한국어.
4. App Store Connect → 사용자 및 액세스 → 통합 → App Store Connect API에서 키를 만든다. 역할은 **Admin**이어야 자동 서명이 인증서와 프로필을 만든다. `.p8` 파일은 한 번만 내려받을 수 있다. Key ID와 Issuer ID를 적어 둔다.
5. 팀 ID는 developer.apple.com → Membership details에 있다.
6. 이 저장소 Settings → Secrets and variables → Actions → New repository secret:

   | 이름 | 값 |
   |---|---|
   | `APPLE_TEAM_ID` | 팀 ID |
   | `ASC_KEY_ID` | Key ID |
   | `ASC_ISSUER_ID` | Issuer ID |
   | `ASC_KEY_P8` | `.p8` 파일 내용 전체(`-----BEGIN PRIVATE KEY-----`부터 끝까지) |

7. Supabase 대시보드 → Authentication → URL Configuration → Redirect URLs에 `oreumit://login`을 추가한다. 없으면 앱 로그인이 웹 주소로 돌아가 로그인 창이 닫히지 않는다.
8. Actions → testflight → Run workflow. 성공하면 App Store Connect → TestFlight에 빌드가 보인다(처리에 10~30분).
9. iPhone에 TestFlight 앱을 설치해 받아 보고 확인한다.
10. App Store Connect에서 심사에 낸다.
    - 스크린샷: 6.9" 또는 6.5" iPhone. TestFlight로 설치한 iPhone에서 캡처한다.
    - 설명 · 키워드 · 지원 URL · 개인정보 처리방침 URL
    - 앱 개인정보: 위치, 사진, 사용자 콘텐츠(커뮤니티), 계정 정보
    - 연령 등급 → 빌드 선택 → 심사에 제출

## 3. 심사 전에 웹(jeju-tour)에서 해야 할 일

2026-11-25 jeju-tour 코드를 확인한 결과다.

| App Store 심사 지침 | 지금 웹 | 해야 할 일 |
|---|---|---|
| 4.8 로그인 서비스 | 구글 · 카카오 · 네이버 · LINE | **Apple 로그인 추가**(Supabase Apple 공급자). Apple 키로 만든 클라이언트 비밀값은 6개월마다 갱신해야 한다 |
| 5.1.1(v) 계정 삭제 | 없음 | 앱 안에서 회원 탈퇴 |
| 1.2 사용자 생성 콘텐츠 | 커뮤니티에 신고는 있고 차단은 없음 | 사용자 차단 |
| 4.2 최소 기능 | — | 웹을 감싼 앱으로 보이면 거절될 수 있다. 위 앱 처리 외에 알림 같은 앱만의 기능을 더하면 안전하다 |

## 4. 확인한 것과 안 한 것

- Swift 코드는 Linux 작업 환경에서 썼고 그곳에서는 컴파일하지 못했다. 컴파일은 GitHub Actions `build`(macOS, Xcode 16)로 확인한다.
- TestFlight 업로드, 실제 iPhone 동작, 심사 통과는 아직 확인하지 않았다.
- 자동 서명은 실행할 때마다 「Apple Development」 인증서를 새로 만들 수 있다(개발자 사이트에 「Created via API」로 쌓인다). 쌓이면 지우거나, 배포 인증서와 프로필을 Secrets로 넣는 수동 서명으로 바꾼다.

## 5. 버전

- 앱 버전: `project.yml`의 `MARKETING_VERSION`
- 빌드 번호: testflight 실행 번호(`GITHUB_RUN_NUMBER`)를 쓴다. 같은 앱 버전 안에서 빌드 번호는 겹치면 안 된다.
