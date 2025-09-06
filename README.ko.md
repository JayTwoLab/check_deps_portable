
# `heck_deps_portable.sh`

[English](README.md)

## 개요
`check_deps_portable.sh`는 배포판에 구애받지 않고 사용할 수 있는 ELF 종속성 스캐너입니다. 다음을 수행합니다.
1) 대상 바이너리(또는 so)에 대해 `ldd`를 실행하여 공유 라이브러리 경로를 수집하고,
2) 각 `.so` 실제 경로가 **어떤 패키지**에 소속되는지 매핑합니다(로컬 설치 DB 우선, 필요 시 저장소 검색 사용),
3) 배포판별 규칙을 이용해 **개발 패키지**(`-dev`/`-devel` 등)를 추정하여 제안합니다.

다른 머신에서 동일 라이브러리로 빌드/링크해야 할 때 필요한 런타임/개발 패키지를 빠르게 파악할 수 있습니다.

## 지원 배포판
`/etc/os-release`를 통해 배포판 계열을 자동 감지하며, 다음을 지원합니다.

- **Debian/Ubuntu/Kali/Pop!_OS**: `dpkg -S`, `apt-file search`
- **RHEL/CentOS/Alma/Rocky/Amazon Linux/Fedora**: `rpm -qf`, `dnf|yum provides`(또는 `repoquery`)
- **openSUSE/SLES**: `rpm -qf`, `zypper what-provides`
- **Arch/Manjaro**: `pacman -Qo`, `pacman -F`(파일 DB 필요)
- **Alpine**: `apk info -W`, `apk search -x`
- **Gentoo**: `equery b`(‘gentoolkit’ 필요)
- **Void**: `xbps-query -o`, `xbps-query -Rs`

> 목록에 없는 배포판이라도 위 계열과 호환된다면 대개 동작합니다.

## 필요 구성요소
- POSIX 셸 및 기본 CLI 도구
- `ldd`(시스템 libc 도구 세트에 포함: `glibc`/`libc-bin`/`musl-utils` 등)
- 저장소 검색(로컬 소유자 불명 시 후보 탐색)을 위해 배포판별 도구 설치 권장:
  - **Debian/Ubuntu**: `apt-file` (`sudo apt update && sudo apt install -y apt-file && sudo apt-file update`)
  - **RHEL/Fedora**: `dnf`/`yum`(또는 `repoquery`) 및 저장소 설정
  - **openSUSE**: `zypper`
  - **Arch**: `pacman -Fy`를 한 번 실행해 파일 DB 초기화
  - **Alpine**: `apk` 기본 포함(저장소 인덱스 필요)
  - **Gentoo**: `app-portage/gentoolkit`(equery 제공)
  - **Void**: `xbps-query`

해당 도구가 없어도 로컬 설치 DB만으로는 동작하지만, 패키지에 속하지 않은 파일의 소유자 후보는 제안하지 못합니다.

## 설치
```bash
chmod +x check_deps_portable.sh
```

## 사용법
```bash
./check_deps_portable.sh /path/to/your/binary
```

### 예시
```bash
./check_deps_portable.sh /usr/bin/curl
```

## 출력 형식
- 확인된 `.so` 파일과 해당 파일의 소유 패키지(가능하면 로컬 DB 기준)
- 로컬에서 소유자가 없을 경우, 저장소 후보 최대 몇 개(라인 앞에 `cand:`)
- **Runtime packages**(중복 제거)
- **Suggested build packages**(휴리스틱; `-dev`/`-devel` 등 또는 `base-devel` 같은 도구 묶음 포함 가능)

## 개발 패키지 추정 규칙
배포판 계열별 명명 규칙이 다릅니다.
- Debian/Ubuntu: `libfooN` → `libfoo-dev`
- RHEL/Fedora/SUSE: `libfoo` → `libfoo-devel`
- Alpine: 대개 `libfoo` → `libfoo-dev`
- Arch/Void/Gentoo: 헤더가 별도 *-dev* 패키지가 아니라 도구 묶음(`base-devel`) 또는 본패키지에 포함될 수 있어 제안은 참고용입니다.

## 문제 해결
- **저장소 검색 결과 없음**: 인덱스를 초기화해야 합니다.
  - Debian/Ubuntu: `apt-file update`
  - Arch: `sudo pacman -Fy`
  - Gentoo: `sudo emerge --ask app-portage/gentoolkit`
- **사내/커스텀 라이브러리**: 패키지 미소속 파일은 “no owner; maybe custom/copy”로 표시됩니다.
- **컨테이너/미니멀 환경**: 먼저 패키지 조회 도구를 설치해야 할 수 있습니다.

## 보안 유의사항
- 스크립트는 `ldd` 출력을 읽습니다. 출처가 불분명한 바이너리에 대해서는 운영 환경에서 실행하지 않는 것을 권장합니다.
- 저장소 조회는 설정된 미러에 패키지 정보가 전송될 수 있습니다(일반적인 패키지 관리자 동작).

## 라이선스
- MIT


