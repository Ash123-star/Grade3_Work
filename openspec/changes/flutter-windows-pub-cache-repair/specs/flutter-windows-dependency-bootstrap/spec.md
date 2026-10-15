## ADDED Requirements
### Requirement: Reproducible Windows dependency recovery
The development bootstrap SHALL recover Flutter dependencies into an ASCII Pub cache without changing locked versions or removing old files. Priority P0, local Windows development only.

#### Scenario: Existing Chinese user cache
- **WHEN** the developer runs the recovery script with existing package configuration
- **THEN** existing packages SHALL be copied through decoded file paths, official pub get SHALL regenerate package and plugin metadata, and successful configuration SHALL persist user PUB_CACHE for future IDE sessions

#### Scenario: Invalid cache path or unavailable package
- **WHEN** the cache path is nonASCII or a locked dependency is unavailable offline
- **THEN** the script SHALL stop with a clear error without pretending startup succeeded, SHALL NOT delete old cache or application data, and SHALL NOT update user environment before successful pub resolution

#### Scenario: Verification scope
- **WHEN** package resolution and client compilation pass without an Android build
- **THEN** the report SHALL distinguish dependency recovery from unverified Android runtime and SHALL NOT claim APK or device acceptance

### Requirement: Verified native SQLite cache
The bootstrap SHALL prepare the locked SQLite Android binaries using official release artifacts and package SHA256 values without changing database behavior. Priority P0, existing native dependency only.

#### Scenario: Release URL times out
- **WHEN** the default GitHub binary download is unavailable but official Release API is reachable
- **THEN** the script SHALL download the matching official asset, verify its package hash before publishing it, and seed the default hook cache for x64/arm64/arm

#### Scenario: Offline rerun or corrupt local binary
- **WHEN** a verified local cache exists or a supplied binary has a mismatched hash
- **THEN** valid cache SHALL be reused without network and corrupt bytes SHALL be rejected before entering the default hook cache
