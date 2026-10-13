# 같이타(GachiTa) Supabase 공유본 — F-07·F-08·F-10

---

## 1. 적용 가이드

다음 순서로 진행합니다. **프로젝트 생성 → CLI 설치 → 마이그레이션 적용 → 앱 로그인 계정 준비 → Firebase 서비스 계정 준비 → F-08 푸시 설정**

이 문서의 파일 경로와 PowerShell 명령은 pubspec.yaml, lib, supabase가 함께 있는 Flutter 프로젝트 루트를 기준으로 합니다.

---

### 1.1 Supabase 프로젝트 만들기

1. Supabase 대시보드에서 새 프로젝트를 만듭니다.
2. 프로젝트 이름, 데이터베이스 비밀번호, 지역을 설정합니다. 지역은 가능하면 **서울**을 선택하세요.
3. 프로젝트 생성 화면의 보안 항목을 다음과 같이 설정합니다.

| 항목 | 설정 |
|---|---|
| 데이터 API 활성화 | 체크 |
| 새 테이블을 자동으로 표시합니다 | 체크 해제 |
| 자동 RLS 활성화 | 체크 |

이 공유본은 마이그레이션에서 테이블 권한과 RLS 정책을 설정합니다. **테이블 권한**은 테이블에 접근할 수 있는지를, **RLS 정책**은 접근한 사용자가 어떤 행을 읽거나 바꿀 수 있는지를 결정합니다. 자동 RLS만 켜도 권한이나 정책이 만들어지는 것은 아닙니다.

프로젝트 생성 후 **Integrations → Data API**에서 `public`이 노출 스키마에 포함되어 있는지 확인합니다.

---

### 1.2 Supabase CLI 설치하기

CLI는 PowerShell에서 명령을 입력해 Supabase 프로젝트를 연결하고 파일을 배포하는 도구입니다. Windows에 한 번 설치하면 됩니다. **이미 `supabase --version`으로 버전이 표시된다면 1.3으로 넘어가세요.**

#### ① Scoop 설치 — 이미 설치되어 있다면 생략

시작 메뉴에서 **PowerShell**을 검색해 일반 권한으로 엽니다. 아래 명령을 순서대로 실행합니다.

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex
scoop --version
```

실행 정책 변경 확인을 요청하면 `Y`를 입력합니다. 정책은 현재 Windows 사용자에게 적용됩니다.

#### ② Supabase CLI 설치

같은 PowerShell 창에서 실행합니다.

```powershell
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase
supabase --version
```

버전 번호가 나오면 설치된 것입니다. 명령을 찾을 수 없다면 PowerShell을 닫고 다시 열어 확인하세요.

---

### 1.3 마이그레이션 적용하기

마이그레이션은 테이블·함수·권한 등 DB 구조를 만드는 SQL 파일입니다.

#### ① 압축을 풀고 PowerShell 열기

**`pubspec.yaml`, `lib`, `supabase`가 함께 있는 Flutter 프로젝트 루트**에서 PowerShell을 엽니다. 이후 명령은 모두 이 위치에서 실행합니다.

#### ② 로그인하고 프로젝트 연결하기

아래의 `<프로젝트-ref>`를 실제 프로젝트 값으로 바꿔 실행합니다. 꺾쇠 괄호도 제거합니다.

```powershell
supabase login
supabase link --project-ref <프로젝트-ref>
```

`supabase login`을 실행하면 브라우저에 **Authorize Supabase CLI** 로그인 인증 창이 열립니다.

1. 인증 창에서 **Copy code**를 누릅니다.
2. 명령을 실행한 **PowerShell 창**으로 돌아가 인증 코드 입력란에 붙여넣고 **Enter**를 누릅니다.
3. 로그인 완료 메시지가 나오면 브라우저 탭을 닫아도 됩니다.
4. 이어서 `supabase link --project-ref <프로젝트-ref>`를 실행합니다.

- **프로젝트-ref:** 대시보드 주소의 `/project/` 다음 값입니다. 예를 들어 `https://supabase.com/dashboard/project/abc123`이면 `abc123`입니다.
- **데이터베이스 비밀번호:** `link`에서 물으면 프로젝트 생성 시 설정한 비밀번호를 입력합니다.

#### ③ 마이그레이션 적용하기

```powershell
supabase db push
```

적용할 파일을 확인하고, 확인 요청이 나오면 `y`를 입력합니다. 다음 두 파일이 순서대로 적용됩니다.

| 순서 | 파일 | 생성하는 내용 |
|---|---|---|
| 1 | `202610050000_common_baseline.sql` | 공통 사용자·팟·신청/참여 테이블과 조회 API |
| 2 | `202610050001_f07_f08_f10.sql` | F-07·F-08·F-10의 테이블·권한·함수·트리거와 프로필 집계 예약 |

프로필 집계는 **한국 시각 매일 00:00**에 실행됩니다. 마이그레이션은 더미 계정이나 팟 데이터를 생성하지 않습니다.

#### ④ 적용 이력 확인하기

```powershell
supabase migration list
```

두 마이그레이션이 원격 프로젝트의 적용 이력에 표시되는지 확인합니다.

#### 공통 기반만 먼저 적용하는 경우 (무시해도 좋습니다.)

`202610050001_f07_f08_f10.sql`을 잠시 `supabase/migrations` 폴더 밖으로 옮긴 뒤 `supabase db push`를 실행합니다. 기능을 추가할 때 파일을 원래 위치로 돌려놓고 다시 실행합니다. 그동안 Flutter 앱의 F-07·F-08·F-10 화면에는 미적용 안내가 표시됩니다.

---

### 1.4 앱 로그인 계정 준비

#### 로그인 계정과 프로필의 역할 

| 저장 위치 | 저장하는 정보 | 역할 |
|---|---|---|
| **Supabase Auth** | 이메일·비밀번호 등 인증 정보 | 로그인할 수 있는 사용자인지 확인 |
| **`public.profiles`** | 사용자 ID·표시 이름·프로필 사진 | 앱에 사용자 정보를 표시 |

두 정보는 **같은 UUID로 연결**됩니다. Supabase도 인증 정보와 앱용 사용자 테이블을 연결하는 구조를 안내합니다.

#### ① Auth 계정 만들기

Supabase 대시보드에서 해당 프로젝트를 열고 진행합니다.

1. **Authentication → Users**로 이동합니다.
2. **Add user → Create new user**를 선택합니다.
3. 앱 로그인에 사용할 실제 이메일과 임시 비밀번호를 입력해 계정을 생성합니다.
4. 생성된 사용자의 User UID(UUID)를 복사합니다.

이미 계정이 있다면 새로 만들지 않고 해당 계정의 UUID를 복사하면 됩니다.

#### ② 같은 UUID로 프로필 등록하기

대시보드의 **SQL Editor**에서 다음 SQL의 두 값을 실제 값으로 바꿔 실행합니다.

```sql
insert into public.profiles (id, display_name)
values (
  '복사한 Auth 사용자 UUID',
  '실제 사용자 이름'
);
```

- `id`: 앞에서 복사한 UUID를 그대로 입력합니다. 새 UUID를 만들면 안 됩니다.
- `display_name`: 앱에서 표시할 실제 이름을 입력합니다.

이미 같은 `id`의 프로필이 있다면 새로 등록할 필요가 없습니다.

#### ③ Flutter 앱에서 로그인하기

Auth에 등록한 **이메일과 비밀번호**로 로그인합니다. 앱은 로그인된 사용자의 UUID로 `profiles`에서 이름 등의 정보를 읽습니다.

Auth 계정 생성만으로 이 공유본의 `profiles` 행이 자동 생성되지는 않습니다.

---

### 1.5 Firebase 푸시 발송용 서비스 계정 준비 (F-08)

Flutter 앱과 같은 Firebase 프로젝트에서 FCM HTTP v1 발송 권한이 있는 서비스 계정을 준비합니다.

#### ① Firebase 프로젝트 확인

Firebase Console에서 Flutter 앱에 연결한 프로젝트를 엽니다.

**프로젝트 설정 → 일반**의 프로젝트 ID가 Flutter의 `config/development.json`에 있는 `FIREBASE_PROJECT_ID`와 같은지 확인합니다.

#### ② FCM API 활성화 확인

**프로젝트 설정 → Cloud Messaging**에서 **Firebase Cloud Messaging API(V1)**의 활성화 상태를 확인합니다.

비활성 상태라면 해당 프로젝트의 Google Cloud Console에서 **API 및 서비스 → 라이브러리 → Firebase Cloud Messaging API → 사용 설정**을 진행합니다.

#### ③ 푸시 발송용 서비스 계정 만들기

Google Cloud Console에서 동일한 프로젝트를 선택하고 진행합니다.

1. **IAM 및 관리자 → 서비스 계정**을 엽니다.
2. **서비스 계정 만들기**를 누릅니다.
3. 이름을 입력합니다. 예: `gachita-keyword-push`
4. **만들고 계속하기**를 누릅니다.
5. 프로젝트 접근 권한에서 **Firebase Cloud Messaging API Admin** 역할을 선택합니다. 역할 ID는 `roles/firebasecloudmessaging.admin`입니다.
6. 나머지 선택 항목은 비워 두고 완료합니다.

이 역할에는 푸시 발송에 필요한 `cloudmessaging.messages.create` 권한이 포함됩니다.

#### ④ 서비스 계정 JSON 키 받기

1. 좌측 서비스탭에서, 생성한 서비스 계정을 클릭합니다.
2. **작업** -> **키(Keys)** 관리를 클릭합니다.
3. **키 추가 → 새 키 만들기**를 누릅니다.
4. **JSON**을 선택하고 **만들기**를 누릅니다.
5. 다운로드된 JSON 파일을 보관합니다.

이 파일은 서버용 비밀키입니다. Flutter 앱, 공유 ZIP, Git에 포함하지 않습니다.

#### ⑤ Supabase 환경 파일에 입력

`Flutter 프로젝트 루트`에서 PowerShell을 열고 실행합니다. 이미 `supabase/.env`가 있다면 다시 복사하지 않습니다.

```powershell
Copy-Item supabase/.env.example supabase/.env
```

JSON 전체를 한 줄로 변환하려면 PowerShell에서 실행합니다. 파일 경로는 실제 다운로드 경로로 바꿉니다.

```powershell
Get-Content -LiteralPath '서비스 계정 JSON 파일 경로' -Raw |
  ConvertFrom-Json |
  ConvertTo-Json -Depth 10 -Compress |
  Set-Clipboard
```

변환한 내용이 클립보드에 복사됩니다. `supabase/.env`를 열고 `FIREBASE_SERVICE_ACCOUNT=` 뒤에 붙여넣습니다.

**`PUSH_DISPATCH_SECRET`은 직접 만드는 비밀값입니다.** 
Firebase나 Supabase에서 발급받거나 JSON 파일에서 복사하는 값이 아닙니다. 
예약 작업이 푸시 발송 함수를 호출할 때, 허용된 요청인지 확인하는 데 사용합니다.

비밀값을 생성하기 전에 현재 PowerShell 버전을 확인합니다.

```powershell
$PSVersionTable.PSVersion
```

`Major`가 `7`인지 확인하세요. `5`라면 PowerShell 7 창을 열고 같은 폴더로 이동한 뒤 진행합니다.

1. PowerShell 7에서 아래 명령을 실행합니다. 길고 무작위인 비밀값이 생성되어 클립보드에 복사됩니다.

   ```powershell
   [Convert]::ToBase64String(
     [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
   ) | Set-Clipboard
   ```

2. `.env`의 `PUSH_DISPATCH_SECRET=` 뒤에 복사된 값을 붙여넣고 파일을 저장합니다.

   ```text
   PUSH_DISPATCH_SECRET=방금 생성해 복사한 비밀값
   ```

직접 값을 정할 수도 있지만, `1234`나 프로젝트 이름처럼 쉽게 추측할 수 있는 값은 피하고 위 생성 명령을 권장합니다.

입력한 두 값을 정리하면 다음과 같습니다.

| 키 | 값의 출처 | 입력 방법 |
|---|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | 다운로드한 서비스 계정 JSON 파일 | 앞 단계에서 한 줄로 변환한 JSON 전체를 붙여넣기 |
| `PUSH_DISPATCH_SECRET` | 직접 생성한 무작위 비밀값 | 위 명령으로 생성한 값을 붙여넣기 |

**1.6의 Vault 설정에서 `keyword_push_secret`에도 `.env`의 `PUSH_DISPATCH_SECRET`과 완전히 같은 값을 넣어야 합니다.** 두 값이 다르면 예약 작업의 푸시 발송 요청이 거부됩니다.

---

### 1.6 F-08 키워드 푸시 설정

**F-08의 기기 푸시를 사용하려면 이 설정이 필요합니다.** 기능 마이그레이션을 적용한 뒤 진행합니다. 1.5에서 준비한 서비스 계정과 환경 파일을 사용합니다.

#### ① 비밀값 등록과 함수 배포

Flutter 프로젝트 루트에서 실행합니다. `<프로젝트-ref>`는 1.3에서 사용한 값으로 바꿉니다.

```powershell
supabase secrets set --env-file supabase/.env --project-ref <프로젝트-ref>
supabase functions deploy dispatch-keyword-push --project-ref <프로젝트-ref>
```

#### ② Vault에 예약 호출 정보 등록하기

Vault는 DB의 예약 작업이 사용할 비밀값을 보관합니다. 
Supabase 대시보드의 **SQL Editor**에서 아래 자리표시자를 실제 값으로 바꿔 실행합니다.

```sql
select vault.create_secret(
  'https://<프로젝트-ref>.supabase.co/functions/v1/dispatch-keyword-push',
  'keyword_push_url'
);

select vault.create_secret(
  '<PUSH_DISPATCH_SECRET과 같은 값>',
  'keyword_push_secret'
);
```

`keyword_push_secret`에는 **`.env`의 `PUSH_DISPATCH_SECRET`과 같은 값**을 넣습니다. 
같은 이름의 Vault 항목이 이미 있으면 중복 생성하지 말고 기존 항목을 갱신합니다.

#### ③ 매분 푸시 발송 예약 등록하기

SQL Editor에서 `supabase/scheduling.example.sql`의 전체 내용을 실행합니다. 
예약 작업이 **매분 발송 함수를 호출**하고, 함수가 대기 중인 키워드 알림을 처리합니다. 
예약을 등록하는 것만으로 기기 수신까지 확인되는 것은 아닙니다.

기기에서 받으려면 Flutter 앱에 같은 Firebase 프로젝트를 설정하고, 실제 계정으로 로그인한 뒤 푸시 권한을 허용하고 기기를 등록해야 합니다.

---

## 2. 공유물 구성 설명

---

### 2.1 파일 구성과 팀 기능 추가 기준

| 파일 | 역할 |
|---|---|
| `supabase/migrations/202610050000_common_baseline.sql` | 사용자·팟·참여 내역 등 공통 기반 설치 |
| `supabase/migrations/202610050001_f07_f08_f10.sql` | F-07 프로필·평가, F-08 키워드 알림, F-10 차단과 일일 집계 설치 |
| `supabase/functions/dispatch-keyword-push/` | `index.ts`가 요청을 받고, `worker.ts`가 FCM 발송과 재시도 처리 |
| `supabase/config.toml` | 프로젝트와 푸시 함수 설정 |
| `supabase/scheduling.example.sql` | 푸시 발송 함수를 매분 호출하는 예약 등록 |
| `supabase/.env.example` | 서버 비밀값을 입력할 파일의 양식 |

**기능 추가 기준**

- 공통 테이블의 사용자 UUID·필드·상태값을 기준으로 연결합니다.
- 각 기능은 **새 마이그레이션**으로 추가하고, 필요한 Flutter 조회 코드와 DB 권한을 함께 연결합니다.
- 기능 마이그레이션이 없어도 다른 기능은 실행되도록 구성합니다.

---

### 2.2 데이터베이스 엔티티와 필드

모든 테이블은 `public` 스키마에 있습니다. **공통 기반은 `profiles`, `rides`, `ride_memberships`**이며, `profile_photo` 필드와 나머지 테이블은 기능 마이그레이션에서 추가됩니다.

**표 읽는 법:** 필수는 `NULL`을 허용하지 않으며, 기본값이 있으면 입력을 생략할 수 있습니다. PK는 행을 구별하는 기본키, 복합 PK는 여러 필드를 묶은 기본키입니다. `→`는 다른 테이블을 참조하는 관계입니다.

#### `profiles` — 사용자 정보

Auth 계정과 같은 UUID로 이름·사진을 연결합니다. 사용자 한 명은 여러 팟의 방장 또는 참여자가 될 수 있습니다.

| 필드 | 타입 / 필수 여부 | 의미 |
|---|---|---|
| `id` | uuid / 필수 / PK | → `auth.users.id`. 계정 삭제 시 프로필도 삭제되지만, 방장으로 연결된 팟이 있으면 계정 삭제가 차단됨 |
| `display_name` | text / 필수 | 표시 이름. 공백만 입력할 수 없음 |
| `created_at` | timestamptz / 필수 | 등록 시각. 기본값 `now()` |
| `profile_photo` | bytea / 선택 | F-07 사진. 정적 PNG, 64KiB 이하, 가로·세로 1~256px. 없으면 `NULL` |

#### `rides` — 팟과 운행

방장·경로·정원·운행 상태를 저장합니다. 하나의 팟에 참여 내역, 평가, 키워드 알림이 연결됩니다.

| 필드 | 타입 / 필수 여부 | 의미 |
|---|---|---|
| `id` | uuid / 필수 / PK | 팟 ID. 자동 생성 |
| `host_id` | uuid / 필수 | 방장. → `profiles.id` |
| `origin_name` | text / 필수 | 출발지. 공백만 입력할 수 없음 |
| `destination_name` | text / 필수 | 도착지. 공백만 입력할 수 없음 |
| `condition_text` | text / 필수 | 이동 조건. 기본값은 빈 문자열, 키워드 비교에 사용 |
| `capacity` | integer / 필수 | 정원. 양수만 허용 |
| `departure_at` | timestamptz / 필수 | 예정 출발 시각 |
| `departed_at` | timestamptz / 선택 | 실제 출발 시각. 참여 집계·평가 자격에 사용 |
| `ended_at` | timestamptz / 선택 | 종료 시각. 평가 기한의 기준 |
| `status` | text / 필수 | `recruiting`(모집), `full`(마감), `completed`(완료), `cancelled`(취소). 기본값 `recruiting` |

#### `ride_memberships` — 신청과 참여

사용자와 팟을 연결합니다. **같은 사용자·팟 조합은 한 행**이며, 방장의 승인된 참여 행은 팟 생성 처리에서 등록해야 합니다. DB가 자동으로 생성하지는 않습니다.

| 필드 | 타입 / 필수 여부 | 의미 |
|---|---|---|
| `ride_id` | uuid / 필수 / 복합 PK | → `rides.id` |
| `user_id` | uuid / 필수 / 복합 PK | → `profiles.id` |
| `status` | text / 필수 | `pending`(신청 대기), `approved`(승인), `reject`(거절). 기본값 `pending` |
| `boarded_at` | timestamptz / 선택 | 실제 탑승 시각. 평가 대상 판정에 사용 |
| `no_show` | boolean / 필수 | 노쇼 여부. 기본값 `false` |

방장이 거절하면 담당 서버가 신청 상태를 `pending → reject`로 변경하고 행은 남겨 둡니다. 
거절된 신청은 대기·참여자 목록, 참여·노쇼 집계와 평가 대상에서 제외됩니다. 
신청자 본인은 거절 상태를 조회할 수 있습니다.
승인·거절 API는 신청 관리 기능에서 연결합니다.

#### `ratings` — 동승자 평가

완료된 팟에서 동승자에게 보낸 평가입니다. 
승인·탑승했고 노쇼가 아닌 동승자끼리 **종료 후 72시간 이내** 제출합니다.

| 필드 | 타입 / 필수 여부 | 의미 |
|---|---|---|
| `id` | uuid / 필수 / PK | 평가 ID. 자동 생성 |
| `ride_id` | uuid / 필수 | 평가한 팟. → `rides.id` |
| `reviewer_id` | uuid / 필수 | 평가자. → `profiles.id` |
| `target_id` | uuid / 필수 | 평가받는 사용자. → `profiles.id` |
| `half_units` | smallint / 필수 | 1~10. 실제 별점은 이 값 ÷ 2로, 0.5~5.0점 |
| `created_at` | timestamptz / 필수 | 제출 시각. 기본값 `now()` |

같은 팟에서 같은 상대에게 한 번만 평가하며, 자기 평가는 불가능합니다. 
제출한 점수는 변경할 수 없습니다. 
동일한 요청이 다시 도착해도 평가는 중복 저장되지 않습니다. 
제출 시 선택한 차단도 함께 반영합니다.

#### `profile_stats` — 프로필 집계

사용자당 한 행으로 **받은 평가·참여·노쇼 횟수**를 저장합니다. 
`ratings`, `rides`, `ride_memberships`를 한국 시각 매일 00:00에 집계하므로 다음 집계까지 표시가 지연될 수 있습니다.

| 필드 | 타입 / 필수 여부 | 의미 |
|---|---|---|
| `user_id` | uuid / 필수 / PK | → `profiles.id` |
| `rating_count` | integer / 필수 | 받은 평가 수. 기본값 `0` |
| `average_rating` | numeric(4,2) / 선택 | 받은 평균 별점(0.5~5.0). 평가가 없으면 `NULL` |
| `participation_count` | integer / 필수 | 실제 출발한 팟의 승인 참여 횟수. 기본값 `0` |
| `no_show_count` | integer / 필수 | 승인 참여 중 노쇼로 기록된 팟 수. 기본값 `0` |
| `refreshed_at` | timestamptz / 필수 | 최종 집계 시각. 기본값 `now()` |

받은 평가가 3개 미만이면 프로필 조회 결과의 평균 별점은 `NULL`입니다. 
참여 횟수와 노쇼 횟수는 따로 계산합니다.

#### `user_keywords` — 관심 키워드

사용자당 최대 5개를 등록합니다. 
`enabled = true`인 키워드만 새 팟의 출발지·도착지·조건과 비교하며, 영문 대소문자는 구분하지 않습니다. 
사용을 중지해도 키워드는 남아 있고 5개 제한에 포함됩니다.

| 필드 | 타입 / 필수 여부 | 의미 |
|---|---|---|
| `id` | uuid / 필수 / PK | 키워드 ID. 자동 생성 |
| `user_id` | uuid / 필수 | → `profiles.id` |
| `text` | text / 필수 | 앞뒤 공백을 제거한 키워드. 빈 값 금지 |
| `normalized_text` | text / 필수 | 소문자로 바꾼 값. 사용자별 중복 확인에 사용 |
| `enabled` | boolean / 필수 | 이 키워드의 알림 사용 여부. 기본값 `true` |
| `created_at` | timestamptz / 필수 | 등록 시각. 기본값 `now()` |


#### `notification_preferences` — 알림 설정

사용자당 한 행으로 키워드 알림 전체의 생성·발송 여부를 저장합니다. 
**전체 설정과 해당 키워드의 `enabled`가 모두 켜져 있어야 알림을 생성합니다.** 
푸시 발송 전에도 현재 활성 키워드가 팟과 일치하는지 확인합니다. 
새 알림 생성과 무관하게, 기존 알림함 기록은 유지됩니다.

| 필드 | 타입 / 필수 여부 | 의미 |
|---|---|---|
| `user_id` | uuid / 필수 / PK | → `profiles.id` |
| `keyword_enabled` | boolean / 필수 | 새 알림 생성 및 기기 푸시 발송 여부. 기본값 `true` |

#### `user_blocks` — 차단 목록

누가 누구를 차단했는지 저장합니다. 본인 차단 목록·해제, 팟 참여자 경고, 차단한 방장의 키워드 알림 제외에 사용합니다.

| 필드 | 타입 / 필수 여부 | 의미 |
|---|---|---|
| `blocker_id` | uuid / 필수 / 복합 PK | 차단한 사용자. → `profiles.id` |
| `blocked_id` | uuid / 필수 / 복합 PK | 차단된 사용자. → `profiles.id` |
| `created_at` | timestamptz / 필수 | 차단 시각. 기본값 `now()` |

같은 조합의 중복과 자기 차단은 불가능하며, 상대에게 차단 정보를 공개하지 않습니다.

#### `keyword_notifications` — 앱 내 알림함

키워드가 일치하는 새 모집 팟이 등록되면 생성합니다. 
**사용자·팟마다 알림은 한 개**이며, 팟을 수정해도 새 알림이 생기지는 않습니다.

| 필드 | 타입 / 필수 여부 | 의미 |
|---|---|---|
| `id` | uuid / 필수 / PK | 알림 ID. 자동 생성 |
| `user_id` | uuid / 필수 | 수신자. → `profiles.id` |
| `ride_id` | uuid / 필수 | 연결된 팟. → `rides.id` |
| `title` | text / 필수 | 서버가 만든 제목 |
| `body` | text / 필수 | 출발지 → 도착지 안내 |
| `created_at` | timestamptz / 필수 | 생성 시각. 기본값 `now()` |
| `read_at` | timestamptz / 선택 | 최초 읽음 시각. 읽기 전에는 `NULL` |

#### `device_tokens` — 푸시 수신 기기

사용자 한 명이 여러 Android 기기를 등록할 수 있습니다. 
토큰 하나는 한 계정에 연결됩니다. FCM 토큰 갱신 시 이전 토큰 삭제를 시도하고, 로그아웃 시 해당 기기 등록 삭제를 시도합니다.
즉, 하나의 계정은 다수의 토큰과 연결될 수 있습니다.

| 필드 | 타입 / 필수 여부 | 의미 |
|---|---|---|
| `token` | text / 필수 / PK | FCM 기기 토큰. 빈 값 금지 |
| `user_id` | uuid / 필수 | 현재 소유자. → `profiles.id` |
| `platform` | text / 필수 | `android`만 사용. 기본값 `android` |
| `updated_at` | timestamptz / 필수 | 등록·소유자 변경 시각. 기본값 `now()` |

#### `keyword_push_jobs` — 푸시 발송 작업

앱 내 알림 하나당 발송 작업 하나를 연결합니다. 
서버가 처리 상태와 재시도를 관리합니다.
작업의 `sent`는 기기별 처리가 끝났다는 뜻이며, 모든 기기가 건너뛰어진 경우에도 이 상태가 될 수 있습니다.

| 필드 | 타입 / 필수 여부 | 의미 |
|---|---|---|
| `notification_id` | uuid / 필수 / PK | → `keyword_notifications.id` |
| `status` | text / 필수 | `pending`(대기), `processing`(처리 중), `sent`(처리 완료), `skipped`(건너뜀), `failed`(실패). 기본값 `pending` |
| `attempts` | integer / 필수 | 처리 시도 횟수. 기본값 `0`. 오류 처리 시 시도 횟수가 5회 이상이면 `failed`로 전환해 재시도 종료. 서버 중단 후 재처리에서는 5회를 넘길 수 있음 |
| `available_at` | timestamptz / 필수 | 다음 처리 가능 시각. 기본값 `now()` |
| `locked_at` | timestamptz / 선택 | 서버가 처리를 시작한 시각 |
| `lease_id` | uuid / 선택 | 현재 작업을 처리할 서버의 권한 확인용 ID |
| `last_error` | text / 선택 | 실패 정보 |

#### `keyword_push_deliveries` — 기기별 발송 결과

알림 하나에 여러 기기의 결과가 연결됩니다.
성공한 기기는 재시도에서 제외합니다.
기기별 `sent`는 FCM 발송 요청이 성공했다는 뜻이며, 기기의 실제 수신을 보장하지는 않습니다.

| 필드 | 타입 / 필수 여부 | 의미 |
|---|---|---|
| `notification_id` | uuid / 필수 / 복합 PK | → `keyword_notifications.id` |
| `token` | text / 필수 / 복합 PK | 발송 대상 토큰. 토큰 삭제 후에도 결과를 남기기 위해 `device_tokens` 외래키는 없음 |
| `status` | text / 필수 | `pending`(대기), `sent`(FCM 요청 성공), `skipped`(건너뜀). 기본값 `pending` |

---

### 2.3 접근 권한과 RLS

12개 테이블 모두 RLS를 사용합니다. 
테이블 권한으로 접근 가능 여부를 정하고, RLS로 접근할 행을 제한합니다.
앱에서 사용하는 RPC는 로그인이 필요합니다.
추가 처리 규칙이 있는 경우, RPC를 사용합니다.

| 대상 | 앱에서 가능한 작업 |
|---|---|
| 프로필·참여 내역·집계 | 본인 행 조회. 타인 표시 정보는 관계를 확인하는 RPC로 조회 |
| 팟 | 모집·마감 팟 또는 본인이 방장·승인 참여자인 팟 조회 |
| 키워드 | 본인 행 조회·삭제와 `enabled` 변경. 추가는 RPC 사용 |
| 차단·기기 토큰 | 본인 행 조회·삭제. 추가·등록은 RPC 사용 |
| 알림 설정 | 본인 행 조회·등록·변경 |
| 평가·알림함 | 본인이 보낸 평가와 받은 알림 조회. 평가 제출·읽음 처리는 RPC 사용 |

공통 테이블의 데이터 변경과 집계·푸시 처리는 서버에서 담당합니다. 
`keyword_push_jobs`, `keyword_push_deliveries`는 **서버 전용**이며 앱은 직접 접근할 수 없습니다.

---

### 2.4 공개 RPC 계약

RPC는 앱이나 서버가 호출하는 DB 함수입니다. 
아래 함수 이름과 매개변수를 Flutter 조회 코드의 연결 기준으로 사용합니다.

#### 공통 기반 — 기능 마이그레이션 없이 사용 가능

| 함수 | 용도 |
|---|---|
| `get_gachita_capabilities()` | F-07·F-08·F-10 설치 여부 확인 |
| `get_user_summaries(p_user_ids)` | 사용자 ID·이름 조회. 최대 100명 |
| `list_ride_profiles(p_ride_ids)` | 팟의 승인 참여자 ID·이름 조회. 최대 100개 팟 |
| `list_ride_applicants(p_ride_id)` | 방장이 해당 팟의 대기 신청자 ID·이름 조회 |

#### F-07·F-08·F-10 — 기능 마이그레이션 적용 후 사용 가능

| 기능 | 함수 | 용도 |
|---|---|---|
| F-07 | `get_profile_summaries(p_user_ids)` | 이름·사진·평균 별점·참여·노쇼 횟수 조회. 최대 20명 |
| F-07 | `set_my_profile_photo(p_photo_base64)` | 본인 사진 저장. `NULL`이면 삭제 |
| F-07 | `list_rating_tasks()` | 평가 대상 운행·동승자와 이미 제출한 대상 조회 |
| F-07 | `submit_ratings(p_ride_id,p_inputs)` | 평가와 선택 차단 제출. `p_inputs` 항목은 `target_id`, `half_units`, 선택 값 `block` |
| F-08 | `add_keyword(p_text)` | 키워드 추가 |
| F-08 | `mark_keyword_notice_read(p_notice_id)` | 본인 알림을 읽음으로 표시 |
| F-08 | `register_device_token(p_token)` | 본인 Android 기기의 FCM 토큰 등록 |
| F-10 | `block_user(p_target_id)` | 사용자 차단 |
| F-10 | `list_my_blocks()` | 본인 차단 목록 조회 |
| F-10 | `blocked_ride_participants(p_ride_id)` | 팟 참여자 중 본인이 차단한 사용자 확인 |
| 설치 확인 | `companion_module_version()` | 기능 버전 반환. 현재 `1` |

`get_profile_summaries()`는 `id`, `display_name`, `photo_base64`, `average_rating`, `participation_count`, `no_show_count`를 반환합니다. 사진은 Base64 문자열입니다.

사용자 조회는 관계가 확인된 경우에만 허용합니다. F-07 프로필은 본인, 조회 가능한 팟의 방장·승인 참여자, 본인 팟의 대기 신청자, 본인 차단 목록의 사용자를 조회할 수 있습니다.

#### 서버 전용 — 앱에서 호출 불가

| 함수 | 용도 |
|---|---|
| `refresh_profile_stats()` | 받은 평가·참여·노쇼 집계 갱신 |
| `claim_keyword_push_jobs(p_limit)` | 처리할 푸시 발송 작업 확보 |

두 함수는 서버의 `service_role` 권한으로 호출합니다.

