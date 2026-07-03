/// Fare calculation scheme.
enum FareMode {
  /// Standard metered fare based on Seoul medium-taxi rates.
  standard,

  /// Carpool cost-sharing mode: flat base fare + fuel-cost-based distance fare.
  carpool;

  String get label {
    switch (this) {
      case FareMode.standard:
        return '미터기 모드';
      case FareMode.carpool:
        return '카풀 모드';
    }
  }

  String get description {
    switch (this) {
      case FareMode.standard:
        return '서울시 요금제';
      case FareMode.carpool:
        return '기본요금 3,000원 + 주행거리 할증';
    }
  }
}
