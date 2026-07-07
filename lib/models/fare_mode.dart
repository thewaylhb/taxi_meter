/// Fare calculation scheme.
enum FareMode {
  /// Standard metered fare based on Seoul medium-taxi rates.
  standard,

  /// Carpool cost-sharing mode: flat base fare + fuel-cost-based distance fare.
  carpool,

  /// No billing at all: a speed/road-info dashboard for driving safely,
  /// not for charging a fare. Ending the trip returns straight to idle
  /// with no settlement step and no trip-history record.
  safeDriving;

  String get label {
    switch (this) {
      case FareMode.standard:
        return '미터기 모드';
      case FareMode.carpool:
        return '카풀 모드';
      case FareMode.safeDriving:
        return '안전 주행 모드';
    }
  }

  String get description {
    switch (this) {
      case FareMode.standard:
        return '서울시 요금제';
      case FareMode.carpool:
        return '기본요금 3,000원 + 주행거리 할증';
      case FareMode.safeDriving:
        return '요금 계산 없이 속도와 도로 정보만 표시';
    }
  }
}
