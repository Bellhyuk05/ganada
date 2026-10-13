# 같이타(GachiTa) Flutter 공유본 — F-07·F-08·F-10

## 1. 적용 가이드

### 1.1 준비
- Dart `^3.13.4`를 지원하는 Flutter SDK와 Android SDK를 설치하고 Android 기기 또는 에뮬레이터를 준비합니다. 
- Supabase 공유본의 안내에 따라 DB와 F-08 푸시 설정을 준비합니다.
- 실제 로그인 계정과, 같은 UUID를 사용하는 `profiles` 행을 준비합니다.

### 1.2 프로젝트 열기와 연결 설정

1. Flutter 공유 ZIP의 압축을 풉니다.
2. Android Studio에서 **`pubspec.yaml`이 들어 있는 폴더**를 프로젝트로 엽니다.
3. Android Studio의 **Terminal**을 열고 아래 명령을 실행합니다. 터미널은 **PowerShell 7**이어야 합니다. `$PSVersionTable.PSVersion`으로 현재 버전을 확인하세요.
   ```powershell
   Copy-Item config/development.example.json config/development.json
   flutter pub get
   ```
   `Copy-Item`은 처음 한 번만 실행하세요. 이미 `development.json`이 있으면 다시 복사하지 않습니다.
4. Supabase 대시보드에서 프로젝트를 열고 **Connect → Server** 탭에서 `SUPABASE_URL`과 `SUPABASE_PUBLISHABLE_KEY`를 복사해 `config/development.json`에 입력합니다.
5. Firebase Console에 Android 패키지 `com.example.unilink`를 등록하고 `google-services.json`을 받습니다. Android Studio Terminal에서 다음 명령을 실행하면 Firebase 공개 설정이 `development.json`에 입력됩니다.
   ```powershell
   ./tool/import_firebase_android.ps1 -AndroidConfig 'google-services.json 파일 경로'
   ```

### 1.3 실행

Android Studio Terminal에서 실행합니다.
```powershell
flutter run --dart-define-from-file=config/development.json
```

실제 계정으로 로그인한 뒤 **MY → 알림 설정 → 이 기기에서 푸시 알림 활성화**를 눌러 알림 권한을 허용하고 기기를 등록합니다.

### 1.4 기능 마이그레이션 미적용 시

- 공통 기반만 적용하면 F-07·F-08·F-10에 미적용 안내가 표시됩니다. 기능 마이그레이션을 적용한 뒤 다시 불러오기를 누르세요.


## 2. 전체 흐름 정리

### 앱 실행

```text
main()
→ 설정 확인
→ Supabase 초기화
→ SessionGate에서 로그인 확인
→ GachiTaApp 생성
→ initState()
→ Controller와 푸시 서비스 생성
→ 데이터 조회 시작
→ build()
→ 조회 중인 화면 표시
→ 조회 결과로 상태 변경
→ setState()
→ build()
→ 현재 화면 표시
```

데이터 조회는 비동기로 진행됩니다. 조회 중에도 화면이 표시되며, 결과가 도착하면 화면을 갱신합니다.

### 홈에서 팟 선택

```text
팟 카드 누르기
→ _openRide(ride)
→ 선택한 팟 ID 저장
→ _go(_Page.detail)
→ setState()
→ build()
→ _body()
→ _pageContent(_page)
→ _detail()
```

### 알림 탭 선택

```text
하단의 알림 탭 누르기
→ _goTab(index)
→ _tab과 _page 변경
→ 이전 화면 기록 초기화
→ 데이터 새로고침 시작
→ build()
→ 키워드 알림과 동승자 평가 안내 표시
→ 조회 결과로 화면 갱신
```

### 로그아웃

```text
MY에서 로그아웃 누르기
→ 푸시 연결 정리 시도
→ Supabase 로그아웃
→ SessionGate가 인증 상태 변경 감지
→ 로그인 화면 표시
```

### 주요 파일과 기능 연결

| 파일 | 역할 |
|---|---|
| `lib/main.dart` | 앱 시작, 화면 이동, 데이터 갱신과 기능 연결 |
| `lib/ui/ride_pages.dart` | 홈, 팟 상세, 알림 등 화면 구성 |
| `lib/core/team_features.dart` | 추가 기능의 화면과 처리 함수를 연결하는 `TeamFeatureBindings` 정의 |

팟 만들기와 대화방은 UI가 준비되어 있지만, 실제 처리와 메시지 조회에는 기능 연결이 필요합니다. 계정 관리는 별도 화면을 연결해야 합니다.

## 핵심적으로 기억할 세 가지

1. **`main()`은 앱을 시작합니다.**
2. **`build()`는 현재 상태를 화면으로 표현합니다.**
3. **사용자 조작이나 데이터 변경이 발생하면 상태를 바꾸고 화면을 다시 구성합니다.**

현재 `main()`은 `GachiTaApp`에 `repository`와 `teamFeatures`를 전달합니다. **기본 실행 상태에서는 참여 신청 처리 함수가 연결되지 않아 신청 버튼이 비활성화**됩니다. 신청 기능은 `TeamFeatureBindings.onRequestJoin` 또는 `GachiTaApp.onRequestJoin`에 연결합니다. 둘 다 지정하면 `GachiTaApp.onRequestJoin`을 사용합니다.
